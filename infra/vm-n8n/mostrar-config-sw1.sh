#!/usr/bin/env bash
# Imprime el bloque que hay que pegar en SW1 para que n8n pueda reiniciar sus puertos de
# acceso (IP2-85). Lleva la contraseña de la cuenta n8n-net: lo corre quien administra el
# switch, en su propia terminal, y el bloque no se guarda en ningún otro lado.
#
#   ssh -t ip2@10.10.30.14 /opt/integrador2/infra/vm-n8n/mostrar-config-sw1.sh
#
# El mismo bloque, sin la contraseña, está en red/switch/SW1-2960.txt.
set -euo pipefail

clave=$(sudo sed -n 's/^SW1_CLAVE=//p' /etc/ip2/red.env)
[[ -n $clave ]] || { echo "Falta /etc/ip2/red.env: correr antes preparar-red.sh." >&2; exit 1; }

cat <<EOF
! ---------- Copiar desde aquí y pegar en SW1 (entrar como admin) ----------
configure terminal
! Nivel 5: lo único que puede hacer la cuenta de n8n.
privilege exec level 5 configure terminal
privilege configure level 5 interface
privilege interface level 5 shutdown
privilege interface level 5 no shutdown
privilege exec level 5 show interfaces
username n8n-net privilege 5 secret $clave
! SSH también desde vm-n8n, que es desde donde actúa n8n.
access-list 40 remark VM de automatizacion (n8n): reinicio de puertos de acceso (IP2-85)
access-list 40 permit host 10.10.30.14
end
write memory
! ---------- Hasta aquí ----------
EOF
