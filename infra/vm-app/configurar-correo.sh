#!/usr/bin/env bash
# Correo de MS Motos por Brevo en vm-app (los códigos de registro, ingreso y recuperación
# llegan al cliente).
#
# Pide la clave de API de Brevo sin mostrarla y el remitente (una dirección ya verificada
# en Brevo → Remitentes), los guarda en app/.env (permisos 600, fuera de Git), recrea el
# contenedor de la app y manda un correo de prueba al propio remitente.
#
# Se corre de forma interactiva, con el usuario ip2:
#   ssh -t root@10.10.30.10 "ssh -t ip2@10.10.30.11 /opt/integrador2/infra/vm-app/configurar-correo.sh"
set -euo pipefail

ENV=/opt/integrador2/app/.env
[[ $EUID -ne 0 ]] || { echo "Correrlo con el usuario ip2, no como root." >&2; exit 1; }
sudo test -f "$ENV" || { echo "No existe $ENV: primero infra/vm-app/desplegar.sh" >&2; exit 1; }

read -rsp "Clave de API de Brevo (no se muestra): " clave; echo
[[ $clave == xkeysib-* ]] || { echo "La clave de API de Brevo empieza con xkeysib-. No se cambió nada." >&2; exit 1; }
read -rp "Correo remitente, verificado en Brevo: " correo
[[ $correo == *@*.* ]] || { echo "Correo no válido. No se cambió nada." >&2; exit 1; }

# Se reemplazan las líneas anteriores, si las había, sin pasar la clave por la línea de comandos.
temporal=$(mktemp)
sudo grep -v -E '^(BREVO_API_KEY|MAIL_FROM)=' "$ENV" > "$temporal" || true
printf 'BREVO_API_KEY=%s\nMAIL_FROM="MS Motos <%s>"\n' "$clave" "$correo" >> "$temporal"
unset clave
sudo install -m 600 "$temporal" "$ENV"
rm -f "$temporal"

cd /opt/integrador2/app
sudo docker compose up -d app >/dev/null 2>&1
echo "Contenedor recreado; esperando a que responda..."
for _ in $(seq 1 20); do
  curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1/api/health | grep -q 200 && break
  sleep 3
done

echo "Correo de prueba a $correo:"
sudo docker exec msmotos-app node -e "
require('./backend/src/services/mailer').enviarCorreo({ to: process.argv[1], subject: 'MS Motos: prueba de correo',
  html: '<p>Si lees esto, la app ya puede enviar los códigos a los clientes.</p>' })
  .then(ok => { console.log(ok ? 'ENVIADO: revisa la bandeja (y el spam).' : 'NO SE ENVIÓ: mira el motivo arriba.'); process.exit(ok ? 0 : 1); })" "$correo"
