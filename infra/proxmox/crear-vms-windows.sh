#!/usr/bin/env bash
# Crea las dos VMs Windows Server 2022 del proyecto en Proxmox VE (IP2-73, IP2-79).
#
# Windows se instala solo: cada VM arranca con el instalador y con un CD de respuestas
# (windows/autounattend.xml) que particiona, instala, pone nombre y contraseña, y al
# final corre windows/primer-arranque.ps1, que deja IP fija, escritorio remoto y SSH.
#
# Se corre como root en el servidor Proxmox, desde la carpeta que tiene este script y
# la carpeta windows/.
#
#   ./crear-vms-windows.sh                    crea las que falten y espera a que respondan
#   ./crear-vms-windows.sh --solo vm-app-win
#
# Opciones:
#   --almacen NOMBRE   dónde van los discos (por defecto local-lvm)
#   --iso VOLUMEN      instalador (por defecto local:iso/windows-server-2022-eval.iso)
#
# El instalador es la evaluación de 180 días de Windows Server 2022, del Centro de
# Evaluación de Microsoft (unos 4,7 GB). Las respuestas aceptan su licencia.
#
# La contraseña de Administrator se genera aquí y queda solo en este servidor:
#   cat /root/secretos-ip2/windows-administrator.txt
# El CD de respuestas la lleva escrita: se expulsa y se borra cuando la VM responde.
set -euo pipefail

ALMACEN="local-lvm"
ISO="local:iso/windows-server-2022-eval.iso"
SOLO=""

BRIDGE="vmbr0"
VLAN=30
RED="10.10.30"
DIR_ISO="/var/lib/vz/template/iso"
SECRETO="/root/secretos-ip2/windows-administrator.txt"
AQUI="$(cd "$(dirname "$0")" && pwd)"
ESPERA_MIN=90

# ID  nombre  nombre en Windows  último octeto  vCPU  RAM (MB)  disco (GB)
WINDOWS=(
  "116 vm-app-win VM-APP-WIN 16 2 4096 60"
  "117 vm-dc      DC01       17 2 4096 60"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --almacen) ALMACEN="$2"; shift 2 ;;
    --iso) ISO="$2"; shift 2 ;;
    --solo) SOLO="$2"; shift 2 ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; exit 1 ;;
  esac
done

pedida() {
  [[ -z $SOLO ]] || [[ ",$SOLO," == *",$1,"* ]]
}

[[ $EUID -eq 0 ]] || { echo "Hay que correrlo como root." >&2; exit 1; }
command -v qm >/dev/null || { echo "Esto no es un Proxmox VE." >&2; exit 1; }
command -v genisoimage >/dev/null || { echo "Falta genisoimage (apt install genisoimage)." >&2; exit 1; }
pvesm path "$ISO" >/dev/null 2>&1 && [[ -s $(pvesm path "$ISO") ]] \
  || { echo "No está el instalador '$ISO'." >&2; exit 1; }
[[ -s $AQUI/windows/autounattend.xml && -s $AQUI/windows/primer-arranque.ps1 ]] \
  || { echo "Falta la carpeta windows/ junto a este script." >&2; exit 1; }

# Una sola contraseña para las dos VMs. Letras y números, con al menos una de cada
# clase, que es lo que exige Windows. No se muestra.
if [[ ! -s $SECRETO ]]; then
  (
    umask 077
    mkdir -p "$(dirname "$SECRETO")"
    echo "Ip2$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 21)" > "$SECRETO"
  )
  echo "Contraseña de Administrator generada en $SECRETO (permisos 600)."
fi

# Quién entra por SSH: la llave de este servidor y las que ya entran a él.
llaves=$(mktemp)
cat /root/.ssh/*.pub /root/.ssh/authorized_keys 2>/dev/null | grep -E '^(ssh|ecdsa)-' | sort -u > "$llaves"
[[ -s $llaves ]] || { echo "No hay llaves públicas en /root/.ssh." >&2; exit 1; }

creadas=()
for fila in "${WINDOWS[@]}"; do
  read -r id nombre equipo octeto cpus ram disco <<<"$fila"
  pedida "$nombre" || continue
  if qm status "$id" >/dev/null 2>&1; then echo "$nombre ($id): ya existe, no se toca."; continue; fi
  echo "$nombre ($id): $RED.$octeto · $cpus vCPU · $((ram / 1024)) GB · $disco GB"

  # CD de respuestas de esta VM. Lleva la contraseña: permisos 600 y se borra al final.
  respuestas="$DIR_ISO/ip2-respuestas-$id.iso"
  temporal=$(mktemp -d)
  (
    umask 077
    sed -e "s/__NOMBRE__/$equipo/" -e "s/__IP__/$RED.$octeto/" -e "s/__CLAVE__/$(cat "$SECRETO")/" \
      "$AQUI/windows/autounattend.xml" > "$temporal/autounattend.xml"
    cp "$AQUI/windows/primer-arranque.ps1" "$temporal/"
    cp "$llaves" "$temporal/authorized_keys"
    genisoimage -quiet -J -r -V IP2RESP -o "$respuestas" "$temporal"
  )
  rm -rf "$temporal"

  # Disco SATA y tarjeta e1000e: Windows los reconoce sin controladores adicionales.
  # El disco vacío no arranca, así que la primera vez entra por el instalador (ide2).
  qm create "$id" --name "$nombre" --ostype win11 --cores "$cpus" --memory "$ram" --cpu host \
    --sata0 "$ALMACEN:$disco,discard=on,ssd=1" --net0 "e1000e,bridge=$BRIDGE,tag=$VLAN" \
    --ide2 "$ISO,media=cdrom" --ide0 "local:iso/$(basename "$respuestas"),media=cdrom" \
    --boot "order=sata0;ide2" --onboot 1
  qm start "$id"
  creadas+=("$id $nombre $octeto")
done
rm -f "$llaves"

[[ ${#creadas[@]} -gt 0 ]] || { echo "No había nada que crear."; exit 0; }

echo
echo "Instalando. Suele tardar entre 15 y 30 minutos por VM; se espera hasta $ESPERA_MIN."
pendientes=("${creadas[@]}")
for ((minuto = 1; minuto <= ESPERA_MIN && ${#pendientes[@]} > 0; minuto++)); do
  sleep 60
  siguen=()
  for fila in "${pendientes[@]}"; do
    read -r id nombre octeto <<<"$fila"
    if timeout 3 bash -c "</dev/tcp/$RED.$octeto/22" 2>/dev/null; then
      echo "  $nombre: responde por SSH en $RED.$octeto (minuto $minuto)."
      # Fuera los dos CD; el de respuestas además se borra.
      qm set "$id" --ide0 none,media=cdrom --ide2 none,media=cdrom >/dev/null
      rm -f "$DIR_ISO/ip2-respuestas-$id.iso"
    else
      siguen+=("$fila")
    fi
  done
  pendientes=("${siguen[@]}")
done

for fila in "${pendientes[@]}"; do
  read -r id nombre octeto <<<"$fila"
  echo "  $nombre: no respondió en $ESPERA_MIN minutos. Ver su pantalla en el panel (Console)."
  echo "    Su CD de respuestas sigue en $DIR_ISO/ip2-respuestas-$id.iso y lleva la contraseña: borrarlo al terminar."
done

cat <<EOF

Listo. Para entrar (vm-app-win es $RED.16 y vm-dc es $RED.17):
  ssh Administrator@$RED.16                 (con llave, abre PowerShell)
  mstsc /v:$RED.16                          (escritorio remoto, usuario Administrator)
La contraseña está en $SECRETO
EOF
