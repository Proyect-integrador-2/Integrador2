#!/usr/bin/env bash
# Instala el cliente sintético (RPA) en vm-rpa, 10.10.30.15 (IP2-56, IP2-57).
#
# Qué hace, en orden:
#   1. Zona horaria, Python y el emisor de Zabbix.
#   2. Trae el repositorio a /opt/integrador2 (o lo actualiza si ya está).
#   3. Entorno de Python con Robot Framework, la librería Browser y Chromium.
#   4. Crea rpa/.env con la cuenta del cliente sintético.
#   5. Programa los dos recorridos con temporizadores de systemd.
#   6. Corre cada recorrido una vez para comprobar.
#
# Se corre en la VM con el usuario ip2 (usa sudo). Se puede repetir.
#
#   ./desplegar.sh
#
# La cuenta del cliente sintético la crea el despliegue de vm-app. Antes de correr este
# script, sus dos líneas se dejan en ~/rpa.env como RPA_CORREO=... y RPA_CLAVE=...; el
# script las pasa a rpa/.env y borra ese archivo. Antes también hay que haber corrido
# configurar-zabbix.py en vm-zabbix, que crea el host que recibe los resultados.
set -euo pipefail
umask 022

REPO_URL="https://github.com/Proyect-integrador-2/Integrador2.git"
DESTINO="/opt/integrador2"
RPA="$DESTINO/rpa"
BASE="/opt/rpa"
ZONA="America/Costa_Rica"

paso() { printf '\n== %s ==\n' "$*"; }

[[ $EUID -ne 0 ]] || { echo "Correrlo con el usuario ip2, no como root." >&2; exit 1; }
sudo -n true 2>/dev/null || { echo "Este usuario no tiene sudo sin contraseña." >&2; exit 1; }

# ---------------------------------------------------------------------------
paso "1. Sistema"
sudo timedatectl set-timezone "$ZONA"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -q
# zabbix-sender sale del repositorio de Zabbix que agregó instalar-agente.sh.
sudo apt-get install -y -q python3-venv git zabbix-sender

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
paso "3. Robot Framework y navegador"
sudo install -d -o "$USER" -g "$USER" "$BASE" "$BASE/salidas"
[[ -x $BASE/venv/bin/python ]] || python3 -m venv "$BASE/venv"
"$BASE/venv/bin/pip" install -q --upgrade pip
"$BASE/venv/bin/pip" install -q -r "$RPA/requirements.txt"
# Con las "baterías" de la librería no hace falta Node.js en la VM. --with-deps instala
# con apt las bibliotecas del sistema que necesita Chromium.
if ! find "$BASE/venv" -type d -name 'chromium_headless_shell-*' | grep -q .; then
  "$BASE/venv/bin/rfbrowser" install --with-deps chromium
fi
echo "  $("$BASE/venv/bin/robot" --version | head -1)"

# ---------------------------------------------------------------------------
paso "4. Variables de entorno"
if [[ ! -s $RPA/.env ]]; then
  (
    umask 077
    cat > "$RPA/.env" <<EOF
# Generado por desplegar.sh. No se sube a Git.
RPA_URL=http://10.10.30.11
ZABBIX_SERVER=10.10.30.12
ZABBIX_HOST=msmotos-rpa-linux
RPA_SALIDAS=$BASE/salidas
EOF
  )
  echo "  creado $RPA/.env (permisos 600)."
fi
if [[ -s $HOME/rpa.env ]]; then
  sed -i '/^RPA_CORREO=/d; /^RPA_CLAVE=/d' "$RPA/.env"
  grep -E '^RPA_(CORREO|CLAVE)=' "$HOME/rpa.env" | tr -d '\r' >> "$RPA/.env"
  rm -f "$HOME/rpa.env"
  echo "  cuenta del cliente sintético guardada en .env."
fi
for variable in RPA_CORREO RPA_CLAVE; do
  grep -q "^$variable=" "$RPA/.env" \
    || { echo "Falta $variable: dejar las líneas de la cuenta en ~/rpa.env y repetir." >&2; exit 1; }
done

# ---------------------------------------------------------------------------
paso "5. Temporizadores"
for recorrido in consulta agendar; do
  sudo tee "/etc/systemd/system/rpa-$recorrido.service" >/dev/null <<EOF
[Unit]
Description=Cliente sintético de MS Motos: recorrido de $recorrido (IP2-57)
After=network-online.target

[Service]
Type=oneshot
User=$USER
EnvironmentFile=$RPA/.env
ExecStart=$BASE/venv/bin/python $RPA/ejecutar.py $recorrido
TimeoutStartSec=120
EOF
done
# Consulta cada 5 minutos; agendar cada 30, a los minutos 13 y 43 para no coincidir.
sudo tee /etc/systemd/system/rpa-consulta.timer >/dev/null <<'EOF'
[Unit]
Description=Cada 5 minutos: recorrido de consulta del cliente sintético

[Timer]
OnCalendar=*:0/5
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
sudo tee /etc/systemd/system/rpa-agendar.timer >/dev/null <<'EOF'
[Unit]
Description=Cada 30 minutos: recorrido de agendar del cliente sintético

[Timer]
OnCalendar=*:13,43
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now rpa-consulta.timer rpa-agendar.timer >/dev/null 2>&1
systemctl list-timers 'rpa-*' --no-pager | head -4

# ---------------------------------------------------------------------------
paso "6. Primera ejecución"
for recorrido in consulta agendar; do
  sudo systemctl start "rpa-$recorrido.service" || true
  journalctl -u "rpa-$recorrido.service" -n 1 --no-pager -o cat
done

cat <<EOF

Listo. Los resultados llegan a Zabbix, host msmotos-rpa-linux.
Ver las últimas ejecuciones:  journalctl -u 'rpa-*' -n 20 --no-pager -o short
Capturas de los fallos:       $BASE/salidas
EOF
