#!/usr/bin/env bash
# Instala el cliente sintético (RPA) en vm-rpa, 10.10.30.15 (IP2-56, IP2-57).
#
# Qué hace, en orden:
#   1. Zona horaria, Python y el emisor de Zabbix.
#   2. Trae el repositorio a /opt/integrador2 (o lo actualiza si ya está).
#   3. Entorno de Python con Robot Framework, la librería Browser y Chromium.
#   4. Crea el archivo de variables de cada instancia (Linux y Windows) con su cuenta.
#   5. Programa los dos recorridos de cada instancia con temporizadores de systemd.
#   6. Corre cada recorrido una vez para comprobar.
#
# Se corre en la VM con el usuario ip2 (usa sudo). Se puede repetir.
#
#   ./desplegar.sh
#
# La cuenta del cliente sintético la crea el despliegue de cada instancia de la aplicación.
# Antes de correr este script, sus dos líneas (RPA_CORREO=... y RPA_CLAVE=...) se dejan en
# ~/rpa.env para la instancia Linux y en ~/rpa-windows.env para la de Windows; el script
# las guarda y borra esos archivos. Antes también hay que haber corrido configurar-zabbix.py
# en vm-zabbix, que crea los hosts que reciben los resultados.
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
sudo apt-get install -y -q python3-venv git zabbix-sender libnss3-tools ca-certificates

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
paso "3b. Confianza en la autoridad interna (HTTPS)"
# La instancia Linux se publica por HTTPS con un certificado de la autoridad interna del
# laboratorio (infra/proxmox/ca-interna.sh). El robot tiene que confiar en ella como
# confiaría un cliente: Python y curl usan el almacén del sistema; Chromium, el suyo (NSS).
CA="$DESTINO/infra/ca/ip2-ca.crt"
sudo install -m 644 "$CA" /usr/local/share/ca-certificates/ip2-ca.crt
sudo update-ca-certificates >/dev/null
install -d -m 700 "$HOME/.pki/nssdb"
[[ -s $HOME/.pki/nssdb/cert9.db ]] || certutil -d "sql:$HOME/.pki/nssdb" -N --empty-password
certutil -d "sql:$HOME/.pki/nssdb" -D -n "IP2 CA interna" 2>/dev/null || true
certutil -d "sql:$HOME/.pki/nssdb" -A -t "C,," -n "IP2 CA interna" -i "$CA"
echo "  $(curl -s -o /dev/null -w 'https://10.10.30.11/api/health con el certificado verificado: HTTP %{http_code}' https://10.10.30.11/api/health)"

# ---------------------------------------------------------------------------
# El robot mide las dos instancias de la aplicación. Cada una tiene su archivo de
# variables, su host en Zabbix y sus temporizadores, con minutos distintos para que
# los recorridos no coincidan.
#   sufijo  variables      dirección            host en Zabbix        cuenta            consulta  agendar
INSTANCIAS=(
  "-      .env           https://10.10.30.11  msmotos-rpa-linux     rpa.env           *:0/5     *:13,43"
  "-win   .env.windows   http://10.10.30.16   msmotos-rpa-windows   rpa-windows.env   *:2/5     *:28,58"
)

paso "4. Variables de entorno"
activas=()
for fila in "${INSTANCIAS[@]}"; do
  read -r sufijo variables url host cuenta _ <<<"$fila"
  [[ $sufijo == - ]] && sufijo=""
  archivo="$RPA/$variables"
  if [[ ! -s $archivo && ( -n $sufijo && ! -s $HOME/$cuenta ) ]]; then
    echo "  $host: sin cuenta todavía (dejar sus dos líneas en ~/$cuenta y repetir). Se omite."
    continue
  fi
  if [[ ! -s $archivo ]]; then
    (
      umask 077
      cat > "$archivo" <<EOF
# Generado por desplegar.sh. No se sube a Git.
RPA_URL=$url
ZABBIX_SERVER=10.10.30.12
ZABBIX_HOST=$host
RPA_SALIDAS=$BASE/salidas$sufijo
EOF
    )
    echo "  creado $archivo (permisos 600)."
  fi
  # La instancia Linux pasó a HTTPS (IP2-90): se corrige un archivo de antes.
  sed -i "s|^RPA_URL=http://10.10.30.11$|RPA_URL=$url|" "$archivo" 2>/dev/null || true
  if [[ -s $HOME/$cuenta ]]; then
    sed -i '/^RPA_CORREO=/d; /^RPA_CLAVE=/d' "$archivo"
    grep -E '^RPA_(CORREO|CLAVE)=' "$HOME/$cuenta" | tr -d '\r' >> "$archivo"
    rm -f "$HOME/$cuenta"
    echo "  $host: cuenta del cliente sintético guardada."
  fi
  for variable in RPA_CORREO RPA_CLAVE; do
    grep -q "^$variable=" "$archivo" \
      || { echo "Falta $variable: dejar las líneas de la cuenta en ~/$cuenta y repetir." >&2; exit 1; }
  done
  sudo install -d -o "$USER" -g "$USER" "$BASE/salidas$sufijo"
  activas+=("$fila")
done

# ---------------------------------------------------------------------------
paso "5. Temporizadores"
unidades=()
for fila in "${activas[@]}"; do
  read -r sufijo variables _ host _ cada_consulta cada_agendar <<<"$fila"
  [[ $sufijo == - ]] && sufijo=""
  for recorrido in consulta agendar; do
    cuando=$cada_consulta
    [[ $recorrido == agendar ]] && cuando=$cada_agendar
    sudo tee "/etc/systemd/system/rpa-$recorrido$sufijo.service" >/dev/null <<EOF
[Unit]
Description=Cliente sintético de MS Motos: recorrido de $recorrido ($host)
After=network-online.target

[Service]
Type=oneshot
User=$USER
EnvironmentFile=$RPA/$variables
ExecStart=$BASE/venv/bin/python $RPA/ejecutar.py $recorrido
TimeoutStartSec=120
EOF
    # Consulta cada 5 minutos y agendar cada 30.
    sudo tee "/etc/systemd/system/rpa-$recorrido$sufijo.timer" >/dev/null <<EOF
[Unit]
Description=Recorrido de $recorrido del cliente sintético ($host)

[Timer]
OnCalendar=$cuando
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
    unidades+=("rpa-$recorrido$sufijo")
  done
done
sudo systemctl daemon-reload
sudo systemctl enable --now "${unidades[@]/%/.timer}" >/dev/null 2>&1
systemctl list-timers 'rpa-*' --no-pager | head -6

# ---------------------------------------------------------------------------
paso "6. Primera ejecución"
for unidad in "${unidades[@]}"; do
  sudo systemctl start "$unidad.service" || true
  journalctl -u "$unidad.service" -n 1 --no-pager -o cat
done

cat <<EOF

Listo. Los resultados llegan a Zabbix, hosts msmotos-rpa-linux y msmotos-rpa-windows.
Ver las últimas ejecuciones:  journalctl -u 'rpa-*' -n 20 --no-pager -o short
Capturas de los fallos:       $BASE/salidas y $BASE/salidas-win
EOF
