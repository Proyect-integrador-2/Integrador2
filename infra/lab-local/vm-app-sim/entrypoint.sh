#!/bin/sh
set -e
# La llave pública se monta desde secrets/ (no se guarda en la imagen ni en Git).
if [ -f /etc/ssh/n8n-ops.pub ]; then
  # tr quita los \r si la llave se generó en Windows.
  tr -d '\r' < /etc/ssh/n8n-ops.pub > /etc/ssh/authorized_keys/n8n-ops
  chmod 644 /etc/ssh/authorized_keys/n8n-ops
else
  echo "Falta /etc/ssh/n8n-ops.pub: ejecutá generar-llave-ssh.ps1" >&2
fi
exec /usr/sbin/sshd -D -e
