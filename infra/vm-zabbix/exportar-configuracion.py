#!/usr/bin/env python3
"""Exporta de Zabbix la configuración del proyecto (IP2-45): los hosts del grupo
"Integrador II" con sus ítems, triggers, escenarios web, macros y plantillas enlazadas.

La fuente de verdad sigue siendo configurar-zabbix.py; este archivo es la evidencia de lo
que quedó configurado y sirve para importarlo en otro Zabbix 7.0.

Las macros secretas (comunidad SNMP, token de Proxmox) Zabbix las exporta sin valor. Aun
así, antes de escribir el archivo se comprueba que no contenga ningún valor del .env; si
aparece uno, no se escribe nada.

Se corre en vm-zabbix y escribe en la salida estándar:
    sudo python3 exportar-configuracion.py > hosts-integrador2.yaml
"""
import importlib.util
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("configurar", AQUI / "configurar-zabbix.py")
cz = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cz)


def main():
    env = cz.leer_env()
    z = cz.Zabbix()
    cz.entrar(z, env)
    grupo = z.uno("hostgroup.get", {"name": [cz.GRUPO]}, ["groupid"])
    hosts = z.call("host.get", {"output": ["hostid"], "groupids": grupo["groupid"]})
    yaml = z.call("configuration.export", {
        "format": "yaml", "prettyprint": True,
        "options": {"host_groups": [grupo["groupid"]], "hosts": [h["hostid"] for h in hosts]}})
    secretos = [v for v in env.values() if len(v) >= 8]
    if any(s in yaml for s in secretos):
        sys.exit("La exportación contiene un valor del .env: no se escribe.")
    sys.stdout.write(yaml)
    print(f"Exportados {len(hosts)} hosts; sin valores del .env.", file=sys.stderr)


if __name__ == "__main__":
    main()
