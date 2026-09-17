#!/usr/bin/env python3
"""Configura Zabbix por API según docs/diseno/monitoreo.md (IP2-41 a IP2-45, IP2-50).

Idempotente: si algo ya existe, lo reutiliza. Lee secretos de .env (nunca de Git).

    python configurar-zabbix.py

Crea:
  - Grupo "Integrador II"
  - Host vm-app (agent 2) con plantillas Linux y Docker
  - Host msmotos-web con escenario web a /api/health (T04 y T05)
  - Trigger T01: contenedor msmotos-app detenido (tag remediation=restart-container)
  - Usuario de solo lectura para Grafana
  - Media type "Webhook n8n" y la acción que le envía los problemas
"""
import json
import sys
import time
import urllib.request
from pathlib import Path

URL = "http://127.0.0.1:8080/api_jsonrpc.php"
AQUI = Path(__file__).resolve().parent
GRUPO = "Integrador II"
CONTENEDOR = "msmotos-app"
WEBHOOK_N8N = "http://n8n:5678/webhook/zabbix"


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


def main():
    env = leer_env()
    z = Zabbix()
    print("Zabbix", z.call("apiinfo.version", {}))
    z.token = z.call("user.login", {"username": "Admin", "password": "zabbix"})

    # --- Grupo ---
    grupo = z.uno("hostgroup.get", {"name": [GRUPO]})
    gid = grupo["groupid"] if grupo else z.call("hostgroup.create", {"name": GRUPO})["groupids"][0]
    print("Grupo:", GRUPO, gid)

    plantillas = {t["host"]: t["templateid"] for t in z.call(
        "template.get", {"output": ["host"], "filter": {"host": ["Linux by Zabbix agent", "Docker by Zabbix agent 2"]}})}
    faltan = {"Linux by Zabbix agent", "Docker by Zabbix agent 2"} - plantillas.keys()
    if faltan:
        sys.exit(f"Faltan plantillas en Zabbix: {faltan}")

    # --- Host vm-app (agente) ---
    host = z.uno("host.get", {"host": ["vm-app"]}, ["hostid"])
    if not host:
        hid = z.call("host.create", {
            "host": "vm-app", "name": "vm-app (App MS Motos)",
            "groups": [{"groupid": gid}],
            "interfaces": [{"type": 1, "main": 1, "useip": 0, "ip": "", "dns": "zabbix-agent", "port": "10050"}],
            "templates": [{"templateid": tid} for tid in plantillas.values()],
            "tags": [{"tag": "capa", "value": "vm"}],
        })["hostids"][0]
    else:
        hid = host["hostid"]
    print("Host vm-app:", hid)

    # --- Host msmotos-web con escenario web (disponibilidad y tiempo de respuesta) ---
    web = z.uno("host.get", {"host": ["msmotos-web"]}, ["hostid"])
    wid = web["hostid"] if web else z.call("host.create", {
        "host": "msmotos-web", "name": "MS Motos (aplicación)",
        "groups": [{"groupid": gid}], "tags": [{"tag": "capa", "value": "aplicacion"}],
    })["hostids"][0]
    if not z.call("httptest.get", {"output": ["httptestid"], "hostids": wid, "filter": {"name": "App MS Motos"}}):
        z.call("httptest.create", {
            "name": "App MS Motos", "hostid": wid, "delay": "30s", "retries": 1,
            "steps": [
                {"name": "health", "url": "http://msmotos-app:3000/api/health", "status_codes": "200",
                 "required": "\"ok\":true", "no": 1, "timeout": "5s"},
                {"name": "frontend", "url": "http://msmotos-app:3000/", "status_codes": "200",
                 "required": "app-root", "no": 2, "timeout": "5s"},
            ],
        })
    triggers_web = [
        ("T04 App MS Motos no disponible", 5,
         "count(/msmotos-web/web.test.fail[App MS Motos],#2,\"ne\",0)=2", "none"),
        ("T05 App MS Motos lenta (health > 2 s)", 2,
         "avg(/msmotos-web/web.test.time[App MS Motos,health,resp],5m)>2", "none"),
    ]
    for nombre, sev, expr, rem in triggers_web:
        if not z.uno("trigger.get", {"description": [nombre]}, ["triggerid"]):
            z.call("trigger.create", {"description": nombre, "expression": expr, "priority": sev,
                                      "tags": [{"tag": "remediation", "value": rem}, {"tag": "capa", "value": "aplicacion"}]})
    print("Escenario web y triggers T04/T05 listos")

    # --- T01: contenedor detenido (espera el descubrimiento de contenedores) ---
    clave = f'docker.container_info.state.running["/{CONTENEDOR}"]'
    item = None
    candidatos = []
    for intento in range(20):
        candidatos = z.call("item.get", {"output": ["itemid", "key_"], "hostids": hid, "search": {"key_": CONTENEDOR}})
        item = next((i for i in candidatos if i["key_"] == clave), None)
        if item:
            break
        if intento == 0:
            reglas = z.call("discoveryrule.get", {"output": ["itemid"], "hostids": hid})
            for r in reglas:
                z.call("task.create", [{"type": 6, "request": {"itemid": r["itemid"]}}])
            print("Descubrimiento forzado; esperando contenedores...")
        time.sleep(15)
    if not item:
        sys.exit(f"No apareció el ítem {clave}. Claves encontradas: {[c['key_'] for c in candidatos]}")
    t01 = "T01 Contenedor msmotos-app detenido"
    if not z.uno("trigger.get", {"description": [t01]}, ["triggerid"]):
        z.call("trigger.create", {
            "description": t01, "priority": 4,
            "expression": f"max(/vm-app/{clave},1m)=0",
            "comments": "Recuperación automática: n8n inicia el contenedor (IP2-53).",
            "tags": [{"tag": "remediation", "value": "restart-container"},
                     {"tag": "target", "value": CONTENEDOR}, {"tag": "capa", "value": "contenedor"}],
        })
    print("Trigger T01 listo sobre", clave)

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

    # --- Media type webhook hacia n8n ---
    script = r"""
var p = JSON.parse(value);
var req = new HttpRequest();
req.addHeader('Content-Type: application/json');
req.addHeader('X-Zabbix-Token: ' + p.token);
var cuerpo = {
  event_id: p.event_id, event_value: p.event_value, severity: p.severity,
  host: p.host, trigger: p.trigger, opdata: p.opdata, tags: p.tags, time: p.time
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
            "filter": {"evaltype": 0, "conditions": [{"conditiontype": 0, "operator": 0, "value": gid}]},
            "operations": [{"operationtype": 0, "opmessage": {"default_msg": 1, "mediatypeid": mtid},
                            "opmessage_usr": [{"userid": admin["userid"]}]}],
            "recovery_operations": [{"operationtype": 11, "opmessage": {"default_msg": 1}}],
        })
    print("Media type 'Webhook n8n' y acción listos ->", WEBHOOK_N8N)

    # --- Usuario y token de API para n8n (acknowledge de eventos: control C6) ---
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
            z.call("token.delete", [t["tokenid"] for t in viejos])
        tid = z.call("token.create", {"name": "n8n", "userid": uid})["tokenids"][0]
        valor = z.call("token.generate", [tid])[0]["token"]
        with open(AQUI / ".env", "a", encoding="utf-8", newline="\n") as f:
            f.write(f"\n# Token de API de Zabbix para n8n (lo generó configurar-zabbix.py)\nZABBIX_N8N_TOKEN={valor}\n")
        print("Token de API para n8n creado y guardado en .env (ejecutar: docker compose up -d n8n)")
    else:
        print("Token de API para n8n ya existe en .env")
    print(f"Listo. Llamadas a la API: {z.n}")


if __name__ == "__main__":
    main()
