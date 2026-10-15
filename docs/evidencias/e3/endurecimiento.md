# Endurecimiento y triggers que completan el diseño

Tareas: IP2-89 (cortafuegos de las VM), IP2-90 (HTTPS y contenedores), IP2-91 (triggers de seguridad) e IP2-45 (triggers restantes). Hecho y probado a distancia el 14 de octubre de 2026.

## 1. MS Motos por HTTPS

| Qué | Cómo quedó |
|---|---|
| Autoridad | "IP2 CA interna", propia del laboratorio, válida 10 años. Su llave está solo en el servidor Proxmox; la parte pública está en [`infra/ca/`](../../../infra/ca/README.md), con las instrucciones para instalarla en un navegador |
| Certificado de la app | `msmotos.ip2.local` y `10.10.30.11`, válido 397 días (hasta noviembre de 2027). Lo firma y lo instala [`ca-interna.sh`](../../../infra/proxmox/ca-interna.sh) |
| Nginx | Puerto 443 con TLS 1.2 y 1.3; el 80 solo redirige (301) a HTTPS. No muestra su versión |
| Contenedor de la app | Sin ninguna capacidad especial de Linux (`cap_drop: ALL`), sin poder ganar privilegios (`no-new-privileges`) y con el sistema de archivos de solo lectura; solo `/tmp` se escribe |
| Contenedor de la base | Sin poder ganar privilegios. MySQL necesita cambiar de usuario al arrancar, así que no se le quitan capacidades |
| Límites | La app, 512 MB, un núcleo y 200 procesos (usa unos 90 MB); la base, 1 GB y un núcleo (usa unos 450 MB). Una fuga o un bucle no dejan sin recursos a la VM |
| Cabeceras de seguridad | Las pone la aplicación: HSTS, Content-Security-Policy, X-Frame-Options, nosniff, Referrer-Policy y Permissions-Policy. Nginx agregaba un segundo HSTS; se quitó |

**Escaneo de la imagen con Trivy (14 de octubre):**

| Momento | Críticas | Altas | Con arreglo disponible |
|---|---|---|---|
| Antes | 5: `perl-base` (3) y `zlib` en Debian, `proxy-addr` en la app | 65 | 21 |
| Después | 1: `zlib` | 48 | **0** |

Se corrigió así: la app actualizó `proxy-addr`, `compression` e `ip-address`; la imagen final aplica los parches de Debian que la base todavía no trae; y se quitó `npm`, que no se usa al correr la app y traía la mayoría de las alertas de Node. La crítica que queda (CVE-2023-45853) no tiene arreglo y está en *minizip*, un componente que el paquete de Debian no incluye: se acepta como riesgo. Las 48 altas restantes tampoco tienen arreglo publicado.

**Pruebas:** `/api/health` y la portada responden 200 por HTTPS, y el puerto 80 responde 301. Desde `vm-rpa`, que confía en la autoridad, el certificado se verifica sin errores. Con el contenedor ya de solo lectura, el robot completó los dos recorridos por HTTPS, incluida la reserva y cancelación de una cita (4,6 s y 7,0 s). El escenario web de Zabbix pasó a HTTPS y responde 200.

La instancia de Windows sigue en HTTP: el diseño dejaba su HTTPS "si el tiempo alcanza".

## 2. Cortafuegos de las VM Linux

[`cortafuegos-vm.sh`](../../../infra/proxmox/cortafuegos-vm.sh): todo lo que entra se rechaza salvo esta lista. Lo que sale no se limita.

| VM | Además de SSH (VLAN 30 y 40) y el agente de Zabbix (solo desde `vm-zabbix`) |
|---|---|
| `vm-app` | 80 y 443 para todos (la aplicación) |
| `vm-zabbix` | Web (80) desde las VLAN 30 y 40; 10051 (datos de agentes, robot y n8n) desde la VLAN 30 |
| `vm-grafana` | Web (80) desde las VLAN 30 y 40 |
| `vm-n8n` | Interfaz y webhook (5678) desde las VLAN 30 y 40; SSH desde sus propios contenedores (el camino de la recuperación de red) |
| `vm-rpa` | Nada más |

Docker publica sus puertos por fuera de ufw, así que esos puertos tienen su propia lista blanca en la cadena `DOCKER-USER`. Un servicio la vuelve a aplicar cada vez que Docker arranca.

**Cómo se activó:** VM por VM, con una red de seguridad. Antes de activar las reglas, cada VM programaba su propia desactivación a los 3 minutos, y solo se cancelaba después de comprobar desde fuera:
- que seguía entrando una sesión SSH nueva;
- que el agente respondía a Zabbix;
- que los servicios de esa VM respondían desde quien los usa.

| Comprobación | Resultado |
|---|---|
| El agente de una VM, desde el servidor Proxmox (no autorizado) | Cerrado |
| La app por HTTPS, desde la laptop y desde `vm-rpa` | 200 |
| Grafana desde `vm-zabbix`, `vm-rpa` y la laptop | 200; los tableros siguen leyendo Zabbix |
| Webhook de n8n desde `vm-zabbix` | 200 |
| El robot hacia el 10051 de Zabbix (`zabbix_sender`) | Enviado |
| `vm-app-win` y `vm-dc` hacia el 10051 de Zabbix | Abierto |
| n8n hacia su VM (SSH, recuperación de red) y hacia `vm-app` (SSH, recuperación de la app) | Abiertos; `n8n-ops` responde |
| n8n hacia Telegram | Responde |

**Dos problemas encontrados y corregidos antes de confirmar:**
- Los contenedores resuelven nombres con el DNS de su propia VM, y el cortafuegos lo bloqueaba: n8n no habría podido avisar por Telegram. Se permitió el DNS desde la red de Docker.
- El servidor de Zabbix corre en un contenedor y llega al agente de su propia VM con una dirección de Docker (172.x), no con la 10.10.30.12; `vm-zabbix` quedó sin monitoreo. Se agregó esa excepción solo en esa VM.

Las VM Windows ya tenían el cortafuegos de Windows activo con su lista: escritorio remoto y SSH desde las VLAN 30 y 40, el agente solo desde Zabbix, y la aplicación en el 80. También tienen Microsoft Defender activo y SMBv1 apagado.

**Un efecto que no se vio al confirmar:** después de activar el cortafuegos en `vm-zabbix`, el servidor de Zabbix dejó de consultar la API de Proxmox (de 17:26 a 19:11). Desde su contenedor el puerto respondía, así que no era una regla: el servidor se había quedado con conexiones cortadas. Se recuperó al reiniciarlo. Nada avisó, y por eso se agregó **T21**: avisa si pasan 10 minutos sin métricas de Proxmox.

### fail2ban

[`fail2ban-vm.sh`](../../../infra/proxmox/fail2ban-vm.sh): en las 5 VM Linux, una dirección que falla 5 inicios de sesión de SSH en 10 minutos queda bloqueada 15 minutos (como el bloqueo de cuentas del dominio). La excepción es el servidor Proxmox (10.10.30.10), porque todo el acceso remoto del equipo llega con esa dirección.

**Prueba:** desde `vm-grafana`, 6 intentos contra `vm-rpa` con un usuario que no existe. Al quinto, `vm-rpa` bloqueó a `vm-grafana`, y el séptimo intento fue rechazado aunque usaba una cuenta válida. T19 se abrió en Zabbix. Después se quitó el bloqueo.

## 3. Triggers que completan el diseño

| Trigger | Condición | Severidad | Prueba |
|---|---|---|---|
| T02 Contenedor con el chequeo de salud fallando | Estado *unhealthy* durante 2 minutos | Alta | No se provocó |
| T09 Puerto de acceso caído | Ver [recuperacion-red.md](recuperacion-red.md) | Alta | Ver ese documento |
| T09-G Enlace de gestión caído | Ver [recuperacion-red.md](recuperacion-red.md) | Desastre | Ver ese documento |
| T09b Puerto bloqueado (*err-disabled*) | Lo cubre T09: un puerto bloqueado aparece como caído | — | — |
| T10 Enlace saturado (troncales y WAN) | Más de 70 % y más de 90 % de la velocidad, promedio de 5 minutos | Advertencia y alta | No se provocó (E4, PR-07) |
| T11 Router o switch saturado | CPU o memoria sobre 90 % durante 10 minutos | Alta; solo alerta | No se provocó |
| T11b Router o switch sin respuesta | Sin ping 2 minutos | Desastre | No se provocó |
| T18 Configuración del router o del switch modificada | Cambió la hora de la última modificación que publica el equipo por SNMP | Advertencia | **Sí**: se abrió a las 14:56 y a las 14:58 con dos reinicios de un puerto, y se cerró solo al minuto |
| T19 Intentos de SSH fallidos en una VM Linux | Más de 10 en 5 minutos | Advertencia | **Sí**: 12 intentos con un usuario inexistente contra `vm-rpa`; se abrió a las 14:58:16 |
| T20 Certificado HTTPS por vencer | Menos de 15 días | Advertencia | Lee el certificado: le quedan 396 días |
| T21 Sin datos del servidor Proxmox (agregado) | 10 minutos sin métricas por la API | Alta | Nace del hueco descrito en la sección 2 |

**T04 después de su causa.** T04 (la aplicación no responde) se abría con dos fallos del chequeo web, unos 45 segundos, antes que la causa: T01 (contenedor) a los ~75 s o T03 (Nginx) a los ~65 s. La dependencia solo lo oculta si la causa ya está abierta, así que llegaban dos avisos. Ahora espera 90 segundos de fallos seguidos. **Prueba (19:19):** se detuvo el contenedor; T01 se abrió a los 22 s, n8n lo inició al segundo, y T04 no llegó a abrirse. Llegó un solo aviso.

Donde un trigger propio reemplaza a uno de plantilla (salud del contenedor, CPU, memoria y ping del router y del switch), el de la plantilla se apagó en ese host, para que el mismo evento no llegue dos veces.

T11 solo alerta. El diseño proponía reiniciar el equipo saturado, pero eso cortaría toda la red del laboratorio.

## 4. Pendiente

| Qué | Tarea |
|---|---|
| Comprobar en el router y el switch los controles de endurecimiento | IP2-88 |
| Cortafuegos de Proxmox y segundo factor (TOTP) para sus administradores. Se hace con alguien en el laboratorio: un error en el cortafuegos de Proxmox corta el único acceso remoto | IP2-89 |
| Provocar T02, T10 y T11 en las pruebas del E4 | IP2-59, IP2-60 |
| HTTPS en la instancia Windows | IP2-90 |
