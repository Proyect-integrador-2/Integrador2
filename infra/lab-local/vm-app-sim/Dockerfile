# Simulación mínima de vm-app para probar las acciones de n8n por SSH.
# En la VM real esto es Ubuntu con OpenSSH; el usuario y el sudoers son los mismos.
FROM alpine:3.22

RUN apk add --no-cache openssh-server sudo docker-cli \
 && ssh-keygen -A \
 && adduser -D -s /bin/sh n8n-ops \
 # adduser -D deja la cuenta bloqueada ("!") y sshd rechaza incluso la llave;
 # "*" = sin contraseña utilizable pero cuenta activa.
 && echo 'n8n-ops:*' | chpasswd -e

# Solo llave, nunca contraseña; sin root por SSH.
# Va en sshd_config.d (se incluye al inicio): en sshd gana el PRIMER valor de cada opción,
# y el sshd_config de Alpine ya define AuthorizedKeysFile más arriba.
RUN mkdir -p /etc/ssh/sshd_config.d /etc/ssh/authorized_keys \
 && grep -q '^Include /etc/ssh/sshd_config.d/' /etc/ssh/sshd_config \
    || sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config \
 && printf '%s\n' \
      'PasswordAuthentication no' \
      'KbdInteractiveAuthentication no' \
      'PermitRootLogin no' \
      'AllowUsers n8n-ops' \
      'AuthorizedKeysFile /etc/ssh/authorized_keys/%u' \
    > /etc/ssh/sshd_config.d/10-integrador2.conf

# Lista cerrada: n8n-ops solo puede iniciar o reiniciar el contenedor de la app.
# Nada de pertenecer al grupo docker (equivale a root en el host).
RUN printf '%s\n' \
      'n8n-ops ALL=(root) NOPASSWD: /usr/bin/docker start msmotos-app' \
      'n8n-ops ALL=(root) NOPASSWD: /usr/bin/docker restart msmotos-app' \
      'n8n-ops ALL=(root) NOPASSWD: /usr/bin/docker inspect -f {{.State.Status}} msmotos-app' \
    > /etc/sudoers.d/n8n-ops \
 && chmod 440 /etc/sudoers.d/n8n-ops

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
