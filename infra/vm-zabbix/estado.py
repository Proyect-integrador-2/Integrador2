#!/usr/bin/env python3
"""Muestra en texto el estado del Zabbix del laboratorio: hosts, datos clave y problemas.

Sirve para comprobar el monitoreo sin abrir el frontend y como evidencia de las pruebas.
Se corre en vm-zabbix; lee la contraseña de Admin del .env de esta carpeta.

    python3 estado.py
"""
import importlib.util
import time
from pathlib import Path

AQUI = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("configurar", AQUI / "configurar-zabbix.py")
configurar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configurar)

SEVERIDAD = ["Sin clasificar", "Información", "Advertencia", "Media", "Alta", "Desastre"]
DISPONIBLE = {"0": "sin datos aún", "1": "disponible", "2": "NO disponible"}
# Ítems que resumen cada capa: (host, nombre visible del ítem)
CLAVE = [
    ("vm-app", "CPU utilization"), ("vm-app", "Memory utilization"),
    ("vm-app", "Container /msmotos-app: Running"), ("vm-app", "Container /msmotos-db: Running"),
    ("vm-app", "Servicio Nginx: estado"), ("vm-app", "Connections active"),
    ("msmotos-web", "Response code for step \"health\" of scenario \"App MS Motos\"."),
    ("msmotos-web", "Response time for step \"health\" of scenario \"App MS Motos\"."),
    ("r1", "ICMP ping"), ("r1", "ICMP response time"),
    ("sw1", "ICMP ping"), ("sw1", "ICMP response time"),
    ("proxmox", "ICMP ping"),
]


def main():
    z = configurar.Zabbix()
    z.token = z.call("user.login", {"username": "Admin", "password": configurar.leer_env()["ZBX_ADMIN_PASSWORD"]})
    grupo = z.uno("hostgroup.get", {"name": [configurar.GRUPO]})

    hosts = z.call("host.get", {"output": ["hostid", "host", "name"], "groupids": grupo["groupid"],
                                "selectInterfaces": ["type", "ip", "available", "error"],
                                "selectParentTemplates": ["name"], "sortfield": "host"})
    print(f"== Hosts del grupo {configurar.GRUPO} ({len(hosts)}) ==")
    por_host = {}
    for h in hosts:
        por_host[h["host"]] = h["hostid"]
        ifaz = h["interfaces"][0] if h["interfaces"] else None
        via = {"1": "agente", "2": "SNMP"}.get(ifaz["type"], "?") if ifaz else "web"
        estado = DISPONIBLE[ifaz["available"]] if ifaz else "-"
        n = z.call("item.get", {"countOutput": True, "hostids": h["hostid"], "monitored": True, "webitems": True})
        sin = z.call("item.get", {"countOutput": True, "hostids": h["hostid"], "monitored": True, "filter": {"state": 1}})
        print(f"  {h['host']:<12} {ifaz['ip'] if ifaz else '-':<12} {via:<7} {estado:<14} ítems: {n:>4}  sin soporte: {sin}")
        if ifaz and ifaz["error"]:
            print(f"      error: {ifaz['error'][:110]}")

    print("\n== Datos clave ==")
    ahora = time.time()
    for host, nombre in CLAVE:
        items = z.call("item.get", {"output": ["name", "lastvalue", "lastclock", "units"], "webitems": True,
                                    "hostids": por_host.get(host, 0), "filter": {"name": nombre}})
        if not items:
            print(f"  {host:<12} {nombre[:52]:<52} (no existe)")
            continue
        i = items[0]
        hace = f"hace {int(ahora - int(i['lastclock']))} s" if i["lastclock"] != "0" else "sin datos aún"
        print(f"  {host:<12} {nombre[:52]:<52} {i['lastvalue'][:18]:>18} {i['units']:<4} {hace}")

    interfaces = z.call("item.get", {"output": ["name", "lastvalue"], "hostids": [por_host[h] for h in ("r1", "sw1") if h in por_host],
                                     "search": {"name": "Operational status"}, "selectHosts": ["host"]})
    arriba = sum(1 for i in interfaces if i["lastvalue"] == "1")
    print(f"\n== Interfaces de red descubiertas por SNMP: {len(interfaces)} ({arriba} arriba) ==")

    triggers = z.call("trigger.get", {"output": ["description", "priority", "value"], "groupids": grupo["groupid"],
                                      "search": {"description": "T0"}, "startSearch": True,
                                      "selectDependencies": ["description"], "sortfield": "description"})
    print("\n== Triggers del proyecto ==")
    for t in triggers:
        dep = " · depende de " + ", ".join(d["description"][:3] for d in t["dependencies"]) if t["dependencies"] else ""
        print(f"  {'PROBLEMA' if t['value'] == '1' else 'ok':<9} {SEVERIDAD[int(t['priority'])]:<12} {t['description']}{dep}")

    problemas = z.call("problem.get", {"output": ["name", "severity", "clock"], "groupids": grupo["groupid"],
                                       "sortfield": "eventid", "sortorder": "DESC"})
    print(f"\n== Problemas abiertos: {len(problemas)} ==")
    for p in problemas:
        print(f"  {SEVERIDAD[int(p['severity'])]:<12} {time.strftime('%H:%M:%S', time.localtime(int(p['clock'])))}  {p['name'][:100]}")


if __name__ == "__main__":
    main()
