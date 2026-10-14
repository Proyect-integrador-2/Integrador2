# Autoridad certificadora interna

`ip2-ca.crt` es la parte **pública** de la autoridad con la que se firma el certificado HTTPS de MS Motos (IP2-90). No es un secreto: es lo que se instala en un equipo para que confíe en `https://10.10.30.11`.

| Dato | Valor |
|---|---|
| Nombre | IP2 CA interna (Integrador II UTN) |
| Vence | 11 de octubre de 2036 |
| Huella SHA-256 | `29:D4:28:15:7F:A8:0A:7D:88:5E:41:74:0F:FD:B8:35:64:D9:49:A6:65:74:CB:B3:3E:45:87:FC:AD:90:F1:9C` |

La llave privada de la autoridad está solo en el servidor Proxmox (`/root/secretos-ip2/ca/`). Con ella, [`infra/proxmox/ca-interna.sh`](../proxmox/ca-interna.sh) firma y renueva el certificado de la aplicación; el trigger T20 avisa cuando le quedan menos de 15 días.

## Instalarla en una computadora con Windows

Para que el navegador no muestre la advertencia al abrir la aplicación:

1. Doble clic en `ip2-ca.crt` → **Instalar certificado** → **Equipo local**.
2. **Colocar todos los certificados en el siguiente almacén** → **Entidades de certificación raíz de confianza**.
3. Antes de aceptar, comprobar que la huella coincide con la de la tabla.

En `vm-rpa` la instala `infra/vm-rpa/desplegar.sh`, para el robot.
