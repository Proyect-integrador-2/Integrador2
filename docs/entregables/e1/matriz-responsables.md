# Matriz de responsables

> Para pegar en Confluence: **01 Gestión → Matriz de responsables** (reemplaza todo el contenido).
> Tarea IP2-12 · Equipo de cinco integrantes; cada uno tiene un área principal, una segunda área y actúa como respaldo de otras dos.

## 1. Integrantes

| # | Integrante | Correo | Área principal | Segunda área | Respaldo de |
|---|---|---|---|---|---|
| 1 | Stiff Alemán | stiffaleman@gmail.com | Líder / Gestión del proyecto | Automatización (n8n) | Monitoreo · RPA |
| 2 | Alexander Jiménez Ortiz | alexjimenezo2005@gmail.com | Redes | Manual técnico y diagramas finales | Infraestructura · Contenedores |
| 3 | Jeffrey Herrera Urbina | jeffreyjohel10@gmail.com | DevOps / Contenedores | Monitoreo (Zabbix) | Redes · Observabilidad |
| 4 | Álvaro Álvarez Rosales | thealvaro875@gmail.com | Observabilidad (Grafana) + RPA | Manual de operación | Monitoreo · Pruebas |
| 5 | Angel Gallardo Espinoza | gallardoespinozar@gmail.com | Infraestructura / Virtualización | Pruebas y QA | Automatización · Gestión |

## 2. Roles, responsabilidades y áreas a cargo

| Rol | Responsable | Respaldo | De qué responde | Épicas |
|---|---|---|---|---|
| Líder / Gestión del proyecto | Stiff Alemán | Angel Gallardo | Cronograma al día, minutas semanales, consolidación de cada entregable, seguimiento de riesgos y bloqueos | IP2-1, IP2-10 |
| Redes | Alexander Jiménez | Jeffrey Herrera | Topología, VLAN, direccionamiento, NAT/PAT, ACL y SNMP; que un usuario no pueda administrar la infraestructura | IP2-2 |
| Infraestructura / Virtualización | Angel Gallardo | Alexander Jiménez | Hipervisor, VMs dimensionadas, redes virtuales y respaldos | IP2-3 |
| DevOps / Contenedores | Jeffrey Herrera | Alexander Jiménez | Imagen y Compose de MS Motos, persistencia, variables, puertos y despliegue en la VM | IP2-4 |
| Monitoreo (Zabbix) | Jeffrey Herrera | Stiff Alemán | Hosts, plantillas, métricas, umbrales y triggers de infraestructura, red, contenedores y aplicación | IP2-5 |
| Observabilidad (Grafana) + RPA | Álvaro Álvarez | Jeffrey Herrera | Los 4 dashboards y el usuario sintético que mide la experiencia real | IP2-6, IP2-8 |
| Automatización (n8n) | Stiff Alemán | Angel Gallardo | Flujos de recuperación, alertas por Telegram y correo, y los controles de seguridad de las automatizaciones | IP2-7 |
| Pruebas y QA | Angel Gallardo | Álvaro Álvarez | Matriz de pruebas, pruebas de falla, capacidad, red y seguridad, y corrección de hallazgos | IP2-9 |

## 3. Carga de trabajo

Las 61 tareas del cronograma quedan repartidas así. La carga del líder incluye las 13 tareas de gestión del E1, que ya están hechas o en revisión.

| Integrante | Tareas | Áreas |
|---|---|---|
| Stiff Alemán | 24 | Gestión, automatización, consolidación de entregables y presentación |
| Jeffrey Herrera | 12 | Contenedores, monitoreo y exportación final de configuraciones |
| Angel Gallardo | 10 | Virtualización, VMs, respaldos y pruebas |
| Alexander Jiménez | 8 | Red, manual técnico y diagramas finales |
| Álvaro Álvarez | 7 | Grafana, RPA y manual de operación |

## 4. Reglas de trabajo

1. Cada tarea de Jira tiene **un solo responsable** y puede tener colaboradores.
2. Cada área tiene un **respaldo** que conoce lo suficiente para sostenerla una semana si el titular falta (riesgo R-08).
3. El responsable de un área es quien la presenta en la demostración final.
4. Nadie cierra su propia tarea sin evidencia: el criterio de terminado de cada tarea dice qué evidencia se adjunta y dónde.
5. El documento de cada entregable lo revisan **al menos dos integrantes** antes de la entrega.

## 5. Accesos del equipo

| Integrante | GitHub | Jira / Confluence |
|---|---|---|
| Stiff Alemán | Dueño de la organización | Administrador del sitio |
| Alexander Jiménez | Invitación pendiente | Invitación pendiente |
| Jeffrey Herrera | Invitación pendiente | Invitación pendiente |
| Álvaro Álvarez | Invitación pendiente | Invitación pendiente |
| Angel Gallardo | Invitación pendiente | Invitación pendiente |

> **Pendiente:** invitar a los cuatro integrantes a GitHub, Jira y Confluence con sus correos, y asignarles sus tareas en Jira. Hasta que acepten la invitación no existen como usuarios del sitio, así que en los documentos aparecen por nombre.

> **Nota para el profesor:** la guía del entregable pide equipos de 6 a 7 integrantes y este grupo es de 5. Conviene confirmarlo en la sesión de la semana 1 (tarea IP2-13) por si afecta el alcance esperado.
