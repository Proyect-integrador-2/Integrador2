#!/usr/bin/env python3
"""Ejecuta un recorrido del cliente sintético y envía el resultado a Zabbix (IP2-57).

    python ejecutar.py consulta
    python ejecutar.py agendar

Qué hace:
  1. Corre el recorrido con Robot Framework, con un tiempo máximo.
  2. Lee del resultado cuánto tardó cada paso ("Paso <nombre>") y cuál falló.
  3. En "agendar", cancela por la API cualquier cita que haya quedado abierta.
  4. Envía a Zabbix resultado, duración total, duración por paso, paso fallido y error.

Las credenciales y direcciones llegan por variables de entorno (archivo .env de la VM,
fuera de Git): RPA_URL, RPA_CORREO, RPA_CLAVE, ZABBIX_SERVER y ZABBIX_HOST.

Devuelve 0 si el resultado llegó a Zabbix, haya pasado o no el recorrido: que el
recorrido falle es un dato del monitoreo, no un error de este programa.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

AQUI = Path(__file__).resolve().parent
SALIDAS = Path(os.environ.get("RPA_SALIDAS", "/opt/rpa/salidas"))
TIEMPO_MAXIMO = 60          # segundos por ejecución (diseño, sección 5)
DIAS_EVIDENCIA = 7          # cuánto se guardan las capturas de los fallos


def cargar_env():
    """Sin systemd (prueba a mano), toma las variables del .env que esté junto al script."""
    archivo = AQUI / ".env"
    if "RPA_CORREO" in os.environ or not archivo.exists():
        return
    for linea in archivo.read_text(encoding="utf-8").splitlines():
        if "=" in linea and not linea.lstrip().startswith("#"):
            k, v = linea.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip())


def correr(recorrido, carpeta):
    """Corre el recorrido. Devuelve None si terminó, o el motivo si hubo que cortarlo."""
    orden = [sys.executable, "-m", "robot", "--outputdir", str(carpeta), "--report", "NONE",
             "--consolewidth", "100", str(AQUI / "recorridos" / f"{recorrido}.robot")]
    try:
        subprocess.run(orden, timeout=TIEMPO_MAXIMO, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except subprocess.TimeoutExpired:
        return f"superó el tiempo máximo de {TIEMPO_MAXIMO} s"
    return None


def leer(carpeta):
    """Pasos con su estado y duración, y el mensaje de error del recorrido."""
    from robot.api import ExecutionResult

    prueba = ExecutionResult(str(carpeta / "output.xml")).suite.tests[0]
    pasos = [(k.name[5:], k.status, k.elapsed_time.total_seconds())
             for k in prueba.body if getattr(k, "name", "").startswith("Paso ")]
    return prueba.status == "PASS", pasos, " ".join(prueba.message.split())


def api(metodo, ruta, cuerpo=None, token=None):
    cabeceras = {"Content-Type": "application/json"}
    if token:
        cabeceras["Authorization"] = f"Bearer {token}"
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    pedido = urllib.request.Request(os.environ["RPA_URL"] + ruta, datos, cabeceras, method=metodo)
    with urllib.request.urlopen(pedido, timeout=15) as r:
        return json.load(r)


def limpiar_citas():
    """Cancela las citas del cliente sintético que hayan quedado agendadas. Devuelve cuántas."""
    sesion = api("POST", "/api/auth/login",
                 {"email": os.environ["RPA_CORREO"], "password": os.environ["RPA_CLAVE"]})["data"]
    abiertas = [c["id"] for c in api("GET", "/api/portal/citas", token=sesion["token"])["data"]
                if c["estado"] == "agendado"]
    for cita in abiertas:
        api("PATCH", f"/api/portal/citas/{cita}/cancelar", {}, sesion["token"])
    return len(abiertas)


def enviar(valores):
    """Envía los pares clave/valor con zabbix_sender. Devuelve (enviados, fallidos)."""
    host = os.environ.get("ZABBIX_HOST", "msmotos-rpa-linux")
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
        for clave, valor in valores:
            texto = str(valor).replace("\\", "\\\\").replace('"', '\\"')
            f.write(f'"{host}" {clave} "{texto}"\n')
        archivo = f.name
    try:
        r = subprocess.run(["zabbix_sender", "-z", os.environ.get("ZABBIX_SERVER", "10.10.30.12"), "-i", archivo],
                           capture_output=True, text=True, timeout=30, check=False)
    finally:
        os.unlink(archivo)
    # Respuesta del servidor: "processed: 10; failed: 0; total: 10; ..."
    cuenta = re.search(r"processed: (\d+); failed: (\d+)", r.stdout)
    enviados, fallidos = (int(cuenta.group(1)), int(cuenta.group(2))) if cuenta else (0, 0)
    return enviados, fallidos, (r.stderr or r.stdout).strip()[-200:]


def borrar_evidencia_vieja(base):
    limite = time.time() - DIAS_EVIDENCIA * 86400
    for carpeta in base.iterdir():
        if carpeta.is_dir() and carpeta.stat().st_mtime < limite:
            shutil.rmtree(carpeta, ignore_errors=True)


def main():
    if len(sys.argv) != 2 or not (AQUI / "recorridos" / f"{sys.argv[1]}.robot").exists():
        sys.exit("Uso: ejecutar.py consulta | agendar")
    recorrido = sys.argv[1]
    cargar_env()
    base = SALIDAS / recorrido
    base.mkdir(parents=True, exist_ok=True)
    carpeta = base / time.strftime("%Y%m%d-%H%M%S")

    cortado = correr(recorrido, carpeta)
    try:
        ok, pasos, error = leer(carpeta)
    except Exception as e:  # sin output.xml: Robot no llegó a escribirlo
        ok, pasos, error = False, [], f"sin resultado de Robot Framework: {e}"
    if cortado:
        ok, error = False, cortado

    fallido = next((nombre for nombre, estado, _ in pasos if estado == "FAIL"), "")
    if not ok and not fallido:
        fallido = "ejecucion"
    total = sum(duracion for _, estado, duracion in pasos if estado != "NOT RUN")

    if recorrido == "agendar":
        try:
            sobrantes = limpiar_citas()
            if sobrantes:
                error = (error + f" · se cancelaron {sobrantes} cita(s) que quedaron abiertas").strip(" ·")
        except Exception as e:
            error = (error + f" · no se pudo revisar si quedaron citas abiertas: {e}").strip(" ·")

    valores = [(f"rpa.status[{recorrido}]", 1 if ok else 0),
               (f"rpa.duration.total[{recorrido}]", f"{total:.2f}"),
               (f"rpa.failed_step[{recorrido}]", fallido),
               (f"rpa.error[{recorrido}]", error[:250])]
    valores += [(f"rpa.step[{recorrido},{nombre}]", f"{duracion:.2f}")
                for nombre, estado, duracion in pasos if estado != "NOT RUN"]
    enviados, fallidos, detalle = enviar(valores)

    # Las ejecuciones buenas no dejan nada; las malas guardan la captura y el log 7 días.
    if ok:
        shutil.rmtree(carpeta, ignore_errors=True)
    borrar_evidencia_vieja(base)

    resumen = ", ".join(f"{n} {d:.2f}" for n, e, d in pasos if e != "NOT RUN")
    print(f"{recorrido}: {'OK' if ok else 'FALLO en ' + fallido} · {total:.2f} s · {resumen}"
          f" · Zabbix: {enviados} enviados, {fallidos} rechazados" + (f" · {error[:160]}" if error else ""))
    if not enviados or fallidos:
        print(f"zabbix_sender: {detalle}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
