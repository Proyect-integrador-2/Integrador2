#!/usr/bin/env bash
# Inicio de sesión en Proxmox con las cuentas del dominio ip2.local (IP2-81).
#
#   - Dominio de autenticación "ip2" de tipo Active Directory, por LDAPS a dc01.ip2.local,
#     confiando solo en la autoridad interna del laboratorio.
#   - Proxmox solo deja entrar a usuarios que conoce: se sincronizan del dominio los
#     miembros de los dos grupos del proyecto. Una cuenta sin grupo no existe aquí y no entra.
#   - Permisos por grupo: administradores con el rol Administrator, operadores con
#     PVEAuditor (solo ver).
#   - root@pam sigue siendo la cuenta local de emergencia (riesgo R-14).
#
# La contraseña de svc-ldap llega por la entrada estándar y queda donde Proxmox guarda
# las de sus dominios (/etc/pve/priv/realm/, solo root). Se corre como root; se puede repetir.
#
#   ... | ./dominio-proxmox.sh
set -euo pipefail

REINO="ip2"
BASE="OU=IP2,DC=ip2,DC=local"
ADMINS="CN=GG-IP2-Administradores,$BASE"
OPERADORES="CN=GG-IP2-Operadores,$BASE"

[[ $EUID -eq 0 ]] || { echo "Hay que correrlo como root." >&2; exit 1; }
read -r clave || true
[[ -n ${clave:-} ]] || { echo "Falta la contraseña de svc-ldap por la entrada estándar." >&2; exit 1; }

# El controlador por su nombre (el certificado lo trae) y la autoridad interna como confiable.
grep -q 'dc01.ip2.local' /etc/hosts || echo '10.10.30.17 dc01.ip2.local dc01' >> /etc/hosts
install -m 644 /root/secretos-ip2/ca/ip2-ca.crt /usr/local/share/ca-certificates/ip2-ca.crt
update-ca-certificates >/dev/null

opciones=(--domain ip2.local --server1 dc01.ip2.local --port 636 --mode ldaps --verify 1
  --bind_dn "CN=svc-ldap,OU=Servicios,$BASE" --base_dn "$BASE" --user_attr sAMAccountName
  --filter "(|(memberOf=$ADMINS)(memberOf=$OPERADORES))"
  --group_dn "$BASE" --group_filter "(&(objectClass=group)(cn=GG-IP2-*))" --group_name_attr cn
  --sync-defaults-options "scope=both,enable-new=1,remove-vanished=acl;entry;properties"
  --comment "Dominio ip2.local por LDAPS (IP2-81)")
if pveum realm list --output-format json | grep -q "\"realm\":\"$REINO\""; then
  pveum realm modify "$REINO" "${opciones[@]}"
else
  pveum realm add "$REINO" --type ad "${opciones[@]}"
fi
install -d -m 700 /etc/pve/priv/realm
printf '%s\n' "$clave" > "/etc/pve/priv/realm/$REINO.pw"
unset clave

pveum realm sync "$REINO"
# Cada hora, para que quien entra o sale de un grupo del dominio se refleje aquí solo.
pvesh get /cluster/jobs/realm-sync --output-format json | grep -q '"id":"ip2-cada-hora"' \
  || pvesh create /cluster/jobs/realm-sync/ip2-cada-hora --realm "$REINO" --schedule hourly --scope both \
       --enable-new 1 --remove-vanished "acl;entry;properties" --comment "Sincroniza los grupos del dominio (IP2-81)"
pveum acl modify / --groups "GG-IP2-Administradores-$REINO" --roles Administrator
pveum acl modify / --groups "GG-IP2-Operadores-$REINO" --roles PVEAuditor

echo "Usuarios del dominio en Proxmox:"
pveum user list --output-format json | python3 -c '
import json, sys
for u in json.load(sys.stdin):
    if u["userid"].endswith("@ip2"):
        print("  ", u["userid"].ljust(26), ",".join(u.get("groups", "").split(",")) if isinstance(u.get("groups"), str) else u.get("groups"))'
pveum acl list | grep -E "GG-IP2|path" | head -5
