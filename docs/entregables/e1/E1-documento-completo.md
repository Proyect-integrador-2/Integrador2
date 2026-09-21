# Entregable #1 — Planteamiento y gestión del proyecto

**UTN · ITI-625 Proyecto Integrador II — Infraestructura de TI**
**Fecha de entrega:** lunes 21 de setiembre de 2026 · **Valor:** 15 %

> Documento completo y autosuficiente. Sirve para entregar aunque Confluence no esté disponible: se pega en Google Docs o Word y se exporta a PDF. La versión viva está en Confluence (*02 Entregables → E1 → E1 · Documento de entrega*).

---

## 1. Portada e identificación del equipo

| Dato | Detalle |
|---|---|
| Nombre del proyecto | Plataforma on-premise de monitoreo y automatización de servicios de TI |
| Empresa (caso) | Servicios Digitales del Pacífico S.A. (ficticia) |
| Aplicación a desplegar | MS Motos, sistema de gestión de taller desarrollado en Integrador I |
| Curso | ITI-625 Proyecto Integrador II — Infraestructura de TI |
| Periodo | 14 de setiembre al 30 de noviembre de 2026 |
| Repositorio | GitHub, organización `Proyect-integrador-2`, repositorio privado `Integrador2` |
| Gestión | Jira (proyecto IP2) · Confluence (espacio Integrador II) |

### Integrantes y roles iniciales

| # | Integrante | Correo | Rol principal | Respaldo de | Áreas a cargo |
|---|---|---|---|---|---|
| 1 | Stiff Alemán | stiffaleman@gmail.com | Líder / Gestión del proyecto | Monitoreo y RPA | Gestión, automatización (n8n), documentación y demostración |
| 2 | Alexander Jiménez Ortiz | alexjimenezo2005@gmail.com | Redes | Infraestructura y Contenedores | Topología, VLAN, NAT/PAT, ACL y SNMP; manual técnico y diagramas |
| 3 | Jeffrey Herrera Urbina | jeffreyjohel10@gmail.com | DevOps / Contenedores | Redes y Observabilidad | Imagen, Compose y despliegue; monitoreo con Zabbix |
| 4 | Álvaro Álvarez Rosales | thealvaro875@gmail.com | Observabilidad (Grafana) + RPA | Monitoreo y Pruebas | Los 4 dashboards, usuario sintético y manual de operación |
| 5 | Angel Gallardo Espinoza | gallardoespinozar@gmail.com | Infraestructura / Virtualización | Automatización y Gestión | Inventario del equipo, hipervisor, VMs, respaldos, pruebas y QA |

Cada integrante tiene un área principal y actúa como respaldo de otras dos, de modo que ninguna área dependa de una sola persona (riesgo R-08).

## 2. Situación actual y problema

Servicios Digitales del Pacífico S.A. opera una aplicación web con módulos de autenticación, consulta y registro, clave para su operación diaria. Hoy funciona así:

- Corre en un ambiente básico, poco estandarizado y sin monitoreo centralizado.
- Las fallas se conocen cuando un usuario llama para reportarlas.
- No hay visibilidad del router, switch, interfaces, VLAN ni del uso del enlace.
- No hay separación formal entre el acceso administrativo y el de usuarios.
- Cuando un servicio o contenedor se detiene, un técnico debe conectarse manualmente para recuperarlo.
- No existen alertas por correo ni por Telegram.

### 2.1 Problemas identificados y sus causas

| # | Problema | Causa | Impacto operativo |
|---|---|---|---|
| P1 | No hay monitoreo centralizado de infraestructura, red, VMs, contenedores y aplicación | Nunca se implementó una herramienta de monitoreo | No se conoce el estado real del servicio |
| P2 | Las fallas se detectan por reportes de usuarios | Sin detección automática ni umbrales | Más tiempo de indisponibilidad y mala experiencia |
| P3 | No hay separación entre red de administración y de usuarios | Red plana, sin VLAN ni reglas de acceso | Un usuario podría alcanzar la infraestructura |
| P4 | No se mide uso de interfaces, caídas ni ancho de banda | Equipos de red sin SNMP ni recolección | Problemas de red invisibles hasta que afectan el servicio |
| P5 | La recuperación de servicios y contenedores es manual | Sin automatización ni procedimiento documentado | Depende de que una persona esté disponible |
| P6 | No hay visualización consolidada de rendimiento y disponibilidad | Sin histórico ni dashboards | Decisiones de TI sin datos |
| P7 | No hay prueba sintética desde la perspectiva del usuario | Nadie mide la experiencia real | Degradaciones parciales pasan inadvertidas |
| P8 | No hay gestión formal ni trazabilidad semanal del trabajo | Sin herramienta de tareas ni evidencias | Retrasos y bloqueos sin control |

### 2.2 Impacto en el negocio y necesidad de mejora

| Consecuencia | Origen |
|---|---|
| El taller queda sin sistema sin que TI lo sepa | P1, P2 |
| Se pierde trabajo de recepción: citas, órdenes y registros que no se pueden ingresar | P2, P5 |
| La recuperación depende de que una persona con conocimiento esté disponible | P5 |
| No se puede justificar una inversión ni explicar una caída a la gerencia | P1, P6 |
| Un usuario común podría alcanzar la consola del hipervisor o del monitoreo | P3 |
| Una degradación parcial (aplicación lenta, módulo roto) pasa inadvertida | P7 |

La mejora que se necesita no es más capacidad: es **ver lo que pasa, avisar a tiempo y recuperar solo lo que se puede recuperar sin riesgo**, con la infraestructura segmentada y con trazabilidad de cada cambio.

## 3. Objetivos y alcance

**Objetivo general:** diseñar e implementar una plataforma de infraestructura de TI on-premise que despliegue MS Motos en contenedores, la monitoree de extremo a extremo, visualice su rendimiento, automatice la recuperación ante fallos controlados y alerte oportunamente ante problemas de capacidad o conectividad.

### 3.1 Objetivos específicos

| # | Objetivo | Cómo se medirá |
|---|---|---|
| OE-1 | Implementar una red segmentada con router NAT/PAT, switch administrable y VLAN de Administración, Usuarios y Servidores | PC-CLIENTE alcanza la aplicación pero no la infraestructura |
| OE-2 | Instalar un hipervisor en el servidor y crear VMs dimensionadas por servicio | VMs operativas con IP fija y acceso SSH documentado |
| OE-3 | Desplegar MS Motos en contenedores con persistencia, redes, variables y puertos documentados | La aplicación responde y los datos sobreviven a un reinicio |
| OE-4 | Monitorear servidor, VMs, contenedores, servicios, aplicación, router, switch e interfaces | Todos los hosts con datos y triggers con umbrales documentados |
| OE-5 | Construir cuatro dashboards: general, técnico, de red y de experiencia | Los cuatro con datos reales y colores de umbral |
| OE-6 | Automatizar la recuperación de un servicio y un contenedor detenidos, y alertar por Telegram y correo | Detección en menos de 2 min y recuperación en menos de 5 min, verificadas |
| OE-7 | Medir la experiencia del usuario con un RPA que ejecute una operación real | Duración por paso, éxito/fallo y paso fallido registrados en Zabbix |
| OE-8 | Gestionar el proyecto con Jira, Confluence y GitHub, con seguimiento semanal | Tareas con responsable, fecha y evidencia; minuta semanal publicada |

### 3.2 Alcance incluido

- Configuración de router, switch, VLAN, trunk, NAT/PAT, ACL y SNMP en el equipo de la universidad
- Hipervisor y máquinas virtuales en un servidor on-premise
- Contenerización y despliegue de MS Motos
- Zabbix, Grafana, n8n, notificaciones por Telegram y correo, y RPA
- Pruebas controladas de falla, capacidad, red, seguridad y segmentación
- Documentación técnica, manual de operación y evidencias

### 3.3 Exclusiones

- Alta disponibilidad, clúster o redundancia de servidores y enlaces
- Ampliación automática de recursos: el documento guía la prohíbe expresamente
- Publicación de la aplicación en Internet con dominio y certificado público
- Nuevas funcionalidades de MS Motos: solo se contenerizan las existentes
- Datos reales de clientes: se usan datos de prueba
- Envío de correo desde la propia aplicación

### 3.4 Supuestos

| # | Supuesto | Si no se cumple |
|---|---|---|
| S1 | La universidad presta un router, un switch administrable y un servidor, disponibles hasta el 30 de noviembre | Se reduce el alcance de red o se virtualiza lo que falte (riesgos R-02 y R-06) |
| S2 | Se permite formatear el servidor e instalar el hipervisor | Se usa un hipervisor alterno autorizado (riesgo R-07) |
| S3 | Hay un punto de red con salida a Internet para el router | Doble NAT desde una red disponible (riesgo R-05) |
| S4 | El router y el switch soportan VLAN, trunk 802.1Q, NAT/PAT y SNMP | Se ajusta el diseño al equipo real tras el inventario (riesgo R-06) |
| S5 | La red del laboratorio permite salida a Telegram, SMTP y a los repositorios de imágenes | Correo como respaldo e imágenes precargadas (riesgo R-04) |
| S6 | El equipo mantiene disponibilidad semanal durante las once semanas | Se redistribuyen tareas usando los roles de respaldo (riesgo R-08) |

### 3.5 Limitaciones

- **Presupuesto cero:** todo el software es libre o de uso interno gratuito, y el hardware es prestado.
- **Acceso restringido al laboratorio:** solo en horario de clase, lo que obliga a construir y probar fuera del laboratorio.
- **Equipo compartido:** las configuraciones pueden perderse entre sesiones, por lo que todo debe ser reaplicable desde el repositorio.
- **Un solo servidor:** no hay redundancia posible; la defensa son los respaldos.
- **Once semanas:** el periodo obliga a adelantar en paralelo lo que no depende del laboratorio.
- **Sin IP pública:** la solución no se expone a Internet.

## 4. Requerimientos iniciales

### 4.1 Por tipo de recurso

| Tipo | Requerimiento |
|---|---|
| Tecnológicos | Servidor con virtualización, router con NAT/PAT, switch administrable con VLAN y 802.1Q, dos PC cliente, hipervisor, Docker, Zabbix, Grafana, n8n y Robot Framework |
| Humanos | Cinco estudiantes con un área principal y un rol de respaldo cada uno; disponibilidad semanal y una sesión de laboratorio por semana |
| Económicos | Sin presupuesto: hardware prestado por la universidad y software libre o de uso interno gratuito. El único costo eventual sería una cuenta de correo para alertas, que se resuelve con una cuenta gratuita |
| Temporales | Once semanas, del 21 de setiembre al 30 de noviembre de 2026, con cinco entregas intermedias y cierre semanal cada lunes |
| De red | Un punto con salida a Internet, direccionamiento propio para tres VLAN, y salida permitida hacia Telegram, SMTP y los repositorios de imágenes y paquetes |
| De seguridad | Segmentación efectiva entre usuarios e infraestructura, SSH con llave, SNMP restringido a la IP de Zabbix, credenciales fuera de Git y Confluence, y privilegios mínimos para las acciones automáticas |
| De monitoreo | Recolección cada 30 a 60 segundos según el ítem, umbrales documentados por métrica, y trazabilidad de cada acción automática en el evento de Zabbix |
| De acceso | Permiso para formatear el servidor e instalar el hipervisor, acceso por consola al router y al switch, cuentas de GitHub y Atlassian para todo el equipo, y acceso al laboratorio con horario conocido |

### 4.2 Requerimientos funcionales

| ID | Requerimiento | Área |
|---|---|---|
| RF-01 | Salida a Internet mediante NAT/PAT en el router | Red |
| RF-02 | VLAN de Administración y de Usuarios con puertos de acceso y troncales | Red |
| RF-03 | Enrutamiento entre VLAN donde sea necesario | Red |
| RF-04 | La VLAN de Usuarios no puede administrar la infraestructura | Red |
| RF-05 | Servidor on-premise con hipervisor y VMs dimensionadas | Virtualización |
| RF-06 | MS Motos ejecutándose en contenedores con Dockerfile y Compose | Contenedores |
| RF-07 | Persistencia, redes, variables y puertos documentados | Contenedores |
| RF-08 | Zabbix monitorea servidor, VMs, contenedores, servicios, aplicación, router, switch e interfaces | Monitoreo |
| RF-09 | Recolección de CPU, memoria, disco, red, latencia, disponibilidad y tiempo de respuesta | Monitoreo |
| RF-10 | Triggers con umbrales documentados, incluidas caída y saturación de interfaces | Monitoreo |
| RF-11 | Dashboards general, técnico, de red y de experiencia | Observabilidad |
| RF-12 | Un servicio detenido se reinicia solo y Zabbix valida la recuperación | Automatización |
| RF-13 | Un contenedor detenido se levanta solo y la aplicación vuelve a responder | Automatización |
| RF-14 | CPU, RAM, disco o red elevados generan alerta, sin asignar recursos automáticamente | Automatización |
| RF-15 | Las alertas se notifican por Telegram y/o correo | Automatización |
| RF-16 | Un usuario sintético ingresa y ejecuta una operación funcional | RPA |
| RF-17 | El RPA registra duración, éxito/fallo y el paso donde falló | RPA |

### 4.3 Requerimientos no funcionales

La última columna es lo ya verificado en el laboratorio de pruebas que el equipo montó en la semana 0.

| ID | Requerimiento | Métrica comprometida | Medición al 17 set 2026 |
|---|---|---|---|
| RNF-01 | Detección oportuna | Falla detectada en 2 minutos o menos | Cumple: 83 s y 114 s en dos corridas |
| RNF-02 | Recuperación rápida | Recuperado en 5 minutos o menos desde la detección | Cumple: menos de 3 s; problema cerrado a los 142 s y 173 s |
| RNF-03 | Automatizaciones seguras | Lista cerrada de acciones, máximo 3 intentos cada 10 min y luego escalar a una persona | Implementado y probado |
| RNF-04 | Trazabilidad | Toda acción automática queda registrada y reconocida en Zabbix | Verificado |
| RNF-05 | Alertas accionables | Host, problema, severidad, hora y acción sugerida | Formato definido; falta el canal de envío |
| RNF-06 | Seguridad | Sin credenciales en Git ni Confluence; SNMP restringido; privilegios mínimos | Verificado |
| RNF-07 | Reproducibilidad | Configuraciones, dashboards y flujos exportados y versionados | En el repositorio |
| RNF-08 | Gestión | Cronograma semanal con responsable y evidencia por tarea | 61 tareas con fechas, recursos, dependencias y evidencia |

## 5. Recursos e inventario

### 5.1 Hardware (préstamo de la universidad)

Se levanta con fotos en la primera visita al laboratorio (tarea IP2-14). Hasta entonces, el diseño trabaja con los supuestos S1 y S4, declarados como tales. De cada equipo se registra: router (modelo, IOS, licencia, RAM, interfaces), switch (modelo, puertos, capa 2 o 3), servidor (CPU, RAM, discos, NIC, iDRAC/iLO), PC-ADMIN y PC-CLIENTE, cables de consola y UTP.

### 5.2 Software, con las versiones ya probadas

| Software | Uso | Versión | Licencia |
|---|---|---|---|
| Proxmox VE | Hipervisor | Serie 8 (a confirmar con el servidor real) | Libre (AGPL) |
| Ubuntu Server | Sistema operativo de las VMs | 24.04 LTS | Libre |
| Docker Engine y Compose | Contenedores | Probado: 29.8.0 y 5.5.1 | Libre (Apache 2.0) |
| Node.js y MySQL | Ejecución y base de datos de MS Motos | Probado: 22 y 8.4 | Libre |
| Zabbix y PostgreSQL | Monitoreo y su base de datos | Probado: 7.0.30 LTS y 16 | Libre (AGPL) |
| Grafana y plugin de Zabbix | Dashboards | Probado: 12.4.3 | Libre (AGPL) |
| n8n | Automatización y alertas | Probado: 2.40.2 | Uso interno gratuito |
| Robot Framework + Browser | RPA | Por instalar | Libre (Apache 2.0) |
| draw.io y Cisco Packet Tracer | Diagramas y ensayo de red | Probado: Packet Tracer 9.0 | Libre / gratuito |

### 5.3 Licencias, cuentas y repositorios

| Recurso | Estado |
|---|---|
| GitHub: organización `Proyect-integrador-2` y repositorio privado `Integrador2` | Creado; falta invitar al equipo |
| Atlassian: Jira (IP2) y Confluence (Integrador II) | Creado; falta invitar al equipo |
| Bot de Telegram y grupo de alertas | Pendiente (IP2-51) |
| Cuenta de correo para alertas, con contraseña de aplicación | Pendiente (IP2-51) |
| Cuenta Cisco para Packet Tracer | Creada |

Ninguna licencia tiene costo. **No se registran contraseñas ni tokens en Confluence ni en el repositorio.**

### 5.4 Otros recursos del equipo

Una computadora personal con Docker, que permitió montar el laboratorio completo de monitoreo y automatización sin depender del laboratorio de la universidad, y Cisco Packet Tracer para ensayar las configuraciones de red antes de tocar el equipo real.

## 6. Gestión del proyecto

### 6.1 EDT

Diez áreas de primer nivel, que en Jira existen como épicas, con 61 tareas y 31 dependencias registradas. Cada tarea tiene criterio de terminado, evidencia esperada, recursos y fechas.

| # | Área | Tareas | # | Área | Tareas |
|---|---|---|---|---|---|
| 1 | Gestión del proyecto | 16 | 6 | Observabilidad con Grafana | 3 |
| 2 | Red y conectividad | 6 | 7 | Automatización y alertamiento | 6 |
| 3 | Virtualización y servidores | 5 | 8 | RPA y monitoreo sintético | 3 |
| 4 | Contenedores y despliegue | 5 | 9 | Pruebas, seguridad y mejoras | 5 |
| 5 | Monitoreo con Zabbix | 6 | 10 | Documentación y demostración | 6 |

### 6.2 Responsables

Ocho áreas repartidas entre cinco integrantes, cada una con un responsable y un respaldo capaz de sostenerla una semana.

| Rol | Responsable | Respaldo | Épicas |
|---|---|---|---|
| Líder / Gestión del proyecto | Stiff Alemán | Angel Gallardo | IP2-1, IP2-10 |
| Redes | Alexander Jiménez | Jeffrey Herrera | IP2-2 |
| Infraestructura / Virtualización | Angel Gallardo | Alexander Jiménez | IP2-3 |
| DevOps / Contenedores | Jeffrey Herrera | Alexander Jiménez | IP2-4 |
| Monitoreo (Zabbix) | Jeffrey Herrera | Stiff Alemán | IP2-5 |
| Observabilidad (Grafana) + RPA | Álvaro Álvarez | Jeffrey Herrera | IP2-6, IP2-8 |
| Automatización (n8n) | Stiff Alemán | Angel Gallardo | IP2-7 |
| Pruebas y QA | Angel Gallardo | Álvaro Álvarez | IP2-9 |

**Reglas:** una sola persona asignada por tarea; nadie cierra una tarea sin la evidencia que pide su criterio de terminado; cada documento de entregable lo revisan al menos dos integrantes; el responsable de un área la presenta en la demostración final.

**Carga de trabajo:** Stiff Alemán 22 tareas · Jeffrey Herrera 12 · Angel Gallardo 11 · Alexander Jiménez 9 · Álvaro Álvarez 7. La carga del líder incluye las 11 tareas de gestión del E1, ya hechas o en revisión.

### 6.3 Dependencias (ruta crítica)

1. **Inventario del equipo real** → diseño de red y dimensionamiento de VMs.
2. **Hipervisor instalado** → creación de VMs → VM de aplicación y VM de Zabbix.
3. **Zabbix operando** → monitoreo de contenedores, servicios y aplicación → integración con n8n y dashboards.
4. **Triggers con umbrales** → flujos de automatización.
5. **Automatización y RPA** → pruebas de falla controlada → E4.

### 6.4 Riesgos

Trece riesgos con probabilidad, impacto, exposición, acción preventiva y plan de contingencia. Los de mayor exposición:

| ID | Riesgo | Exp. | Cómo se enfrenta |
|---|---|---|---|
| R-09 | Todo el proyecto depende de un único servidor prestado | 9 | Respaldos de VMs y todo reproducible desde el repositorio |
| R-01 | Borran las configuraciones del router y switch entre clases | 9 | Mitigado: configuraciones versionadas y ensayadas; se reaplican en minutos |
| R-03 | Horario limitado de acceso al laboratorio | 6 | Mitigado: el laboratorio local permite construir y medir fuera de la universidad |
| R-04 | La red de la universidad bloquea Telegram, SMTP o las imágenes | 6 | Probarlo en la primera visita; correo de respaldo e imágenes precargadas |
| R-02 | El servidor es compartido o lo formatean | 6 | Confirmar exclusividad por escrito; respaldos de las VMs |
| R-05 | No se asigna IP o punto WAN para el router | 6 | Consulta al profesor en la semana 1; doble NAT como contingencia |
| R-08 | Un integrante abandona o no cumple | 6 | Rol de respaldo por área y seguimiento semanal con evidencia |

Dos riesgos ya bajaron por trabajo hecho: **R-10** (problemas al contenerizar la aplicación) quedó **cerrado**, y **R-12** (una automatización causando un problema mayor) quedó mitigado con controles probados.

### 6.5 Herramientas de gestión

| Herramienta | Para qué |
|---|---|
| Jira (proyecto IP2) | Tareas, responsables, fechas, dependencias, estados y bloqueos |
| Confluence (espacio Integrador II) | Documentación, diseños, minutas y evidencias |
| GitHub (organización privada) | Código, scripts, configuraciones, dashboards y flujos; cada commit cita la clave de su tarea |
| draw.io | Diagramas de arquitectura y de red, con la fuente versionada |

## 7. Cronograma detallado

El cronograma completo — 61 tareas con ID, responsable, inicio, fin, recursos, dependencia, estado y evidencia — está en [cronograma-tabla.md](cronograma-tabla.md), en la página *Cronograma detallado y plan de seguimiento* de Confluence y en la vista Cronograma de Jira. Resumen por semana:

| Semana | Periodo | Tareas | Hito o entrega |
|---|---|---|---|
| 0 | 14/09 – 20/09 | 12 | Planteamiento y gestión listos |
| 1 | 21/09 – 27/09 | 1 | **Entrega E1** (21/09) |
| 2 | 28/09 – 04/10 | 3 | Diseño de red y de contenedores |
| 3 | 05/10 – 11/10 | 10 | **Entrega E2** (05/10) · hipervisor instalado |
| 4 | 12/10 – 18/10 | 3 | VMs operativas y respaldadas |
| 5 | 19/10 – 25/10 | 4 | Red operativa y segmentada · Zabbix instalado |
| 6 | 26/10 – 01/11 | 9 | Aplicación desplegada y monitoreada |
| 7 | 02/11 – 08/11 | 7 | **Entrega E3** (02/11) · recuperación automática funcionando |
| 8 | 09/11 – 15/11 | 4 | Pruebas de falla, capacidad, red, RPA y seguridad |
| 9 | 16/11 – 22/11 | 2 | **Entrega E4** (16/11) · hallazgos corregidos |
| 10 | 23/11 – 29/11 | 5 | Manuales, exportaciones y ensayos de la demo |
| 11 | 30/11 | 1 | **Entrega E5 y presentación final** (30/11) |

## 8. Plan de seguimiento

| Tema | Definición |
|---|---|
| Reunión | Cada lunes, 30 minutos, con agenda fija; conduce el líder de proyecto |
| Agenda | 1) Tareas terminadas y su evidencia · 2) Tareas vencidas con causa y acción correctiva · 3) Bloqueos y quién los destraba · 4) Revisión de riesgos · 5) Compromiso de la semana siguiente |
| Registro de acuerdos | Una minuta por semana en Confluence (01 Gestión → Minutas semanales) |
| Bloqueos | Se marcan en Jira con el indicador de impedimento y se enlazan con la tarea que los bloquea; se nombran en la minuta con responsable y fecha |
| Tareas vencidas | Se registran con causa y acción correctiva concreta: mover fecha, reducir alcance, pedir ayuda o reasignar. No se mueven en silencio |
| Cierre de una tarea | Solo con la evidencia que declara su criterio de terminado, y revisada por alguien distinto de quien la ejecutó |

## 9. Respuestas a las preguntas orientadoras

**¿Qué problema empresarial concreto se desea resolver?** La empresa opera una aplicación crítica sin monitoreo, sin segmentación de red y sin recuperación automática. El problema no es que el sistema falle, sino que nadie se entera cuando falla y que volver a levantarlo depende de una persona disponible.

**¿Qué se incluye y qué queda fuera del proyecto?** Se incluye la plataforma on-premise completa: red segmentada, hipervisor con VMs, la aplicación en contenedores, monitoreo, dashboards, recuperación automática de dos fallas controladas, alertas y un usuario sintético. Queda fuera la alta disponibilidad, la ampliación automática de recursos, la publicación en Internet y cualquier cambio funcional de la aplicación.

**¿Qué tareas dependen de otras?** La ruta crítica de la sección 6.3: el inventario del equipo condiciona el diseño de red y el dimensionamiento de VMs; las VMs condicionan el monitoreo; el monitoreo condiciona la automatización; la automatización condiciona las pruebas de falla. Están registradas como enlaces de bloqueo en Jira.

**¿Qué recurso o acceso podría bloquear el avance?** Cuatro: que el servidor no se pueda formatear o no sea exclusivo, que no haya punto WAN con salida a Internet, que el horario de laboratorio sea insuficiente, y que la red de la universidad bloquee Telegram, SMTP o la descarga de imágenes. Los cuatro están en el registro de riesgos con su contingencia, y las preguntas al profesor (IP2-13) buscan confirmarlos en la semana 1.

**¿Cómo se demostrará cada semana que una tarea realmente terminó?** Con la evidencia que cada tarea declara de antemano: una captura, una salida de comando, un commit con la clave de la tarea, una página de Confluence o una medición. La tarea pasa a *En revisión* y la aprueba alguien distinto de quien la ejecutó; recién entonces queda Completada. La minuta semanal enlaza cada tarea cerrada con su evidencia.

## 10. Criterios y pruebas de aceptación

| ID | Criterio | Cómo se cumple | Estado |
|---|---|---|---|
| A-01 | Cronograma completo, con tareas para todo el periodo y fecha límite semanal | 61 tareas con inicio y fin, del 14/09 al 30/11, distribuidas en 12 semanas | Cumple |
| A-02 | Cada tarea con responsable primario y recursos asociados | Cada tarea del cronograma tiene responsable con nombre y el recurso que necesita | Cumple |
| A-03 | Cada tarea define evidencia verificable de finalización | Columna de evidencia en el cronograma y criterio de terminado en cada tarea de Jira | Cumple |
| A-04 | La propuesta incluye red, virtualización, contenedores, monitoreo, automatización, Grafana y RPA | Objetivos OE-1 a OE-7 y áreas 2 a 8 de la EDT | Cumple |
| A-05 | Mecanismo semanal para registrar acuerdos, bloqueos y acciones correctivas | Plan de seguimiento de la sección 8: minuta semanal, indicador de impedimento en Jira y registro de tareas vencidas | Cumple |

## 11. Evidencias que acompañan este entregable

- Este documento en PDF.
- Repositorio del equipo en GitHub, con la aplicación contenerizada, las configuraciones de red, los dashboards y el flujo de automatización.
- Tablero y cronograma de Jira (vista Cronograma), con las 61 tareas fechadas.
- Espacio de Confluence con las páginas de detalle y las evidencias.
- Fuente editable del diagrama de arquitectura (`.drawio`) y su imagen.
- Mediciones del laboratorio de pruebas: tiempos de detección y recuperación de la prueba de contenedor detenido.

## 12. Avance técnico anticipado (semana 0)

Aunque el E1 es el planteamiento, el equipo adelantó el trabajo que no depende del equipo de la universidad, para descargar las semanas de implementación:

| Qué | Estado | Evidencia |
|---|---|---|
| MS Motos en contenedores | Probado | Imagen, Compose y 10 pruebas; se corrigieron dos errores de la aplicación original |
| Configuraciones de router y switch | Escritas y ensayadas | Validadas en Packet Tracer: 8 de 9 pruebas de conectividad y segmentación |
| Laboratorio de monitoreo y automatización | Funcionando | Zabbix, Grafana, n8n y la cadena completa de recuperación automática, con tiempos medidos |
| Dashboards de Grafana | Construidos | Los 4 tableros versionados; 20 de 29 paneles ya con datos reales |
| Diseños técnicos del E2 | Borradores listos | Virtualización, monitoreo, automatización y RPA |

---

### Control del documento

| Versión | Fecha | Cambios | Revisado por |
|---|---|---|---|
| 1.0 | 17 set 2026 | Versión inicial consolidada | |
| 1.1 | 17 set 2026 | Reordenado según la guía del entregable: portada, supuestos y limitaciones, requerimientos por tipo de recurso, plan de seguimiento, criterios A-01 a A-05 y evidencias | |
| 1.2 | 20 set 2026 | Integrantes, roles y reparto de las 61 tareas entre los cinco miembros del equipo | |

**Pendiente antes de entregar:** captura de la vista Cronograma de Jira y revisión cruzada por dos integrantes.

**Nota:** la guía pide equipos de 6 a 7 integrantes y este grupo es de 5; se consultará al profesor en la sesión de la semana 1 (tarea IP2-13).
