#!/usr/bin/env python3
"""Crea un token de solo lectura de Grafana que vence en una hora, para tomar capturas
de los tableros con un navegador sin interfaz (IP2-48).

Imprime solo el token, para pasarlo por una tubería a quien toma las capturas: no hay
que mostrarlo en pantalla. Se corre en vm-grafana; lee la contraseña de admin del .env.

    python3 token-capturas.py | ssh ip2@10.10.30.15 'umask 077; cat > ~/grafana.token'
"""
import base64
import json
import time
import urllib.request
from pathlib import Path

AQUI = Path(__file__).resolve().parent
URL = "http://127.0.0.1"
CUENTA = "capturas"


def leer_env():
    valores = {}
    for linea in (AQUI / ".env").read_text(encoding="utf-8").splitlines():
        if "=" in linea and not linea.lstrip().startswith("#"):
            k, v = linea.split("=", 1)
            valores[k.strip()] = v.strip()
    return valores


def api(auth, metodo, ruta, cuerpo=None):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    pedido = urllib.request.Request(URL + ruta, datos, {"Content-Type": "application/json", "Authorization": auth},
                                    method=metodo)
    with urllib.request.urlopen(pedido, timeout=30) as r:
        return json.load(r)


def main():
    clave = leer_env()["GRAFANA_ADMIN_PASSWORD"]
    auth = "Basic " + base64.b64encode(f"admin:{clave}".encode()).decode()
    # Cuenta de servicio con el rol que solo permite ver.
    cuentas = api(auth, "GET", f"/api/serviceaccounts/search?query={CUENTA}")["serviceAccounts"]
    cuenta = next((c for c in cuentas if c["name"] == CUENTA), None) \
        or api(auth, "POST", "/api/serviceaccounts", {"name": CUENTA, "role": "Viewer"})
    token = api(auth, "POST", f"/api/serviceaccounts/{cuenta['id']}/tokens",
                {"name": f"capturas-{int(time.time())}", "secondsToLive": 3600})
    print(token["key"])


if __name__ == "__main__":
    main()
