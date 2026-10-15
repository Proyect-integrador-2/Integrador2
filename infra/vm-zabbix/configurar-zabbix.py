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
  - Las dos VMs Windows por agente, el servicio MSMotos (T03-W) y el escenario web de
    la instancia Windows (T04-W, T05-W)
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
# Por HTTPS desde el 14 oct 2026 (IP2-90); el puerto 80 solo redirige.
APP = "https://10.10.30.11"
APP_WIN = "http://10.10.30.16"
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
# VMs Windows Server: host, nombre visible, dirección
WINDOWS = [
    ("vm-app-win", "vm-app-win (App MS Motos · Windows)", "10.10.30.16"),
    ("vm-dc", "vm-dc (Controlador de dominio)", "10.10.30.17"),
]
PLANTILLA_WINDOWS = "Windows by Zabbix agent"
# host, nombre visible, dirección
RED = [
    ("r1", "r1 (Router ISR 4221)", "10.10.30.1"),
    ("sw1", "sw1 (Switch 2960)", "10.10.99.2"),
]
# Cliente sintético (RPA). El nombre visible lleva "rpa": los tableros filtran por él.
# host, nombre visible, dirección desde la que se aceptan sus datos
RPA_HOSTS = [
    ("msmotos-rpa-linux", "msmotos-rpa-linux (Cliente sintético · Linux)", "10.10.30.15"),
    ("msmotos-rpa-windows", "msmotos-rpa-windows (Cliente sintético · Windows)", "10.10.30.15"),
]
# recorrido: (pasos, segundos a partir de los cuales es lento, tiempo sin datos que alerta)
RPA_RECORRIDOS = {
    "consulta": (["abrir", "login", "inicio", "motos", "citas", "logout"], 10, "15m"),
    "agendar": (["abrir", "login", "elegir", "reservar", "verificar", "cancelar", "logout"], 20, "75m"),
}
# Lo que n8n reporta de sus ejecuciones: un juego de ítems por tipo de recuperación.
N8N_TIPOS = ["servicio", "contenedor", "servicio-win", "interfaz"]
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


def crear_trigger(z, nombre, expresion, severidad, etiquetas, comentario="", host=None, opdata="", forzar=False):
    """Crea el trigger si no existe. Con `host`, el mismo nombre puede repetirse en cada host.
    Con `forzar`, si ya existe le pone la expresión de aquí (para cambios de condición)."""
    busqueda = {"output": ["triggerid"], "filter": {"description": [nombre]}}
    if host:
        busqueda["host"] = host
    existente = z.call("trigger.get", busqueda)
    if existente:
        if forzar:
            z.call("trigger.update", {"triggerid": existente[0]["triggerid"], "expression": expresion})
        return existente[0]["triggerid"]
    return z.call("trigger.create", {
        "description": nombre, "expression": expresion, "priority": severidad, "comments": comentario,
        "opdata": opdata, "tags": [{"tag": k, "value": v} for k, v in etiquetas.items()]})["triggerids"][0]


def disponibilidad(z, hostid, escenario):
    """Ítem calculado: 100 si el escenario web pasó todos sus pasos, 0 si falló alguno.

    El tablero General promedia este ítem. Antes tomaba el código HTTP por 0,5, y un 502
    durante una caída daba más de 100 %.
    """
    clave = "app.disponibilidad"
    if z.call("item.get", {"output": ["itemid"], "hostids": hostid, "filter": {"key_": clave}}):
        return
    z.call("item.create", {
        "hostid": hostid, "name": "Disponibilidad de la app", "key_": clave, "type": 15, "value_type": 0,
        "units": "%", "delay": "30s", "history": "31d", "trends": "365d",
        "params": f"100*(last(//web.test.fail[{escenario}])=0)",
        "tags": [{"tag": "component", "value": "aplicacion"}]})


def main():
    env = leer_env()
    z = Zabbix()
    print("Zabbix", z.call("apiinfo.version", {}))
    entrar(z, env)

    # --- Grupo ---
    grupo = z.uno("hostgroup.get", {"name": [GRUPO]})
    gid = grupo["groupid"] if grupo else z.call("hostgroup.create", {"name": GRUPO})["groupids"][0]
    print("Grupo:", GRUPO, gid)

    necesarias = {p for _, _, _, ps in VMS for p in ps} | {PLANTILLA_RED, PLANTILLA_PING, PLANTILLA_PVE, PLANTILLA_WINDOWS}
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
        # T21: el servidor deja de mandar datos por la API. Sin esto, si Zabbix pierde la API
        # (el 14-oct pasó casi 2 horas) no avisa nada: la plantilla no lo ve como problema.
        cpu = "proxmox.node.cpu[pve]"
        if z.call("item.get", {"output": ["itemid"], "hostids": pid, "filter": {"key_": cpu}}):
            crear_trigger(z, "T21 Sin datos del servidor Proxmox por la API", f"nodata(/proxmox/{cpu},10m)=1", 4,
                          {"remediation": "none", "capa": "servidor"},
                          "Zabbix no recibe métricas de Proxmox hace 10 minutos. Revisar que el servidor "
                          "responda en el 8006 y el token; si responde, reiniciar el contenedor zabbix-server.")
            print("T21 listo (sin datos de Proxmox)")
        else:
            print("T21 pendiente: la plantilla aún no descubrió el nodo; volver a correr el script")

    # --- Aplicación: escenario web a través de Nginx, como la ve un usuario ---
    web = z.uno("host.get", {"host": ["msmotos-web"]}, ["hostid"])
    wid = web["hostid"] if web else z.call("host.create", {
        "host": "msmotos-web", "name": "MS Motos (aplicación)",
        "groups": [{"groupid": gid}], "tags": [{"tag": "capa", "value": "aplicacion"}],
    })["hostids"][0]
    pasos = [
        {"name": "health", "url": f"{APP}/api/health", "status_codes": "200",
         "required": "\"ok\":true", "no": 1, "timeout": "5s"},
        {"name": "frontend", "url": f"{APP}/", "status_codes": "200",
         "required": "app-root", "no": 2, "timeout": "5s"},
    ]
    escenario = z.call("httptest.get", {"output": ["httptestid"], "hostids": wid, "filter": {"name": "App MS Motos"},
                                        "selectSteps": ["url"]})
    if not escenario:
        z.call("httptest.create", {"name": "App MS Motos", "hostid": wid, "delay": "30s", "retries": 1, "steps": pasos})
    elif escenario[0]["steps"][0]["url"] != pasos[0]["url"]:
        # La dirección cambió (pasó a HTTPS): se actualizan los pasos.
        z.call("httptest.update", {"httptestid": escenario[0]["httptestid"], "steps": pasos})
    # T04 espera 90 s de fallos seguidos: así T01 (contenedor, ~75 s) o T03 (Nginx, ~65 s) ya
    # están abiertos cuando se evalúa, y la dependencia lo oculta. Con dos fallos (~45 s) se
    # abría antes que la causa. Una caída sin causa conocida se ve igual en menos de 2 minutos.
    disponibilidad(z, wid, "App MS Motos")
    t04 = crear_trigger(z, "T04 App MS Motos no disponible",
                        "min(/msmotos-web/web.test.fail[App MS Motos],90s)>0", 5,
                        {"remediation": "none", "capa": "aplicacion"}, forzar=True)
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
            # Trapper: los escribe n8n por la API (history.push). Sin lista de orígenes: por la
            # API Zabbix no ve la dirección de n8n, y lo que limita quién escribe es el token
            # de n8n, que solo tiene permiso sobre el grupo del proyecto.
            z.call("item.create", {"hostid": aid, "name": nombre, "key_": clave, "type": 2,
                                   "value_type": tipo, "units": unidad, "trapper_hosts": "",
                                   "history": "31d", "tags": [{"tag": "component", "value": "n8n"}]})
    con_origen = z.call("item.get", {"output": ["itemid", "trapper_hosts"], "hostids": aid})
    for item in con_origen:
        if item["trapper_hosts"]:
            z.call("item.update", {"itemid": item["itemid"], "trapper_hosts": ""})
    print("Automatización: host e ítems de n8n listos")

    # --- VMs Windows (IP2-75, IP2-82): agente, servicio de la aplicación y escenario web ---
    for host, visible, ip in WINDOWS:
        if not z.uno("host.get", {"host": [host]}, ["hostid"]):
            z.call("host.create", {
                "host": host, "name": visible, "groups": [{"groupid": gid}],
                "interfaces": [{"type": 1, "main": 1, "useip": 1, "ip": ip, "dns": "", "port": "10050"}],
                "templates": [{"templateid": plantillas[PLANTILLA_WINDOWS]}],
                "tags": [{"tag": "capa", "value": "vm"}]})
    # La plantilla alerta por cada servicio automático detenido, menos los de una lista.
    # StateRepository arranca y se detiene solo según la demanda: se suma a esa lista.
    macro = "{$SERVICE.NAME.NOT_MATCHES}"
    base = z.call("usermacro.get", {"output": ["value"], "hostids": plantillas[PLANTILLA_WINDOWS],
                                    "filter": {"macro": macro}})
    if base and "(?:" in base[0]["value"]:
        valor = base[0]["value"].replace("(?:", "(?:StateRepository|", 1)
        for host, _, _ in WINDOWS:
            hw = z.uno("host.get", {"host": [host]}, ["hostid"])["hostid"]
            if not z.call("usermacro.get", {"output": ["hostmacroid"], "hostids": hw, "filter": {"macro": macro}}):
                z.call("usermacro.create", {"hostid": hw, "macro": macro, "value": valor})
                # Que el descubrimiento de servicios corra ya con la lista nueva.
                for regla in z.call("discoveryrule.get", {"output": ["itemid"], "hostids": hw,
                                                          "search": {"key_": "service.discovery"}}):
                    try:
                        z.call("task.create", [{"type": 6, "request": {"itemid": regla["itemid"]}}])
                    except RuntimeError:
                        pass
    wvm = z.uno("host.get", {"host": ["vm-app-win"]}, ["hostid"])["hostid"]
    # service.info devuelve 0 cuando el servicio está en ejecución y 6 cuando está detenido.
    clave_servicio = "service.info[MSMotos,state]"
    if not z.call("item.get", {"output": ["itemid"], "hostids": wvm, "filter": {"key_": clave_servicio}}):
        interfaz = z.call("hostinterface.get", {"output": ["interfaceid"], "hostids": wvm})[0]["interfaceid"]
        z.call("item.create", {
            "hostid": wvm, "interfaceid": interfaz, "name": "Servicio MSMotos: estado (0 = en ejecución)",
            "key_": clave_servicio, "type": 0, "value_type": 3, "delay": "30s", "history": "31d",
            "tags": [{"tag": "component", "value": "servicio"}]})
    etiquetas_w = {"remediation": "restart-service-win", "target": "MSMotos", "capa": "servicio"}
    t03w = crear_trigger(z, "T03-W Servicio MSMotos detenido (Windows)", f"min(/vm-app-win/{clave_servicio},1m)<>0", 4,
                         etiquetas_w, "Recuperación automática: n8n inicia el servicio de Windows (IP2-74).",
                         opdata="estado {ITEM.LASTVALUE1}")
    # crear_trigger no toca uno que ya existe: las etiquetas se fijan siempre.
    z.call("trigger.update", {"triggerid": t03w, "tags": [{"tag": k, "value": v} for k, v in etiquetas_w.items()],
                              "comments": "Recuperación automática: n8n inicia el servicio de Windows (IP2-74)."})

    web = z.uno("host.get", {"host": ["msmotos-web-win"]}, ["hostid"])
    wwid = web["hostid"] if web else z.call("host.create", {
        "host": "msmotos-web-win", "name": "MS Motos (aplicación · Windows)",
        "groups": [{"groupid": gid}], "tags": [{"tag": "capa", "value": "aplicacion"}],
    })["hostids"][0]
    if not z.call("httptest.get", {"output": ["httptestid"], "hostids": wwid, "filter": {"name": "App MS Motos Windows"}}):
        z.call("httptest.create", {
            "name": "App MS Motos Windows", "hostid": wwid, "delay": "30s", "retries": 1,
            "steps": [
                {"name": "health", "url": f"{APP_WIN}/api/health", "status_codes": "200",
                 "required": "\"ok\":true", "no": 1, "timeout": "5s"},
                {"name": "frontend", "url": f"{APP_WIN}/", "status_codes": "200",
                 "required": "app-root", "no": 2, "timeout": "5s"},
            ],
        })
    disponibilidad(z, wwid, "App MS Motos Windows")
    t04w = crear_trigger(z, "T04-W App MS Motos no disponible (Windows)",
                         "min(/msmotos-web-win/web.test.fail[App MS Motos Windows],90s)>0", 5,
                         {"remediation": "none", "capa": "aplicacion"}, forzar=True)
    # Si el servicio está detenido, que la aplicación no responda es su consecuencia.
    z.call("trigger.update", {"triggerid": t04w, "dependencies": [{"triggerid": t03w}]})
    crear_trigger(z, "T05-W App MS Motos lenta en Windows (health > 2 s)",
                  "avg(/msmotos-web-win/web.test.time[App MS Motos Windows,health,resp],5m)>2", 2,
                  {"remediation": "none", "capa": "aplicacion"})
    print("Windows: vm-app-win y vm-dc por agente, servicio MSMotos (T03-W) y escenario web (T04-W, T05-W)")

    # --- Controlador de dominio (IP2-82): sus servicios y los eventos de seguridad ---
    # Estas alertas solo avisan: ninguna acción automática toca cuentas de usuario.
    dc = z.uno("host.get", {"host": ["vm-dc"]}, ["hostid"])["hostid"]
    interfaz = z.call("hostinterface.get", {"output": ["interfaceid"], "hostids": dc})[0]["interfaceid"]
    existentes = {i["key_"] for i in z.call("item.get", {"output": ["key_"], "hostids": dc})}
    servicios = [("NTDS", "Active Directory"), ("DNS", "DNS"), ("Kdc", "Kerberos")]
    for servicio, nombre in servicios:
        clave = f"service.info[{servicio},state]"
        if clave not in existentes:
            z.call("item.create", {
                "hostid": dc, "interfaceid": interfaz, "name": f"Servicio {nombre}: estado (0 = en ejecución)",
                "key_": clave, "type": 0, "value_type": 3, "delay": "30s", "history": "31d",
                "tags": [{"tag": "component", "value": "dominio"}]})
    identidad = {"remediation": "none", "capa": "identidad"}
    crear_trigger(z, "T15 Servicio del dominio caído en vm-dc",
                  " or ".join(f"min(/vm-dc/service.info[{s},state],1m)<>0" for s, _ in servicios), 4, identidad,
                  "Active Directory, DNS o Kerberos no están en ejecución: nadie puede validar su cuenta.")

    # Eventos del registro de seguridad. El agente los envía él mismo (chequeo activo) y de
    # cada evento se guarda solo el nombre de la cuenta, que es lo que hace falta en la alerta.
    eventos = [
        ("eventlog[Security,,,,4625,,skip]", "Seguridad: inicio de sesión fallido (cuenta)",
         r"Account For Which Logon Failed:[\s\S]*?Account Name:\s+(\S+)"),
        ("eventlog[Security,,,,4740,,skip]", "Seguridad: cuenta bloqueada (cuenta)",
         r"Account That Was Locked Out:[\s\S]*?Account Name:\s+(\S+)"),
    ]
    for clave, nombre, patron in eventos:
        if clave not in existentes:
            z.call("item.create", {
                "hostid": dc, "name": nombre, "key_": clave, "type": 7, "value_type": 2, "delay": "30s",
                "history": "31d", "tags": [{"tag": "component", "value": "seguridad"}],
                # type 5 = expresión regular; si no encuentra la cuenta, guarda "desconocida".
                "preprocessing": [{"type": 5, "params": patron + "\n\\1", "error_handler": 2,
                                   "error_handler_params": "desconocida"}]})
    # "and now()>0" no cambia la condición: obliga a Zabbix a recalcular el trigger cada
    # 30 segundos. Sin eso solo lo recalcula cuando llega un evento nuevo, y una alerta
    # de este tipo se quedaría abierta hasta el siguiente inicio de sesión fallido.
    seguridad = [
        ("T16 Muchos inicios de sesión fallidos en el dominio (más de 10 en 5 min)",
         f"count(/vm-dc/{eventos[0][0]},5m)>10 and now()>0",
         "Posible intento de adivinar contraseñas. Revisar el registro de seguridad de vm-dc.",
         "última cuenta: {ITEM.LASTVALUE1}"),
        ("T17 Cuenta del dominio bloqueada",
         f"count(/vm-dc/{eventos[1][0]},15m)>0 and now()>0",
         "El dominio bloqueó una cuenta por intentos fallidos (política de 5 intentos).",
         "cuenta: {ITEM.LASTVALUE1}"),
    ]
    for nombre, expresion, comentario, dato in seguridad:
        tid = crear_trigger(z, nombre, expresion, 2, identidad, comentario, opdata=dato)
        # crear_trigger no toca uno que ya existe: la expresión se fija siempre.
        z.call("trigger.update", {"triggerid": tid, "expression": expresion})
    print("Dominio: servicios (T15) y eventos de seguridad (T16, T17) listos")

    # --- Red (IP2-86): puertos de acceso que n8n reinicia y enlaces de gestión que solo alertan ---
    def estado_interfaz(host, nombre):
        """Clave del ítem "Operational status" que la plantilla descubrió para esa interfaz."""
        hid_red = z.uno("host.get", {"host": [host]}, ["hostid"])["hostid"]
        items = z.call("item.get", {"output": ["key_", "name"], "hostids": hid_red,
                                    "search": {"key_": "net.if.status[ifOperStatus."}})
        return next((i["key_"] for i in items if i["name"].startswith(f"Interface {nombre}(")), None), hid_red

    def sin_alerta_de_plantilla(hid_red, nombre):
        # La plantilla también avisa "Link down"; el trigger propio la reemplaza.
        macro = f'{{$IFCONTROL:"{nombre}"}}'
        if not z.call("usermacro.get", {"output": ["hostmacroid"], "hostids": hid_red, "filter": {"macro": macro}}):
            z.call("usermacro.create", {"hostid": hid_red, "macro": macro, "value": "0"})

    # T09: un puerto de acceso que estaba conectado y lleva 2 minutos caído (o bloqueado,
    # err-disabled). "Estaba conectado en los últimos 15 minutos" evita actuar sobre los
    # puertos que no tienen nada enchufado. Se cierra cuando el puerto vuelve.
    roles = {**{n: "Administración" for n in range(1, 5)}, **{n: "Usuarios" for n in range(5, 13)},
             **{n: "Servidores" for n in range(13, 21)}}
    for numero, rol in roles.items():
        nombre = f"Fa0/{numero}"
        clave, hid_red = estado_interfaz("sw1", nombre)
        if not clave:
            print(f"AVISO: sw1 no tiene el ítem de estado de {nombre}; se omite")
            continue
        sin_alerta_de_plantilla(hid_red, nombre)
        descripcion = f"T09 Puerto de acceso caído: sw1 {nombre} ({rol})"
        if not z.call("trigger.get", {"output": ["triggerid"], "hostids": hid_red, "filter": {"description": [descripcion]}}):
            z.call("trigger.create", {
                "description": descripcion, "priority": 4,
                "expression": f"max(/sw1/{clave},2m)=2 and min(/sw1/{clave},15m)=1",
                "recovery_mode": 1, "recovery_expression": f"last(/sw1/{clave})=1",
                "comments": "Recuperación automática: n8n reinicia el puerto (shutdown y no shutdown) por la "
                            "cuenta n8n-net. Si sigue caído, requiere una persona (IP2-86).",
                "tags": [{"tag": "remediation", "value": "restart-interface"}, {"tag": "target", "value": f"sw1:{nombre}"},
                         {"tag": "capa", "value": "red"}, {"tag": "interfaz", "value": nombre}]})

    # T09-G: enlaces de gestión. Solo alerta: reiniciarlos dejaría a n8n sin camino.
    gestion = [("sw1", "Gi0/1", "troncal hacia R1"), ("sw1", "Gi0/2", "troncal hacia el servidor"),
               ("r1", "Gi0/0/0", "WAN, salida a Internet"), ("r1", "Gi0/0/1", "troncal hacia SW1")]
    for host, nombre, que in gestion:
        clave, hid_red = estado_interfaz(host, nombre)
        if not clave:
            print(f"AVISO: {host} no tiene el ítem de estado de {nombre}; se omite")
            continue
        sin_alerta_de_plantilla(hid_red, nombre)
        crear_trigger(z, f"T09-G Enlace de gestión caído: {host} {nombre} ({que})", f"max(/{host}/{clave},1m)=2", 5,
                      {"remediation": "none", "capa": "red", "interfaz": nombre},
                      "Solo alerta: si la automatización lo reiniciara, perdería el camino para volver a encenderlo. "
                      "Se atiende a mano.", host=host)
    print("Red: T09 en los puertos de acceso de sw1 y T09-G en los enlaces de gestión listos")

    # --- Triggers que completan el diseño (IP2-45, IP2-91) ---
    def hostid_de(host):
        return z.uno("host.get", {"host": [host]}, ["hostid"])["hostid"]

    def item_por_nombre(host, inicio, clave_inicio):
        items = z.call("item.get", {"output": ["key_", "name"], "hostids": hostid_de(host),
                                    "search": {"key_": clave_inicio}})
        return next((i["key_"] for i in items if i["name"].startswith(inicio)), None)

    def apagar_de_plantilla(host, *textos):
        """Apaga en un host los triggers de plantilla que un trigger propio reemplaza,
        para que el mismo evento no avise dos veces."""
        for t in z.call("trigger.get", {"output": ["triggerid", "description", "status"], "hostids": hostid_de(host),
                                        "inherited": True}):
            if t["status"] == "0" and any(x in t["description"] for x in textos):
                z.call("trigger.update", {"triggerid": t["triggerid"], "status": 1})

    # T02: el contenedor responde, pero su chequeo de salud falla (2 = unhealthy).
    salud = f'docker.container_info.state.health["/{CONTENEDOR}"]'
    crear_trigger(z, "T02 Contenedor msmotos-app con el chequeo de salud fallando",
                  f"max(/vm-app/{salud},2m)=2 and min(/vm-app/{salud},2m)=2", 4,
                  {"remediation": "none", "capa": "contenedor"},
                  "Docker marca el contenedor como unhealthy: /api/health no responde bien. Solo alerta: "
                  "reiniciarlo a ciegas puede ocultar un error de la aplicación.")
    apagar_de_plantilla("vm-app", f"Container /{CONTENEDOR}: Health state container is unhealthy")

    # T10: enlaces principales saturados, comparando el tráfico con la velocidad del enlace.
    enlaces = [("sw1", "Gi0/1", "troncal hacia R1"), ("sw1", "Gi0/2", "troncal hacia el servidor"),
               ("r1", "Gi0/0/0", "WAN"), ("r1", "Gi0/0/1", "troncal hacia SW1")]
    for host, nombre, que in enlaces:
        entrada = item_por_nombre(host, f"Interface {nombre}(", "net.if.in[")
        salida = item_por_nombre(host, f"Interface {nombre}(", "net.if.out[")
        velocidad = item_por_nombre(host, f"Interface {nombre}(", "net.if.speed[")
        if not (entrada and salida and velocidad):
            print(f"AVISO: faltan ítems de tráfico de {host} {nombre}; se omite T10")
            continue
        uso = (f"(avg(/{host}/{entrada},5m)>{{}}/100*last(/{host}/{velocidad}) or "
               f"avg(/{host}/{salida},5m)>{{}}/100*last(/{host}/{velocidad})) and last(/{host}/{velocidad})>0")
        etiquetas = {"remediation": "none", "capa": "red", "interfaz": nombre}
        grave = crear_trigger(z, f"T10 Enlace saturado: {host} {nombre} ({que}) > 90 %, promedio de 5 min",
                              uso.format(90, 90), 4, etiquetas, host=host)
        leve = crear_trigger(z, f"T10 Enlace saturado: {host} {nombre} ({que}) > 70 %, promedio de 5 min",
                             uso.format(70, 70), 2, etiquetas, host=host)
        z.call("trigger.update", {"triggerid": leve, "dependencies": [{"triggerid": grave}]})

    # T11 y T11b: el router o el switch saturados, o sin responder. Solo alertan: reiniciar
    # el equipo (lo que proponía el diseño) cortaría la red de todo el laboratorio.
    cpu = {"r1": "system.cpu.util[cpmCPUTotal5minRev.7]", "sw1": "system.cpu.util[cpmCPUTotal5minRev.1]"}
    for host in ("r1", "sw1"):
        memoria = "vm.memory.util[vm.memory.util.1]"
        crear_trigger(z, f"T11 Equipo de red saturado: {host} (CPU o memoria > 90 % durante 10 min)",
                      f"min(/{host}/{cpu[host]},10m)>90 or min(/{host}/{memoria},10m)>90", 4,
                      {"remediation": "none", "capa": "red"},
                      "Solo alerta. Reiniciar el equipo cortaría toda la red del laboratorio: se atiende a mano.",
                      host=host, opdata="CPU {ITEM.LASTVALUE1} · memoria {ITEM.LASTVALUE2}")
        t11b = crear_trigger(z, f"T11b Equipo de red sin respuesta: {host}", f"max(/{host}/icmpping,2m)=0", 5,
                             {"remediation": "none", "capa": "red"},
                             "No responde al ping desde Zabbix. Sin red no hay acción automática posible.", host=host)
        apagar_de_plantilla(host, "High CPU utilization", "High memory utilization", "Unavailable by ICMP ping")
        # Si el equipo no responde, los demás problemas de ese equipo son consecuencia.
        for t in z.call("trigger.get", {"output": ["triggerid", "description"], "hostids": hostid_de(host),
                                        "search": {"description": "T09-G"}}):
            z.call("trigger.update", {"triggerid": t["triggerid"], "dependencies": [{"triggerid": t11b}]})

    # T18: alguien cambió la configuración del router o del switch. El equipo publica por SNMP
    # cuándo cambió por última vez su configuración en uso (ccmHistoryRunningLastChanged).
    for host in ("r1", "sw1"):
        hid_red = hostid_de(host)
        clave = "ip2.config.running.changed"
        if not z.call("item.get", {"output": ["itemid"], "hostids": hid_red, "filter": {"key_": clave}}):
            interfaz = z.call("hostinterface.get", {"output": ["interfaceid"], "hostids": hid_red,
                                                    "filter": {"type": 2}})[0]["interfaceid"]
            z.call("item.create", {
                "hostid": hid_red, "interfaceid": interfaz, "type": 20, "value_type": 3, "delay": "1m",
                "name": "Configuración en uso: momento del último cambio", "key_": clave,
                "snmp_oid": "get[1.3.6.1.4.1.9.9.43.1.1.1.0]", "history": "31d",
                "tags": [{"tag": "component", "value": "configuracion"}]})
        crear_trigger(z, f"T18 Configuración de {host} modificada", f"change(/{host}/{clave})<>0", 2,
                      {"remediation": "none", "capa": "seguridad"},
                      "Confirmar que el cambio fue autorizado. n8n también cambia la configuración en uso cuando "
                      "reinicia un puerto de acceso.", host=host)

    # T19: intentos de SSH fallidos en las VMs Linux. El agente lee el registro de
    # autenticación por su cuenta (chequeo activo); necesita estar en el grupo adm.
    patron_ssh = "sshd.*(Failed password|Invalid user|authentication failure|Connection closed by invalid user)"
    clave_ssh = f'log[/var/log/auth.log,"{patron_ssh}",,,skip]'
    for host, _, _, _ in VMS:
        hid_vm = hostid_de(host)
        if not z.call("item.get", {"output": ["itemid"], "hostids": hid_vm, "filter": {"key_": clave_ssh}}):
            z.call("item.create", {"hostid": hid_vm, "type": 7, "value_type": 2, "delay": "30s",
                                   "name": "SSH: intento fallido", "key_": clave_ssh, "history": "31d",
                                   "tags": [{"tag": "component", "value": "seguridad"}]})
        expresion = f"count(/{host}/{clave_ssh},5m)>10 and now()>0"
        tid = crear_trigger(z, f"T19 Intentos de SSH fallidos en {host} (más de 10 en 5 min)", expresion, 2,
                            {"remediation": "none", "capa": "seguridad"},
                            "Posible intento de adivinar contraseñas por SSH. Revisar /var/log/auth.log.", host=host)
        z.call("trigger.update", {"triggerid": tid, "expression": expresion})
    print("Triggers T02, T10, T11, T11b, T18 y T19 listos")

    # T20: el certificado HTTPS de la aplicación vence pronto. El agente 2 de vm-app lee el
    # certificado que presenta Nginx; de ahí se calcula cuántos días le quedan.
    hid_app = hostid_de("vm-app")
    clave_cert = "web.certificate.get[10.10.30.11,443]"
    existentes = {i["key_"]: i["itemid"] for i in z.call("item.get", {"output": ["key_"], "hostids": hid_app,
                                                                       "search": {"key_": "certificate"}})}
    existentes |= {i["key_"]: i["itemid"] for i in z.call("item.get", {"output": ["key_"], "hostids": hid_app,
                                                                        "filter": {"key_": "ip2.cert.dias"}})}
    if clave_cert not in existentes:
        interfaz = z.call("hostinterface.get", {"output": ["interfaceid"], "hostids": hid_app})[0]["interfaceid"]
        existentes[clave_cert] = z.call("item.create", {
            "hostid": hid_app, "interfaceid": interfaz, "type": 0, "value_type": 4, "delay": "1h",
            "name": "Certificado HTTPS de la aplicación", "key_": clave_cert, "history": "7d",
            "tags": [{"tag": "component", "value": "certificado"}]})["itemids"][0]
    if "ip2.cert.dias" not in existentes:
        z.call("item.create", {
            "hostid": hid_app, "type": 18, "master_itemid": existentes[clave_cert], "value_type": 3,
            "name": "Certificado HTTPS de la aplicación: días para vencer", "key_": "ip2.cert.dias", "units": "días",
            "history": "31d", "tags": [{"tag": "component", "value": "certificado"}],
            "preprocessing": [
                {"type": 12, "params": "$.x509.not_after.timestamp", "error_handler": 0, "error_handler_params": ""},
                {"type": 21, "params": "return Math.floor((Number(value) - Date.now() / 1000) / 86400);",
                 "error_handler": 0, "error_handler_params": ""}]})
    crear_trigger(z, "T20 Certificado HTTPS de la aplicación por vencer (menos de 15 días)",
                  "last(/vm-app/ip2.cert.dias)<15", 2, {"remediation": "none", "capa": "seguridad"},
                  "Renovarlo con infra/proxmox/ca-interna.sh en el servidor Proxmox.", host="vm-app",
                  opdata="quedan {ITEM.LASTVALUE1}")
    print("T20: certificado HTTPS vigilado")

    # --- Active Directory (IP2-81): el personal entra con su cuenta del dominio ---
    # El usuario se crea solo en su primer inicio de sesión (JIT), con los permisos de su
    # grupo del dominio. Una cuenta que no está en ninguno de los dos grupos no entra.
    # Admin sigue siendo una cuenta local: es la de emergencia si el dominio no responde.
    if not env.get("LDAP_BIND_PASSWORD"):
        print("AVISO: falta LDAP_BIND_PASSWORD en .env; no se configura el dominio")
    else:
        roles_z = {r["name"]: r["roleid"] for r in z.call("role.get", {"output": ["roleid", "name"]})}
        grupos_z = {}
        for nombre, permiso in (("Dominio · administradores", 3), ("Dominio · operadores", 2)):
            actual = z.uno("usergroup.get", {"name": [nombre]}, ["usrgrpid"])
            # gui_access 2: sus miembros siempre se autentican contra el dominio.
            datos = {"name": nombre, "gui_access": 2, "hostgroup_rights": [{"id": gid, "permission": permiso}]}
            if actual:
                z.call("usergroup.update", dict(datos, usrgrpid=actual["usrgrpid"]))
                grupos_z[nombre] = actual["usrgrpid"]
            else:
                grupos_z[nombre] = z.call("usergroup.create", datos)["usrgrpids"][0]
        base = "OU=IP2,DC=ip2,DC=local"
        directorio = {
            "idp_type": 1, "name": "ip2.local", "host": "ldaps://dc01.ip2.local", "port": 636,
            "base_dn": base, "search_attribute": "sAMAccountName",
            "bind_dn": f"CN=svc-ldap,OU=Servicios,{base}", "bind_password": env["LDAP_BIND_PASSWORD"],
            "description": "Active Directory del laboratorio (IP2-81)",
            "provision_status": 1, "group_basedn": base, "group_name": "cn", "group_member": "member",
            "user_ref_attr": "distinguishedName", "group_filter": "(member=%{ref})",
            "user_username": "givenName", "user_lastname": "sn",
            "provision_groups": [
                {"name": "GG-IP2-Administradores", "roleid": roles_z["Admin role"],
                 "user_groups": [{"usrgrpid": grupos_z["Dominio · administradores"]}]},
                {"name": "GG-IP2-Operadores", "roleid": roles_z["User role"],
                 "user_groups": [{"usrgrpid": grupos_z["Dominio · operadores"]}]},
            ],
        }
        actual = next((d for d in z.call("userdirectory.get", {"output": ["userdirectoryid", "name"]})
                       if d["name"] == "ip2.local"), None)
        if actual:
            z.call("userdirectory.update", dict(directorio, userdirectoryid=actual["userdirectoryid"]))
            did = actual["userdirectoryid"]
        else:
            did = z.call("userdirectory.create", directorio)["userdirectoryids"][0]
        # Zabbix solo da de alta a un usuario nuevo si el dominio es el método por defecto.
        # Las cuentas locales que deben seguir funcionando sin el dominio quedan fijadas como
        # internas: Admin (emergencia) y la que usa Grafana para leer Zabbix.
        for local in ("Zabbix administrators", "Grafana lectura"):
            grupo = z.uno("usergroup.get", {"name": [local]}, ["usrgrpid"])
            if grupo:
                z.call("usergroup.update", {"usrgrpid": grupo["usrgrpid"], "gui_access": 1})
        # Quien sale de los grupos del dominio pasa al grupo "Disabled" de Zabbix: ya no entra.
        deshabilitados = z.uno("usergroup.get", {"name": ["Disabled"]}, ["usrgrpid"])["usrgrpid"]
        z.call("authentication.update", {"authentication_type": 1, "ldap_auth_enabled": 1,
                                         "ldap_userdirectoryid": did, "ldap_jit_status": 1,
                                         "jit_provision_interval": "1h", "disabled_usrgrpid": deshabilitados})
        print("Dominio: inicio de sesión con cuentas de ip2.local por LDAPS, por grupos")

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
