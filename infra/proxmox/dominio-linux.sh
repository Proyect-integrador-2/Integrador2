#!/usr/bin/env bash
# SSH de una VM Linux con las cuentas del dominio ip2.local (IP2-81).
#
# SSSD consulta el dominio por LDAPS, confiando solo en la autoridad interna. La VM no se
# une al dominio: no hacen falta Kerberos ni el DNS del controlador, y si el dominio no
# responde la VM sigue funcionando.
#
#   - Solo entran los miembros de GG-IP2-Administradores, con su contraseña del dominio,
#     y tienen sudo (pidiendo esa contraseña).
#   - Los operadores y cualquier otra cuenta del dominio son rechazados.
#   - La cuenta local ip2 (solo con llave) sigue siendo la de emergencia (riesgo R-14).
#   - Una cuenta marcada "cambiar la contraseña en el primer inicio de sesión" no entra:
#     el dominio rechaza su validación por LDAP. Ver infra/vm-dc/nueva-clave.ps1.
#
# Se corre en la VM con el usuario ip2. La contraseña de svc-ldap llega por la entrada
# estándar y queda solo en /etc/sssd/sssd.conf (permisos 600). Se puede repetir.
#
#   ... | ./dominio-linux.sh
set -euo pipefail

BASE="OU=IP2,DC=ip2,DC=local"
GRUPO="GG-IP2-Administradores"
AQUI="$(cd "$(dirname "$0")" && pwd)"

[[ $EUID -ne 0 ]] || { echo "Correrlo con el usuario ip2, no como root." >&2; exit 1; }
read -r clave || true
[[ -n ${clave:-} ]] || { echo "Falta la contraseña de svc-ldap por la entrada estándar." >&2; exit 1; }

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q sssd-ldap libnss-sss libpam-sss >/dev/null
grep -q 'dc01.ip2.local' /etc/hosts || echo '10.10.30.17 dc01.ip2.local dc01' | sudo tee -a /etc/hosts >/dev/null
sudo install -m 644 "$AQUI/../ca/ip2-ca.crt" /usr/local/share/ca-certificates/ip2-ca.crt
sudo update-ca-certificates >/dev/null 2>&1

sudo install -m 600 /dev/stdin /etc/sssd/sssd.conf <<EOF
# Generado por infra/proxmox/dominio-linux.sh (IP2-81). No se sube a Git: lleva la
# contraseña de svc-ldap.
[sssd]
services = nss, pam
domains = ip2.local

[domain/ip2.local]
id_provider = ldap
auth_provider = ldap
chpass_provider = ldap
access_provider = ldap
ldap_uri = ldaps://dc01.ip2.local
ldap_schema = ad
ldap_id_mapping = true
ldap_search_base = $BASE
# Los grupos, en todo el dominio: el grupo principal de cada cuenta (Domain Users) está fuera de OU=IP2.
ldap_group_search_base = DC=ip2,DC=local
ldap_default_bind_dn = CN=svc-ldap,OU=Servicios,$BASE
ldap_default_authtok_type = password
ldap_default_authtok = $clave
ldap_tls_reqcert = demand
ldap_tls_cacert = /etc/ssl/certs/ca-certificates.crt
ldap_referrals = false
ldap_access_order = filter, expire
ldap_access_filter = (memberOf=CN=$GRUPO,$BASE)
ldap_account_expire_policy = ad
use_fully_qualified_names = false
fallback_homedir = /home/%u
default_shell = /bin/bash
cache_credentials = false
enumerate = false
EOF
unset clave
sudo systemctl enable sssd >/dev/null 2>&1
sudo systemctl restart sssd
sudo pam-auth-update --enable mkhomedir >/dev/null

# sudo para el grupo de administradores del dominio (pide la contraseña del dominio).
temporal=$(mktemp)
echo "%$GRUPO ALL=(ALL:ALL) ALL" > "$temporal"
sudo visudo -cf "$temporal" >/dev/null
sudo install -m 440 -o root -g root "$temporal" /etc/sudoers.d/ip2-dominio
rm -f "$temporal"

# SSH: las cuentas locales siguen solo con llave; los administradores del dominio entran
# con su contraseña. El bloque va al final de sshd_config, donde Match no afecta a nada más.
if ! sudo grep -q "^Match Group $GRUPO" /etc/ssh/sshd_config; then
  printf '\n# Integrador II (IP2-81): administradores del dominio con su contraseña.\nMatch Group %s\n    PasswordAuthentication yes\n' "$GRUPO" \
    | sudo tee -a /etc/ssh/sshd_config >/dev/null
fi
sudo sshd -t
sudo systemctl reload ssh

sleep 2
printf '%s: ' "$(hostname)"
if getent passwd prueba.admin >/dev/null; then
  echo "SSSD ve las cuentas del dominio ($(id -nG prueba.admin | tr ' ' '\n' | grep -c 'GG-IP2') grupo del proyecto para prueba.admin)"
else
  echo "SSSD NO ve las cuentas del dominio: revisar journalctl -u sssd" >&2
  exit 1
fi
