# Tableros de Grafana (IP2-48)

Cuatro tableros sobre la fuente de datos **Zabbix** (`uid: zabbix`), uno por pregunta, según el diseño de [docs/diseno/monitoreo.md](../../docs/diseno/monitoreo.md) §3.

| Archivo | Tablero | Pregunta que responde |
|---|---|---|
| `ip2-general.json` | IP2 · General (ejecutivo) | ¿El servicio está bien? |
| `ip2-tecnico.json` | IP2 · Técnico (infraestructura) | ¿Dónde está el cuello de botella? |
| `ip2-red.json` | IP2 · Red | ¿La red está sana? |
| `ip2-experiencia.json` | IP2 · Experiencia del usuario | ¿Qué vive el usuario? |

Los cuatro están etiquetados con `ip2`, así que el enlace *Tableros del Integrador II* de la barra superior salta entre ellos.

## Cómo se cargan

En el laboratorio local se cargan solos: [infra/lab-local/docker-compose.yml](../../infra/lab-local/docker-compose.yml) monta esta carpeta en `/etc/grafana/dashboards-ip2` y [grafana/provisioning/dashboards/ip2.yml](../../infra/lab-local/grafana/provisioning/dashboards/ip2.yml) la provisiona en la carpeta **Integrador II**. Al editar un archivo, Grafana lo recarga en 30 s.

En el servidor real, la VM `vm-grafana` repite el mismo esquema (el repositorio se clona en la VM) o, si se prefiere a mano: **Dashboards → New → Import → Upload JSON file**.

Están marcados con `allowUiUpdates: true`: se pueden retocar desde la interfaz, pero **el cambio no vuelve al repositorio**. Para conservarlo: *Dashboard settings → JSON Model*, copiar y pegar en el archivo correspondiente.

## Requisitos para que los paneles traigan datos

| Necesita | Se crea en |
|---|---|
| Fuente de datos con `uid: zabbix` y usuario de solo lectura | `infra/lab-local/grafana/provisioning/datasources/zabbix.yml` |
| Plugin `alexanderzobnin-zabbix-app` habilitado | provisioning de plugins |
| Grupo de hosts **Integrador II** en Zabbix | `infra/lab-local/configurar-zabbix.py` |
| Hosts `vm-app` y `msmotos-web` | idem |
| Hosts `r1`, `sw1`, `proxmox` (SNMP e ICMP) | IP2-44 — hasta entonces 5 paneles del tablero de Red quedan vacíos |
| Host `msmotos-rpa` con los ítems trapper | IP2-56 / IP2-57 — hasta entonces 4 paneles del tablero de Experiencia quedan vacíos |

## Detalles del plugin de Zabbix que costaron tiempo

1. **Los filtros de host usan el *nombre visible*, no el nombre técnico.** El host técnico `msmotos-web` tiene nombre visible *MS Motos (aplicación)*, así que el filtro es `/^MS Motos/`. Un filtro `msmotos-web` no devuelve nada.
2. **El filtro debe ir en forma de expresión regular** (`/…/`) para que lo resuelva el backend del plugin. Los nombres exactos, sin barras, no traen series.
3. **Los parámetros de las funciones van como texto.** `scale` con `"params": [0.5]` responde *failed to convert value to string*; lo correcto es `"params": ["0.5"]`.
4. **Los ítems se filtran por nombre, no por clave.** Por eso el diseño del RPA ([rpa.md](../../docs/diseno/rpa.md) §3) fija el nombre de cada ítem trapper.
5. **Las consultas de tipo *Problems* y *Text* solo se resuelven en el navegador**: la API `/api/ds/query` responde *non-metrics queries are not supported*. No es un error del tablero.

## Dos trucos que conviene reconocer al leer el JSON

- **Disponibilidad en %**: el panel consulta el código de respuesta HTTP del escenario web (200 cuando está arriba, 0 cuando falla) con la función `scale(0.5)` → la serie vale 100 o 0, y el promedio del rango es el porcentaje de disponibilidad.
- **Semáforo por componente**: el mismo código HTTP con `scale(0.005)` vale 1 o 0, igual que los ítems `Running` de los contenedores y el `agent ping`, de modo que un solo panel los pinta todos con el mapeo *1 = Arriba / 0 = CAÍDO*.

## Verificación (17 sep 2026)

Ejecutadas las consultas de los 29 paneles de métricas contra el laboratorio local: **20 con datos**, 9 vacíos por hosts que aún no existen (`r1`, `sw1`, `msmotos-rpa`) y **ninguna con error**.
