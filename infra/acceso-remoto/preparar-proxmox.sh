#!/usr/bin/env bash
# Deja un Proxmox VE recién instalado listo para administrarse a distancia (IP2-93).
#
# Qué hace, en orden:
#   1. Repositorios sin suscripción y paquetes necesarios.
#   2. Red: la tarjeta "fuera de banda" toma IP por DHCP de la red de la universidad;
#      la otra queda como bridge vmbr0 con VLAN, y Proxmox en 10.10.30.10 (VLAN 30).
#   3. Cortafuegos: por la tarjeta fuera de banda no entra nada ni se reenvía nada.
#   4. Tailscale, publicando las redes del laboratorio.
#   5. El comando "consola", para entrar a R1 y a SW1 por los cables serie.
#
# Se corre como root en la CONSOLA FÍSICA del servidor, no por SSH: el paso 2
# cambia la red y cortaría la sesión.
#
#   ./preparar-proxmox.sh                         lista las tarjetas de red y sale
#   ./preparar-proxmox.sh --oob eno2 --lab eno1   prepara el servidor
#   ./preparar-proxmox.sh --oob eno2 --lab eno1 --simular /tmp/prueba
#                                                 no toca nada: deja en esa carpeta
#                                                 los archivos que escribiría
#
# Opciones: --actualizar  aplica además todas las actualizaciones pendientes (tarda).
set -euo pipefail

IP_LAB="10.10.30.10/24"
GW_LAB="10.10.30.1"
VLAN_LAB=30
# Redes del laboratorio que Proxmox no tiene conectadas: se alcanzan por R1.
REDES_POR_R1=(10.10.20.0/24 10.10.40.0/24 10.10.99.0/24)
# Redes que se publican en Tailscale para llegar a ellas desde la casa.
RUTAS_TAILSCALE="10.10.20.0/24,10.10.30.0/24,10.10.40.0/24,10.10.99.0/24"
NOMBRE_TAILSCALE="pve-ip2"

OOB="" LAB="" SIMULAR="" RAIZ="" ACTUALIZAR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --oob) OOB="$2"; shift 2 ;;
    --lab) LAB="$2"; shift 2 ;;
    --simular) SIMULAR=1; RAIZ="$2"; shift 2 ;;
    --actualizar) ACTUALIZAR=1; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; exit 1 ;;
  esac
done

paso() { printf '\n== %s ==\n' "$*"; }

# Ejecuta el comando, o solo lo muestra si se está simulando.
ejecutar() {
  if [[ -n $SIMULAR ]]; then echo "  [simulado] $*"; else "$@"; fi
}

# escribir RUTA: guarda lo que llega por la entrada estándar.
escribir() {
  local destino="$RAIZ$1"
  mkdir -p "$(dirname "$destino")"
  cat > "$destino"
  echo "  escrito: $destino"
}

# Tarjetas físicas: las que tienen un dispositivo detrás y no son inalámbricas.
tarjetas() {
  local n
  for n in /sys/class/net/*; do
    [[ -e $n/device && ! -d $n/wireless ]] || continue
    basename "$n"
  done
}

listar_tarjetas() {
  local n dueno ip
  printf '%-12s %-8s %-19s %s\n' TARJETA ENLACE MAC "IP ACTUAL"
  for n in $(tarjetas); do
    # Tras instalar Proxmox, la tarjeta de gestión está dentro de vmbr0 y la IP es del bridge.
    dueno=$n
    [[ -e /sys/class/net/$n/master ]] && dueno=$(basename "$(readlink "/sys/class/net/$n/master")")
    ip=$(ip -4 -o addr show dev "$dueno" 2>/dev/null | awk '{print $4}' | paste -sd' ' -)
    [[ $dueno != "$n" && -n $ip ]] && ip="$ip (en $dueno)"
    printf '%-12s %-8s %-19s %s\n' "$n" "$(cat "/sys/class/net/$n/operstate")" \
      "$(cat "/sys/class/net/$n/address")" "${ip:--}"
  done
}

if [[ -z $OOB || -z $LAB ]]; then
  listar_tarjetas
  cat <<'EOF'

Falta indicar las tarjetas:
  --oob  la que va DIRECTO a la red de la universidad (fuera de banda)
  --lab  la que va a SW1 Gi0/2 (troncal del laboratorio)

Para distinguirlas: desconectar un cable y volver a correr el script; la que
pasa a "down" es la de ese cable.
EOF
  exit 1
fi

[[ $OOB != "$LAB" ]] || { echo "--oob y --lab no pueden ser la misma tarjeta." >&2; exit 1; }
if [[ -z $SIMULAR ]]; then
  [[ $EUID -eq 0 ]] || { echo "Hay que correrlo como root." >&2; exit 1; }
  command -v pveversion >/dev/null || { echo "Esto no es un Proxmox VE." >&2; exit 1; }
  for n in "$OOB" "$LAB"; do
    tarjetas | grep -qx "$n" || { echo "No existe la tarjeta '$n'." >&2; listar_tarjetas; exit 1; }
  done
  if [[ -n ${SSH_CONNECTION:-} ]]; then
    echo "Se está corriendo por SSH: el cambio de red va a cortar la sesión." >&2
    echo "Correrlo en la consola física, o dentro de tmux si no hay otra opción." >&2
    [[ -n ${TMUX:-} ]] || exit 1
  fi
fi

# ---------------------------------------------------------------------------
paso "1. Repositorios y paquetes"
# shellcheck disable=SC1091
codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
case "$codename" in
  trixie)
    # Proxmox VE 9: fuentes en formato deb822.
    for f in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
      if [[ -f $f ]] && ! grep -q '^Enabled: *false' "$f"; then
        ejecutar sh -c "echo 'Enabled: false' >> $f"
      fi
    done
    escribir /etc/apt/sources.list.d/pve-no-subscription.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    ;;
  bookworm)
    # Proxmox VE 8: fuentes en formato clásico.
    for f in /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/ceph.list; do
      [[ -f $f ]] && ejecutar sed -i 's/^deb /#deb /' "$f"
    done
    escribir /etc/apt/sources.list.d/pve-no-subscription.list <<EOF
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
EOF
    ;;
  *)
    echo "  Versión de Debian no prevista ('$codename'): no se tocan los repositorios."
    ;;
esac
ejecutar apt-get update
# isc-dhcp-client: es el cliente DHCP que ifupdown2 sabe manejar en la tarjeta fuera de banda.
ejecutar apt-get install -y curl nftables picocom tmux isc-dhcp-client
[[ $ACTUALIZAR -eq 1 ]] && ejecutar apt-get -y dist-upgrade

# ---------------------------------------------------------------------------
paso "2. Red"
INTERFACES=/etc/network/interfaces
if [[ -z $SIMULAR ]]; then
  cp -a "$INTERFACES" "$INTERFACES.antes-ip2-$(date +%Y%m%d-%H%M%S)"
fi
{
  cat <<EOF
# Generado por preparar-proxmox.sh (IP2-93).
# La configuración anterior quedó en $INTERFACES.antes-ip2-<fecha>.
auto lo
iface lo inet loopback

# Fuera de banda: red de la universidad. Por aquí sale Tailscale, sin pasar por R1.
auto $OOB
iface $OOB inet dhcp

# Laboratorio: troncal 802.1Q hacia SW1 Gi0/2.
iface $LAB inet manual

auto vmbr0
iface vmbr0 inet manual
	bridge-ports $LAB
	bridge-stp off
	bridge-fd 0
	bridge-vlan-aware yes
	bridge-vids 2-4094

# Gestión de Proxmox en la VLAN de Servidores. Sin gateway: la ruta por defecto es
# la de la tarjeta fuera de banda. Las demás redes del laboratorio van por R1.
auto vmbr0.$VLAN_LAB
iface vmbr0.$VLAN_LAB inet static
	address $IP_LAB
EOF
  for red in "${REDES_POR_R1[@]}"; do
    printf '\tpost-up ip route replace %s via %s || true\n' "$red" "$GW_LAB"
  done
  printf '\nsource /etc/network/interfaces.d/*\n'
} | escribir "$INTERFACES"

# Proxmox necesita que su nombre resuelva a una IP que el equipo tenga siempre.
# La de la tarjeta fuera de banda cambia con el DHCP; la del laboratorio es fija.
corto=$(hostname -s)
completo=$(hostname -f 2>/dev/null || echo "$corto")
{
  awk -v h="$corto" '$0 ~ "(^|[[:space:]])" h "([[:space:].]|$)" && $1 !~ /^(127\.|::1)/ {next} {print}' /etc/hosts
  if [[ $completo == "$corto" ]]; then
    echo "${IP_LAB%/*} $corto"
  else
    echo "${IP_LAB%/*} $completo $corto"
  fi
} > "${TMPDIR:-/tmp}/hosts.ip2"
escribir /etc/hosts < "${TMPDIR:-/tmp}/hosts.ip2"
rm -f "${TMPDIR:-/tmp}/hosts.ip2"

ejecutar ifreload -a
if [[ -z $SIMULAR ]]; then
  sleep 5
  if ip route get 1.1.1.1 2>/dev/null | grep -q "dev $OOB"; then
    echo "  Salida a Internet por $OOB: correcto."
  else
    echo "  AVISO: no hay salida a Internet por $OOB. Revisar el cable y que la red de la"
    echo "  universidad entregue dirección por DHCP en ese punto. Sin eso, Tailscale no conecta."
  fi
fi

# ---------------------------------------------------------------------------
paso "3. Cortafuegos de la tarjeta fuera de banda"
# Esa tarjeta está en la red de la universidad, fuera del NAT y de las ACL de R1.
# Se usa solo para salir: no acepta conexiones ni reenvía tráfico en ningún sentido,
# para que el servidor no se convierta en un atajo que esquive al router.
escribir /etc/ip2-oob.nft <<EOF
#!/usr/sbin/nft -f
table inet ip2_oob
delete table inet ip2_oob

table inet ip2_oob {
	chain entrada {
		type filter hook input priority filter; policy accept;
		iifname != "$OOB" accept
		ct state established,related accept
		meta l4proto ipv6-icmp accept
		udp sport 67 udp dport 68 accept comment "DHCP de la universidad"
		udp dport 41641 accept comment "Tailscale, conexion directa"
		counter drop
	}
	chain reenvio {
		type filter hook forward priority filter; policy accept;
		iifname "$OOB" counter drop
		oifname "$OOB" counter drop
	}
}
EOF
escribir /etc/systemd/system/ip2-oob.service <<'EOF'
[Unit]
Description=Cortafuegos de la tarjeta fuera de banda (IP2-93)
Wants=network-pre.target
Before=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/ip2-oob.nft
ExecStop=/usr/sbin/nft delete table inet ip2_oob

[Install]
WantedBy=multi-user.target
EOF
# Reenvío: lo necesita Tailscale para llevar el tráfico de la casa al laboratorio.
escribir /etc/sysctl.d/90-ip2-reenvio.conf <<'EOF'
net.ipv4.ip_forward = 1
EOF
ejecutar systemctl daemon-reload
ejecutar systemctl enable --now ip2-oob.service
ejecutar sysctl --system

# ---------------------------------------------------------------------------
paso "4. Tailscale"
if [[ -n $SIMULAR ]] || ! command -v tailscale >/dev/null; then
  ejecutar sh -c 'curl -fsSL https://tailscale.com/install.sh | sh'
fi
echo "  Va a aparecer un código QR y un enlace: abrirlo en el celular o la portátil"
echo "  e iniciar sesión con la cuenta del proyecto. El script espera hasta que se haga."
ejecutar tailscale up --advertise-routes="$RUTAS_TAILSCALE" --accept-dns=false \
  --hostname="$NOMBRE_TAILSCALE" --qr

# ---------------------------------------------------------------------------
paso "5. Consolas de R1 y SW1"
escribir /usr/local/bin/consola <<'EOF'
#!/bin/sh
# Abre la consola serie de un equipo de red por su cable USB (IP2-93).
#   consola                    lista los puertos y los nombres asignados
#   consola asignar r1 RUTA    guarda a qué puerto corresponde un nombre
#   consola r1                 abre la consola (9600 8N1). Salir: Ctrl-A y luego Ctrl-X
MAPA=/etc/ip2-consolas

case "${1:-}" in
  "")
    echo "Puertos serie:"
    if [ -d /dev/serial/by-id ]; then
      for p in /dev/serial/by-id/*; do echo "  $p"; done
    else
      echo "  (ninguno: revisar los cables USB)"
    fi
    echo "Asignados:"
    if [ -s "$MAPA" ]; then sed 's/^/  /' "$MAPA"; else echo "  (ninguno)"; fi
    ;;
  asignar)
    if [ $# -ne 3 ] || [ ! -e "$3" ]; then
      echo "Uso: consola asignar NOMBRE /dev/serial/by-id/..." >&2
      exit 1
    fi
    touch "$MAPA"
    grep -v "^$2=" "$MAPA" > "$MAPA.tmp" || true
    echo "$2=$3" >> "$MAPA.tmp"
    mv "$MAPA.tmp" "$MAPA"
    echo "$2 -> $3"
    ;;
  *)
    puerto=$(sed -n "s|^$1=||p" "$MAPA" 2>/dev/null)
    [ -n "$puerto" ] || puerto=$1
    if [ ! -e "$puerto" ]; then
      echo "No existe '$1'. Correr 'consola' sin argumentos para ver los puertos." >&2
      exit 1
    fi
    exec picocom -b 9600 "$puerto"
    ;;
esac
EOF
ejecutar chmod +x /usr/local/bin/consola

# ---------------------------------------------------------------------------
paso "Listo. Falta, a mano"
cat <<EOF
  1. En https://login.tailscale.com/admin/machines abrir "$NOMBRE_TAILSCALE" →
     Edit route settings → aprobar las cuatro redes 10.10.x.0/24.
  2. Conectar los cables de consola y correr:  consola
     Después:  consola asignar r1 <puerto>   y   consola asignar sw1 <puerto>
  3. Desde la portátil, con los datos del celular (no la red de la universidad):
       ping ${IP_LAB%/*}      y abrir      https://${IP_LAB%/*}:8006
  4. Reiniciar el servidor y confirmar que vuelve a aparecer en línea en Tailscale.

  Si la red quedó mal: la configuración anterior está en
  $INTERFACES.antes-ip2-<fecha>; copiarla de vuelta y correr  ifreload -a
EOF
