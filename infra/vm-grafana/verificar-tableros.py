#!/usr/bin/env python3
"""Ejecuta las consultas de cada panel de los tableros y dice cuáles traen datos.

Sirve para comprobar los tableros sin abrir el navegador y como evidencia. Las consultas
de tipo Problems y Text solo se resuelven en el navegador (ver monitoreo/grafana/README.md):
aquí se cuentan aparte, no como error.

Se corre en vm-grafana; lee la contraseña de admin del .env de esta carpeta.

    python3 verificar-tableros.py
"""
import base64
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

AQUI = Path(__file__).resolve().parent
TABLEROS = AQUI.parent.parent / "monitoreo" / "grafana"
URL = "http://127.0.0.1"
MINUTOS = 30  # si el tablero no dice su rango
UNIDADES = {"m": 1, "h": 60, "d": 1440}


def rango(tablero):
    """Minutos del rango por defecto del tablero ("now-24h" -> 1440): se consulta lo que ve quien lo abre."""
    desde = tablero.get("time", {}).get("from", "")
    if desde.startswith("now-") and desde[-1] in UNIDADES and desde[4:-1].isdigit():
        return int(desde[4:-1]) * UNIDADES[desde[-1]]
    return MINUTOS


def leer_env():
    valores = {}
    for linea in (AQUI / ".env").read_text(encoding="utf-8").splitlines():
        if "=" in linea and not linea.lstrip().startswith("#"):
            k, v = linea.split("=", 1)
            valores[k.strip()] = v.strip()
    return valores


def consultar(auth, objetivos, minutos):
    ahora = int(time.time() * 1000)
    cuerpo = {"from": str(ahora - minutos * 60000), "to": str(ahora),
              "queries": [dict(o, datasource={"type": "alexanderzobnin-zabbix-datasource", "uid": "zabbix"},
                               intervalMs=60000, maxDataPoints=300) for o in objetivos]}
    req = urllib.request.Request(URL + "/api/ds/query", json.dumps(cuerpo).encode(),
                                 {"Content-Type": "application/json", "Authorization": auth})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            resp = json.load(r)
    except urllib.error.HTTPError as e:
        resp = json.loads(e.read() or b"{}")
    series, errores = 0, []
    for ref, res in resp.get("results", {}).items():
        if res.get("error"):
            errores.append(res["error"])
        for marco in res.get("frames", []):
            valores = marco.get("data", {}).get("values", [])
            if valores and valores[0]:
                series += 1
    if "message" in resp and not resp.get("results"):
        errores.append(resp["message"])
    return series, errores


def paneles(tablero):
    for p in tablero.get("panels", []):
        if p.get("type") == "row":
            yield from p.get("panels", [])
        else:
            yield p


def main():
    auth = "Basic " + base64.b64encode(f"admin:{leer_env()['GRAFANA_ADMIN_PASSWORD']}".encode()).decode()
    total = {"con datos": 0, "vacío": 0, "navegador": 0, "error": 0}
    for archivo in sorted(TABLEROS.glob("ip2-*.json")):
        tablero = json.loads(archivo.read_text(encoding="utf-8"))
        minutos = rango(tablero)
        print(f"\n== {tablero.get('title', archivo.name)} (últimos {minutos} min) ==")
        for p in paneles(tablero):
            objetivos = [o for o in p.get("targets", []) if not o.get("hide")]
            if not objetivos:
                continue
            # queryType "0" = métricas; el resto (problemas, texto) lo resuelve el navegador.
            metricas = [o for o in objetivos if str(o.get("queryType", "0")) == "0"]
            if not metricas:
                estado, detalle = "navegador", ""
            else:
                series, errores = consultar(auth, metricas, minutos)
                solo_navegador = errores and all("non-metrics" in e for e in errores)
                if solo_navegador:
                    estado, detalle = "navegador", ""
                elif errores:
                    estado, detalle = "error", errores[0][:90]
                elif series:
                    estado, detalle = "con datos", f"{series} serie(s)"
                else:
                    estado, detalle = "vacío", ""
            total[estado] += 1
            print(f"  {estado:<10} {p.get('title', '(sin título)')[:60]:<60} {detalle}")
    print("\n== Resumen ==")
    for k, v in total.items():
        print(f"  {k:<10} {v}")


if __name__ == "__main__":
    main()
