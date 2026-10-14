#!/usr/bin/env bash
# Levanta n8n en la VM de automatización, vm-n8n 10.10.30.14 (IP2-50, IP2-52, IP2-53).
#
# Qué hace, en orden:
#   1. Zona horaria y Docker Engine con Compose.
#   2. Trae el repositorio a /opt/integrador2 (o lo actualiza si ya está).
#   3. Crea .env: clave de cifrado aleatoria y los dos tokens que vienen de Zabbix.
#   4. Genera la llave SSH con la que n8n entra a vm-app como n8n-ops.
#   5. Levanta n8n, importa la credencial SSH y el flujo de recuperación, y lo publica.
#
# Se corre en la VM con el usuario ip2 (usa sudo). Se puede repetir sin perder datos.
#
#   ./desplegar.sh
#
# Los tokens los crea configurar-zabbix.py en vm-zabbix. Antes de correr este script,
# sus dos líneas (N8N_WEBHOOK_TOKEN y ZABBIX_N8N_TOKEN) se dejan en ~/zabbix-n8n.env;
# el script las pasa al .env y borra ese archivo.
#
# Al terminar muestra dónde quedó la llave pública: hay que instalarla en vm-app con
# infra/vm-app/preparar-n8n-ops.sh.
set -euo pipefail
# Los contenedores leen archivos del repositorio con otro usuario: que no hereden una
# máscara restrictiva de la sesión. Los .env y la llave se crean aparte, con permisos 600.
umask 022

REPO_URL="https://github.com/Proyect-integrador-2/Integrador2.git"
DESTINO="/opt/integrador2"
AQUI="$DESTINO/infra/vm-n8n"
FLUJOS="$DESTINO/automatizacion/n8n"
LLAVE="$AQUI/secrets/n8n_ops_ed25519"
VM_APP="10.10.30.11"
VM_APP_WIN="10.10.30.16"
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
  echo "  $AQUI/.env ya existe: no se toca la clave de cifrado."
else
  (
    umask 077
    cat > "$AQUI/.env" <<EOF
# Generado por desplegar.sh. No se sube a Git.
# Clave con la que n8n cifra las credenciales guardadas. Si se pierde, hay que recrearlas.
N8N_ENCRYPTION_KEY=$(secreto 40)
ZABBIX_API_URL=http://10.10.30.12/api_jsonrpc.php
EOF
  )
  echo "  creado $AQUI/.env con la clave de cifrado (permisos 600)."
fi
if [[ -s $HOME/zabbix-n8n.env ]]; then
  sed -i '/^N8N_WEBHOOK_TOKEN=/d; /^ZABBIX_N8N_TOKEN=/d' "$AQUI/.env"
  grep -E '^(N8N_WEBHOOK_TOKEN|ZABBIX_N8N_TOKEN)=' "$HOME/zabbix-n8n.env" | tr -d '\r' >> "$AQUI/.env"
  rm -f "$HOME/zabbix-n8n.env"
  echo "  tokens de Zabbix guardados en .env."
fi
for variable in N8N_WEBHOOK_TOKEN ZABBIX_N8N_TOKEN; do
  grep -q "^$variable=" "$AQUI/.env" \
    || { echo "Falta $variable: dejar las líneas de vm-zabbix en ~/zabbix-n8n.env y repetir." >&2; exit 1; }
done

# ---------------------------------------------------------------------------
paso "4. Llave SSH de n8n"
if [[ -s $LLAVE ]]; then
  echo "  la llave ya existe: no se regenera."
else
  ( umask 077; mkdir -p "$(dirname "$LLAVE")"; ssh-keygen -q -t ed25519 -N '' -C 'n8n-ops@vm-n8n' -f "$LLAVE" )
  echo "  llave generada en $LLAVE (la privada no sale de esta VM)."
fi

# ---------------------------------------------------------------------------
paso "5. n8n, credencial y flujo"
cd "$AQUI"
sudo docker compose up -d
echo "  Esperando a n8n..."
ok=""
for _ in $(seq 1 60); do
  ok=$(curl -s -m 5 http://127.0.0.1:5678/healthz | grep -o '"status": *"ok"' || true)
  [[ -n $ok ]] && break
  sleep 5
done
[[ -n $ok ]] || { echo "n8n no respondió. Ver: sudo docker compose logs n8n" >&2; exit 1; }

# La credencial se arma en un archivo temporal de la VM y se borra: la llave privada
# no pasa por ningún otro equipo. n8n la guarda cifrada con N8N_ENCRYPTION_KEY.
temporal=$(mktemp)
python3 - "$LLAVE" "$VM_APP" "$VM_APP_WIN" > "$temporal" <<'PY'
import json, sys
llave = open(sys.argv[1]).read()
# La misma llave para las dos VMs de la aplicación; en cada una la cuenta n8n-ops
# solo puede hacer lo de su lista cerrada.
print(json.dumps([
    {"id": "IP2sshN8nOps01", "name": "SSH vm-app (n8n-ops)", "type": "sshPrivateKey",
     "data": {"host": sys.argv[2], "port": 22, "username": "n8n-ops", "privateKey": llave}},
    {"id": "IP2sshN8nOpsWin01", "name": "SSH vm-app-win (n8n-ops)", "type": "sshPrivateKey",
     "data": {"host": sys.argv[3], "port": 22, "username": "n8n-ops", "privateKey": llave}},
]))
PY
sudo docker cp "$temporal" n8n:/tmp/credencial.json
rm -f "$temporal"
sudo docker exec -u root n8n chown node:node /tmp/credencial.json
sudo docker exec n8n n8n import:credentials --input=/tmp/credencial.json
sudo docker exec n8n rm -f /tmp/credencial.json

# Todos los flujos versionados: la recuperación desde Zabbix y la consulta /estado por Telegram.
for flujo in "$FLUJOS"/*.json; do
  id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["id"])' "$flujo")
  sudo docker cp "$flujo" n8n:/tmp/flujo.json
  sudo docker exec -u root n8n chown node:node /tmp/flujo.json
  sudo docker exec n8n n8n import:workflow --input=/tmp/flujo.json
  sudo docker exec n8n n8n publish:workflow --id="$id"
  sudo docker exec n8n rm -f /tmp/flujo.json
done
# n8n 2.x registra el webhook de un flujo publicado al arrancar.
sudo docker compose restart n8n
for _ in $(seq 1 30); do
  curl -s -m 5 http://127.0.0.1:5678/healthz | grep -q '"status": *"ok"' && break
  sleep 3
done
# n8n responde "ok" unos segundos antes de registrar el webhook: se espera a que exista.
codigo=""
for _ in $(seq 1 20); do
  codigo=$(curl -s -o /dev/null -m 10 -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:5678/webhook/zabbix)
  [[ $codigo == 200 ]] && break
  sleep 3
done
printf '  webhook sin token: HTTP %s (200 = lo recibe; el flujo lo descarta por no traer el token)\n' "$codigo"
[[ $codigo == 200 ]] || { echo "El webhook no quedó registrado. Ver: sudo docker compose logs n8n" >&2; exit 1; }
sudo docker compose ps

cat <<EOF

Listo. n8n en http://$(hostname -I | cut -d' ' -f1):5678
Falta instalar la llave pública en vm-app:  $LLAVE.pub
La primera persona que abra n8n crea la cuenta de dueño: hacerlo de inmediato.
EOF
