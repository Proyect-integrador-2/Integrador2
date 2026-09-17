# Laboratorio local de monitoreo y automatización

Réplica en una PC de lo que irá en las VMs del servidor, para construir y probar **antes** de tener el equipo del laboratorio. Tareas: IP2-41 a IP2-45 (Zabbix), IP2-47 y IP2-48 (Grafana), IP2-50, IP2-52 y IP2-53 (n8n), IP2-58 (pruebas).

## Qué levanta

| Servicio | Equivale a | Acceso | Versión |
|---|---|---|---|
| `lab-zabbix-server` + `lab-zabbix-db` + `lab-zabbix-web` | `vm-zabbix` | http://localhost:8080 (Admin / zabbix) | Zabbix 7.0.30 LTS |
| `lab-zabbix-agent` | Agente de `vm-app` | — | Zabbix agent 2 7.0.30 |
| `lab-grafana` | `vm-grafana` | http://localhost:3001 (admin, contraseña en `.env`) | Grafana 12.4.3 |
| `lab-n8n` | `vm-n8n` | http://localhost:5678 | n8n 2.40.2 |
| `lab-vm-app-sim` | Acceso SSH a `vm-app` | — | Alpine con OpenSSH |

El laboratorio se conecta a la red `msmotos-backend` de [app/docker-compose.yml](../../app/docker-compose.yml): monitorea y recupera la aplicación real.

Grafana monta [monitoreo/grafana/](../../monitoreo/grafana/) y carga por provisioning los 4 tableros del proyecto en la carpeta **Integrador II**; el JSON del repositorio es la fuente de verdad.

## Puesta en marcha

```powershell
cd app;  docker compose up -d           # la aplicación debe estar corriendo
cd ..\infra\lab-local
cp .env.example .env                    # completar contraseñas
.\generar-llave-ssh.ps1                 # llave SSH de n8n (queda en secrets/, fuera de Git)
docker compose up -d --build
python configurar-zabbix.py             # hosts, plantillas, triggers, usuario de Grafana y webhook
docker compose up -d n8n                # recarga n8n con el token de API que creó el script
```

Importar el flujo de n8n (una vez):

```powershell
docker cp ..\..\automatizacion\n8n\recuperacion-zabbix.json lab-n8n:/tmp/flujo.json
docker exec lab-n8n n8n import:workflow --input=/tmp/flujo.json
docker exec lab-n8n n8n publish:workflow --id=IP2recuperacion01
docker compose restart n8n
```

La credencial SSH se importa con `n8n import:credentials` (ver el script del equipo) o se crea en la interfaz pegando `secrets/n8n_ops_ed25519`.

## Qué configura `configurar-zabbix.py`

Es **idempotente**: se puede correr las veces que sea. Crea, si faltan:

- Grupo **Integrador II**.
- Host **vm-app** con las plantillas *Linux by Zabbix agent* y *Docker by Zabbix agent 2*.
- Host **msmotos-web** con escenario web a `/api/health` y al frontend, más los triggers **T04** (app caída) y **T05** (app lenta).
- Trigger **T01** (contenedor `msmotos-app` detenido) con las etiquetas `remediation=restart-container` y `target=msmotos-app`.
- Usuario **grafana** de solo lectura y usuario **n8n** con token de API (para reconocer eventos).
- Media type **Webhook n8n** habilitado y la acción que le envía los problemas y las recuperaciones, **restringida al grupo Integrador II** (para que un host ajeno no dispare la automatización).
- Deshabilita el host de ejemplo **Zabbix server** que trae la instalación: apunta a `127.0.0.1:10050`, donde no hay agente, y dejaba un problema permanente en el panel. En el servidor real, `vm-zabbix` se monitorea con su propio agente dentro del grupo Integrador II.

## Resultados de las pruebas (17 sep 2026)

| Prueba | Resultado |
|---|---|
| Zabbix API y agente | ✅ Agente disponible; CPU, memoria y disco reportando |
| Descubrimiento de contenedores | ✅ `msmotos-app` y `msmotos-db` detectados |
| Grafana → Zabbix (usuario de solo lectura) | ✅ "Zabbix API version 7.0.30" |
| Webhook con token inválido | ✅ Descartado: no ejecuta ninguna acción |
| SSH restringido de n8n (controles C1 y C4) | ✅ Permite iniciar `msmotos-app`; **rechaza** `docker ps` y detener la base |
| **PR-02 (contenedor detenido), 2 corridas** | ✅ Detección **83 s y 114 s**; recuperación **< 3 s** tras la detección; evento cerrado a los 142 s y 173 s |
| Trazabilidad en Zabbix (control C6) | ✅ Mensajes de n8n en el evento: intento de recuperación y resolución |
| Tableros de Grafana (IP2-48) | ✅ 29 paneles de métricas consultados: 20 con datos, 9 esperan `r1`/`sw1`/`msmotos-rpa`, 0 con error |

Cumple RNF-01 (detectar en menos de 2 minutos) y RNF-02 (recuperar en menos de 5 minutos).

## Hallazgos

| # | Problema | Solución |
|---|---|---|
| L1 | Zabbix generaba las alertas pero no las enviaba: *"Media type disabled"*. La API crea el media type **deshabilitado** si no se indica `status: 0` | Se agregó `status: 0` en `configurar-zabbix.py` |
| L2 | `sshd` ignoraba `AuthorizedKeysFile` y rechazaba la llave: en SSH gana el **primer** valor de cada opción y Alpine ya lo define | La configuración va en `sshd_config.d/10-integrador2.conf`, que se incluye al inicio |
| L3 | OpenSSH de Linux no lee llaves generadas en Windows con fin de línea CRLF | `generar-llave-ssh.ps1` normaliza a LF y el contenedor limpia los `\r` |
| L4 | El descubrimiento de contenedores corre cada 15 minutos por defecto | El script fuerza el descubrimiento y espera a que aparezcan los ítems |
| L5 | Los paneles salían vacíos con el filtro de host `msmotos-web`: el plugin de Zabbix filtra por el **nombre visible** del host (*MS Motos (aplicación)*) y exige forma de expresión regular | Todos los filtros de los tableros van como `/…/`; detalle en [monitoreo/grafana/README.md](../../monitoreo/grafana/README.md) |
| L6 | La función `scale` fallaba con *failed to convert value to string* | Los parámetros de las funciones del plugin van como texto: `"params": ["0.5"]` |

## Apagar

```powershell
docker compose down          # conserva historial, dashboards y flujos
docker compose down -v       # borra todo el laboratorio (volúmenes incluidos)
```
