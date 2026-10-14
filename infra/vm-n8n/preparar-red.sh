#!/usr/bin/env bash
# Prepara en vm-n8n el paso por el que n8n actúa sobre la red (IP2-85, IP2-86).
#
#   n8n (contenedor) --SSH, cuenta n8n-red--> vm-n8n --SSH, cuenta n8n-net--> SW1
#
# Qué hace:
#   1. Instala paramiko (Python), que sí habla los algoritmos antiguos del 2960.
#   2. Crea la cuenta n8n-red: sin contraseña, y su llave solo sirve desde los
#      contenedores de esta VM y solo para ejecutar red-accion.py.
#   3. Genera la contraseña de la cuenta n8n-net del switch y la guarda en
#      /etc/ip2/red.env, que solo lee n8n-red. No se muestra.
#
# Se corre en la VM con el usuario ip2 (usa sudo). Se puede repetir.
#
#   ./preparar-red.sh
#
# Después, quien administra el switch corre ./mostrar-config-sw1.sh, que imprime el
# bloque de configuración con esa contraseña, y lo pega en SW1.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
USUARIO="n8n-red"
PROGRAMA="/usr/local/lib/ip2/red-accion.py"
ENV="/etc/ip2/red.env"
LLAVE_PUB="$AQUI/secrets/n8n_ops_ed25519.pub"
# Los contenedores de Docker salen con direcciones 172.16.0.0/12 al conectarse a la VM.
ORIGEN="172.16.0.0/12"

[[ $EUID -ne 0 ]] || { echo "Correrlo con el usuario ip2, no como root." >&2; exit 1; }
[[ -s $LLAVE_PUB ]] || { echo "Falta $LLAVE_PUB: correr antes desplegar.sh." >&2; exit 1; }

echo "== 1. paramiko =="
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q python3-paramiko >/dev/null
python3 -c 'import paramiko; print("  paramiko", paramiko.__version__)'

echo "== 2. Cuenta $USUARIO =="
id "$USUARIO" >/dev/null 2>&1 \
  || sudo adduser --disabled-password --gecos 'Automatizacion de red n8n (IP2-86)' "$USUARIO" >/dev/null
# El programa es de root: la cuenta lo ejecuta pero no lo puede cambiar.
sudo install -d -m 755 "$(dirname "$PROGRAMA")"
sudo install -m 755 -o root -g root "$AQUI/red-accion.py" "$PROGRAMA"
sudo install -d -m 700 -o "$USUARIO" -g "$USUARIO" "/home/$USUARIO/.ssh"
printf 'command="%s",from="%s",no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding %s\n' \
  "$PROGRAMA" "$ORIGEN" "$(cut -d' ' -f1,2 "$LLAVE_PUB")" \
  | sudo tee "/home/$USUARIO/.ssh/authorized_keys" >/dev/null
sudo chown "$USUARIO:$USUARIO" "/home/$USUARIO/.ssh/authorized_keys"
sudo chmod 600 "/home/$USUARIO/.ssh/authorized_keys"
echo "  llave aceptada solo desde $ORIGEN y solo para $PROGRAMA"

echo "== 3. Contraseña de n8n-net en el switch =="
sudo install -d -m 750 -o root -g "$USUARIO" /etc/ip2
if sudo test -s "$ENV"; then
  echo "  $ENV ya existe: no se cambia la contraseña."
else
  clave=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 24)
  printf '# Generado por preparar-red.sh. No se sube a Git.\nSW1_HOST=10.10.99.2\nSW1_USUARIO=n8n-net\nSW1_CLAVE=%s\n' "$clave" \
    | sudo tee "$ENV" >/dev/null
  unset clave
  echo "  generada y guardada en $ENV."
fi
sudo chown "root:$USUARIO" "$ENV"
sudo chmod 640 "$ENV"

cat <<EOF

Listo. Falta configurar el switch: quien lo administra corre
  ssh -t ip2@10.10.30.14 $AQUI/mostrar-config-sw1.sh
y pega en SW1 el bloque que imprime.
EOF
