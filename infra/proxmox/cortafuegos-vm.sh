#!/usr/bin/env bash
# Cortafuegos de una VM Linux del laboratorio, con lista blanca (IP2-89).
#
# Todo lo que entra se rechaza salvo lo que la VM necesita recibir, y solo desde donde
# lo necesita (tabla de abajo). Lo que sale no se limita.
#
#   - ufw filtra los servicios de la propia VM (SSH, agente de Zabbix, Nginx).
#   - Los puertos que publica Docker no pasan por ufw: van por la cadena DOCKER-USER, que
#     llena el servicio ip2-docker-cortafuegos con la misma lista blanca.
#
# Se corre en cada VM con el usuario ip2 (usa sudo). Se puede repetir.
#
#   ./cortafuegos-vm.sh
#
# Red de seguridad: antes de activar las reglas se programa su desactivación a los
# 3 minutos. Si todo funciona, se cancela con:
#   sudo systemctl stop ip2-cortafuegos-respaldo.timer
set -euo pipefail

SERVIDORES="10.10.30.0/24"
ADMINISTRACION="10.10.40.0/24"
ZABBIX="10.10.30.12"
CONTENEDORES="172.16.0.0/12"

# Qué recibe cada VM además de SSH (desde Servidores y Administración) y del agente de
# Zabbix (solo desde vm-zabbix). Formato: puerto:orígenes separados por coma.
case "$(hostname)" in
  vm-app)     PROPIOS="80:any 443:any";  DOCKER="" ;;                    # la aplicación, para todos
  # El servidor de Zabbix corre en un contenedor: llega al agente de su VM desde 172.x.
  vm-zabbix)  PROPIOS="10050:$CONTENEDORES"; DOCKER="80:$SERVIDORES,$ADMINISTRACION 10051:$SERVIDORES" ;;
  vm-grafana) PROPIOS="";                DOCKER="80:$SERVIDORES,$ADMINISTRACION" ;;
  vm-n8n)     PROPIOS="22:$CONTENEDORES"; DOCKER="5678:$SERVIDORES,$ADMINISTRACION" ;;  # n8n entra a su VM (red)
  vm-rpa)     PROPIOS="";                DOCKER="" ;;
  *) echo "VM desconocida: $(hostname)" >&2; exit 1 ;;
esac

[[ $EUID -ne 0 ]] || { echo "Correrlo con el usuario ip2, no como root." >&2; exit 1; }

# 1. Red de seguridad: si algo sale mal, todo se apaga solo a los 3 minutos.
sudo systemctl stop ip2-cortafuegos-respaldo.timer 2>/dev/null || true
sudo systemd-run --quiet --unit=ip2-cortafuegos-respaldo --on-active=180 \
  /bin/sh -c 'ufw --force disable; iptables -F DOCKER-USER 2>/dev/null; iptables -A DOCKER-USER -j RETURN 2>/dev/null; systemctl stop ip2-docker-cortafuegos 2>/dev/null; true'
echo "Red de seguridad: las reglas se desactivan solas a los 3 minutos si no se confirma."

# 2. ufw: servicios de la propia VM.
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q ufw >/dev/null
sudo ufw --force reset >/dev/null
sudo ufw default deny incoming >/dev/null
sudo ufw default allow outgoing >/dev/null
for origen in $SERVIDORES $ADMINISTRACION; do
  sudo ufw allow proto tcp from "$origen" to any port 22 comment 'SSH de administracion' >/dev/null
done
sudo ufw allow proto tcp from "$ZABBIX" to any port 10050 comment 'Agente de Zabbix' >/dev/null
for regla in $PROPIOS; do
  puerto=${regla%%:*}; origen=${regla#*:}
  sudo ufw allow proto tcp from "$origen" to any port "$puerto" comment 'IP2' >/dev/null
done
# Con Docker, los contenedores resuelven nombres con el DNS de su propia VM (ver
# infra/proxmox/dns-vm.sh): sin esta regla, n8n no llega a Telegram.
if command -v docker >/dev/null; then
  sudo ufw allow from "$CONTENEDORES" to any port 53 comment 'DNS para los contenedores' >/dev/null
fi
sudo ufw --force enable >/dev/null

# 3. Puertos publicados por Docker: lista blanca en DOCKER-USER, como servicio que se
#    vuelve a aplicar cada vez que Docker arranca.
if command -v docker >/dev/null; then
  sudo tee /usr/local/sbin/ip2-docker-cortafuegos >/dev/null <<EOF
#!/bin/sh
# Generado por infra/proxmox/cortafuegos-vm.sh (IP2-89). Lista blanca de los puertos que
# publica Docker en $(hostname). ctorigdstport es el puerto al que apuntó el cliente,
# antes de que Docker lo traduzca al del contenedor.
set -e
IF=\$(ip route show default | awk '{print \$5; exit}')
iptables -F DOCKER-USER
iptables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
for regla in $DOCKER; do
  puerto=\${regla%%:*}
  for origen in \$(echo "\${regla#*:}" | tr ',' ' '); do
    iptables -A DOCKER-USER -i "\$IF" -p tcp -m conntrack --ctorigdstport "\$puerto" -s "\$origen" -j RETURN
  done
done
# Todo lo demás que llega de la red hacia un contenedor se descarta.
iptables -A DOCKER-USER -i "\$IF" -j DROP
iptables -A DOCKER-USER -j RETURN
EOF
  sudo chmod 755 /usr/local/sbin/ip2-docker-cortafuegos
  sudo tee /etc/systemd/system/ip2-docker-cortafuegos.service >/dev/null <<'EOF'
[Unit]
Description=Lista blanca de los puertos publicados por Docker (IP2-89)
After=docker.service
PartOf=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/ip2-docker-cortafuegos

[Install]
WantedBy=docker.service
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable ip2-docker-cortafuegos >/dev/null 2>&1
  sudo systemctl restart ip2-docker-cortafuegos
fi

echo "== $(hostname) =="
sudo ufw status | sed -n '/^To/,$p' | grep -v '(v6)'
command -v docker >/dev/null && sudo iptables -S DOCKER-USER | grep -v '^-N'
echo "Si todo responde: sudo systemctl stop ip2-cortafuegos-respaldo.timer"
