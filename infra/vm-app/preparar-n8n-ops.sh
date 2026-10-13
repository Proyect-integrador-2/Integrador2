#!/usr/bin/env bash
# Crea en vm-app la cuenta restringida con la que n8n ejecuta las recuperaciones (IP2-52).
#
# Controles del diseño (docs/diseno/automatizacion.md):
#   C1  Lista cerrada: n8n-ops solo puede iniciar o reiniciar msmotos-app y Nginx.
#   C4  Mínimo privilegio: sin contraseña, sin grupo docker (equivale a root) y con
#       la llave aceptada únicamente desde la dirección de vm-n8n.
#
# Se corre en vm-app con el usuario ip2 (usa sudo). Se puede repetir.
#
#   ./preparar-n8n-ops.sh ARCHIVO.pub          la llave pública generada en vm-n8n
#   ./preparar-n8n-ops.sh ARCHIVO.pub 10.10.30.14
set -euo pipefail

PUBLICA="${1:?Indicar el archivo con la llave pública de n8n}"
ORIGEN="${2:-10.10.30.14}"
USUARIO="n8n-ops"

[[ $EUID -ne 0 ]] || { echo "Correrlo con el usuario ip2, no como root." >&2; exit 1; }
llave=$(tr -d '\r' < "$PUBLICA" | grep -m1 -E '^ssh-(ed25519|rsa) ') \
  || { echo "'$PUBLICA' no contiene una llave pública SSH." >&2; exit 1; }

if ! id "$USUARIO" >/dev/null 2>&1; then
  # --disabled-password: la cuenta existe pero no tiene contraseña utilizable.
  sudo adduser --disabled-password --gecos 'Automatizacion n8n (IP2-52)' "$USUARIO" >/dev/null
fi

# from="...": aunque alguien copiara la llave privada, no sirve desde otro equipo.
sudo install -d -m 700 -o "$USUARIO" -g "$USUARIO" "/home/$USUARIO/.ssh"
printf 'from="%s",no-agent-forwarding,no-port-forwarding,no-X11-forwarding %s\n' "$ORIGEN" "$llave" \
  | sudo tee "/home/$USUARIO/.ssh/authorized_keys" >/dev/null
sudo chown "$USUARIO:$USUARIO" "/home/$USUARIO/.ssh/authorized_keys"
sudo chmod 600 "/home/$USUARIO/.ssh/authorized_keys"

# Lista cerrada de comandos. Se valida antes de instalarla: un sudoers con errores
# deja a toda la VM sin sudo.
temporal=$(mktemp)
cat > "$temporal" <<EOF
# Integrador II: lo único que n8n puede hacer en esta VM (IP2-52).
$USUARIO ALL=(root) NOPASSWD: /usr/bin/docker start msmotos-app
$USUARIO ALL=(root) NOPASSWD: /usr/bin/docker restart msmotos-app
$USUARIO ALL=(root) NOPASSWD: /usr/bin/docker inspect -f {{.State.Status}} msmotos-app
$USUARIO ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx
$USUARIO ALL=(root) NOPASSWD: /usr/bin/systemctl is-active nginx
EOF
sudo visudo -cf "$temporal" >/dev/null
sudo install -m 440 -o root -g root "$temporal" "/etc/sudoers.d/$USUARIO"
rm -f "$temporal"

echo "Cuenta $USUARIO lista: llave aceptada solo desde $ORIGEN."
echo "Grupos: $(id -nG "$USUARIO")"
sudo -l -U "$USUARIO" | sed -n '/may run/,$p'
