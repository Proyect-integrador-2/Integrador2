# Visita al laboratorio del 12 de octubre de 2026

Tareas: IP2-27 y IP2-28 (switch y router), IP2-32 (hipervisor), IP2-93 (administración remota), IP2-14 e IP2-31 (inventario y dimensionamiento).

Resultado: el router, el switch y el servidor quedaron configurados, y la plataforma se administra a distancia desde ese día. Las pruebas de red desde una computadora de usuario y desde una de administración pasaron todas (V1 y V3 a V9), las cinco máquinas virtuales Linux quedaron creadas y la aplicación MS Motos ya responde en `vm-app` y Zabbix vigila las VM, el router, el switch y la aplicación, Grafana muestra los tableros con esos datos y n8n recupera solo el contenedor y Nginx cuando se caen. Faltan las alertas a una persona, el robot y las dos VM de Windows Server.

## 1. Equipos del grupo

| Equipo | Modelo | Función |
|---|---|---|
| R1 | Cisco ISR 4221 | Enrutamiento entre VLAN, NAT, DHCP de usuarios y listas de acceso |
| SW1 | Cisco Catalyst WS-C2960-24TT-L | VLAN, troncales y controles de capa 2 |
| Servidor | Dell PowerEdge R450 | Hipervisor Proxmox VE |

### Servidor

| Dato | Valor |
|---|---|
| Procesador | Intel Xeon Silver 4314, 16 núcleos y 32 hilos, con VT-x |
| Memoria | 64 GB (4 módulos de 16 GB; 12 ranuras libres) |
| Disco | 2,2 TB en un volumen de la controladora PERC H345 |
| Almacenamiento en Proxmox | `local` 94 GB para ISO y plantillas; `local-lvm` cerca de 2 TB para discos de VM |
| Tarjetas de red | Cuatro: dos de 1 Gb sin cable y dos de 10 Gb en uso (`nic2` y `nic3`) |
| Sistema | Proxmox VE 9.2.2, núcleo 7.0.2-6-pve, zona horaria America/Costa_Rica |

Con 64 GB caben las siete máquinas virtuales del diseño (24 GB asignados, más 2 GB de Proxmox) sin aplicar ninguno de los recortes previstos en la sección 4.4 del Entregable 2. También sobran núcleos (13 vCPU sobre 32 hilos) y disco (290 GB sobre 2 TB).

El servidor traía un Ubuntu de otro grupo con credenciales desconocidas. Se reinstaló desde cero con Proxmox VE.

## 2. Qué se configuró

| Equipo | Qué quedó | Cómo se comprobó |
|---|---|---|
| R1 | Subinterfaces de las VLAN 20, 30, 40 y 99, NAT, DHCP de usuarios, listas de acceso, SSH y SNMP. Configuración guardada | La WAN recibió dirección de la universidad por DHCP y el ping a 8.8.8.8 respondió 5 de 5 |
| SW1 | VLAN 20, 30, 40, 99 y 999, troncales en Gi0/1 y Gi0/2, puertos de acceso, seguridad de puertos, DHCP snooping y control de tormentas. Configuración guardada | Revisión de `show running-config` |
| Servidor | Proxmox VE con el puente `vmbr0` (con VLAN) sobre el troncal hacia SW1 y la dirección `10.10.30.10` en la VLAN de servidores | Ver la sección 3 |

La configuración aplicada es la de [`red/router/R1-4221.txt`](../../../red/router/R1-4221.txt) y [`red/switch/SW1-2960.txt`](../../../red/switch/SW1-2960.txt), con las contraseñas y la comunidad SNMP reales, que no están en el repositorio.

## 3. Administración remota

El servidor tiene dos caminos de red, como se diseñó en [`infra/acceso-remoto/`](../../../infra/acceso-remoto/README.md):

| Tarjeta | Conectada a | Para qué |
|---|---|---|
| `nic2` | Red de la universidad, por DHCP | Salida de Tailscale. No depende de R1 ni de SW1 |
| `nic3` | SW1 Gi0/2, troncal | Red del proyecto: Proxmox y las VM en la VLAN 30 |

Tailscale publica las cuatro redes del proyecto (`10.10.20.0/24`, `10.10.30.0/24`, `10.10.40.0/24` y `10.10.99.0/24`) solo a los equipos de la cuenta del proyecto. La tarjeta `nic2` tiene un cortafuegos que no acepta conexiones entrantes ni reenvía tráfico, para que el servidor no sirva de atajo que esquive al router.

### Pruebas, desde la portátil y a través de Tailscale

| Prueba | Resultado |
|---|---|
| Panel de Proxmox en `https://10.10.30.10:8006` | Abre |
| SSH al servidor con llave, sin contraseña | Entra |
| Ping a R1 (`10.10.30.1`) y a SW1 (`10.10.99.2`) | Responden |
| SSH a R1 y a SW1 desde el servidor | Puerto abierto, después de permitir `10.10.30.10` en sus listas de acceso |
| Cortafuegos de `nic2` | Cargado; ya descartaba conexiones entrantes desde la red de la universidad |

### Prueba de reinicio

Se reinició el servidor sin tocar nada más. Volvió solo con la ruta por defecto por `nic2`, la dirección `10.10.30.10`, el cortafuegos, Tailscale y el panel activos, sin servicios fallidos, y con alcance al router, al switch y a Internet.

## 4. Segmentación desde una computadora de usuario

PC-CLIENTE: computadora del laboratorio conectada a SW1 Fa0/5 (VLAN 20), con la red en automático.

| # | Prueba | Esperado | Resultado | Evidencia |
|---|---|---|---|---|
| V1 | `ipconfig` | Dirección por DHCP entre .100 y .200 | `10.10.20.100`, puerta de enlace `10.10.20.1` | [foto](red/v1-cliente-ipconfig.jpg) |
| — | `ping 10.10.20.1` | Responde | Responde, 4 de 4 | [foto](red/v1b-cliente-ping-gateway.jpg) |
| V3 | `ping 10.10.30.10` (servidores) | Bloqueado | Bloqueado por el router | [foto](red/v3-cliente-ping-servidores.jpg) |
| — | Abrir `https://10.10.30.10:8006` (panel de Proxmox) | No abre | No abre: tiempo de espera agotado | [foto](red/v3b-cliente-panel-proxmox-bloqueado.jpg) |
| V4 | `ping 10.10.40.10` (administración) | Bloqueado | Bloqueado por el router | [foto](red/v4-cliente-ping-administracion.jpg) |
| V5 | `ping 10.10.99.2` (gestión del switch) | Bloqueado | Bloqueado por el router | [foto](red/v5-cliente-ping-gestion.jpg) |
| V8 | `ping 8.8.8.8` | Responde por NAT | Responde, 4 de 4, 61 ms en promedio | [foto](red/v8-cliente-ping-internet.jpg) |

En las pruebas bloqueadas quien contesta es el router (`Reply from 10.10.20.1: Destination net unreachable`): es la lista `ACL-USUARIOS-IN` rechazando el paquete. Windows cuenta esos rechazos como recibidos, pero ningún ping llegó a su destino.

Un usuario recibe dirección sola, sale a Internet y no alcanza los servidores, la red de administración ni la gestión de los equipos.

## 5. Alcance desde la computadora de administración

PC-ADMIN: computadora del laboratorio conectada a SW1 Fa0/1 (VLAN 40), con la dirección fija `10.10.40.10`.

| # | Prueba | Esperado | Resultado | Evidencia |
|---|---|---|---|---|
| — | `ipconfig` | `10.10.40.10` | `10.10.40.10`, puerta de enlace `10.10.40.1` | [foto](red/v6a-admin-ipconfig.jpg) |
| V6 | `ping 10.10.30.10` (servidor) | Responde | Responde, 4 de 4 | [foto](red/v6b-admin-ping-servidor.jpg) |
| V6 | `ping 10.10.99.2` (gestión del switch) | Responde | Responde, 4 de 4 | [foto](red/v6c-admin-ping-switch.jpg) |
| V6 | `ping 10.10.20.100` (PC-CLIENTE) | Responde | Responde, 4 de 4 | [foto](red/v6d-admin-ping-cliente.jpg) |
| — | Abrir `https://10.10.30.10:8006` | Panel de Proxmox | Abre y permite iniciar sesión | [foto](red/v6e-admin-panel-proxmox.jpg) |
| — | `ping 8.8.8.8` | Responde por NAT | Responde, 4 de 4, 58 ms | [foto](red/v6f-admin-ping-internet.jpg) |
| V7 | SSH a SW1 (`10.10.99.2`) | Entra | Entra con usuario y contraseña; prompt `SW1#` | [foto](red/v7-admin-ssh-switch.jpg) |
| V9 | SSH a R1 (`10.10.40.1`) y `show ip nat translations` | Traducciones activas | 122 traducciones, con origen en `10.10.20.100` y en `10.10.40.10`, todas saliendo con la dirección de la WAN | [traducciones](red/v9-router-nat-traducciones.jpg), [total y versión](red/v9b-router-nat-total-y-version.jpg) |

Las mismas tres redes que el usuario tiene bloqueadas responden desde Administración, y el mismo panel que al usuario no le abre aquí sí carga.

R1 corre Cisco IOS XE 17.12.03a y muestra el aviso de acceso restringido al entrar. Entre las traducciones está la del ping de PC-CLIENTE a 8.8.8.8, que se dejó corriendo durante la prueba.

SW1 corre IOS 15.0(2)SE11 (imagen `C2960-LANBASEK9-M`). Su servidor SSH solo ofrece algoritmos antiguos (intercambio Diffie-Hellman con SHA-1, cifrado AES-CBC y verificación `hmac-sha1`), que el cliente de Windows trae desactivados: hay que habilitarlos en el comando para esa conexión. Es una limitación del equipo y se anota en la sección de seguridad.

Medido aparte desde el servidor: 0,4 ms al router, 1,3 ms al switch y 1,5 ms a PC-ADMIN pasando por el router. Desde el servidor no responde el ping a PC-CLIENTE, como está diseñado: la lista de usuarios solo deja volver las respuestas hacia Administración.

## 6. Máquinas virtuales Linux

Creadas el mismo día por la tarde, a distancia, con [`infra/proxmox/crear-vms.sh`](../../../infra/proxmox/crear-vms.sh) (tarea IP2-33). Salen de la imagen oficial de Ubuntu 24.04 para la nube y quedan configuradas por cloud-init.

| ID | VM | Dirección | vCPU | Memoria | Disco | Arranca con el servidor |
|---|---|---|---|---|---|---|
| 111 | `vm-app` | 10.10.30.11 | 2 | 4 GB | 40 GB | Sí |
| 112 | `vm-zabbix` | 10.10.30.12 | 2 | 4 GB | 60 GB | Sí |
| 113 | `vm-grafana` | 10.10.30.13 | 1 | 2 GB | 20 GB | Sí |
| 114 | `vm-n8n` | 10.10.30.14 | 2 | 2 GB | 20 GB | Sí |
| 115 | `vm-rpa` | 10.10.30.15 | 2 | 4 GB | 30 GB | Sí |

Comprobado en las cinco: Ubuntu 24.04.5, nombre y dirección correctos, recursos según la tabla, cloud-init terminado, `sudo` sin contraseña para el usuario `ip2`, salida a Internet por R1 (ping a 8.8.8.8) y acceso por SSH con llave desde el servidor y desde la portátil por Tailscale. No tienen contraseña: solo se entra con llave.

Con las cinco encendidas el servidor usa 6 GB de sus 64 GB de memoria y el 0,5 % del almacenamiento de VM.

## 7. Aplicación MS Motos en contenedores

Desplegada el mismo día en `vm-app` con [`infra/vm-app/desplegar.sh`](../../../infra/vm-app/desplegar.sh) (tarea IP2-38). La imagen se construyó en la propia VM desde el `Dockerfile` del repositorio.

| Componente | Dónde corre | Estado |
|---|---|---|
| Nginx | Servicio del sistema en `vm-app`, puerto 80 | Activo y habilitado al arranque |
| `msmotos-app` | Contenedor, publicado solo en `127.0.0.1:3000` | En ejecución, `healthy` |
| `msmotos-db` (MySQL 8.4) | Contenedor con el volumen `msmotos-db-data`, sin puerto publicado | En ejecución, `healthy` |

| Prueba | Resultado |
|---|---|
| `http://127.0.0.1:3000/api/health` dentro de la VM | HTTP 200 |
| `http://10.10.30.11/api/health` por Nginx | HTTP 200, `{"ok":true}` |
| `http://10.10.30.11/` | HTTP 200, portada "MS Motos · Taller" |
| Las mismas dos direcciones desde la portátil, por Tailscale | HTTP 200 |
| Inicio de sesión de `admin@taller.com` | HTTP 200, rol `admin` |
| Inicio de sesión de `recepcion@taller.com` y de `rpa@taller.local` | HTTP 200, rol `recepcion` |
| Inicio de sesión con contraseña incorrecta | HTTP 401 |

Los secretos (base de datos, firma de sesiones y contraseñas de las tres cuentas) se generaron al azar en la VM y viven solo en `/opt/integrador2/app/.env`, con permisos 600. No están en el repositorio.

La construcción tomó cerca de 4 minutos. Con la aplicación arriba, la VM usa 1,1 GB de sus 4 GB de memoria y 5,4 GB de disco.

## 8. Monitoreo con Zabbix

Desplegado el mismo día en `vm-zabbix` (tareas IP2-41 a IP2-45). Todo sale de [`infra/vm-zabbix/`](../../../infra/vm-zabbix/): `desplegar.sh` levanta Zabbix 7.0.30 con PostgreSQL 16 en contenedores, `instalar-agente.sh` pone Zabbix agent 2 (7.0.31) en cada VM y `configurar-zabbix.py` crea hosts, plantillas y triggers por la API. El frontend queda en `http://10.10.30.12`.

| Host | Qué es | Método | Estado | Ítems |
|---|---|---|---|---|
| `vm-app` | VM de la aplicación | Agente, con Docker y Nginx | Disponible | 226 |
| `vm-zabbix`, `vm-grafana`, `vm-n8n`, `vm-rpa` | Las otras cuatro VM | Agente | Disponibles | 75 cada una |
| `r1` | Router ISR 4221 | SNMP v2c, solo lectura | Disponible | 96 |
| `sw1` | Switch 2960 | SNMP v2c, solo lectura | Disponible | 245 |
| `proxmox` | Servidor físico | Ping | Responde | 3 |
| `msmotos-web` | La aplicación como la ve un usuario | Escenario web por Nginx, cada 30 s | HTTP 200 en 6 ms | 9 |

Zabbix descubrió por SNMP 30 interfaces de red. Arriba al momento de la prueba: la WAN, el troncal y las cinco subinterfaces en R1; `Gi0/1`, `Gi0/2` y `Vl99` en SW1.

El router y el switch solo responden SNMP a `10.10.30.12` y con la comunidad correcta: con otra comunidad no contestan. La comunidad viaja a la VM por el túnel y queda como macro secreta en Zabbix; no está en el repositorio.

| Trigger | Condición | Severidad | Etiqueta para la automatización |
|---|---|---|---|
| T01 Contenedor `msmotos-app` detenido | Sin estado *running* durante 1 min | Alta | `restart-container` |
| T03 Servicio Nginx detenido | Sin estado `active` durante 1 min | Alta | `restart-service` |
| T04 App MS Motos no disponible | El chequeo web falla 2 veces seguidas | Desastre | `none` (depende de T01 y T03) |
| T05 App MS Motos lenta | Respuesta promedio mayor a 2 s en 5 min | Advertencia | `none` |

### Prueba de detección: contenedor detenido

| Hora | Qué pasó |
|---|---|
| 20:10:39 | Se detiene `msmotos-app` con `docker stop` |
| +73 s | Zabbix tiene abierto T01. También abrió T04 y el aviso de la plantilla de Docker |
| — | Durante la caída, Nginx sigue arriba y el usuario recibe HTTP 502 |
| 20:12:45 | Se inicia el contenedor a mano |
| +67 s | Zabbix cierra los tres problemas. El usuario vuelve a recibir HTTP 200 |

La detección quedó dentro del requisito de menos de 2 minutos (RNF-01).

**Hallazgo:** la dependencia de T04 sobre T01 no ocultó T04 en esta prueba. T04 se disparó antes que T01, y Zabbix solo suprime el síntoma si la causa ya está abierta. Hay que ajustar los tiempos para que la causa siempre llegue primero.

**Sin soporte, esperado:** en R1, los contadores de errores y descartes de las subinterfaces (IOS XE no los publica por subinterfaz). No afecta al resto.

## 9. Tableros de Grafana

Desplegado el mismo día en `vm-grafana` con [`infra/vm-grafana/desplegar.sh`](../../../infra/vm-grafana/desplegar.sh) (tarea IP2-47). Grafana 12.4.3 con el plugin de Zabbix; lee Zabbix con un usuario de solo lectura y carga los cinco tableros de [`monitoreo/grafana/`](../../../monitoreo/grafana/). Queda en `http://10.10.30.13`.

La fuente de datos responde "Zabbix API version 7.0.30". [`verificar-tableros.py`](../../../infra/vm-grafana/verificar-tableros.py) ejecutó las consultas de los 40 paneles:

| Tablero | Con datos | Vacíos | Solo en el navegador |
|---|---|---|---|
| General (ejecutivo) | 4 | 0 | 2 |
| Técnico (infraestructura) | 11 | 0 | 0 |
| Red | 7 | 0 | 0 |
| Experiencia del usuario | 3 | 4 | 2 |
| Automatización (n8n y RPA) | 0 | 5 | 2 |
| **Total** | **25** | **9** | **6** |

Ninguna consulta dio error. Los 9 vacíos esperan al robot y a n8n, que todavía no están desplegados. Los 6 "solo en el navegador" son listas de problemas y textos, que el plugin resuelve del lado del navegador y no se pueden comprobar por la API.

El tablero de Red, que en la réplica local tenía 5 paneles vacíos, aquí trae datos reales de R1 y SW1: tráfico y estado de las 30 interfaces, errores y descartes, y latencia y pérdida hacia el router, el switch y el servidor.

## 10. Automatización con n8n

Desplegado el mismo día en `vm-n8n` con [`infra/vm-n8n/desplegar.sh`](../../../infra/vm-n8n/desplegar.sh) (tareas IP2-50, IP2-52 e IP2-53). n8n 2.40.2 con el flujo [`recuperacion-zabbix.json`](../../../automatizacion/n8n/recuperacion-zabbix.json) publicado. Zabbix le avisa cada problema del grupo del proyecto por un webhook; n8n decide, actúa por SSH sobre `vm-app` y deja constancia en el evento de Zabbix.

### Controles probados

La cuenta `n8n-ops` de `vm-app` la crea [`infra/vm-app/preparar-n8n-ops.sh`](../../../infra/vm-app/preparar-n8n-ops.sh): sin contraseña, fuera del grupo `docker` y con una lista cerrada de comandos.

| Prueba | Esperado | Resultado |
|---|---|---|
| Consultar el estado del contenedor y de Nginx | Permitido | Responde `running` y `active` |
| `docker ps` con sudo | Rechazado | `sudo: a password is required` |
| Detener la base de datos | Rechazado | `sudo: a password is required` |
| `docker ps` sin sudo | Rechazado | Sin permiso sobre el socket de Docker |
| Abrir una sesión de root | Rechazado | `sudo: a password is required` |
| Entrar como `n8n-ops` desde otro equipo (el servidor Proxmox) | Rechazado | `Permission denied (publickey)` |
| Aviso al webhook con token falso, con el contenedor detenido | Descartado | El contenedor siguió detenido |

La llave privada se generó en `vm-n8n` y no salió de esa VM; `vm-app` solo la acepta desde `10.10.30.14`.

### PR-02: contenedor detenido

| Hora | Desde la parada | Qué pasó |
|---|---|---|
| 21:48:33 | 0 s | `docker stop msmotos-app` |
| 21:49:31 | 58 s | Zabbix abre T04 (la aplicación no responde) y avisa a n8n: solo notifica |
| 21:49:54 | 81 s | Zabbix abre T01 (contenedor detenido) y avisa a n8n |
| 21:49:55 | 82 s | `n8n-ops` ejecuta `docker start msmotos-app` (registro de sudo en `vm-app`) |
| 21:49:56 | 83 s | n8n anota en el evento: "recuperación automática (intento 1 de 3): comando ejecutado" |
| 21:49:57 | 84 s | El contenedor vuelve a estar en ejecución |
| 21:50:54 | 141 s | Zabbix cierra T01 y n8n anota "RESUELTO" |

### PR-01: servicio Nginx detenido

| Hora | Desde la parada | Qué pasó |
|---|---|---|
| 21:56:24 | 0 s | `systemctl stop nginx`. El usuario no logra conectar |
| 21:57:27 | 63 s | Zabbix abre T03 (servicio detenido) y avisa a n8n |
| 21:57:28 | 64 s | `n8n-ops` ejecuta `systemctl restart nginx`; n8n lo anota en el evento |
| 21:57:29 | 65 s | Nginx activo |
| 21:57:57 | 93 s | Zabbix cierra T03 y n8n anota "RESUELTO" |

En las dos pruebas la detección tomó menos de 2 minutos (RNF-01) y la recuperación menos de 5 (RNF-02), sin intervención de una persona. Durante PR-01 el contenedor siguió en ejecución: Zabbix distinguió el servicio caído del contenedor caído.

**Detección adicional:** al crear la cuenta `n8n-ops`, Zabbix abrió por su cuenta "/etc/passwd has been changed" en `vm-app`.

**Por revisar:** el aviso de la plantilla "Nginx: Process is not running" llegó dos veces a n8n, y la dependencia de T04 sigue sin ocultarlo cuando la causa es T01 o T03.

## 11. Incidencias

| Qué pasó | Cómo se resolvió |
|---|---|
| En la primera corrida del script el servidor quedó sin ruta por defecto y no pudo descargar Tailscale. Al recargar la red, Proxmox quitó el gateway que había dejado la instalación y se llevó la ruta recién recibida por DHCP | Se renovó el DHCP en `nic2` y se repitió el script. El script ya lo hace solo (commit `096ff8a`) |
| Grafana arrancó sin fuente de datos ni tableros: el repositorio se había clonado con permisos que el contenedor no podía leer | Se corrigieron los permisos y los scripts de despliegue ya fijan la máscara (commit `cdf3652`) |
| La plantilla de Nginx de Zabbix recibía 403 al leer la página de estado: consultaba `localhost`, que resuelve a IPv6, y solo se permite `127.0.0.1` | Macro del host ajustada a `127.0.0.1` |
| R1 y SW1 rechazaban SSH desde el servidor: sus listas solo permitían la VLAN 40 | Se agregó `permit host 10.10.30.10` a `ACL-SSH-ADMIN` de R1 y a la lista 40 de SW1. Ya está en las configuraciones del repositorio |

## 12. Diferencias con lo planeado

| Planeado | Lo que se hizo | Consecuencia |
|---|---|---|
| Dejar los cables de consola de R1 y SW1 conectados al servidor | No se dejaron: el servidor solo tiene dos USB traseros y el 2960 solo trae consola RJ45 | R1 y SW1 se administran solo por SSH. Antes de cada cambio riesgoso se programa `reload in 10`, para que el equipo vuelva solo a la configuración guardada si se pierde el acceso |
| Activar el encendido automático del servidor tras un corte de corriente | No se activó | Los servidores del laboratorio no se apagan y están en UPS |

## 13. Pendiente

| Qué | Tarea |
|---|---|
| Verificar en los equipos reales cada control de endurecimiento | IP2-88 |
| Crear las dos máquinas virtuales de Windows Server | IP2-73, IP2-79 |
| Abrir la aplicación desde PC-CLIENTE (V2), que ya se puede probar | IP2-29 |
| Ajustar los tiempos de T01 y T04 para que la dependencia oculte el síntoma | IP2-43 |
| Monitorear Proxmox por su API, no solo por ping | IP2-41 |
| Capturas de los cinco tableros con datos del laboratorio | IP2-48 |
| Crear la cuenta de dueño de n8n (la crea la primera persona que abre la interfaz) | IP2-50 |
| Alertas a una persona por Telegram o correo | IP2-51 |
| Recuperación de interfaces de red por n8n | IP2-76 en adelante |
| Desplegar el robot en su máquina virtual | IP2-56 |
| Cortafuegos en cada máquina virtual | IP2-89 |
| Foto del rack con los equipos del grupo y los cables | Evidencia A-01 |
