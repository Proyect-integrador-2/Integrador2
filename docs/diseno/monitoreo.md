# Diseño de monitoreo, umbrales y dashboards

Tareas: IP2-40 (métricas, umbrales, triggers), IP2-46 (dashboards). Borrador para el E2 (05 oct 2026).

## 1. Qué se monitorea y cómo

| Capa | Host en Zabbix | Método | Plantilla | Intervalo clave |
|---|---|---|---|---|
| Servidor físico | `proxmox` | HTTP (API de Proxmox, token de solo lectura) | Proxmox VE by HTTP | 60 s |
| VMs | `vm-app`, `vm-zabbix`, `vm-grafana`, `vm-n8n`, `vm-rpa` | Zabbix agent 2 (activo) | Linux by Zabbix agent active | 60 s |
| Contenedores | `vm-app` | Plugin Docker del agent 2 | Docker by Zabbix agent 2 | 30 s |
| Servicios | `vm-app` | Agent 2 (systemd) + stub_status de Nginx | Nginx by Zabbix agent + ítems de systemd | 30 s |
| Aplicación | `msmotos-web` | Escenarios web (HTTP) | Propia: `Template App MS Motos` | 60 s |
| Experiencia de usuario | `msmotos-rpa` | Ítems *trapper* alimentados por el RPA | Propia: `Template RPA MS Motos` | Cada ejecución (5 min) |
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
| T03 | Servicio Nginx detenido | Estado del servicio ≠ active durante 1 min | High | `restart-service` | **Recuperación automática** |
| T04 | App no disponible | `/api/health` ≠ 200 en 2 lecturas seguidas | Disaster | `none` | Alerta (la causa puede ser red, Nginx o contenedor: lo recuperan T01/T03) |
| T05 | App lenta | Tiempo de respuesta del login > 2 s promedio de 5 min | Warning | `none` | Alerta |
| T06 | CPU alta | > 85 % promedio de 5 min (Warning) · > 95 % (High) | Warning / High | `none` | **Solo alerta** (PDF §5.4) |
| T07 | Memoria alta | Disponible < 15 % durante 5 min (Warning) · < 5 % (High) | Warning / High | `none` | **Solo alerta** |
| T08 | Disco lleno | Uso > 80 % (Warning) · > 90 % (High) | Warning / High | `none` | **Solo alerta** |
| T09 | Interfaz caída | Estado operativo = down (interfaces con enlace esperado) | High | `none` | Alerta |
| T10 | Enlace saturado | Uso > 70 % durante 5 min (Warning) · > 90 % (High) | Warning / High | `none` | Alerta |
| T11 | Equipo sin respuesta | ICMP sin respuesta durante 2 min | Disaster | `none` | Alerta |
| T12 | RPA falló | Resultado = fallo en la última ejecución | High | `none` | Alerta con el paso donde falló |
| T13 | RPA lento | Duración total > 15 s | Warning | `none` | Alerta |
| T14 | RPA sin datos | Sin resultados en 15 min | Warning | `none` | Alerta (el propio RPA dejó de correr) |

### Por qué solo dos fallas se recuperan solas

| Criterio | T01 contenedor / T03 servicio | CPU, RAM, disco, red |
|---|---|---|
| Causa conocida y acción segura | ✅ Levantar lo detenido no destruye nada | ❌ Hay que investigar la causa |
| Resultado verificable | ✅ Zabbix confirma que volvió a estar arriba | ❌ Asignar recursos esconde el problema |
| Lo exige el PDF | ✅ §5.4 | ❌ §5.4 prohíbe ampliar recursos automáticamente |

## 3. Dashboards de Grafana

Cada panel responde una pregunta concreta y usa colores de umbral (verde, amarillo, rojo), no solo gráficas (PDF §8.3).

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

### 3.4 Experiencia / aplicación — "¿Qué vive el usuario?"

| Panel | Tipo |
|---|---|
| Resultado de la última ejecución del RPA | Stat (OK / FALLO) |
| Duración total del RPA | Gráfica con umbral 15 s |
| Duración por paso (login, consulta, registro, logout) | Barras apiladas |
| Tasa de éxito (24 h) | Stat % |
| Último paso fallido | Texto |

## 4. Contenido mínimo de una alerta (RNF-05)

```
🔴 [HIGH] Contenedor msmotos-app detenido
Host: vm-app (10.10.30.11)
Desde: 2026-11-03 10:42:15 (hace 1 min)
Acción automática: reinicio del contenedor (intento 1 de 3)
Qué revisar si no se recupera: docker compose logs app
Evento Zabbix: #12345
```
