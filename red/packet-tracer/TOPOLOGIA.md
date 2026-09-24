# Topología de Packet Tracer (IP2-26)

Ensayo de la red **antes** de tocar el equipo real, para llegar al laboratorio con las configuraciones ya probadas (mitiga el riesgo R-03, horario limitado). El archivo se guarda como `integrador2-red.pkt` en esta carpeta.

## 1. Equipos

| Nombre en PT | Modelo en Packet Tracer | Equivale en el laboratorio | Por qué |
|---|---|---|---|
| `R1` | **ISR4321** | Cisco **ISR 4221** | Packet Tracer no tiene el 4221, pero el 4321 usa los mismos nombres de interfaz (`Gi0/0/0`, `Gi0/0/1`), así que `router/R1-4221.txt` se pega sin cambiar una línea |
| `SW1` | **2960-24TT** | Catalyst **WS-C2960-24TT-L** | Mismo modelo |
| `ISP` | 2911 | No existe: es la red de la universidad | Simula Internet y entrega la WAN. Ver `ISP-simulado-2911.txt` |
| `PC-ADMIN` | PC-PT | PC de administración | VLAN 10 |
| `PC-CLIENTE` | PC-PT | PC de usuario | VLAN 20, IP por DHCP |
| `SRV-APP` | Server-PT | `vm-app` (10.10.30.11) | Instancia Linux de MS Motos |
| `SRV-ZABBIX` | Server-PT | `vm-zabbix` (10.10.30.12) | Monitoreo; también es el origen SNMP permitido |
| `SRV-APP-WIN` | Server-PT | `vm-app-win` (10.10.30.16) | Instancia Windows de MS Motos (RF-19) |
| `SRV-DC` | Server-PT | `vm-dc` (10.10.30.17) | Controlador de dominio. PT no simula Active Directory: solo sirve para probar que **los usuarios no lo alcanzan** |

En el laboratorio real los cuatro servidores son VMs dentro de un solo servidor físico, conectado por un trunk. En Packet Tracer cada uno va en su propio puerto de acceso de la VLAN 30, porque PT no simula un hipervisor.

## 2. Conexiones

| Origen | Puerto | Destino | Puerto | Cable |
|---|---|---|---|---|
| `ISP` | Gi0/0 | `R1` | **Gi0/0/0** | cross |
| `R1` | **Gi0/0/1** | `SW1` | Gi0/1 | straight |
| `PC-ADMIN` | Fa0 | `SW1` | Fa0/1 | straight |
| `PC-CLIENTE` | Fa0 | `SW1` | Fa0/5 | straight |
| `SRV-APP` | Fa0 | `SW1` | Fa0/13 | straight |
| `SRV-ZABBIX` | Fa0 | `SW1` | Fa0/14 | straight |
| `SRV-APP-WIN` | Fa0 | `SW1` | Fa0/15 | straight |
| `SRV-DC` | Fa0 | `SW1` | Fa0/16 | straight |

Los puertos siguen el reparto de [../README.md](../README.md) §2: Fa0/1–4 administración, Fa0/5–12 usuarios, Fa0/13–20 servidores.

## 3. Direcciones para configurar a mano en PT

| Equipo | IP | Máscara | Gateway | DNS |
|---|---|---|---|---|
| `PC-ADMIN` | 10.10.10.10 | 255.255.255.0 | 10.10.10.1 | 8.8.8.8 |
| `PC-CLIENTE` | DHCP | — | — | — |
| `SRV-APP` | 10.10.30.11 | 255.255.255.0 | 10.10.30.1 | 8.8.8.8 |
| `SRV-ZABBIX` | 10.10.30.12 | 255.255.255.0 | 10.10.30.1 | 8.8.8.8 |
| `SRV-APP-WIN` | 10.10.30.16 | 255.255.255.0 | 10.10.30.1 | 10.10.30.17 |
| `SRV-DC` | 10.10.30.17 | 255.255.255.0 | 10.10.30.1 | 127.0.0.1 |

En `SRV-APP` y `SRV-APP-WIN` hay que dejar **activo el servicio HTTP** (pestaña *Services → HTTP*), que es lo que responde en las pruebas V2 y V10.

## 4. Orden para armarla

1. Colocar los equipos y conectarlos según la tabla de arriba.
2. Pegar la configuración de `../router/R1-4221.txt` en `R1`, **descomentando las dos líneas marcadas "Packet Tracer"**: la IP fija de la WAN (172.16.0.2/30) y la ruta por defecto hacia el ISP. En PT no hay DHCP en la WAN.
3. Pegar `ISP-simulado-2911.txt` en el `ISP`.
4. Pegar `../switch/SW1-2960.txt` en `SW1`.
5. Configurar las IP de las PC y los servidores.
6. Correr las validaciones V1 a V11 de [../README.md](../README.md) §6 y anotar el resultado.
7. Guardar como `integrador2-red.pkt` en esta carpeta y hacer commit.

## 5. Diferencias conocidas de Packet Tracer

Las que ya encontramos al cargar las configuraciones están en [../README.md](../README.md) §6. Las principales:

- Los comandos globales no se aceptan dentro del submodo de una ACL ni del pool de DHCP: por eso tanto cada ACL como `ip dhcp pool` terminan con `exit` en `../router/R1-4221.txt`.
- **Hay que esperar a que el router termine de arrancar antes de pegar la configuración.** Si se pega mientras arranca, las líneas `interface ...` se pierden y las direcciones IP caen sobre la interfaz equivocada (nos pasó: la WAN quedó con 10.10.99.1). Se reconoce porque `Gi0/0/0` aparece con una IP de VLAN en lugar de 172.16.0.2.
- `snmp-server location` y `contact` no existen en PT, y el 2960 no acepta la ACL en la comunidad SNMP.
- Las consultas SNMP reales no se simulan: el monitoreo se prueba en el laboratorio, no aquí.
- PT no simula Active Directory ni servicios de Windows: `SRV-DC` y `SRV-APP-WIN` solo responden ping y HTTP.

## 6. Armarla con asistencia

Si se abre Packet Tracer con el puente del asistente activo (*Extensions → Builder Code Editor*), la topología se puede crear de una sola vez en lugar de arrastrar equipos. El puente es solo para armarla más rápido: **el resultado y las validaciones son los mismos**.

Dos cosas que conviene saber si se vuelve a usar:

- El enlace **entre los dos routers** (ISP ↔ R1) es el único que el puente no logra crear con el cable *cross*; hay que crearlo a mano en Packet Tracer o con el comando directo `addLink`. Los demás cables sí los crea sin problema.
- El puente **responde con un retraso de una llamada**: la respuesta que devuelve suele ser la de la operación anterior. Por eso el estado se comprueba consultando la topología dos veces seguidas, no leyendo lo que contestó.
