# Integrador II — Automatización y Monitoreo de Servicios de Infraestructura TI

UTN · ITI-625 · Empresa ficticia: **Servicios Digitales del Pacífico S.A.**

Plataforma on-premise que despliega la aplicación de Integrador I (**MS Motos**) en contenedores,
la monitorea con Zabbix, la visualiza en Grafana, recupera servicios caídos con n8n y mide la
experiencia de usuario con un RPA.

## Dónde vive cada cosa

| Qué | Dónde |
|---|---|
| Código fuente, scripts, configuraciones, pipelines | **Este repositorio (Git)** |
| Documentación, diseños, evidencias, minutas | **Confluence** |
| Tareas, responsables, seguimiento semanal | **Jira** |

> Regla: si se puede ejecutar o importar, va en Git. Si se lee o se muestra como evidencia, va en Confluence.
> Cada tarea de Jira enlaza a su commit/PR y a su página de evidencia.

## Estructura

| Carpeta | Contenido |
|---|---|
| `app/` | Aplicación MS Motos (Integrador I) + `Dockerfile` y `docker-compose.yml` |
| `red/` | Configuraciones de router y switch (VLAN, trunk, NAT/PAT, ACL, SNMP) y topología Packet Tracer |
| `infra/` | Proxmox, definición y dimensionamiento de VMs, scripts de aprovisionamiento |
| `monitoreo/zabbix/` | Plantillas exportadas, media types, scripts de agente |
| `monitoreo/grafana/` | Dashboards (JSON) y provisioning |
| `automatizacion/n8n/` | Flujos exportados (JSON) |
| `automatizacion/jenkins/` | `Jenkinsfile` y jobs (si se usa) |
| `rpa/` | Usuario sintético con Robot Framework |
| `pruebas/` | Scripts para provocar fallas controladas y matriz de resultados |
| `scripts/` | Utilidades generales |
| `docs/diagramas/` | Fuentes editables de diagramas (`.drawio`); la versión publicada va a Confluence |

## Convenciones

- Rama principal: `main` (solo por Pull Request).
- Ramas: `<CLAVE-JIRA>-descripcion-corta` → ej. `IP2-14-vlan-administracion`.
- Commits: `<CLAVE-JIRA> verbo en presente` → ej. `IP2-14 configura VLAN 10 y 20 en el switch`.
- **Nunca** subir `.env`, contraseñas, llaves ni respaldos de base de datos.

## Fechas oficiales

| Entregable | Fecha | Valor |
|---|---|---|
| E1 — Planteamiento y gestión | 21 sep 2026 | 15% |
| E2 — Análisis y diseño | 05 oct 2026 | 15% |
| E3 — Implementación técnica | 02 nov 2026 | 25% |
| E4 — Pruebas, seguridad y mejoras | 16 nov 2026 | 15% |
| E5 — Producto final + presentación | 30 nov 2026 | 15% + 15% |
