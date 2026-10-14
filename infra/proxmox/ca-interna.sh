#!/usr/bin/env bash
# Autoridad certificadora interna del laboratorio y certificado HTTPS de MS Motos (IP2-90).
#
# La plataforma no se publica en Internet, así que no usa una autoridad pública: el
# servidor Proxmox guarda una autoridad propia ("IP2 CA interna") y con ella firma el
# certificado de la aplicación. Los equipos que confían en esa autoridad (el robot, y
# los navegadores donde se instale ip2-ca.crt) ven la conexión como segura.
#
# Se corre como root en el servidor Proxmox. Se puede repetir: la autoridad se crea una
# sola vez y el certificado se renueva cada vez que se corre.
#
#   ./ca-interna.sh                       certificado para vm-app (10.10.30.11)
#
# La llave de la autoridad no sale del servidor. La del certificado viaja directo a la
# VM por SSH, sin mostrarse. La parte pública de la autoridad queda en
# /root/secretos-ip2/ca/ip2-ca.crt y se copia al repositorio (infra/ca/ip2-ca.crt).
set -euo pipefail

DIR="/root/secretos-ip2/ca"
NOMBRE="msmotos"
DOMINIO="msmotos.ip2.local"
IP="10.10.30.11"
VM="ip2@10.10.30.11"
DIAS=397          # un poco más de un año: el límite que aceptan los navegadores

[[ $EUID -eq 0 ]] || { echo "Hay que correrlo como root." >&2; exit 1; }
umask 077
mkdir -p "$DIR"

if [[ ! -s $DIR/ip2-ca.key ]]; then
  openssl req -x509 -new -newkey rsa:4096 -nodes -sha256 -days 3650 \
    -keyout "$DIR/ip2-ca.key" -out "$DIR/ip2-ca.crt" \
    -subj "/O=Integrador II UTN/CN=IP2 CA interna" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
  chmod 644 "$DIR/ip2-ca.crt"
  echo "Autoridad creada: $DIR/ip2-ca.crt (válida 10 años)."
fi

openssl req -new -newkey rsa:2048 -nodes -keyout "$DIR/$NOMBRE.key" -out "$DIR/$NOMBRE.csr" \
  -subj "/O=Integrador II UTN/CN=$DOMINIO" 2>/dev/null
openssl x509 -req -sha256 -days "$DIAS" -in "$DIR/$NOMBRE.csr" \
  -CA "$DIR/ip2-ca.crt" -CAkey "$DIR/ip2-ca.key" -CAcreateserial -out "$DIR/$NOMBRE.crt" \
  -extfile <(printf 'subjectAltName=DNS:%s,IP:%s\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n' "$DOMINIO" "$IP") 2>/dev/null
rm -f "$DIR/$NOMBRE.csr"
echo "Certificado de $DOMINIO ($IP) firmado: vence el $(openssl x509 -enddate -noout -in "$DIR/$NOMBRE.crt" | cut -d= -f2)."

# A la VM: la llave (solo root) y el certificado con la autoridad detrás.
ssh -o BatchMode=yes "$VM" "sudo install -d -m 755 /etc/nginx/ssl && sudo install -m 600 /dev/stdin /etc/nginx/ssl/$NOMBRE.key" < "$DIR/$NOMBRE.key"
cat "$DIR/$NOMBRE.crt" "$DIR/ip2-ca.crt" | ssh -o BatchMode=yes "$VM" "sudo install -m 644 /dev/stdin /etc/nginx/ssl/$NOMBRE.crt"
ssh -o BatchMode=yes "$VM" "sudo nginx -t -q && sudo systemctl reload nginx && echo 'Nginx recargado con el certificado nuevo.'"
