#!/usr/bin/env bash
# Levanta Zabbix en la VM de monitoreo, vm-zabbix 10.10.30.12 (IP2-41).
#
# Qué hace, en orden:
#   1. Zona horaria, Docker Engine con Compose y las herramientas de SNMP.
#   2. Trae el repositorio a /opt/integrador2 (o lo actualiza si ya está).
#   3. Crea .env con secretos aleatorios, solo si no existe.
#   4. Levanta la base, el servidor y el frontend de Zabbix.
#   5. Espera a que la API responda.
#
# Se corre en la VM con el usuario ip2 (usa sudo). Se puede repetir sin perder datos.
#
#   ./desplegar.sh
#
# La comunidad SNMP de R1 y SW1 no está en el repositorio. Antes de correrlo se deja
# en ~/snmp.env, en una línea  SNMP_COMMUNITY=...  ; el script la pasa al .env y borra
# ese archivo. Después hay que correr configurar-zabbix.py e instalar los agentes.
set -euo pipefail

REPO_URL="https://github.com/Proyect-integrador-2/Integrador2.git"
DESTINO="/opt/integrador2"
AQUI="$DESTINO/infra/vm-zabbix"
ZONA="America/Costa_Rica"

paso() { printf '\n== %s ==\n' "$*"; }

# Secreto aleatorio, solo letras y números.
secreto() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$1"; }

[[ $EUID -ne 0 ]] || { echo "Correrlo con el usuario ip2, no como root." >&2; exit 1; }
sudo -n true 2>/dev/null || { echo "Este usuario no tiene sudo sin contraseña." >&2; exit 1; }

# ---------------------------------------------------------------------------
paso "1. Sistema y Docker"
sudo timedatectl set-timezone "$ZONA"
export DEBIAN_FRONTEND=noninteractive
if ! command -v docker >/dev/null; then
  # Repositorio oficial de Docker para Ubuntu.
  sudo apt-get update -q
  sudo apt-get install -y -q ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
fi
sudo apt-get update -q
# snmp: para probar a mano que R1 y SW1 responden (snmpget, snmpwalk).
sudo apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git snmp
sudo systemctl enable --now docker
echo "  $(sudo docker --version)"

# ---------------------------------------------------------------------------
paso "2. Repositorio"
if [[ -d $DESTINO/.git ]]; then
  git -C "$DESTINO" pull --ff-only
else
  sudo install -d -o "$USER" -g "$USER" "$DESTINO"
  git clone --depth 1 "$REPO_URL" "$DESTINO"
fi
echo "  versión: $(git -C "$DESTINO" log -1 --format='%h %s')"

# ---------------------------------------------------------------------------
paso "3. Variables de entorno"
if [[ -s $AQUI/.env ]]; then
  echo "  $AQUI/.env ya existe: no se toca."
else
  (
    umask 077
    cat > "$AQUI/.env" <<EOF
# Generado por desplegar.sh. No se sube a Git.
ZBX_DB_PASSWORD=$(secreto 32)
# Contraseña del usuario Admin del frontend (reemplaza la de fábrica).
ZBX_ADMIN_PASSWORD=$(secreto 20)
# Usuario de solo lectura que usará Grafana.
ZABBIX_API_USER=grafana
ZABBIX_API_PASSWORD=$(secreto 24)
EOF
  )
  echo "  creado $AQUI/.env con secretos nuevos (permisos 600)."
fi
if [[ -s $HOME/snmp.env ]]; then
  comunidad=$(grep -m1 '^SNMP_COMMUNITY=' "$HOME/snmp.env" | tr -d '\r' || true)
  if [[ -n $comunidad ]]; then
    sed -i '/^SNMP_COMMUNITY=/d' "$AQUI/.env"
    printf '# Comunidad SNMP de solo lectura de R1 y SW1.\n%s\n' "$comunidad" >> "$AQUI/.env"
    echo "  comunidad SNMP guardada en .env."
  fi
  rm -f "$HOME/snmp.env"
fi
grep -q '^SNMP_COMMUNITY=' "$AQUI/.env" || echo "  AVISO: falta SNMP_COMMUNITY en .env; R1 y SW1 quedarán sin datos."

# ---------------------------------------------------------------------------
paso "4. Contenedores"
cd "$AQUI"
sudo docker compose up -d
sudo docker compose ps

# ---------------------------------------------------------------------------
paso "5. Frontend y API"
echo "  Esperando a que Zabbix cree su base y responda (la primera vez tarda un par de minutos)..."
version=""
for _ in $(seq 1 90); do
  version=$(curl -s -m 5 -H 'Content-Type: application/json-rpc' \
    -d '{"jsonrpc":"2.0","method":"apiinfo.version","params":{},"id":1}' \
    http://127.0.0.1/api_jsonrpc.php | grep -o '"result":"[^"]*"' || true)
  [[ -n $version ]] && break
  sleep 5
done
[[ -n $version ]] || { echo "La API no respondió. Ver: sudo docker compose logs server web" >&2; exit 1; }
echo "  API de Zabbix: $version"

cat <<EOF

Listo. Frontend en http://$(hostname -I | cut -d' ' -f1)  (usuario Admin).
Sigue:  python3 $AQUI/configurar-zabbix.py
EOF
