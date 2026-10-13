#!/usr/bin/env bash
# Despliega MS Motos en la VM de aplicación, vm-app 10.10.30.11 (IP2-38).
#
# Qué hace, en orden:
#   1. Zona horaria, Docker Engine con Compose, y Nginx.
#   2. Trae el repositorio a /opt/integrador2 (o lo actualiza si ya está).
#   3. Crea app/.env con secretos aleatorios, solo si no existe.
#   4. Construye la imagen y levanta la base y la aplicación.
#   5. Crea las cuentas iniciales (admin, recepción y el usuario del RPA).
#   6. Configura Nginx como servicio del sistema, de proxy hacia el contenedor.
#   7. Comprueba que todo responde.
#
# Se corre en la VM con el usuario ip2 (usa sudo). Se puede repetir: no borra datos
# ni cambia los secretos que ya existen.
#
#   ./desplegar.sh
#
# Las contraseñas quedan solo en /opt/integrador2/app/.env (permisos 600). Para verlas:
#   grep SEED_ /opt/integrador2/app/.env
set -euo pipefail

REPO_URL="https://github.com/Proyect-integrador-2/Integrador2.git"
DESTINO="/opt/integrador2"
APP="$DESTINO/app"
ZONA="America/Costa_Rica"

paso() { printf '\n== %s ==\n' "$*"; }

# Secreto aleatorio, solo letras y números: no da problemas en el .env ni en MySQL.
secreto() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$1"; }

[[ $EUID -ne 0 ]] || { echo "Correrlo con el usuario ip2, no como root." >&2; exit 1; }
sudo -n true 2>/dev/null || { echo "Este usuario no tiene sudo sin contraseña." >&2; exit 1; }

# ---------------------------------------------------------------------------
paso "1. Sistema, Docker y Nginx"
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
sudo apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin nginx git
sudo systemctl enable --now docker nginx
echo "  $(sudo docker --version)"
echo "  $(sudo docker compose version)"

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
if [[ -s $APP/.env ]]; then
  echo "  $APP/.env ya existe: no se toca."
else
  (
    umask 077
    sed -e "s|^DB_PASSWORD=.*|DB_PASSWORD=$(secreto 32)|" \
        -e "s|^MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=$(secreto 32)|" \
        -e "s|^JWT_SECRET=.*|JWT_SECRET=$(secreto 48)|" \
        -e "s|^SEED_ADMIN_PASSWORD=.*|SEED_ADMIN_PASSWORD=$(secreto 16)|" \
        -e "s|^SEED_RECEP_PASSWORD=.*|SEED_RECEP_PASSWORD=$(secreto 16)|" \
        -e "s|^SEED_RPA_PASSWORD=.*|SEED_RPA_PASSWORD=$(secreto 16)|" \
        "$APP/.env.example" > "$APP/.env"
  )
  echo "  creado $APP/.env con secretos nuevos (permisos 600)."
fi

# ---------------------------------------------------------------------------
paso "4. Contenedores"
cd "$APP"
sudo docker compose up -d --build
echo "  Esperando a que la aplicación quede sana..."
for _ in $(seq 1 60); do
  estado=$(sudo docker inspect -f '{{.State.Health.Status}}' msmotos-app 2>/dev/null || echo "sin-crear")
  [[ $estado == healthy ]] && break
  sleep 5
done
sudo docker compose ps
[[ $estado == healthy ]] || { echo "La aplicación no quedó sana. Ver: sudo docker compose logs app" >&2; exit 1; }

# ---------------------------------------------------------------------------
paso "5. Cuentas iniciales"
sudo docker compose run --rm seed

# ---------------------------------------------------------------------------
paso "6. Nginx"
sudo install -m 0644 "$APP/docker/nginx/msmotos.conf" /etc/nginx/sites-available/msmotos.conf
sudo ln -sf /etc/nginx/sites-available/msmotos.conf /etc/nginx/sites-enabled/msmotos.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

# ---------------------------------------------------------------------------
paso "7. Comprobación"
ip=$(hostname -I | cut -d' ' -f1)
printf '  contenedor  (127.0.0.1:3000/api/health): HTTP %s\n' "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/api/health)"
printf '  por Nginx   (%s/api/health):     HTTP %s\n' "$ip" "$(curl -s -o /dev/null -w '%{http_code}' "http://$ip/api/health")"
printf '  portada     (%s/):               HTTP %s\n' "$ip" "$(curl -s -o /dev/null -w '%{http_code}' "http://$ip/")"

cat <<EOF

Listo. La aplicación responde en http://$ip
Cuentas: admin@taller.com, recepcion@taller.com y rpa@taller.local.
Sus contraseñas:  grep SEED_ $APP/.env
EOF
