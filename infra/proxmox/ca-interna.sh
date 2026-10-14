#!/usr/bin/env bash
# Autoridad certificadora interna del laboratorio y los certificados que firma (IP2-90, IP2-81).
#
# La plataforma no se publica en Internet, así que no usa una autoridad pública: el
# servidor Proxmox guarda una autoridad propia ("IP2 CA interna") y con ella firma:
#   - el certificado HTTPS de MS Motos en vm-app;
#   - con --dc, el del controlador de dominio, para LDAPS.
# Los equipos que confían en esa autoridad (el robot, las VMs, y los navegadores donde se
# instale ip2-ca.crt) ven esas conexiones como seguras.
#
# Se corre como root en el servidor Proxmox. Se puede repetir: la autoridad se crea una
# sola vez y el certificado se renueva cada vez que se corre.
#
#   ./ca-interna.sh          certificado HTTPS de vm-app (10.10.30.11)
#   ./ca-interna.sh --dc     certificado LDAPS del controlador de dominio (10.10.30.17)
#
# La llave de la autoridad no sale del servidor. La de cada certificado viaja directo a
# su equipo por SSH, sin mostrarse. La parte pública de la autoridad queda en
# /root/secretos-ip2/ca/ip2-ca.crt y se copia al repositorio (infra/ca/ip2-ca.crt).
set -euo pipefail

DIR="/root/secretos-ip2/ca"
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

# firmar NOMBRE CN SAN: deja NOMBRE.key y NOMBRE.crt en $DIR.
firmar() {
  local nombre=$1 cn=$2 san=$3
  openssl req -new -newkey rsa:2048 -nodes -keyout "$DIR/$nombre.key" -out "$DIR/$nombre.csr" \
    -subj "/O=Integrador II UTN/CN=$cn" 2>/dev/null
  openssl x509 -req -sha256 -days "$DIAS" -in "$DIR/$nombre.csr" \
    -CA "$DIR/ip2-ca.crt" -CAkey "$DIR/ip2-ca.key" -CAcreateserial -out "$DIR/$nombre.crt" \
    -extfile <(printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n' "$san") 2>/dev/null
  rm -f "$DIR/$nombre.csr"
  echo "Certificado de $cn firmado: vence el $(openssl x509 -enddate -noout -in "$DIR/$nombre.crt" | cut -d= -f2)."
}

if [[ ${1:-} == --dc ]]; then
  # Controlador de dominio: Windows lo importa desde un PKCS#12 con contraseña de un solo uso.
  firmar dc01 dc01.ip2.local "DNS:dc01.ip2.local,DNS:ip2.local,IP:10.10.30.17"
  clave=$(openssl rand -hex 24)
  { openssl pkcs12 -export -in "$DIR/dc01.crt" -inkey "$DIR/dc01.key" -certfile "$DIR/ip2-ca.crt" \
      -passout "pass:$clave" | base64 -w0; echo; echo "$clave"; } \
    | ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new Administrator@10.10.30.17 \
        "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\ip2\\certificado-ldaps.ps1"
  unset clave
  exit 0
fi

# MS Motos en vm-app: la llave (solo root) y el certificado con la autoridad detrás.
firmar msmotos msmotos.ip2.local "DNS:msmotos.ip2.local,IP:10.10.30.11"
VM="ip2@10.10.30.11"
ssh -o BatchMode=yes "$VM" "sudo install -d -m 755 /etc/nginx/ssl && sudo install -m 600 /dev/stdin /etc/nginx/ssl/msmotos.key" < "$DIR/msmotos.key"
cat "$DIR/msmotos.crt" "$DIR/ip2-ca.crt" | ssh -o BatchMode=yes "$VM" "sudo install -m 644 /dev/stdin /etc/nginx/ssl/msmotos.crt"
ssh -o BatchMode=yes "$VM" "sudo nginx -t -q && sudo systemctl reload nginx && echo 'Nginx recargado con el certificado nuevo.'"
