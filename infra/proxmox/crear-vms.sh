#!/usr/bin/env bash
# Crea las máquinas virtuales del proyecto en Proxmox VE (IP2-33, IP2-73, IP2-79).
#
# Las cinco VMs Linux salen de la imagen oficial de Ubuntu 24.04 para la nube y quedan
# configuradas por cloud-init: nombre, IP fija en la VLAN 30, usuario y llave SSH.
# Las dos VMs Windows se crean vacías, con el instalador montado: Windows se instala
# a mano desde la consola del panel de Proxmox.
#
# Se corre como root en el servidor Proxmox.
#
#   ./crear-vms.sh                       crea las que falten (las que existen no se tocan)
#   ./crear-vms.sh --solo vm-app,vm-zabbix
#   ./crear-vms.sh --simular             muestra los comandos sin ejecutar nada
#
# Opciones:
#   --almacen NOMBRE   dónde van los discos (por defecto local-lvm)
#   --llave ARCHIVO    llave pública que entra a las VMs Linux (por defecto la de root del servidor)
#   --iso-windows VOL  instalador de Windows Server, p. ej. local:iso/windows-server-2022.iso
#
# Antes de correrlo: las VMs salen a Internet por R1 (gateway 10.10.30.1). Si el router,
# el switch y el troncal todavía no están configurados, arrancan pero no pueden instalar nada.
set -euo pipefail

ALMACEN="local-lvm"
LLAVE="/root/.ssh/authorized_keys"
ISO_WINDOWS=""
SOLO=""
SIMULAR=""

BRIDGE="vmbr0"
VLAN=30
RED="10.10.30"
GATEWAY="10.10.30.1"
DNS="8.8.8.8"
USUARIO="ip2"
IMAGEN_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGEN="/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img"

# ID  nombre  último octeto  vCPU  RAM (MB)  disco (GB)   — tabla 4.2 del E2
LINUX=(
  "111 vm-app     11 2 4096 40"
  "112 vm-zabbix  12 2 4096 60"
  "113 vm-grafana 13 1 2048 20"
  "114 vm-n8n     14 2 2048 20"
  "115 vm-rpa     15 2 4096 30"
)
WINDOWS=(
  "116 vm-app-win 16 2 4096 60"
  "117 vm-dc      17 2 4096 60"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --almacen) ALMACEN="$2"; shift 2 ;;
    --llave) LLAVE="$2"; shift 2 ;;
    --iso-windows) ISO_WINDOWS="$2"; shift 2 ;;
    --solo) SOLO="$2"; shift 2 ;;
    --simular) SIMULAR=1; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; exit 1 ;;
  esac
done

ejecutar() {
  if [[ -n $SIMULAR ]]; then echo "  [simulado] $*"; else "$@"; fi
}

# ¿Se pidió esta VM? Sin --solo, se piden todas.
pedida() {
  [[ -z $SOLO ]] || [[ ",$SOLO," == *",$1,"* ]]
}

existe() {
  [[ -z $SIMULAR ]] && qm status "$1" >/dev/null 2>&1
}

if [[ -z $SIMULAR ]]; then
  [[ $EUID -eq 0 ]] || { echo "Hay que correrlo como root." >&2; exit 1; }
  command -v qm >/dev/null || { echo "Esto no es un Proxmox VE." >&2; exit 1; }
  pvesm status --storage "$ALMACEN" >/dev/null 2>&1 \
    || { echo "No existe el almacenamiento '$ALMACEN'. Los disponibles:" >&2; pvesm status >&2; exit 1; }
  [[ -s $LLAVE ]] || { echo "No hay llave pública en '$LLAVE'. Indicar otra con --llave." >&2; exit 1; }
fi

echo "== VMs Linux =="
necesita_imagen=""
for fila in "${LINUX[@]}"; do
  read -r id nombre _ <<<"$fila"
  pedida "$nombre" && ! existe "$id" && necesita_imagen=1
done
if [[ -n $necesita_imagen && ! -s $IMAGEN ]]; then
  echo "  Descargando la imagen de Ubuntu 24.04 (unos 600 MB)..."
  ejecutar mkdir -p "$(dirname "$IMAGEN")"
  ejecutar wget -q --show-progress -O "$IMAGEN.parcial" "$IMAGEN_URL"
  ejecutar mv "$IMAGEN.parcial" "$IMAGEN"
fi

for fila in "${LINUX[@]}"; do
  read -r id nombre octeto cpus ram disco <<<"$fila"
  pedida "$nombre" || continue
  if existe "$id"; then echo "  $nombre ($id): ya existe, no se toca."; continue; fi
  echo "  $nombre ($id): $RED.$octeto · $cpus vCPU · $((ram / 1024)) GB · $disco GB"
  ejecutar qm create "$id" --name "$nombre" --ostype l26 --cores "$cpus" --memory "$ram" \
    --cpu host --scsihw virtio-scsi-single --agent enabled=1 \
    --net0 "virtio,bridge=$BRIDGE,tag=$VLAN" --serial0 socket --vga serial0 --onboot 1
  ejecutar qm set "$id" --scsi0 "$ALMACEN:0,import-from=$IMAGEN,discard=on"
  ejecutar qm disk resize "$id" scsi0 "${disco}G"
  ejecutar qm set "$id" --ide2 "$ALMACEN:cloudinit" --boot order=scsi0 \
    --ciuser "$USUARIO" --sshkeys "$LLAVE" --ciupgrade 0 \
    --ipconfig0 "ip=$RED.$octeto/24,gw=$GATEWAY" --nameserver "$DNS"
  ejecutar qm start "$id"
done

echo "== VMs Windows =="
for fila in "${WINDOWS[@]}"; do
  read -r id nombre octeto cpus ram disco <<<"$fila"
  pedida "$nombre" || continue
  if existe "$id"; then echo "  $nombre ($id): ya existe, no se toca."; continue; fi
  if [[ -z $ISO_WINDOWS ]]; then
    echo "  $nombre ($id): falta --iso-windows. Subir el instalador al panel (local → ISO Images) y repetir."
    continue
  fi
  echo "  $nombre ($id): $RED.$octeto · $cpus vCPU · $((ram / 1024)) GB · $disco GB"
  # Disco SATA y tarjeta e1000: Windows los reconoce sin controladores adicionales.
  ejecutar qm create "$id" --name "$nombre" --ostype win11 --cores "$cpus" --memory "$ram" \
    --cpu host --sata0 "$ALMACEN:$disco" --net0 "e1000,bridge=$BRIDGE,tag=$VLAN" \
    --ide2 "$ISO_WINDOWS,media=cdrom" --boot "order=sata0;ide2" --onboot 1
  echo "    Instalar desde el panel: $nombre → Console. Después, IP fija $RED.$octeto/24, gateway $GATEWAY."
done

cat <<EOF

Listo. Para entrar a una VM Linux desde el servidor:  ssh $USUARIO@$RED.11
Si una no responde, su consola está en el panel (Console) o con:  qm terminal <id>
EOF
