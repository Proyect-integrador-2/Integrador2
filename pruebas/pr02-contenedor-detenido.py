#!/usr/bin/env python3
"""Prueba PR-02: contenedor detenido (IP2-58).

Detiene msmotos-app y mide la cadena completa de la demo:
    Zabbix detecta -> n8n recupera por SSH -> la app vuelve a responder -> Zabbix cierra el problema.

Uso (laboratorio local, con app/ e infra/lab-local/ corriendo):
    python pruebas/pr02-contenedor-detenido.py
"""
import json
import subprocess
import sys
import time
import urllib.request
from datetime import datetime

ZBX = "http://127.0.0.1:8080/api_jsonrpc.php"
APP = "http://127.0.0.1:3000/api/health"
TRIGGER = "T01 Contenedor msmotos-app detenido"
LIMITE_S = 420


def zbx(metodo, params, token=None):
    cab = {"Content-Type": "application/json-rpc"}
    if token:
        cab["Authorization"] = f"Bearer {token}"
    cuerpo = json.dumps({"jsonrpc": "2.0", "method": metodo, "params": params, "id": 1}).encode()
    with urllib.request.urlopen(urllib.request.Request(ZBX, cuerpo, cab), timeout=15) as r:
        d = json.load(r)
    if "error" in d:
        raise RuntimeError(d["error"])
    return d["result"]


def app_responde():
    try:
        with urllib.request.urlopen(APP, timeout=3) as r:
            return r.status == 200
    except Exception:
        return False


def estado_contenedor():
    r = subprocess.run(["docker", "inspect", "-f", "{{.State.Status}}", "msmotos-app"], capture_output=True, text=True)
    return r.stdout.strip() or r.stderr.strip()


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    token = zbx("user.login", {"username": "Admin", "password": "zabbix"})
    trig = zbx("trigger.get", {"output": ["triggerid", "value"], "filter": {"description": TRIGGER}}, token)[0]
    if trig["value"] != "0" or not app_responde():
        sys.exit("La app debe estar sana y el trigger en OK antes de empezar.")

    t0 = time.time()
    marca = lambda: f"+{time.time() - t0:5.0f} s"
    print(f"{datetime.now():%H:%M:%S} Deteniendo msmotos-app (docker stop)")
    subprocess.run(["docker", "stop", "msmotos-app"], capture_output=True)

    detectado = recuperado = responde = resuelto = None
    ultimo = None
    while time.time() - t0 < LIMITE_S:
        cont = estado_contenedor()
        valor = zbx("trigger.get", {"output": ["value"], "triggerids": trig["triggerid"]}, token)[0]["value"]
        vivo = app_responde()
        linea = f"contenedor={cont:8} trigger={'PROBLEMA' if valor == '1' else 'OK':8} app={'responde' if vivo else 'caída':8}"
        if linea != ultimo:
            print(f"{marca()}  {linea}")
            ultimo = linea
        if detectado is None and valor == "1":
            detectado = time.time() - t0
        if detectado is not None and recuperado is None and cont == "running":
            recuperado = time.time() - t0
        if recuperado is not None and responde is None and vivo:
            responde = time.time() - t0
        if detectado is not None and valor == "0" and vivo:
            resuelto = time.time() - t0
            break
        time.sleep(3)

    print("\n=== Resultado PR-02 ===")
    filas = [("Detección (Zabbix)", detectado), ("Contenedor iniciado (n8n)", recuperado),
             ("App responde otra vez", responde), ("Problema cerrado en Zabbix", resuelto)]
    for nombre, seg in filas:
        print(f"  {nombre:28} {'%.0f s' % seg if seg is not None else 'NO ocurrió'}")
    if detectado is not None and recuperado is not None:
        print(f"  {'Tiempo de recuperación':28} {recuperado - detectado:.0f} s desde la detección")

    # Los mensajes de n8n se adjuntan al evento del PROBLEMA (value=1), no al de resolución.
    eventos = zbx("event.get", {"output": ["eventid", "name", "clock", "value"], "objectids": trig["triggerid"],
                                 "select_acknowledges": ["clock", "message", "userid"],
                                 "sortfield": ["clock"], "sortorder": "DESC", "limit": 4}, token)
    print("\n=== Registro en Zabbix (acknowledge de n8n) ===")
    problema = next((e for e in eventos if e["value"] == "1" and int(e["clock"]) >= int(t0)), None)
    if not problema:
        print("  (no se encontró el evento de problema de esta corrida)")
    else:
        for ack in sorted(problema["acknowledges"], key=lambda a: a["clock"]):
            print(f"  {datetime.fromtimestamp(int(ack['clock'])):%H:%M:%S}  {ack['message']}")
        if not problema["acknowledges"]:
            print("  (sin mensajes: revisar el nodo 'Registrar en Zabbix' del flujo)")

    if estado_contenedor() != "running":
        print("\n⚠️  La app quedó detenida: iniciándola manualmente.")
        subprocess.run(["docker", "start", "msmotos-app"], capture_output=True)
    sys.exit(0 if resuelto is not None else 1)


if __name__ == "__main__":
    main()
