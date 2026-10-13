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
  - Router R1 y switch SW1 por SNMP
  - Servidor Proxmox por ping y, si el .env trae su token, por la API (nodo, VMs y discos)
  - Host msmotos-web con el escenario web contra la aplicación
  - Triggers T01 (contenedor), T03 (Nginx), T04 y T05 (aplicación)
  - Host "automatizacion" con los ítems que n8n reporta de cada ejecución
  - Usuario de solo lectura para Grafana
  - Media type "Webhook n8n", la acción que le envía los problemas, y el usuario
    y token de API con que n8n deja constancia en cada evento

La réplica de infra/lab-local tiene su propio configurador: allá los nombres de red
son los de Docker y aquí son las direcciones de la VLAN 30.
"""
import json
import secrets
import sys
import time
import urllib.request
from pathlib import Path

URL = "http://127.0.0.1/api_jsonrpc.php"
AQUI = Path(__file__).resolve().parent
GRUPO = "Integrador II"
CONTENEDOR = "msmotos-app"
APP = "http://10.10.30.11"
WEBHOOK_N8N = "http://10.10.30.14:5678/webhook/zabbix"

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
# Cliente sintético (RPA). El nombre visible lleva "rpa": los tableros filtran por él.
# host, nombre visible, dirección desde la que se aceptan sus datos
RPA_HOSTS = [
    ("msmotos-rpa-linux", "msmotos-rpa-linux (Cliente sintético · Linux)", "10.10.30.15"),
]
# recorrido: (pasos, segundos a partir de los cuales es lento, tiempo sin datos que alerta)
RPA_RECORRIDOS = {
    "consulta": (["abrir", "login", "inicio", "motos", "citas", "logout"], 10, "15m"),
    "agendar": (["abrir", "login", "elegir", "reservar", "verificar", "cancelar", "logout"], 20, "75m"),
}
# Lo que n8n reporta de sus ejecuciones: un juego de ítems por tipo de recuperación.
N8N_TIPOS = ["servicio", "contenedor"]
N8N_ORIGEN = "10.10.30.14"
PLANTILLA_RED = "Cisco IOS by SNMP"
PLANTILLA_PING = "ICMP Ping"
PLANTILLA_PVE = "Proxmox VE by HTTP"
# Token de solo lectura que crea infra/proxmox/token-zabbix.sh en el servidor.
PVE_HOST = "10.10.30.10"
PVE_TOKEN_ID = "zabbix@pve!monitoreo"


def leer_env():
    valores = {}
    for linea in (AQUI / ".env").read_text(encoding="utf-8").splitlines():
        if "=" in linea and not linea.lstrip().startswith("#"):
            k, v = linea.split("=", 1)
            valores[k.strip()] = v.strip()
    return valores


def agregar_env(comentario, clave, valor):
    """Agrega una variable al .env (que ya existe con permisos 600)."""
    with open(AQUI / ".env", "a", encoding="utf-8", newline="\n") as f:
        f.write(f"# {comentario}\n{clave}={valor}\n")


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


def crear_trigger(z, nombre, expresion, severidad, etiquetas, comentario="", host=None, opdata=""):
    """Crea el trigger si no existe. Con `host`, el mismo nombre puede repetirse en cada host."""
    busqueda = {"output": ["triggerid"], "filter": {"description": [nombre]}}
    if host:
        busqueda["host"] = host
    existente = z.call("trigger.get", busqueda)
    if existente:
        return existente[0]["triggerid"]
    return z.call("trigger.create", {
        "description": nombre, "expression": expresion, "priority": severidad, "comments": comentario,
        "opdata": opdata, "tags": [{"tag": k, "value": v} for k, v in etiquetas.items()]})["triggerids"][0]


def main():
    env = leer_env()
    z = Zabbix()
    print("Zabbix", z.call("apiinfo.version", {}))
    entrar(z, env)

    # --- Grupo ---
    grupo = z.uno("hostgroup.get", {"name": [GRUPO]})
    gid = grupo["groupid"] if grupo else z.call("hostgroup.create", {"name": GRUPO})["groupids"][0]
    print("Grupo:", GRUPO, gid)

    necesarias = {p for _, _, _, ps in VMS for p in ps} | {PLANTILLA_RED, PLANTILLA_PING, PLANTILLA_PVE}
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

    # --- Servidor físico: disponibilidad por ping y métricas por la API de Proxmox ---
    pve = z.uno("host.get", {"host": ["proxmox"]}, ["hostid"])
    pid = pve["hostid"] if pve else z.call("host.create", {
        "host": "proxmox", "name": "proxmox (Servidor R450)", "groups": [{"groupid": gid}],
        "interfaces": [{"type": 1, "main": 1, "useip": 1, "ip": PVE_HOST, "dns": "", "port": "10050"}],
        "templates": [{"templateid": plantillas[PLANTILLA_PING]}],
        "tags": [{"tag": "capa", "value": "servidor"}],
    })["hostids"][0]
    secreto = env.get("PVE_TOKEN_SECRET", "")
    if not secreto:
        print("Servidor: proxmox solo por ping (falta PVE_TOKEN_SECRET en .env; ver infra/proxmox/token-zabbix.sh)")
    else:
        # El secreto va como macro secreta (type 1). Se reescribe siempre, por si el token cambió.
        # La memoria de una VM vista desde el hipervisor no es la que usa el sistema de adentro
        # (cuenta la caché de Linux, y Windows sin controlador de globo aparece siempre al
        # 100 %): con 200 esa alerta de la plantilla no dispara. La memoria real la vigila T07.
        macros = {"{$PVE.URL.HOST}": (PVE_HOST, 0), "{$PVE.TOKEN.ID}": (PVE_TOKEN_ID, 0),
                  "{$PVE.TOKEN.SECRET}": (secreto, 1), "{$PVE.VM.MEMORY.PUSE.MAX.WARN}": ("200", 0)}
        actuales = {m["macro"]: m["hostmacroid"] for m in z.call(
            "usermacro.get", {"output": ["hostmacroid", "macro"], "hostids": pid})}
        for macro, (valor, tipo) in macros.items():
            if macro in actuales:
                z.call("usermacro.update", {"hostmacroid": actuales[macro], "value": valor, "type": tipo})
            else:
                z.call("usermacro.create", {"hostid": pid, "macro": macro, "value": valor, "type": tipo})
        z.call("host.update", {"hostid": pid, "templates": [
            {"templateid": plantillas[PLANTILLA_PING]}, {"templateid": plantillas[PLANTILLA_PVE]}]})
        print("Servidor: proxmox por ping y por la API (nodo, VMs y almacenamiento)")

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

    # --- T06 a T08: capacidad de las VMs. Solo alertan: nadie amplía recursos en automático ---
    # (nombre, clave del ítem de la plantilla, función, umbral de advertencia, umbral alto)
    capacidad = [
        ("T06 CPU alta", "system.cpu.util", "avg({},5m)", 85, 95, "promedio de 5 min"),
        ("T07 Memoria alta", "vm.memory.util", "avg({},5m)", 85, 95, "promedio de 5 min"),
        ("T08 Disco / lleno", "vfs.fs.dependent.size[/,pused]", "last({})", 80, 90, "última lectura"),
    ]
    for host, _, _, _ in VMS:
        for nombre, clave, funcion, aviso, alto, ventana in capacidad:
            etiquetas = {"remediation": "none", "capa": "capacidad"}
            valor = funcion.format(f"/{host}/{clave}")
            grave = crear_trigger(z, f"{nombre} en {{HOST.HOST}} (> {alto} %, {ventana})", f"{valor}>{alto}", 4,
                                  etiquetas, host=host, opdata="{ITEM.LASTVALUE1}")
            leve = crear_trigger(z, f"{nombre} en {{HOST.HOST}} (> {aviso} %, {ventana})", f"{valor}>{aviso}", 2,
                                 etiquetas, host=host, opdata="{ITEM.LASTVALUE1}")
            # Si ya está abierto el nivel alto, no hace falta mostrar además la advertencia.
            z.call("trigger.update", {"triggerid": leve, "dependencies": [{"triggerid": grave}]})
    print("Capacidad: T06 a T08 listos en las cinco VMs")

    # --- Cliente sintético (RPA): ítems que recibe de rpa/ejecutar.py y sus triggers ---
    for host, visible, origen in RPA_HOSTS:
        actual = z.uno("host.get", {"host": [host]}, ["hostid"])
        rid_host = actual["hostid"] if actual else z.call("host.create", {
            "host": host, "name": visible, "groups": [{"groupid": gid}],
            "tags": [{"tag": "capa", "value": "experiencia"}]})["hostids"][0]
        existentes = {i["key_"] for i in z.call("item.get", {"output": ["key_"], "hostids": rid_host})}
        nuevos = []
        for recorrido, (pasos, _, _) in RPA_RECORRIDOS.items():
            # (clave, nombre, tipo de valor, unidad). Tipos: 0 decimal, 1 texto corto, 3 entero, 4 texto.
            nuevos += [
                (f"rpa.status[{recorrido}]", f"RPA: resultado · {recorrido}", 3, ""),
                (f"rpa.duration.total[{recorrido}]", f"RPA: duración total · {recorrido}", 0, "s"),
                (f"rpa.failed_step[{recorrido}]", f"RPA: paso fallido · {recorrido}", 1, ""),
                (f"rpa.error[{recorrido}]", f"RPA: último error · {recorrido}", 4, ""),
            ] + [(f"rpa.step[{recorrido},{p}]", f"RPA: duración del paso {p} · {recorrido}", 0, "s") for p in pasos]
        for clave, nombre, tipo, unidad in nuevos:
            if clave not in existentes:
                # type 2 = trapper. trapper_hosts: solo la VM del robot puede escribir estos datos.
                z.call("item.create", {"hostid": rid_host, "name": nombre, "key_": clave, "type": 2,
                                       "value_type": tipo, "units": unidad, "trapper_hosts": origen,
                                       "history": "31d", "tags": [{"tag": "component", "value": "rpa"}]})
        for recorrido, (_, lento, sin_datos) in RPA_RECORRIDOS.items():
            etiquetas = {"remediation": "none", "capa": "experiencia", "recorrido": recorrido}
            # El paso fallido entra en la expresión solo para poder mostrarlo en la alerta.
            if not z.uno("trigger.get", {"description": [f"T12 El cliente no pudo completar: {recorrido} ({host})"]}, ["triggerid"]):
                z.call("trigger.create", {
                    "description": f"T12 El cliente no pudo completar: {recorrido} ({host})", "priority": 4,
                    "expression": f"last(/{host}/rpa.status[{recorrido}])=0 and length(last(/{host}/rpa.failed_step[{recorrido}]))>=0",
                    "opdata": "Paso: {ITEM.LASTVALUE2}",
                    "comments": "El detalle está en el ítem «RPA: último error» y la captura en /opt/rpa/salidas de vm-rpa.",
                    "tags": [{"tag": k, "value": v} for k, v in etiquetas.items()]})
            crear_trigger(z, f"T13 Recorrido lento: {recorrido} > {lento} s ({host})",
                          f"last(/{host}/rpa.duration.total[{recorrido}])>{lento}", 2, etiquetas)
            crear_trigger(z, f"T14 El robot dejó de reportar: {recorrido} ({host})",
                          f"nodata(/{host}/rpa.status[{recorrido}],{sin_datos})=1", 2, etiquetas,
                          "El recorrido no envió resultados: revisar los temporizadores en vm-rpa.")
    print("Cliente sintético: ítems y triggers T12 a T14 listos")

    # --- Automatización: lo que n8n reporta de cada ejecución (IP2-77) ---
    # El tablero de Automatización filtra por estos nombres ("n8n: ...") y por el host.
    actual = z.uno("host.get", {"host": ["automatizacion"]}, ["hostid"])
    aid = actual["hostid"] if actual else z.call("host.create", {
        "host": "automatizacion", "name": "Automatización (n8n)", "groups": [{"groupid": gid}],
        "tags": [{"tag": "capa", "value": "automatizacion"}]})["hostids"][0]
    existentes = {i["key_"] for i in z.call("item.get", {"output": ["key_"], "hostids": aid})}
    nuevos = [("n8n.rejected", "n8n: acciones rechazadas", 3, ""),
              ("n8n.escalated", "n8n: escalamientos a una persona", 3, "")]
    for tipo in N8N_TIPOS:
        nuevos += [
            (f"n8n.exec.status[{tipo}]", f"n8n: resultado · {tipo}", 3, ""),
            (f"n8n.exec.duration[{tipo}]", f"n8n: duración · {tipo}", 0, "s"),
            (f"n8n.exec.action[{tipo}]", f"n8n: última acción · {tipo}", 4, ""),
            (f"n8n.recovery.count[{tipo}]", f"n8n: recuperaciones · {tipo}", 3, ""),
            (f"n8n.recovery.seconds[{tipo}]", f"n8n: tiempo hasta la recuperación · {tipo}", 0, "s"),
        ]
    for clave, nombre, tipo, unidad in nuevos:
        if clave not in existentes:
            # Trapper: los escribe n8n por la API (history.push), solo desde su VM.
            z.call("item.create", {"hostid": aid, "name": nombre, "key_": clave, "type": 2,
                                   "value_type": tipo, "units": unidad, "trapper_hosts": N8N_ORIGEN,
                                   "history": "31d", "tags": [{"tag": "component", "value": "n8n"}]})
    print("Automatización: host e ítems de n8n listos")

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

    # --- Webhook hacia n8n (control C5: el aviso lleva un token que n8n comprueba) ---
    if not env.get("N8N_WEBHOOK_TOKEN"):
        env["N8N_WEBHOOK_TOKEN"] = secrets.token_urlsafe(32)
        agregar_env("Token que Zabbix envía a n8n en cada aviso (va también al .env de vm-n8n).",
                    "N8N_WEBHOOK_TOKEN", env["N8N_WEBHOOK_TOKEN"])
    script = r"""
var p = JSON.parse(value);
var req = new HttpRequest();
req.addHeader('Content-Type: application/json');
req.addHeader('X-Zabbix-Token: ' + p.token);
var cuerpo = {
  event_id: p.event_id, event_value: p.event_value, severity: p.severity,
  host: p.host, trigger: p.trigger, opdata: p.opdata, tags: p.tags, time: p.time,
  duration: p.duration
};
var resp = req.post(p.url, JSON.stringify(cuerpo));
if (req.getStatus() < 200 || req.getStatus() >= 300) {
  throw 'n8n respondio ' + req.getStatus() + ': ' + resp;
}
return 'OK';
"""
    parametros = [
        {"name": "url", "value": WEBHOOK_N8N},
        {"name": "token", "value": env["N8N_WEBHOOK_TOKEN"]},
        {"name": "event_id", "value": "{EVENT.ID}"},
        {"name": "event_value", "value": "{EVENT.VALUE}"},
        {"name": "severity", "value": "{EVENT.SEVERITY}"},
        {"name": "host", "value": "{HOST.HOST}"},
        {"name": "trigger", "value": "{EVENT.NAME}"},
        {"name": "opdata", "value": "{EVENT.OPDATA}"},
        {"name": "tags", "value": "{EVENT.TAGSJSON}"},
        {"name": "time", "value": "{EVENT.DATE} {EVENT.TIME}"},
        # Cuánto lleva abierto el problema; en el aviso de cierre, cuánto duró.
        {"name": "duration", "value": "{EVENT.DURATION}"},
    ]
    mt = z.uno("mediatype.get", {"name": ["Webhook n8n"]}, ["mediatypeid"])
    # status 0 = habilitado. Sin indicarlo, la API lo crea deshabilitado y las alertas
    # quedan como "Media type disabled" sin llegar a n8n.
    datos_mt = {"name": "Webhook n8n", "type": 4, "status": 0, "script": script, "parameters": parametros, "timeout": "15s",
                "message_templates": [
                    {"eventsource": 0, "recovery": 0, "subject": "Problema: {EVENT.NAME}", "message": "{EVENT.NAME}"},
                    {"eventsource": 0, "recovery": 1, "subject": "Resuelto: {EVENT.NAME}", "message": "{EVENT.NAME}"}]}
    if mt:
        datos_mt["mediatypeid"] = mt["mediatypeid"]
        z.call("mediatype.update", datos_mt)
        mtid = mt["mediatypeid"]
    else:
        mtid = z.call("mediatype.create", datos_mt)["mediatypeids"][0]
    admin = z.uno("user.get", {"username": ["Admin"]}, ["userid"])
    z.call("user.update", {"userid": admin["userid"], "medias": [
        {"mediatypeid": mtid, "sendto": "n8n", "active": 0, "severity": 63, "period": "1-7,00:00-24:00"}]})
    if not z.uno("action.get", {"name": ["Enviar problemas a n8n"]}, ["actionid"]):
        z.call("action.create", {
            "name": "Enviar problemas a n8n", "eventsource": 0, "status": 0, "esc_period": "1m",
            # Solo el grupo del proyecto: un host ajeno no dispara la automatización.
            "filter": {"evaltype": 0, "conditions": [{"conditiontype": 0, "operator": 0, "value": gid}]},
            "operations": [{"operationtype": 0, "opmessage": {"default_msg": 1, "mediatypeid": mtid},
                            "opmessage_usr": [{"userid": admin["userid"]}]}],
            "recovery_operations": [{"operationtype": 11, "opmessage": {"default_msg": 1}}],
        })
    print("Media type 'Webhook n8n' y acción listos ->", WEBHOOK_N8N)

    # --- Usuario y token de API para n8n (constancia en cada evento: control C6) ---
    if not env.get("ZABBIX_N8N_TOKEN"):
        rol_admin = z.uno("role.get", {"name": ["Admin role"]}, ["roleid"])
        grupo_n8n = z.uno("usergroup.get", {"name": ["n8n automatizacion"]}, ["usrgrpid"])
        gnid = grupo_n8n["usrgrpid"] if grupo_n8n else z.call("usergroup.create", {
            "name": "n8n automatizacion", "gui_access": 3,
            "hostgroup_rights": [{"id": gid, "permission": 3}]})["usrgrpids"][0]
        usuario = z.uno("user.get", {"username": ["n8n"]}, ["userid"])
        uid = usuario["userid"] if usuario else z.call("user.create", {
            "username": "n8n", "roleid": rol_admin["roleid"], "usrgrps": [{"usrgrpid": gnid}]})["userids"][0]
        viejos = z.call("token.get", {"output": ["tokenid"], "userids": uid, "filter": {"name": "n8n"}})
        if viejos:
            z.call("token.delete", [v["tokenid"] for v in viejos])
        tid = z.call("token.create", {"name": "n8n", "userid": uid})["tokenids"][0]
        valor = z.call("token.generate", [tid])[0]["token"]
        agregar_env("Token de API de Zabbix para n8n (va también al .env de vm-n8n).", "ZABBIX_N8N_TOKEN", valor)
        print("Token de API para n8n creado y guardado en .env")
    else:
        print("Token de API para n8n ya existe en .env")

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
