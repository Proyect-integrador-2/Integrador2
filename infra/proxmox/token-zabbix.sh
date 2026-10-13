#!/usr/bin/env bash
# Crea en Proxmox el acceso de solo lectura con que Zabbix lee el nodo, las VMs y los
# discos por la API (IP2-42), y deja el secreto en el .env de vm-zabbix.
#
# El secreto pasa directo del servidor a vm-zabbix: no se muestra en pantalla.
#
# Se corre como root en el servidor Proxmox. Se puede repetir: si el token ya existe,
# no hace nada.
#
#   ./token-zabbix.sh
#
# Después, en vm-zabbix:  python3 /opt/integrador2/infra/vm-zabbix/configurar-zabbix.py
set -euo pipefail

USUARIO="zabbix@pve"
TOKEN="monitoreo"
VM_ZABBIX="ip2@10.10.30.12"
ENV_ZABBIX="/opt/integrador2/infra/vm-zabbix/.env"

[[ $EUID -eq 0 ]] || { echo "Hay que correrlo como root." >&2; exit 1; }
command -v pveum >/dev/null || { echo "Esto no es un Proxmox VE." >&2; exit 1; }

if pveum user token list "$USUARIO" --output-format json 2>/dev/null | grep -q "\"$TOKEN\""; then
  echo "El token $USUARIO!$TOKEN ya existe: no se toca."
  exit 0
fi

# Usuario sin contraseña (solo sirve con token) y con el rol que solo permite ver.
pveum user list --output-format json | grep -q "\"$USUARIO\"" \
  || pveum user add "$USUARIO" --comment "Monitoreo de Zabbix (solo lectura)"
pveum acl modify / --users "$USUARIO" --roles PVEAuditor

# privsep 0: el token hereda el permiso del usuario, que ya es de solo lectura.
pveum user token add "$USUARIO" "$TOKEN" --privsep 0 --output-format json \
  | python3 -c 'import json, sys; print("# Token de solo lectura de Proxmox (infra/proxmox/token-zabbix.sh).\nPVE_TOKEN_SECRET=" + json.load(sys.stdin)["value"])' \
  | ssh -o BatchMode=yes "$VM_ZABBIX" "sed -i '/^PVE_TOKEN_SECRET=/d; /Token de solo lectura de Proxmox/d' $ENV_ZABBIX && cat >> $ENV_ZABBIX"

echo "Token $USUARIO!$TOKEN creado y guardado en $ENV_ZABBIX de vm-zabbix."
