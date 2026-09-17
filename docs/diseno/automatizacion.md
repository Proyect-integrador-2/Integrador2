# Diseño de automatización y alertamiento

Tarea: IP2-49 (qué se automatiza, qué solo alerta y con qué controles). Borrador para el E2 (05 oct 2026).

## 1. Herramienta: n8n (Jenkins opcional)

| Criterio | **n8n** | Jenkins |
|---|---|---|
| Recibir alertas de Zabbix | ✅ Nodo Webhook nativo | ⚠️ Requiere plugin y token de build remoto |
| Ejecutar acciones en la VM | ✅ Nodo SSH | ✅ Agentes o `sh` por SSH |
| Telegram y correo | ✅ Nodos nativos | ⚠️ Plugins |
| Lógica condicional (según tags, reintentos) | ✅ Visual (IF, Switch, Code) | ⚠️ Groovy en Pipeline |
| Evidencia exportable (PDF §8.5) | ✅ Flujo en JSON | ✅ Jenkinsfile |
| Consumo | Bajo (~300 MB) | Alto (JVM, ~1 GB) |

**Decisión:** n8n para la recuperación y las notificaciones. Jenkins queda como mejora opcional para desplegar la app (CI/CD), fuera del alcance mínimo.

## 2. Matriz falla → acción

| Falla | Trigger | Detecta | Acción | Notifica | Valida |
|---|---|---|---|---|---|
| Contenedor `msmotos-app` detenido | T01 | Zabbix (Docker, 30 s) | n8n → SSH → `docker start msmotos-app` | Telegram + correo: problema y recuperación | Zabbix cierra el problema; RPA vuelve a OK |
| Servicio Nginx detenido | T03 | Zabbix (systemd, 30 s) | n8n → SSH → `sudo systemctl restart nginx` | Telegram + correo | Zabbix cierra el problema |
| CPU, RAM, disco altos | T06–T08 | Zabbix (agente) | **Ninguna automática** | Telegram + correo con valor y umbral | Intervención humana |
| Interfaz caída / enlace saturado | T09–T10 | Zabbix (SNMP) | **Ninguna automática** | Telegram + correo | Dashboard de red |
| App no disponible / lenta | T04–T05 | Zabbix (escenario web) | **Ninguna automática** | Telegram + correo | Revisar T01/T03 |
| RPA falla o se degrada | T12–T14 | RPA → Zabbix | **Ninguna automática** | Telegram + correo con el paso fallido | Intervención humana |

## 3. Flujo de integración

```
Zabbix detecta problema
   │  Media type "Webhook n8n" (POST JSON con token)
   ▼
n8n · Webhook  ──► ¿token válido? ── no ──► descartar y registrar
   │ sí
   ▼
Switch por tag "remediation"
   ├── restart-container ─┐
   ├── restart-service ───┤
   │                      ▼
   │           ¿objetivo en la lista permitida?  ── no ──► alerta "acción rechazada"
   │                      │ sí
   │           ¿menos de 3 intentos en 10 min?  ── no ──► escalar a humano (alerta crítica)
   │                      │ sí
   │           SSH a vm-app con usuario restringido → ejecutar acción
   │                      │
   │           Acknowledge en Zabbix (API) con comentario del resultado
   │                      │
   └── none ──────────────┴──► Mensaje a Telegram + correo
```

## 4. Controles de seguridad (pregunta orientadora del E4)

| # | Control | Cómo se implementa | Evita |
|---|---|---|---|
| C1 | **Lista cerrada de acciones** | n8n solo conoce dos comandos fijos; el nombre del objetivo viene de una lista (`msmotos-app`, `nginx`), nunca del texto del webhook | Ejecución de comandos inyectados |
| C2 | **Límite de reintentos** | Máximo 3 intentos por objetivo cada 10 minutos (contador en n8n) | Reinicios en bucle (riesgo R-12) |
| C3 | **Escalamiento a humano** | Al superar el límite: alerta crítica "recuperación automática agotada" | Que la automatización oculte una falla de fondo |
| C4 | **Usuario SSH restringido** | Usuario `n8n-ops` en `vm-app` con llave, sin contraseña; `sudoers` permite solo `systemctl restart nginx`; pertenece al grupo `docker` | Escalada de privilegios si se compromete n8n |
| C5 | **Webhook autenticado** | Encabezado con token secreto; n8n solo accesible desde la VLAN 30 | Que alguien dispare acciones desde fuera |
| C6 | **Trazabilidad** | Cada acción queda en el historial de ejecuciones de n8n y como acknowledge en el evento de Zabbix | Acciones sin registro |
| C7 | **Interruptor de emergencia** | Desactivar el flujo en n8n detiene toda acción automática sin afectar las alertas de Zabbix | Pérdida de control durante una falla mayor |

Configuración de `sudoers` en `vm-app` (`/etc/sudoers.d/n8n-ops`):

```
n8n-ops ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx
```

## 5. Notificaciones

| Canal | Uso | Configuración |
|---|---|---|
| Telegram | Canal principal (inmediato) | Bot creado con @BotFather, agregado a un grupo del equipo; token y chat ID guardados como credenciales de n8n |
| Correo | Respaldo y registro formal | Cuenta dedicada con contraseña de aplicación SMTP (puerto 587/465) |

Formato del mensaje: ver [monitoreo.md §4](monitoreo.md#4-contenido-mínimo-de-una-alerta-rnf-05).

**Riesgo R-04:** si la red de la universidad bloquea Telegram o SMTP, se detecta en la primera visita al laboratorio (IP2-13).
