#!/usr/bin/env python3
"""Configura el Zabbix del laboratorio por API según docs/diseno/monitoreo.md
(IP2-41 a IP2-45).

Idempotente: si algo ya existe, lo reutiliza. Lee los secretos del .env de esta
carpeta (nunca de Git). Se corre en vm-zabbix:

    python3 configurar-zabbix.py

Crea o ajusta:
  - Contraseña del usuario Admin (reemplaza la de fábrica)
  - Grupo "Integrador II"
  - Las cinco VMs Linux por agente; vm-app además con Docker y Nginx
  - Router R1 y switch SW1 por SNMP, y el servidor Proxmox por ping
  - Host msmotos-web con el escenario web contra la aplicación
  - Triggers T01 (contenedor), T03 (Nginx), T04 y T05 (aplicación)
  - Usuario de solo lectura para Grafana

La réplica de infra/lab-local tiene su propio configurador: allá los nombres de red
son los de Docker y aquí son las direcciones de la VLAN 30.
"""
import json
import sys
import time
import urllib.request
from pathlib import Path

URL = "http://127.0.0.1/api_jsonrpc.php"
AQUI = Path(__file__).resolve().parent
GRUPO = "Integrador II"
CONTENEDOR = "msmotos-app"
APP = "http://10.10.30.11"

# host, nombre visible, dirección, plantillas, capa
VMS = [
    ("vm-app", "vm-app (App MS Motos)", "10.10.30.11",
     ["Linux by Zabbix agent", "Docker by Zabbix agent 2", "Nginx by Zabbix agent"]),
    ("vm-zabbix", "vm-zabbix (Monitoreo)", "10.10.30.12", ["Linux by Zabbix agent"]),
    ("vm-grafana", "vm-grafana (Dashboards)", "10.10.30.13", ["Linux by Zabbix agent"]),
    ("vm-n8n", "vm-n8n (Automatización)", "10.10.30.14", ["Linux by Zabbix agent"]),
    ("vm-rpa", "vm-rpa (Usuario sintético)", "10.10.30.15", ["Linux by Zabbix agent"]),
]
# host, nombre visible, dirección
RED = [
    ("r1", "r1 (Router ISR 4221)", "10.10.30.1"),
    ("sw1", "sw1 (Switch 2960)", "10.10.99.2"),
]
PLANTILLA_RED = "Cisco IOS by SNMP"
PLANTILLA_PING = "ICMP Ping"


def leer_env():
    valores = {}
    for linea in (AQUI / ".env").read_text(encoding="utf-8").splitlines():
        if "=" in linea and not linea.lstrip().startswith("#"):
            k, v = linea.split("=", 1)
            valores[k.strip()] = v.strip()
    return valores


class Zabbix:
    def __init__(self):
        self.token = None
        self.n = 0

    def call(self, metodo, params):
        self.n += 1
        cuerpo = {"jsonrpc": "2.0", "method": metodo, "params": params, "id": self.n}
        cabeceras = {"Content-Type": "application/json-rpc"}
        if self.token and metodo not in ("user.login", "apiinfo.version"):
            cabeceras["Authorization"] = f"Bearer {self.token}"
        req = urllib.request.Request(URL, json.dumps(cuerpo).encode(), cabeceras)
        with urllib.request.urlopen(req, timeout=30) as r:
            resp = json.load(r)
        if "error" in resp:
            raise RuntimeError(f"{metodo}: {resp['error'].get('data') or resp['error']}")
        return resp["result"]

    def uno(self, metodo, filtro, salida="extend"):
        res = self.call(metodo, {"output": salida, "filter": filtro})
        return res[0] if res else None


def entrar(z, env):
    """Entra con la contraseña del .env; si todavía rige la de fábrica, la cambia."""
    nueva = env["ZBX_ADMIN_PASSWORD"]
    try:
        z.token = z.call("user.login", {"username": "Admin", "password": nueva})
        return
    except RuntimeError:
        pass
    z.token = z.call("user.login", {"username": "Admin", "password": "zabbix"})
    admin = z.uno("user.get", {"username": ["Admin"]}, ["userid"])
    z.call("user.update", {"userid": admin["userid"], "passwd": nueva, "current_passwd": "zabbix"})
    z.token = z.call("user.login", {"username": "Admin", "password": nueva})
    print("Contraseña de fábrica de Admin reemplazada por la del .env")


def crear_trigger(z, nombre, expresion, severidad, etiquetas, comentario=""):
    existente = z.uno("trigger.get", {"description": [nombre]}, ["triggerid"])
    if existente:
        return existente["triggerid"]
    return z.call("trigger.create", {
        "description": nombre, "expression": expresion, "priority": severidad, "comments": comentario,
        "tags": [{"tag": k, "value": v} for k, v in etiquetas.items()]})["triggerids"][0]


def main():
    env = leer_env()
    z = Zabbix()
    print("Zabbix", z.call("apiinfo.version", {}))
    entrar(z, env)

    # --- Grupo ---
    grupo = z.uno("hostgroup.get", {"name": [GRUPO]})
    gid = grupo["groupid"] if grupo else z.call("hostgroup.create", {"name": GRUPO})["groupids"][0]
    print("Grupo:", GRUPO, gid)

    necesarias = {p for _, _, _, ps in VMS for p in ps} | {PLANTILLA_RED, PLANTILLA_PING}
    plantillas = {t["host"]: t["templateid"] for t in z.call(
        "template.get", {"output": ["host"], "filter": {"host": sorted(necesarias)}})}
    faltan = necesarias - plantillas.keys()
    if faltan:
        sys.exit(f"Faltan plantillas en Zabbix: {faltan}")

    # --- VMs Linux (agente) ---
    hostids = {}
    for host, visible, ip, ps in VMS:
        actual = z.uno("host.get", {"host": [host]}, ["hostid"])
        hostids[host] = actual["hostid"] if actual else z.call("host.create", {
            "host": host, "name": visible, "groups": [{"groupid": gid}],
            "interfaces": [{"type": 1, "main": 1, "useip": 1, "ip": ip, "dns": "", "port": "10050"}],
            "templates": [{"templateid": plantillas[p]} for p in ps],
            "tags": [{"tag": "capa", "value": "vm"}],
        })["hostids"][0]
    print("VMs:", ", ".join(hostids))
    hid = hostids["vm-app"]

    # La plantilla de Nginx consulta "localhost", que en Ubuntu resuelve primero a ::1,
    # y la página de estado solo se permite desde 127.0.0.1: respondía 403.
    macro = "{$NGINX.STUB_STATUS.HOST}"
    if not z.call("usermacro.get", {"output": ["hostmacroid"], "hostids": hid, "filter": {"macro": macro}}):
        z.call("usermacro.create", {"hostid": hid, "macro": macro, "value": "127.0.0.1"})
        print("Macro de Nginx ajustada a 127.0.0.1")

    # --- Router y switch (SNMP v2c de solo lectura) ---
    comunidad = env.get("SNMP_COMMUNITY", "")
    if not comunidad:
        print("AVISO: falta SNMP_COMMUNITY en .env; r1 y sw1 se crean pero no traerán datos")
    for host, visible, ip in RED:
        if z.uno("host.get", {"host": [host]}, ["hostid"]):
            continue
        z.call("host.create", {
            "host": host, "name": visible, "groups": [{"groupid": gid}],
            "interfaces": [{"type": 2, "main": 1, "useip": 1, "ip": ip, "dns": "", "port": "161",
                            "details": {"version": 2, "bulk": 1, "community": "{$SNMP_COMMUNITY}"}}],
            "templates": [{"templateid": plantillas[PLANTILLA_RED]}],
            # type 1 = macro secreta: el frontend no la muestra.
            "macros": [{"macro": "{$SNMP_COMMUNITY}", "value": comunidad, "type": 1}],
            "tags": [{"tag": "capa", "value": "red"}],
        })
    print("Red: r1 y sw1 por SNMP")

    # --- Servidor físico: por ahora solo disponibilidad por ping ---
    if not z.uno("host.get", {"host": ["proxmox"]}, ["hostid"]):
        z.call("host.create", {
            "host": "proxmox", "name": "proxmox (Servidor R450)", "groups": [{"groupid": gid}],
            "interfaces": [{"type": 1, "main": 1, "useip": 1, "ip": "10.10.30.10", "dns": "", "port": "10050"}],
            "templates": [{"templateid": plantillas[PLANTILLA_PING]}],
            "tags": [{"tag": "capa", "value": "servidor"}],
        })
    print("Servidor: proxmox por ping")

    # --- Aplicación: escenario web a través de Nginx, como la ve un usuario ---
    web = z.uno("host.get", {"host": ["msmotos-web"]}, ["hostid"])
    wid = web["hostid"] if web else z.call("host.create", {
        "host": "msmotos-web", "name": "MS Motos (aplicación)",
        "groups": [{"groupid": gid}], "tags": [{"tag": "capa", "value": "aplicacion"}],
    })["hostids"][0]
    if not z.call("httptest.get", {"output": ["httptestid"], "hostids": wid, "filter": {"name": "App MS Motos"}}):
        z.call("httptest.create", {
            "name": "App MS Motos", "hostid": wid, "delay": "30s", "retries": 1,
            "steps": [
                {"name": "health", "url": f"{APP}/api/health", "status_codes": "200",
                 "required": "\"ok\":true", "no": 1, "timeout": "5s"},
                {"name": "frontend", "url": f"{APP}/", "status_codes": "200",
                 "required": "app-root", "no": 2, "timeout": "5s"},
            ],
        })
    t04 = crear_trigger(z, "T04 App MS Motos no disponible",
                        "count(/msmotos-web/web.test.fail[App MS Motos],#2,\"ne\",0)=2", 5,
                        {"remediation": "none", "capa": "aplicacion"})
    crear_trigger(z, "T05 App MS Motos lenta (health > 2 s)",
                  "avg(/msmotos-web/web.test.time[App MS Motos,health,resp],5m)>2", 2,
                  {"remediation": "none", "capa": "aplicacion"})
    print("Escenario web y triggers T04/T05 listos")

    # --- T03: servicio Nginx detenido ---
    clave_nginx = 'systemd.unit.info["nginx.service"]'
    if not z.call("item.get", {"output": ["itemid"], "hostids": hid, "filter": {"key_": clave_nginx}}):
        interfaz = z.call("hostinterface.get", {"output": ["interfaceid"], "hostids": hid})[0]["interfaceid"]
        z.call("item.create", {
            "hostid": hid, "interfaceid": interfaz, "name": "Servicio Nginx: estado",
            "key_": clave_nginx, "type": 0, "value_type": 1, "delay": "30s", "history": "31d",
            "tags": [{"tag": "component", "value": "servicio"}]})
    t03 = crear_trigger(z, "T03 Servicio Nginx detenido",
                        f"find(/vm-app/{clave_nginx},1m,\"regexp\",\"^active$\")=0", 4,
                        {"remediation": "restart-service", "target": "nginx", "capa": "servicio"},
                        "Recuperación automática: n8n inicia el servicio (IP2-53).")
    print("Ítem y trigger T03 listos")

    # --- T01: contenedor detenido (espera el descubrimiento de contenedores) ---
    clave = f'docker.container_info.state.running["/{CONTENEDOR}"]'
    item = None
    candidatos = []
    for intento in range(24):
        candidatos = z.call("item.get", {"output": ["itemid", "key_"], "hostids": hid, "search": {"key_": CONTENEDOR}})
        item = next((i for i in candidatos if i["key_"] == clave), None)
        if item:
            break
        if intento % 4 == 0:
            for r in z.call("discoveryrule.get", {"output": ["itemid"], "hostids": hid}):
                try:
                    z.call("task.create", [{"type": 6, "request": {"itemid": r["itemid"]}}])
                except RuntimeError:
                    pass  # la regla todavía no está en la caché del servidor
            print("Descubrimiento forzado; esperando contenedores...")
        time.sleep(15)
    if not item:
        sys.exit(f"No apareció el ítem {clave}. Claves encontradas: {[c['key_'] for c in candidatos]}")
    t01 = crear_trigger(z, "T01 Contenedor msmotos-app detenido", f"max(/vm-app/{clave},1m)=0", 4,
                        {"remediation": "restart-container", "target": CONTENEDOR, "capa": "contenedor"},
                        "Recuperación automática: n8n inicia el contenedor (IP2-53).")
    print("Trigger T01 listo sobre", clave)

    # --- Causa y síntoma: si el contenedor o Nginx están caídos, T04 es su consecuencia ---
    # Con la dependencia, Zabbix muestra la causa (T01 o T03) y no abre además T04.
    z.call("trigger.update", {"triggerid": t04, "dependencies": [{"triggerid": t01}, {"triggerid": t03}]})
    print("T04 depende de T01 y T03")

    # --- Usuario de solo lectura para Grafana ---
    rol = z.uno("role.get", {"name": ["Solo lectura Grafana"]}, ["roleid"])
    rid = rol["roleid"] if rol else z.call("role.create", {"name": "Solo lectura Grafana", "type": 1})["roleids"][0]
    ugrupo = z.uno("usergroup.get", {"name": ["Grafana lectura"]}, ["usrgrpid"])
    ugid = ugrupo["usrgrpid"] if ugrupo else z.call("usergroup.create", {
        "name": "Grafana lectura", "gui_access": 3,
        "hostgroup_rights": [{"id": gid, "permission": 2}]})["usrgrpids"][0]
    if not z.uno("user.get", {"username": [env["ZABBIX_API_USER"]]}, ["userid"]):
        z.call("user.create", {"username": env["ZABBIX_API_USER"], "passwd": env["ZABBIX_API_PASSWORD"],
                               "roleid": rid, "usrgrps": [{"usrgrpid": ugid}]})
    print("Usuario de Grafana listo (solo lectura sobre", GRUPO + ")")

    # --- Host por defecto "Zabbix server": se deshabilita ---
    # Apunta a 127.0.0.1:10050 dentro del contenedor, donde no hay agente, y deja un
    # problema permanente. vm-zabbix ya se vigila con su propio agente.
    defecto = z.uno("host.get", {"host": ["Zabbix server"]}, ["hostid", "status"])
    if defecto and defecto["status"] == "0":
        z.call("host.update", {"hostid": defecto["hostid"], "status": 1})
        print("Host de ejemplo 'Zabbix server' deshabilitado (no tiene agente)")

    # --- Ítems de la plantilla de Docker que ninguna versión moderna puede reportar ---
    sin_soporte = ["docker.kernel_mem.enabled", "docker.kernel_mem_tcp.enabled"]
    apagar = [i["itemid"] for i in z.call("item.get", {
        "output": ["itemid"], "hostids": hid, "filter": {"key_": sin_soporte, "status": "0"}})]
    if apagar:
        z.call("item.update", [{"itemid": i, "status": 1} for i in apagar])
        print(f"Ítems de memoria del kernel de Docker deshabilitados ({len(apagar)}): Docker ya no los expone")

    print(f"Listo. Llamadas a la API: {z.n}")


if __name__ == "__main__":
    main()
