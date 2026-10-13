#!/usr/bin/env bash
# Conecta el bot de Telegram al flujo de alertas de n8n (IP2-51).
#
# Lo corre una persona, porque pide el token del bot y no lo muestra al escribirlo:
#
#   ssh -t ip2@10.10.30.14 /opt/integrador2/infra/vm-n8n/configurar-telegram.sh
#
# Antes:
#   1. En Telegram, hablar con @BotFather, enviar /newbot y guardar el token que entrega.
#   2. Crear un grupo para las alertas, agregar el bot y escribir cualquier mensaje ahí.
#      (Sin grupo también sirve: abrir el chat del bot y enviarle un mensaje.)
#
# El script comprueba el token, busca el chat, guarda los dos datos en .env (permisos 600),
# reinicia n8n y envía un mensaje de prueba.
set -euo pipefail

AQUI="/opt/integrador2/infra/vm-n8n"
API="https://api.telegram.org"

[[ -t 0 ]] || { echo "Hay que correrlo en una terminal (ssh -t): pide el token por teclado." >&2; exit 1; }

read -rs -p "Token del bot (no se muestra al escribir): " token
echo
[[ $token =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]] || { echo "Eso no tiene forma de token de bot." >&2; exit 1; }

bot=$(curl -s -m 15 "$API/bot$token/getMe" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["result"]["username"] if d.get("ok") else "")')
[[ -n $bot ]] || { echo "Telegram no reconoce ese token." >&2; exit 1; }
echo "Bot reconocido: @$bot"

# El chat se toma del último mensaje que recibió el bot, dando preferencia a un grupo.
buscar_chat() {
  curl -s -m 15 "$API/bot$token/getUpdates" | python3 -c '
import json, sys
chats = {}
for u in json.load(sys.stdin).get("result", []):
    m = u.get("message") or u.get("my_chat_member") or u.get("channel_post") or {}
    c = m.get("chat")
    if c:
        chats[c["id"]] = c
grupos = [c for c in chats.values() if c["type"] in ("group", "supergroup")]
elegido = (grupos or list(chats.values()) or [None])[-1]
if elegido:
    print(elegido["id"], elegido.get("title") or elegido.get("first_name") or "chat privado", sep="\t")
'
}
chat=$(buscar_chat)
if [[ -z $chat ]]; then
  echo "El bot todavía no ha recibido mensajes."
  read -r -p "Escribe algo en el grupo donde está @$bot (o en su chat) y presiona Enter... " _
  chat=$(buscar_chat)
fi
[[ -n $chat ]] || { echo "No apareció ningún chat. Revisar que el bot esté en el grupo y repetir." >&2; exit 1; }
chat_id=${chat%%$'\t'*}
echo "Chat de las alertas: ${chat#*$'\t'}"

sed -i '/^TELEGRAM_BOT_TOKEN=/d; /^TELEGRAM_CHAT_ID=/d' "$AQUI/.env"
printf 'TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_CHAT_ID=%s\n' "$token" "$chat_id" >> "$AQUI/.env"
chmod 600 "$AQUI/.env"

cd "$AQUI"
sudo docker compose up -d >/dev/null 2>&1
echo "n8n reiniciado con el bot."

enviado=$(curl -s -m 15 "$API/bot$token/sendMessage" \
  --data-urlencode "chat_id=$chat_id" \
  --data-urlencode "text=✅ Integrador II: las alertas del laboratorio llegarán a este chat." \
  | python3 -c 'import json,sys; print("si" if json.load(sys.stdin).get("ok") else "no")')
if [[ $enviado == si ]]; then
  echo "Mensaje de prueba enviado: debe verse en Telegram."
else
  echo "El mensaje de prueba no salió. Revisar que el bot pueda escribir en ese chat." >&2
  exit 1
fi
