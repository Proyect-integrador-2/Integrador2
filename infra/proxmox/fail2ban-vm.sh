#!/usr/bin/env bash
# fail2ban en el SSH de una VM Linux del laboratorio (IP2-89).
#
# Una dirección que falla 5 inicios de sesión en 10 minutos queda bloqueada 15 minutos
# (la misma medida que el bloqueo de cuentas del dominio). El bloqueo lo pone ufw, así que
# esa dirección no llega a ningún servicio de la VM mientras dura.
#
# T19 en Zabbix sigue avisando de los intentos fallidos; fail2ban es lo que los frena.
#
# Excepción: 10.10.30.10, el servidor Proxmox. Todo el acceso remoto por Tailscale llega
# con esa dirección: bloquearla dejaría a todo el equipo sin acceso a la VM.
#
# Se corre en cada VM con el usuario ip2 (usa sudo). Se puede repetir.
#
#   ./fail2ban-vm.sh
set -euo pipefail

[[ $EUID -ne 0 ]] || { echo "Correrlo con el usuario ip2, no como root." >&2; exit 1; }

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q fail2ban >/dev/null

sudo install -m 644 /dev/stdin /etc/fail2ban/jail.d/ip2.local <<'EOF'
# Generado por infra/proxmox/fail2ban-vm.sh (IP2-89).
[DEFAULT]
bantime  = 15m
findtime = 10m
maxretry = 5
banaction = ufw
# Proxmox: por ahí entra el acceso remoto de todo el equipo (Tailscale).
ignoreip = 127.0.0.1/8 ::1 10.10.30.10

[sshd]
enabled = true
backend = systemd
EOF

sudo systemctl enable fail2ban >/dev/null 2>&1
sudo systemctl restart fail2ban
sleep 2
printf '%s: ' "$(hostname)"
sudo fail2ban-client status sshd | grep -E "Currently banned|Total failed" | tr -s ' \t' ' ' | tr '\n' ' '
echo
