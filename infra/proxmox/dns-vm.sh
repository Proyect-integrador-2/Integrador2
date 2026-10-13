#!/usr/bin/env bash
# Pone en una VM Linux del laboratorio los servidores DNS que sí responden (IP2-33).
#
# Las VMs nacieron con 8.8.8.8. Desde la red de la universidad ese servidor pierde
# cerca del 40 % de las consultas (medido el 13 oct 2026: 8 fallos de 20), y cada
# fallo se veía como un error intermitente: avisos de Telegram que no salían, n8n
# sin resolver nombres. Los DNS de la universidad y 1.1.1.1 no perdieron ninguna.
#
# Se corre en cada VM con el usuario ip2 (usa sudo). Se puede repetir.
#
#   ./dns-vm.sh
set -euo pipefail

# Los dos de la universidad primero; 1.1.1.1 queda de respaldo.
SERVIDORES="10.100.8.2 10.100.8.3 1.1.1.1"

[[ $EUID -ne 0 ]] || { echo "Correrlo con el usuario ip2, no como root." >&2; exit 1; }

# 1. El sistema. "Domains=~." hace que estos servidores se usen para todo, por encima
#    del 8.8.8.8 que cloud-init dejó en la tarjeta de red.
#    Con Docker, el resolvedor de la VM escucha además en la dirección del puente de
#    Docker para que los contenedores lo usen a él (paso 2).
PUENTE="172.17.0.1"
escucha=""
command -v docker >/dev/null && escucha="DNSStubListenerExtra=$PUENTE"
sudo install -d /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/ip2-dns.conf >/dev/null <<EOF
# Integrador II: ver infra/proxmox/dns-vm.sh
[Resolve]
DNS=$SERVIDORES
Domains=~.
$escucha
EOF
sudo systemctl restart systemd-resolved

# 2. Docker, si está: los contenedores preguntan al resolvedor de la VM, no a los
#    servidores de afuera. Así comparten su memoria de respuestas y sus reintentos: la
#    red del laboratorio pierde de vez en cuando una consulta DNS, y una sola pérdida
#    dejaba al contenedor esperando varios segundos. Solo se reinicia Docker si algo cambió.
if command -v docker >/dev/null; then
  lista="[\"$PUENTE\"]"
  nuevo=$(sudo python3 - "$lista" <<'PY'
import json, os, sys
ruta = "/etc/docker/daemon.json"
actual = json.load(open(ruta)) if os.path.exists(ruta) and os.path.getsize(ruta) else {}
deseado = dict(actual, dns=json.loads(sys.argv[1]))
if deseado != actual:
    json.dump(deseado, open(ruta, "w"), indent=2)
    print("cambio")
PY
)
  if [[ $nuevo == cambio ]]; then
    sudo systemctl restart docker
    echo "  Docker reiniciado con los DNS nuevos."
  fi
fi

# 3. Comprobación: diez resoluciones seguidas.
fallos=0
for _ in $(seq 1 10); do
  resolvectl query -4 --cache=no api.telegram.org >/dev/null 2>&1 || fallos=$((fallos + 1))
done
printf '%s: DNS %s · %s fallos de 10\n' "$(hostname)" "$(resolvectl dns | awk -F': ' '/^Global/{print $2}')" "$fallos"
