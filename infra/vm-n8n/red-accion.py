#!/usr/bin/env python3
"""Lo único que n8n puede hacer en la red (IP2-85, IP2-86).

n8n no entra directo al switch: el 2960 solo ofrece algoritmos de SSH antiguos que el
nodo SSH de n8n no soporta. n8n entra por SSH a vm-n8n con la cuenta n8n-red, y sshd
obliga a que esa sesión ejecute este programa, que acepta dos pedidos:

    estado Fa0/5       estado del puerto (connected, notconnect, err-disabled, disabled...)
    reiniciar Fa0/5    shutdown, 5 segundos, no shutdown, y espera a que vuelva

Controles (docs/diseno/automatizacion.md, sección 5):
  - Lista blanca (C8): solo los puertos de acceso Fa0/1 a Fa0/20 de SW1. Los enlaces de
    gestión (Gi0/1 hacia R1, Gi0/2 hacia el servidor, la VLAN 99) no están en la lista:
    apagarlos dejaría a n8n sin camino para volver a encenderlos.
  - Un puerto apagado por una persona (`shutdown`, estado "disabled") no se toca.
  - En el switch, la cuenta n8n-net tiene un nivel de privilegio propio que solo permite
    entrar a una interfaz, shutdown, no shutdown y ver interfaces.

Código de salida: 0 el puerto quedó conectado (o la consulta salió bien), 2 pedido no
permitido, 3 se reinició pero sigue sin conexión, 4 apagado por una persona, 5 error de
conexión con el switch. Cada acción queda en el registro del sistema (journalctl -t ip2-red).
"""
import os
import re
import sys
import syslog
import time
from pathlib import Path

ENV = Path("/etc/ip2/red.env")
CONOCIDOS = Path.home() / ".ssh" / "known_hosts_red"
PERMITIDAS = {f"Fa0/{n}" for n in range(1, 21)}
ESTADOS = ("err-disabled", "notconnect", "connected", "disabled", "inactive", "monitoring", "faulty")
ESPERA_REINICIO = 5       # segundos entre shutdown y no shutdown
ESPERA_ENLACE = 30        # segundos que se espera a que el puerto vuelva


def salir(codigo, texto):
    print(texto)
    syslog.syslog(texto)
    sys.exit(codigo)


def leer_env():
    valores = {}
    for linea in ENV.read_text(encoding="utf-8").splitlines():
        if "=" in linea and not linea.lstrip().startswith("#"):
            k, v = linea.split("=", 1)
            valores[k.strip()] = v.strip()
    return valores


def conectar(cfg):
    import paramiko
    cliente = paramiko.SSHClient()
    # La llave del switch se aprende la primera vez y después se exige la misma.
    CONOCIDOS.parent.mkdir(mode=0o700, exist_ok=True)
    CONOCIDOS.touch(mode=0o600, exist_ok=True)
    cliente.load_host_keys(str(CONOCIDOS))
    cliente.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    cliente.connect(cfg["SW1_HOST"], username=cfg["SW1_USUARIO"], password=cfg["SW1_CLAVE"],
                    look_for_keys=False, allow_agent=False, timeout=15, banner_timeout=15, auth_timeout=15)
    cliente.save_host_keys(str(CONOCIDOS))
    return cliente


class Consola:
    """Sesión interactiva con el switch: manda una línea y lee hasta el prompt."""

    def __init__(self, cliente):
        self.canal = cliente.invoke_shell(width=200, height=0)
        self.leer(3)
        self.enviar("terminal length 0")

    def leer(self, espera):
        datos, fin = b"", time.time() + espera
        while time.time() < fin:
            if self.canal.recv_ready():
                datos += self.canal.recv(65535)
                if re.search(rb"[>#]\s*$", datos):
                    break
            else:
                time.sleep(0.1)
        return datos.decode(errors="replace")

    def enviar(self, linea, espera=5):
        self.canal.send(linea + "\n")
        salida = self.leer(espera)
        if "% Invalid" in salida or "% Authorization failed" in salida or "% Ambiguous" in salida:
            raise RuntimeError(f"el switch rechazó '{linea}': {salida.strip()[-120:]}")
        return salida

    def estado(self, puerto):
        salida = self.enviar(f"show interfaces {puerto} status")
        for linea in salida.splitlines():
            if linea.startswith(puerto + " "):
                for estado in ESTADOS:
                    if re.search(rf"\s{re.escape(estado)}\s", linea + " "):
                        return estado
        raise RuntimeError(f"no se pudo leer el estado de {puerto}")


def main():
    syslog.openlog("ip2-red")
    # El nodo SSH de n8n antepone "cd <carpeta> ;" a cada comando: se quita.
    pedido = re.sub(r"^cd\s+\S+\s*(;|&&)\s*", "", os.environ.get("SSH_ORIGINAL_COMMAND", "").strip())
    m = re.fullmatch(r"(estado|reiniciar) (Fa0/\d{1,2})", pedido)
    if not m or m.group(2) not in PERMITIDAS:
        salir(2, "Accion no permitida: " + re.sub(r"[^\w /;&.-]", "?", pedido)[:80])
    accion, puerto = m.groups()

    try:
        consola = Consola(conectar(leer_env()))
        antes = consola.estado(puerto)
        if accion == "estado":
            salir(0, f"{puerto} {antes}")
        if antes == "disabled":
            salir(4, f"{puerto} está apagado a propósito (shutdown): no se toca")
        consola.enviar("configure terminal")
        consola.enviar(f"interface {puerto}")
        consola.enviar("shutdown")
        time.sleep(ESPERA_REINICIO)
        consola.enviar("no shutdown")
        consola.enviar("end")
        ahora, fin = antes, time.time() + ESPERA_ENLACE
        while time.time() < fin:
            time.sleep(3)
            ahora = consola.estado(puerto)
            if ahora == "connected":
                break
    except SystemExit:
        raise
    except Exception as error:  # noqa: BLE001 - se informa cualquier falla a n8n
        salir(5, f"Error con el switch: {error}")

    if ahora == "connected":
        salir(0, f"{puerto}: estaba {antes}, se reinició y quedó conectado")
    salir(3, f"{puerto}: estaba {antes}, se reinició y sigue {ahora}: revisar el cable o el equipo conectado")


if __name__ == "__main__":
    main()
