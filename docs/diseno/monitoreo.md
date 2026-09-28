# Diseño de monitoreo, umbrales y dashboards

Tareas: IP2-40 (métricas, umbrales, triggers), IP2-46 (los cinco dashboards), IP2-75 (instancia Windows) e IP2-82 (eventos del controlador de dominio). Borrador para el E2 (05 oct 2026).

## 1. Qué se monitorea y cómo

| Capa | Host en Zabbix | Método | Plantilla | Intervalo clave |
|---|---|---|---|---|
| Servidor físico | `proxmox` | HTTP (API de Proxmox, token de solo lectura) | Proxmox VE by HTTP | 60 s |
| VMs Linux | `vm-app`, `vm-zabbix`, `vm-grafana`, `vm-n8n`, `vm-rpa` | Zabbix agent 2 (activo) | Linux by Zabbix agent active | 60 s |
| VMs Windows | `vm-app-win`, `vm-dc` | Agente de Zabbix para Windows | Windows by Zabbix agent | 60 s |
| Contenedores | `vm-app` | Plugin Docker del agent 2 | Docker by Zabbix agent 2 | 30 s |
| Servicios (Linux) | `vm-app` | Agent 2 (systemd) + stub_status de Nginx | Nginx by Zabbix agent + ítems de systemd | 30 s |
| Servicio (Windows) | `vm-app-win` | Estado del servicio `MSMotos` | Ítem de servicio de Windows | 30 s |
| Seguridad del dominio | `vm-dc` | Registro de seguridad de Windows (eventos 4625 y 4740) | Ítems de log | 60 s |
| Aplicación | `msmotos-web` (Linux) y `msmotos-web-win` (Windows) | Escenarios web (HTTP) contra cada instancia | Propia: `Template App MS Motos` | 60 s |
| Experiencia del cliente | `msmotos-rpa-linux`, `msmotos-rpa-windows` | Ítems *trapper* alimentados por el RPA, uno por recorrido (consulta y agendar) | Propia: `Template RPA MS Motos` | Cada ejecución (consulta cada 5 min, agendar cada 30 min) |
| Router | `r1` | SNMP | Cisco IOS by SNMP | 60 s (interfaces 30 s) |
| Switch | `sw1` | SNMP | Cisco IOS by SNMP | 60 s (interfaces 30 s) |
| Conectividad | `r1`, `sw1`, `proxmox` | ICMP ping desde Zabbix | ICMP Ping | 30 s |

**Sobre los intervalos:** 30 s en los ítems de los que depende la demo (contenedor, servicio, interfaces) para que la detección tarde menos de 2 minutos (RNF-01). El resto a 60 s para no llenar la base de historial.

## 2. Umbrales y triggers

Columna **Tag `remediation`**: la etiqueta que Zabbix envía a n8n para decidir la acción.

| # | Trigger | Condición | Severidad | Tag `remediation` | Acción |
|---|---|---|---|---|---|
| T01 | Contenedor `msmotos-app` detenido | Estado ≠ running durante 1 min | High | `restart-container` | **Recuperación automática** |
| T02 | Contenedor `msmotos-app` unhealthy | Health = unhealthy durante 2 min | High | `none` | Alerta (reiniciar a ciegas puede ocultar un error de la app) |
| T03 | Servicio Nginx detenido (Linux) | Estado del servicio ≠ active durante 1 min | High | `restart-service` | **Recuperación automática** |
| T03-W | Servicio `MSMotos` detenido (Windows) | Estado del servicio ≠ running durante 1 min | High | `restart-service-win` | **Recuperación automática** |
| T04 | App no disponible | `/api/health` ≠ 200 en 2 lecturas seguidas | Disaster | `none` | Alerta (la causa puede ser red, Nginx o contenedor: lo recuperan T01/T03) |
| T05 | App lenta | Tiempo de respuesta del login > 2 s promedio de 5 min | Warning | `none` | Alerta |
| T06 | CPU alta | > 85 % promedio de 5 min (Warning) · > 95 % (High) | Warning / High | `none` | **Solo alerta** (PDF §5.4) |
| T07 | Memoria alta | Disponible < 15 % durante 5 min (Warning) · < 5 % (High) | Warning / High | `none` | **Solo alerta** |
| T08 | Disco lleno | Uso > 80 % (Warning) · > 90 % (High) | Warning / High | `none` | **Solo alerta** |
| T09 | Interfaz de acceso caída o con errores | Estado operativo = down durante 2 min, o errores y descartes sobre el umbral | High | `restart-interface` | **Recuperación automática** (RF-23) |
| T09-G | Enlace de gestión caído (trunk R1↔SW1, servidor, WAN) | Estado operativo = down durante 1 min | Disaster | `none` | **Solo alerta:** reiniciarlo dejaría a n8n sin camino |
| T09b | Puerto en *err-disabled* | Estado del puerto = err-disabled | Warning | `enable-port` | **Recuperación automática** (RF-23) |
| T10 | Enlace saturado | Uso > 70 % durante 5 min (Warning) · > 90 % (High) | Warning / High | `none` | Alerta |
| T11 | Equipo de red saturado | CPU o memoria del router/switch > 90 % durante 10 min | High | `reload-device` | **Recuperación automática** con respaldo previo (RF-23) |
| T11b | Equipo sin respuesta | ICMP sin respuesta durante 2 min | Disaster | `none` | Alerta: sin red no hay acción posible |
| T12 | RPA falló | Resultado = fallo en la última ejecución de cualquiera de los dos recorridos | High | `none` | Alerta con el paso donde falló |
| T13 | RPA lento | Consulta > 10 s o agendar > 20 s (umbrales de RF-16 y RF-17) | Warning | `none` | Alerta |
| T14 | RPA sin datos | Sin resultados de consulta en 15 min o de agendar en 75 min | Warning | `none` | Alerta (el propio RPA dejó de correr) |
| T15 | Controlador de dominio caído | Servicio AD DS o DNS detenido, o la VM sin responder 2 min | Disaster | `none` | Alerta: se entra con las cuentas locales de emergencia (riesgo R-14) |
| T16 | Inicios de sesión fallidos | Más de 10 eventos 4625 en 5 min | Warning | `none` | Alerta (RNF-09) |
| T17 | Cuenta bloqueada | Evento 4740 | Warning | `none` | Alerta con el nombre de la cuenta |

### Qué se recupera solo y qué no

| Criterio | Se recupera solo: T01, T03, T03-W, T09, T09b, T11 | Solo alerta: capacidad (T06–T08), enlaces de gestión (T09-G), app (T04–T05), RPA (T12–T14), dominio (T15–T17) |
|---|---|---|
| Causa conocida y acción segura | ✅ Levantar lo que se cayó o reiniciar una interfaz no destruye nada | ❌ Hay que investigar la causa antes de actuar |
| Resultado verificable | ✅ Zabbix confirma que volvió a estar arriba | ❌ Asignar recursos o tocar cuentas esconde el problema |
| Lo exige el PDF y el profesor | ✅ §5.4 y la observación del 21 set 2026 sobre la red | ❌ §5.4 prohíbe ampliar recursos automáticamente |
| La acción es alcanzable | ✅ El equipo responde por la red | ❌ Si el equipo o el dominio no responden, no hay acción posible |

Los límites de cada acción automática (intentos, orden, exclusiones) están en [automatizacion.md §5](automatizacion.md).

## 3. Dashboards de Grafana

Cada panel responde una pregunta concreta y usa colores de umbral (verde, amarillo, rojo), no solo gráficas (PDF §8.3).

**Ya construidos y probados** (IP2-48). El JSON vive en [monitoreo/grafana/](../../monitoreo/grafana/) y Grafana los carga por provisioning en la carpeta *Integrador II*:

| Tablero | Archivo / uid | Estado en el laboratorio (17 sep 2026) |
|---|---|---|
| General (ejecutivo) | `ip2-general.json` | 6 paneles, todos con datos |
| Técnico (infraestructura) | `ip2-tecnico.json` | 11 paneles, todos con datos |
| Red | `ip2-red.json` | 2 paneles con datos; 5 esperan los hosts SNMP `r1` y `sw1` (IP2-44) |
| Experiencia del cliente | `ip2-experiencia.json` | 4 paneles con datos; 4 esperan los hosts `msmotos-rpa-linux` y `msmotos-rpa-windows` (IP2-56) |
| **Automatización** | `ip2-automatizacion.json` | 7 paneles, construido el 23 sep 2026 (IP2-77); **falta cargarlo en Grafana** para verlo con datos. Es el quinto dashboard que pidió el profesor |

**Por qué cinco y no cuatro:** el profesor pidió el 21 set 2026 un tablero del estado de los procesos automáticos. Como también aclaró que **CI/CD no forma parte del proyecto**, ese tablero muestra las automatizaciones que sí existen: los flujos de n8n y las ejecuciones del RPA. Si alguno de los cinco queda cargado, se divide (por ejemplo el técnico, en *Servidor y VMs* y *Contenedores y servicios*).

Los paneles que todavía no tienen datos ya traen escritas las consultas con los nombres definitivos (`r1`, `sw1`, `proxmox`, `msmotos-rpa-linux`, `msmotos-rpa-windows`), así que se llenan solos cuando esos hosts existan.

### 3.1 General / ejecutivo — "¿El servicio está bien?"

| Panel | Tipo | Pregunta |
|---|---|---|
| Disponibilidad de la app (24 h / 7 días) | Stat % | ¿Cuánto tiempo estuvo disponible? |
| Estado por componente | Mapa de estados (verde/rojo) | ¿Qué parte está fallando? Red · Servidor · VMs · Contenedor · Nginx · App |
| Problemas activos por severidad | Tabla | ¿Qué hay abierto ahora y desde cuándo? |
| Recuperaciones automáticas del día | Stat | ¿Cuántas veces actuó n8n? |
| Tiempo de respuesta de la app | Gráfica con umbral 2 s | ¿Los usuarios la sienten lenta? |

### 3.2 Técnico — "¿Dónde está el cuello de botella?"

| Panel | Tipo |
|---|---|
| CPU, RAM y disco del servidor físico | Medidores con umbrales T06–T08 |
| CPU y RAM por VM | Gráficas por host |
| Estado, CPU y memoria de contenedores | Tabla + gráficas |
| Estado de Nginx y conexiones activas | Stat + gráfica |

### 3.3 Red — "¿La red está sana?"

| Panel | Tipo |
|---|---|
| Estado de interfaces de R1 y SW1 | Tabla con color por estado |
| Tráfico de entrada/salida por interfaz | Gráficas con umbral 70 % / 90 % |
| Errores y descartes por interfaz | Gráficas |
| Latencia y pérdida hacia R1, SW1 y Proxmox | Gráficas |

### 3.4 Experiencia del cliente — "¿Qué vive el cliente?"

| Panel | Tipo |
|---|---|
| Resultado de la última ejecución, por recorrido e instancia | Stat (OK / FALLO), 4 series |
| Duración total del recorrido de consulta | Gráfica con umbral 10 s |
| Duración total del recorrido de agendamiento | Gráfica con umbral 20 s |
| Duración por paso | Barras apiladas |
| Tasa de éxito (24 h) | Stat % |
| Último paso fallido y su error | Texto |

Las series se separan por host (`msmotos-rpa-linux` y `msmotos-rpa-windows`) para comparar los dos ambientes. Ver [rpa.md](rpa.md).

### 3.5 Automatización — "¿Los procesos automáticos están funcionando?" (IP2-77)

| Panel | Tipo | Pregunta |
|---|---|---|
| Última ejecución de cada flujo de n8n | Tabla con estado y hora | ¿Corrió lo que tenía que correr? |
| Recuperaciones automáticas en 24 h, por tipo | Barras (contenedor · servicio · interfaz · puerto · equipo) | ¿Cuánto está trabajando la automatización? |
| Tiempo entre detección y recuperación | Gráfica con umbral 5 min (RNF-02) | ¿Se cumple el compromiso de recuperación? |
| Acciones rechazadas o agotadas por límite | Stat con color | ¿Hay algo que la automatización no logró arreglar? |
| Ejecuciones del RPA (éxito / fallo) | Barras por hora | ¿El monitoreo sintético está corriendo? |
| Escalamientos a una persona | Tabla | ¿Qué quedó pendiente de atención humana? |

**De dónde salen los datos:** n8n envía a Zabbix, con `zabbix_sender`, un ítem por ejecución (flujo, resultado, duración y acción aplicada), igual que hace el RPA. Así el tablero se alimenta de la misma fuente que el resto y no necesita un origen de datos aparte.

## 4. Contenido mínimo de una alerta (RNF-05)

```
🔴 [HIGH] Contenedor msmotos-app detenido
Host: vm-app (10.10.30.11)
Desde: 2026-11-03 10:42:15 (hace 1 min)
Acción automática: reinicio del contenedor (intento 1 de 3)
Qué revisar si no se recupera: docker compose logs app
Evento Zabbix: #12345
```

Para los eventos de red el mensaje incluye además el equipo y la interfaz:

```
🔴 [HIGH] Interfaz Fa0/7 caída en SW1
Host: sw1 (10.10.99.2) · VLAN 20 (Usuarios)
Desde: 2026-11-03 14:02:10 (hace 2 min)
Acción automática: reinicio de la interfaz (intento 1 de 3)
Resultado: interfaz arriba a los 12 s
Evento Zabbix: #12389
```
