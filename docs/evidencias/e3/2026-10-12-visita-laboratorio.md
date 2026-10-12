# Visita al laboratorio del 12 de octubre de 2026

Tareas: IP2-27 y IP2-28 (switch y router), IP2-32 (hipervisor), IP2-93 (administración remota), IP2-14 e IP2-31 (inventario y dimensionamiento).

Resultado: el router, el switch y el servidor quedaron configurados, y la plataforma se administra a distancia desde ese día. Faltan las pruebas desde las computadoras de usuario y las máquinas virtuales.

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

## 4. Incidencias

| Qué pasó | Cómo se resolvió |
|---|---|
| En la primera corrida del script el servidor quedó sin ruta por defecto y no pudo descargar Tailscale. Al recargar la red, Proxmox quitó el gateway que había dejado la instalación y se llevó la ruta recién recibida por DHCP | Se renovó el DHCP en `nic2` y se repitió el script. El script ya lo hace solo (commit `096ff8a`) |
| R1 y SW1 rechazaban SSH desde el servidor: sus listas solo permitían la VLAN 40 | Se agregó `permit host 10.10.30.10` a `ACL-SSH-ADMIN` de R1 y a la lista 40 de SW1. Ya está en las configuraciones del repositorio |

## 5. Diferencias con lo planeado

| Planeado | Lo que se hizo | Consecuencia |
|---|---|---|
| Dejar los cables de consola de R1 y SW1 conectados al servidor | No se dejaron: el servidor solo tiene dos USB traseros y el 2960 solo trae consola RJ45 | R1 y SW1 se administran solo por SSH. Antes de cada cambio riesgoso se programa `reload in 10`, para que el equipo vuelva solo a la configuración guardada si se pierde el acceso |
| Activar el encendido automático del servidor tras un corte de corriente | No se activó | Los servidores del laboratorio no se apagan y están en UPS |

## 6. Pendiente

| Qué | Tarea |
|---|---|
| Pruebas V1 a V8 desde PC-ADMIN y PC-CLIENTE (DHCP, segmentación entre VLAN, salida a Internet) | IP2-29 |
| Verificar en los equipos reales cada control de endurecimiento | IP2-88 |
| Crear las siete máquinas virtuales | IP2-33, IP2-73, IP2-79 |
| Foto del rack con los equipos del grupo y los cables | Evidencia A-01 |
