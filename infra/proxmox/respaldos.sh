#!/usr/bin/env bash
# Prepara los respaldos de las VMs en Proxmox VE (IP2-34, riesgo R-14).
#
# Qué hace:
#   1. Crea un volumen aparte para los respaldos y lo registra como almacenamiento
#      "respaldos". Así, si las copias crecen, no llenan el disco del sistema.
#   2. Programa los respaldos con la frecuencia y la retención del diseño
#      (docs/diseno/virtualizacion.md, sección 4).
#
# Se corre como root en el servidor Proxmox. Se puede repetir.
#
#   ./respaldos.sh
#
# Respaldar ya una VM:      vzdump 117 --storage respaldos --mode snapshot --compress zstd
# Ver las copias:           pvesm list respaldos
# Restaurar en otra VM:     qmrestore <archivo> <id nuevo> --unique 1
#
# Límite conocido: el volumen está en los mismos discos del servidor. Protege de borrar
# o dañar una VM, no de perder el servidor entero; para eso hace falta un destino externo.
set -euo pipefail

ALMACEN="respaldos"
VOLUMEN="respaldos"
TAMANO="300G"
PUNTO="/mnt/respaldos"

# id  horario (formato de Proxmox)  VMs  copias que se conservan  descripción
TRABAJOS=(
  "ip2-diario-criticas  02:00      111,112,117  3  Diario: vm-app, vm-zabbix y vm-dc"
  "ip2-diario-windows   02:40      116          2  Diario: vm-app-win"
  "ip2-semanal          sun_03:20  113,114,115  2  Semanal: vm-grafana, vm-n8n y vm-rpa"
)

[[ $EUID -eq 0 ]] || { echo "Hay que correrlo como root." >&2; exit 1; }
command -v pvesm >/dev/null || { echo "Esto no es un Proxmox VE." >&2; exit 1; }

echo "== 1. Almacenamiento =="
if ! lvs "pve/$VOLUMEN" >/dev/null 2>&1; then
  # Volumen delgado: ocupa del disco solo lo que de verdad se escribe.
  lvcreate -q -V "$TAMANO" -T pve/data -n "$VOLUMEN"
  mkfs.ext4 -q "/dev/pve/$VOLUMEN"
  echo "  volumen pve/$VOLUMEN de $TAMANO creado."
fi
mkdir -p "$PUNTO"
grep -q " $PUNTO " /etc/fstab \
  || echo "/dev/pve/$VOLUMEN $PUNTO ext4 defaults,nofail 0 2" >> /etc/fstab
mountpoint -q "$PUNTO" || mount "$PUNTO"
# is_mountpoint: si el volumen no está montado, Proxmox no escribe en el disco del sistema.
pvesm status --storage "$ALMACEN" >/dev/null 2>&1 \
  || pvesm add dir "$ALMACEN" --path "$PUNTO" --content backup --is_mountpoint yes
df -h "$PUNTO" | tail -n 1

echo "== 2. Trabajos programados =="
existentes=$(pvesh get /cluster/backup --output-format json)
for fila in "${TRABAJOS[@]}"; do
  read -r id horario vms copias descripcion <<<"$fila"
  if grep -q "\"$id\"" <<<"$existentes"; then
    echo "  $id: ya existe, no se toca."
    continue
  fi
  pvesh create /cluster/backup --id "$id" --schedule "${horario/_/ }" --vmid "$vms" \
    --storage "$ALMACEN" --mode snapshot --compress zstd --prune-backups "keep-last=$copias" \
    --enabled 1 --comment "$descripcion" >/dev/null
  echo "  $id: $descripcion ($horario, $copias copias)."
done
