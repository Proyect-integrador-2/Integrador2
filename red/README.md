# Diseño de red — Integrador II

Tareas: IP2-24 (topología, VLAN y direccionamiento), IP2-25 (ACL, NAT/PAT, SNMP), IP2-26 (ensayo en Packet Tracer), IP2-27/28 (configuración), IP2-29 (validación).

> **Equipo real.** El router del laboratorio es un **Cisco ISR 4221** (IOS XE), confirmado con fotos el 21 set 2026 (IP2-14): dos puertos Gigabit (Gi0/0/0, que también acepta SFP, y Gi0/0/1), consola RJ45 y USB, y un módulo NIM-2T de dos seriales que no se usa. La configuración se escribió primero para un 2911; al pasar al 4221 solo cambiaron los nombres de interfaz (Gi0/0 → **Gi0/0/0** WAN, Gi0/1 → **Gi0/0/1** trunk), no la lógica. El switch (**2960-24TT**) sigue pendiente de confirmar.

## 1. VLAN y direccionamiento

| VLAN | Nombre | Red | Gateway (R1) | Uso |
|---|---|---|---|---|
| 10 | ADMINISTRACION | 10.10.10.0/24 | 10.10.10.1 | PC-ADMIN (IP fija) |
| 20 | USUARIOS | 10.10.20.0/24 | 10.10.20.1 | PC-CLIENTE (DHCP .100–.200) |
| 30 | SERVIDORES | 10.10.30.0/24 | 10.10.30.1 | Hipervisor y VMs (IP fija) |
| 99 | GESTION | 10.10.99.0/24 | 10.10.99.1 | IP de gestión del switch |
| 999 | NATIVA-SIN-USO | — | — | VLAN nativa de los trunks y puertos sin uso |
| WAN | — | DHCP de la universidad (PT: 172.16.0.0/30) | — | Salida a Internet por NAT/PAT |

**Por qué VLAN 99 y 999:** la gestión del switch no comparte red con usuarios, y la VLAN nativa no es la 1. Así se evita el salto de VLAN (VLAN hopping) por etiquetado doble.

### Direcciones fijas

| Equipo | VLAN | IP | Observación |
|---|---|---|---|
| R1 (subinterfaces) | 10/20/30/99 | .1 de cada red | Gateway de cada VLAN |
| SW1 (SVI VLAN 99) | 99 | 10.10.99.2 | Gestión SSH y SNMP |
| PC-ADMIN | 10 | 10.10.10.10 | |
| Hipervisor (Proxmox) | 30 | 10.10.30.10 | Panel web :8006 |
| VM App (Nginx + Docker) | 30 | 10.10.30.11 | Único servidor visible para usuarios (80/443) |
| VM Monitoreo (Zabbix) | 30 | 10.10.30.12 | Recolector SNMP autorizado |
| VM Visualización (Grafana) | 30 | 10.10.30.13 | |
| VM Automatización (n8n) | 30 | 10.10.30.14 | |
| VM RPA | 30 | 10.10.30.15 | |

## 2. Puertos del switch (SW1)

| Puerto | Modo | VLAN | Conecta a |
|---|---|---|---|
| Gi0/1 | Trunk | 10, 20, 30, 99 (nativa 999) | R1 Gi0/0/1 |
| Gi0/2 | Trunk | 30, 99 (nativa 999) | Servidor Proxmox (bridge con VLAN) |
| Fa0/1 – Fa0/4 | Acceso | 10 | PCs de administración |
| Fa0/5 – Fa0/12 | Acceso | 20 | PCs de usuarios |
| Fa0/13 – Fa0/20 | Acceso | 30 | Servidores (solo en Packet Tracer: cada VM es un Server-PT) |
| Fa0/21 – Fa0/24 | Apagados | 999 | Sin uso |

Puertos de acceso: `spanning-tree portfast` + `bpduguard`. Puertos de usuarios: `port-security` (máx. 2 MAC, modo restrict).

## 3. Política de acceso entre VLAN

Implementada con la ACL extendida `ACL-USUARIOS-IN` en la subinterfaz de la VLAN 20 (entrada).

| Origen → Destino | Administración (10) | Usuarios (20) | Servidores (30) | Gestión (99) | Internet |
|---|---|---|---|---|---|
| **Administración (10)** | ✅ | ✅ | ✅ todo | ✅ | ✅ |
| **Usuarios (20)** | ❌ | ✅ | ⚠️ **solo App 10.10.30.11 TCP 80/443** | ❌ | ✅ |
| **Servidores (30)** | ✅ | ✅ respuestas | ✅ | ✅ (SNMP desde Zabbix) | ✅ |

Controles adicionales en los equipos:

| Control | Dónde | Detalle |
|---|---|---|
| SSH solo desde Administración | R1 y SW1 (`access-class` en VTY) | Telnet deshabilitado |
| SNMP solo desde Zabbix | R1 y SW1 | Comunidad de solo lectura restringida a 10.10.30.12 |
| NAT/PAT | R1 Gi0/0/0 | Todas las VLAN internas salen con la IP de la WAN |
| DHCP | R1 | Solo VLAN 20 (usuarios) |

## 4. Archivos

| Archivo | Contenido |
|---|---|
| [`router/R1-4221.txt`](router/R1-4221.txt) | Configuración completa del router (ISR 4221) |
| [`switch/SW1-2960.txt`](switch/SW1-2960.txt) | Configuración completa del switch |
| [`packet-tracer/ISP-simulado-2911.txt`](packet-tracer/ISP-simulado-2911.txt) | Router que simula la red de la universidad en Packet Tracer |
| `packet-tracer/integrador2-red.pkt` | Topología de ensayo (se guarda desde Packet Tracer) |

**Antes de aplicar en equipo real:** reemplazar todo lo marcado `CAMBIAR-` por contraseñas propias. Esas contraseñas **no se suben a Git**: se guardan fuera del repositorio.

## 5. Diferencias entre Packet Tracer y el laboratorio real

| Tema | Packet Tracer | Laboratorio |
|---|---|---|
| WAN | Router "ISP" con 172.16.0.0/30 y un loopback que simula Internet | `ip address dhcp` hacia la red de la universidad |
| Servidor | Un Server-PT por VM en puertos de acceso VLAN 30 | Un solo servidor físico en trunk (Gi0/2) con Proxmox |
| SNMP | Comunidad v2c | Preferir SNMPv3 si la imagen IOS lo soporta (`show version` con `k9`) |
| Router | 2911 (el ensayo del 17 set) o **ISR4321**, que en Packet Tracer usa los mismos nombres de interfaz que el 4221 | ISR 4221 con IOS XE: arranca en varios minutos, tenerlo en cuenta al hacer `reload` |

## 6. Validación (IP2-29 / prueba PR-10)

Ensayo en **Packet Tracer 9.0** (17 sep 2026), con las configuraciones de esta carpeta cargadas línea por línea. Topología: ISP simulado, R1 (2911, IOS 15.1(4)M4), SW1 (2960-24TT), PC-ADMIN, PC-CLIENTE, SRV-APP (10.10.30.11) y SRV-ZABBIX (10.10.30.12).

| # | Prueba | Esperado | Resultado en Packet Tracer |
|---|---|---|---|
| V1 | PC-CLIENTE recibe IP por DHCP | 10.10.20.100 o superior | ✅ 10.10.20.100, gateway .1, DNS 8.8.8.8 |
| V2 | PC-CLIENTE → `http://10.10.30.11` | ✅ Responde | ⏳ Pendiente: se prueba con el navegador del PC (la consola de PT no tiene cliente HTTP). La regla existe en la ACL |
| V3 | PC-CLIENTE → ping 10.10.30.12 (Zabbix) | ❌ Bloqueado | ✅ "Destination host unreachable" desde 10.10.20.1 |
| V4 | PC-CLIENTE → ping 10.10.10.10 (Admin) | ❌ Bloqueado | ✅ Bloqueado |
| V5 | PC-CLIENTE → 10.10.99.2 (gestión del switch) | ❌ Bloqueado | ✅ Bloqueado |
| V6 | PC-ADMIN → PC-CLIENTE y servidores | ✅ Responde | ✅ 10.10.20.100 (4/4) y 10.10.30.12 |
| V7 | PC-ADMIN → SSH a SW1 | ✅ Acceso | ✅ Banner y prompt `SW1#` con usuario local |
| V8 | VLAN de usuarios → ping 8.8.8.8 (Internet) | ✅ Responde (NAT/PAT) | ✅ 3/4 (el primero se pierde por ARP) |
| V9 | NAT en R1 | Traducciones activas | ✅ 3 traducciones dinámicas; 4 interfaces inside |

Contadores de `ACL-USUARIOS-IN` tras las pruebas: 4 coincidencias en cada regla ejercitada (DHCP, `echo-reply` hacia Administración, denegación hacia VLAN 10/30/99 y salida a Internet).

### Diferencias de Packet Tracer encontradas al cargar las configuraciones

| Comando | Packet Tracer | IOS real |
|---|---|---|
| Comandos globales dentro del submodo de una ACL nombrada | ❌ Los rechaza | ✅ Los acepta. Se agregó `exit` tras cada ACL (válido en ambos) |
| `snmp-server location` / `contact` | ❌ No existen | ✅ |
| `snmp-server community X RO <acl>` en el 2960 | ❌ Solo acepta `snmp-server community X RO` | ✅ Con ACL (recomendado) |
