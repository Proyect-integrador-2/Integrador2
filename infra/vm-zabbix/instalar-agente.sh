#!/usr/bin/env bash
# Instala Zabbix agent 2 en una VM Linux del proyecto y lo apunta a vm-zabbix (IP2-42).
#
# Se corre en cada VM con el usuario ip2 (usa sudo). Se puede repetir.
#
#   ./instalar-agente.sh              servidor por defecto: 10.10.30.12
#   ./instalar-agente.sh 10.10.30.12
#
# El nombre con que el agente se presenta es el de la VM (vm-app, vm-zabbix...), que es
# el mismo nombre del host en Zabbix.
set -euo pipefail

SERVIDOR="${1:-10.10.30.12}"
SERIE="7.0"
CONF="/etc/zabbix/zabbix_agent2.conf"

[[ $EUID -ne 0 ]] || { echo "Correrlo con el usuario ip2, no como root." >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
if ! command -v zabbix_agent2 >/dev/null; then
  # shellcheck disable=SC1091
  version_ubuntu=$(. /etc/os-release && echo "$VERSION_ID")
  paquete="zabbix-release_latest_${SERIE}+ubuntu${version_ubuntu}_all.deb"
  curl -fsSLo "/tmp/$paquete" "https://repo.zabbix.com/zabbix/$SERIE/ubuntu/pool/main/z/zabbix-release/$paquete"
  sudo dpkg -i "/tmp/$paquete"
  rm -f "/tmp/$paquete"
  sudo apt-get update -q
  sudo apt-get install -y -q zabbix-agent2
fi

# En vm-zabbix el servidor corre en un contenedor: sus consultas a esta misma VM llegan
# desde la red interna de Docker, no desde 10.10.30.12.
permitidos="$SERVIDOR"
[[ $(hostname) == vm-zabbix ]] && permitidos="$SERVIDOR,172.16.0.0/12"

sudo sed -i \
  -e "s|^Server=.*|Server=$permitidos|" \
  -e "s|^ServerActive=.*|ServerActive=$SERVIDOR|" \
  -e "s|^Hostname=.*|Hostname=$(hostname)|" \
  "$CONF"

# Con Docker en la VM, el agente necesita leer su socket para vigilar los contenedores.
if getent group docker >/dev/null; then
  sudo usermod -aG docker zabbix
fi

sudo systemctl enable zabbix-agent2 >/dev/null 2>&1
sudo systemctl restart zabbix-agent2
sleep 2
printf '%s: %s, agente %s, servidor %s\n' "$(hostname)" "$(systemctl is-active zabbix-agent2)" \
  "$(zabbix_agent2 -V | head -1 | awk '{print $NF}')" "$permitidos"
