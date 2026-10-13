#!/usr/bin/env bash
# Levanta Grafana en la VM de dashboards, vm-grafana 10.10.30.13 (IP2-47).
#
# Qué hace, en orden:
#   1. Zona horaria y Docker Engine con Compose.
#   2. Trae el repositorio a /opt/integrador2 (o lo actualiza si ya está).
#   3. Crea .env: contraseña de admin aleatoria y el usuario de Zabbix de solo lectura.
#   4. Levanta Grafana con el plugin de Zabbix, la fuente de datos y los cinco tableros.
#   5. Comprueba la fuente de datos y los tableros cargados.
#
# Se corre en la VM con el usuario ip2 (usa sudo). Se puede repetir sin perder datos.
#
#   ./desplegar.sh
#
# El usuario de Zabbix que usa Grafana lo crea configurar-zabbix.py en vm-zabbix. Antes
# de correr este script, sus dos líneas (ZABBIX_API_USER y ZABBIX_API_PASSWORD) se dejan
# en ~/zabbix-api.env; el script las pasa al .env y borra ese archivo.
set -euo pipefail

REPO_URL="https://github.com/Proyect-integrador-2/Integrador2.git"
DESTINO="/opt/integrador2"
AQUI="$DESTINO/infra/vm-grafana"
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
sudo apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git
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
  echo "  $AQUI/.env ya existe: no se toca la contraseña de admin."
else
  (
    umask 077
    cat > "$AQUI/.env" <<EOF
# Generado por desplegar.sh. No se sube a Git.
GRAFANA_ADMIN_PASSWORD=$(secreto 20)
ZABBIX_API_URL=http://10.10.30.12/api_jsonrpc.php
EOF
  )
  echo "  creado $AQUI/.env con la contraseña de admin (permisos 600)."
fi
if [[ -s $HOME/zabbix-api.env ]]; then
  sed -i '/^ZABBIX_API_USER=/d; /^ZABBIX_API_PASSWORD=/d' "$AQUI/.env"
  grep -E '^ZABBIX_API_(USER|PASSWORD)=' "$HOME/zabbix-api.env" | tr -d '\r' >> "$AQUI/.env"
  rm -f "$HOME/zabbix-api.env"
  echo "  usuario de Zabbix de solo lectura guardado en .env."
fi
grep -q '^ZABBIX_API_PASSWORD=' "$AQUI/.env" \
  || { echo "Falta ZABBIX_API_PASSWORD: dejar las líneas del usuario de Zabbix en ~/zabbix-api.env y repetir." >&2; exit 1; }

# ---------------------------------------------------------------------------
paso "4. Contenedor"
cd "$AQUI"
sudo docker compose up -d
echo "  Esperando a Grafana (la primera vez descarga el plugin de Zabbix)..."
ok=""
for _ in $(seq 1 60); do
  ok=$(curl -s -m 5 http://127.0.0.1/api/health | grep -o '"database": *"ok"' || true)
  [[ -n $ok ]] && break
  sleep 5
done
sudo docker compose ps
[[ -n $ok ]] || { echo "Grafana no respondió. Ver: sudo docker compose logs grafana" >&2; exit 1; }

# ---------------------------------------------------------------------------
paso "5. Comprobación"
clave=$(grep -m1 '^GRAFANA_ADMIN_PASSWORD=' .env | cut -d= -f2-)
api() { curl -s -m 20 -u "admin:$clave" "http://127.0.0.1$1"; }
printf '  versión:          %s\n' "$(api /api/health | grep -o '"version": *"[^"]*"' | cut -d'"' -f4)"
printf '  fuente de datos:  %s\n' "$(api /api/datasources/uid/zabbix/health | grep -o '"message": *"[^"]*"' | cut -d'"' -f4)"
printf '  tableros con la etiqueta ip2: %s\n' "$(api '/api/search?tag=ip2' | grep -o '"uid"' | wc -l)"

cat <<EOF

Listo. Grafana en http://$(hostname -I | cut -d' ' -f1)  (usuario admin).
Su contraseña:  grep GRAFANA_ADMIN $AQUI/.env
EOF
