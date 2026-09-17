# Diseño de virtualización

Tareas: IP2-30 (comparar hipervisores), IP2-31 (dimensionar VMs). Borrador para el E2 (05 oct 2026).

## 1. Comparación de hipervisores

| Criterio | **Proxmox VE** | Hyper-V | VMware ESXi | XCP-ng |
|---|---|---|---|---|
| Costo / licencia | Gratuito (AGPL); suscripción opcional solo para soporte | Requiere licencia de Windows Server (la edición gratuita "Hyper-V Server" se descontinuó en 2019) | Licenciamiento cambiante desde la compra por Broadcom; la opción gratuita es limitada e incierta | Gratuito (GPL) |
| Instalación en servidor sin sistema previo | ✅ ISO propia (Debian) | ⚠️ Instalar Windows Server primero | ✅ ISO propia | ✅ ISO propia |
| Administración | Web integrada (puerto 8006) | Hyper-V Manager / Windows Admin Center | vSphere Client web | Requiere Xen Orchestra aparte |
| VLAN hacia las VMs | ✅ Bridge "VLAN aware" nativo | ✅ vSwitch con VLAN ID | ✅ Port groups | ✅ |
| Respaldos incluidos | ✅ `vzdump` programable desde la web | ⚠️ Windows Server Backup / terceros | ❌ Requiere herramienta externa | ✅ Con Xen Orchestra |
| Contenedores ligeros (LXC) | ✅ | ❌ | ❌ | ❌ |
| API REST | ✅ | ⚠️ PowerShell / WMI | ✅ (según licencia) | ✅ |
| Monitoreo con Zabbix | ✅ Plantilla oficial "Proxmox VE by HTTP" | ✅ Plantillas de Windows | ✅ Plantillas VMware | ⚠️ Plantillas de la comunidad |
| Curva de aprendizaje del equipo | Media (basado en Linux) | Media | Media | Media-alta |

### Decisión: **Proxmox VE**

1. **Costo cero sin limitaciones funcionales**, coherente con el requisito del PDF de preferir tecnologías gratuitas o de código abierto.
2. **Se instala directo en el servidor de la universidad** y se administra por navegador, sin depender de otro sistema operativo.
3. **Bridge con VLAN nativo**: un solo cable en trunk desde el switch lleva las VLAN a las VMs.
4. **Respaldos programables incluidos**, que mitigan los riesgos R-02 (servidor formateado) y R-09 (único servidor).
5. **Plantilla oficial de Zabbix**: el monitoreo del servidor físico no requiere desarrollo propio.

**Condición:** requiere permiso para formatear el servidor (pregunta pendiente en IP2-13). Si no se autoriza, la alternativa es el hipervisor que la universidad ya tenga instalado.

## 2. Distribución y dimensionamiento de VMs

Sistema operativo de todas las VMs: **Ubuntu Server 24.04 LTS** (mínimo, sin entorno gráfico).

| VM | IP (VLAN 30) | Servicios | vCPU | RAM | Disco | Justificación |
|---|---|---|---|---|---|---|
| `vm-app` | 10.10.30.11 | Nginx (systemd), Docker: MS Motos + MySQL 8.4, Zabbix agent 2 | 2 | 4 GB | 40 GB | Node con 2 procesos (~300 MB) + MySQL (~1 GB) + margen para pruebas de carga |
| `vm-zabbix` | 10.10.30.12 | Zabbix server + frontend + PostgreSQL | 2 | 4 GB | 60 GB | La base de historial crece con los intervalos cortos (30–60 s) |
| `vm-grafana` | 10.10.30.13 | Grafana + plugin Zabbix | 1 | 2 GB | 20 GB | Carga liviana: solo consulta a Zabbix |
| `vm-n8n` | 10.10.30.14 | n8n (Docker) | 2 | 2 GB | 20 GB | Flujos cortos y poco frecuentes |
| `vm-rpa` | 10.10.30.15 | Robot Framework + Browser (Chromium sin interfaz) | 2 | 4 GB | 30 GB | El navegador es lo que más memoria consume |
| **Total asignado** | | | **9 vCPU** | **16 GB** | **170 GB** | |
| Reserva para Proxmox | | | — | 2 GB | 20 GB | Sistema del hipervisor |
| **Necesario en el servidor** | | | **≥ 8 núcleos** (con sobreasignación ligera) | **≥ 20 GB** (recomendado 32 GB) | **≥ 250 GB SSD** | |

### Plan si el servidor tiene menos recursos

Se decide cuando esté el inventario (IP2-14):

| RAM del servidor | Ajuste |
|---|---|
| ≥ 32 GB | Distribución completa de la tabla |
| 16–24 GB | Unir Grafana en `vm-zabbix` (4 → 5 GB) y bajar `vm-rpa` a 3 GB |
| < 16 GB | Además, ejecutar n8n como contenedor en `vm-zabbix`. Justificarlo en el informe como decisión por capacidad |

## 3. Redes virtuales

| Elemento | Configuración |
|---|---|
| Interfaz física del servidor | Conectada a SW1 Gi0/2 (trunk VLAN 30, 99; nativa 999) |
| Bridge de Proxmox | `vmbr0`, **VLAN aware** activado |
| IP de gestión de Proxmox | 10.10.30.10/24 (VLAN 30), gateway 10.10.30.1 |
| Tarjeta de red de cada VM | `vmbr0` con **VLAN tag 30** |

## 4. Respaldos

| Qué | Frecuencia | Destino | Retención |
|---|---|---|---|
| `vm-app`, `vm-zabbix` | Diario (madrugada) | Disco externo USB o almacenamiento alterno | 3 copias |
| `vm-grafana`, `vm-n8n`, `vm-rpa` | Semanal | Mismo destino | 2 copias |
| Configuraciones (dashboards, flujos, plantillas) | En cada cambio | GitHub | Historial completo |

Se prueba una restauración antes del E3 (IP2-34).
