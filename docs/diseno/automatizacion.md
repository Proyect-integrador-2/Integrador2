# Diseño de automatización y alertamiento

Tareas: IP2-49 (qué se automatiza, qué solo alerta y con qué controles) e IP2-84 (recuperación automática de la red). Borrador para el E2 (05 oct 2026).

## 1. Herramienta: n8n

| Criterio | **n8n** | Jenkins |
|---|---|---|
| Recibir alertas de Zabbix | ✅ Nodo Webhook nativo | ⚠️ Requiere plugin y token de build remoto |
| Ejecutar acciones en la VM | ✅ Nodo SSH | ✅ Agentes o `sh` por SSH |
| Telegram y correo | ✅ Nodos nativos | ⚠️ Plugins |
| Lógica condicional (según tags, reintentos) | ✅ Visual (IF, Switch, Code) | ⚠️ Groovy en Pipeline |
| Evidencia exportable (PDF §8.5) | ✅ Flujo en JSON | ✅ Jenkinsfile |
| Consumo | Bajo (~300 MB) | Alto (JVM, ~1 GB) |

**Decisión:** n8n para la recuperación y las notificaciones. Jenkins se descartó: el profesor indicó el 21 set 2026 que CI/CD no forma parte de este proyecto.

## 2. Matriz falla → acción

| Falla | Trigger | Detecta | Acción | Notifica | Valida |
|---|---|---|---|---|---|
| Contenedor `msmotos-app` detenido | T01 | Zabbix (Docker, 30 s) | n8n → SSH → `docker start msmotos-app` | Telegram + correo: problema y recuperación | Zabbix cierra el problema; RPA vuelve a OK |
| Servicio Nginx detenido (Linux) | T03 | Zabbix (systemd, 30 s) | n8n → SSH → `sudo systemctl restart nginx` | Telegram + correo | Zabbix cierra el problema |
| Servicio `MSMotos` detenido (Windows) | T03-W | Zabbix (agente de Windows, 30 s) | n8n → WinRM → `Start-Service MSMotos` | Telegram + correo | Zabbix cierra el problema |
| CPU, RAM, disco altos | T06–T08 | Zabbix (agente) | **Ninguna automática** | Telegram + correo con valor y umbral | Intervención humana |
| Interfaz de acceso caída o con errores | T09 | Zabbix (SNMP, 60 s) | n8n → SSH al equipo → reiniciar la interfaz (`shutdown` / `no shutdown`) | Telegram: evento, acción y resultado | Zabbix cierra el problema · ver §5 |
| Puerto bloqueado por seguridad de puerto (*err-disabled*) | T09b | Zabbix (SNMP) | n8n → SSH → reactivar el puerto | Telegram | Zabbix cierra el problema · ver §5 |
| CPU o memoria del router/switch saturadas más de 10 min | T11 | Zabbix (SNMP) | n8n → respaldar configuración → `reload` del equipo | Telegram | Zabbix cierra el problema · ver §5 |
| Enlace saturado (tráfico alto sostenido) | T10 | Zabbix (SNMP) | **Ninguna automática** | Telegram + correo | Dashboard de red |
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
   ├── restart-interface ─┤   (red, ver §5)
   ├── enable-port ───────┤   (red, ver §5)
   ├── reload-device ─────┤   (red, ver §5)
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

## 5. Recuperación automática de la red (RF-23, RNF-10)

El profesor pidió el 21 set 2026 que, ante un evento de red, **la automatización reinicie el dispositivo para que vuelva a la normalidad**. Aclaró que es automático, no con autorización previa.

### 5.1 Qué se hace ante cada evento

| Evento que detecta Zabbix | Acción automática | Alcance | Espera antes de actuar |
|---|---|---|---|
| Interfaz de acceso caída, intermitente o con errores y descartes sobre el umbral | Reiniciar la interfaz (`shutdown` / `no shutdown`) | Solo esa interfaz | 2 minutos: evita actuar si alguien solo desconectó un cable un momento |
| Puerto en *err-disabled* por seguridad de puerto | Reactivar el puerto | Solo ese puerto | Inmediato |
| CPU o memoria del router o el switch saturadas | Respaldar la configuración y `reload` del equipo | Todo el equipo | 10 minutos sostenidos |

### 5.2 Qué nunca se toca

| Regla | Por qué |
|---|---|
| **Los enlaces de gestión no se reinician solos:** el trunk R1 Gi0/0/1 ↔ SW1 Gi0/1 y el enlace al servidor (SW1 Gi0/2) | Al hacer `shutdown` n8n perdería la conexión con el equipo y no podría ejecutar el `no shutdown`. Esos enlaces solo generan alerta |
| **La interfaz WAN (R1 Gi0/0/0) tampoco** | Es la salida a Internet; se atiende a mano |
| **Nunca se borra ni se reescribe configuración** | Las únicas acciones permitidas son las tres de la tabla anterior |

### 5.3 Límites (RNF-10)

| Control | Valor |
|---|---|
| Orden de las acciones | Primero la acción menor (la interfaz); el `reload` del equipo solo si la saturación persiste |
| Intentos por interfaz | Máximo 3 cada 10 minutos |
| Reinicios por equipo | Máximo 1 por hora |
| Si no se recupera | Alerta crítica y escalamiento a una persona; la automatización no vuelve a intentar |
| Si el equipo no responde por la red | No hay acción posible: se alerta y se atiende por consola |

### 5.4 Cuenta de automatización en el router y el switch (IP2-85)

| Tema | Decisión |
|---|---|
| Usuario | `n8n-net`, local en cada equipo (el router y el switch no se unen al dominio) |
| Acceso | SSH desde la IP de `vm-n8n` únicamente, por ACL |
| Privilegios | Nivel de privilegio propio con **solo** estos comandos: entrar a una interfaz, `shutdown`, `no shutdown`, `copy running-config startup-config` y `reload` |
| Contraseña | Aleatoria, guardada en las credenciales de n8n y en `red/secrets/`, fuera de Git |
| Respaldo previo al `reload` | n8n ejecuta `copy running-config startup-config` antes de reiniciar, para no perder la configuración |

### 5.5 Secuencia del flujo

```
Zabbix: interfaz Fa0/7 caída (tag remediation=restart-interface)
   ▼
n8n · ¿la interfaz está en la lista de gestión? ── sí ──► solo alerta
   │ no
   ▼
¿menos de 3 intentos en 10 min? ── no ──► alerta crítica + escalar
   │ sí
   ▼
SSH a SW1 con n8n-net → interface Fa0/7 → shutdown → esperar 5 s → no shutdown
   ▼
Esperar 60 s y consultar el estado en Zabbix (API)
   ├── recuperada ──► Telegram: "Fa0/7 reiniciada, servicio restablecido" + acknowledge en Zabbix
   └── sigue caída ──► Telegram crítico: "Fa0/7 no se recuperó, revisar el cable" + escalar
```

### 5.6 Controles que se suman a los de la sección 4

| # | Control | Cómo se implementa |
|---|---|---|
| C8 | **Lista blanca de interfaces** | n8n solo actúa sobre puertos de acceso; los de gestión están excluidos por nombre |
| C9 | **Respaldo antes del `reload`** | La configuración se guarda antes de reiniciar el equipo |
| C10 | **Ensayo previo en Packet Tracer** | El flujo se prueba contra la topología simulada antes de tocar el equipo real (riesgo R-15) |
| C11 | **Ventana de prueba** | Las pruebas de la IP2-87 se hacen en horario de laboratorio, nunca durante una demostración |

## 6. Lo que n8n reporta a Zabbix (IP2-77)

Al terminar cada ejecución, n8n envía sus resultados con `zabbix_sender`, igual que hace el RPA. Así el tablero de automatización se alimenta de la misma fuente que el resto y no necesita otro origen de datos.

**Host en Zabbix:** `automatizacion`, nombre visible **Automatización (n8n)**, en el grupo *Integrador II*. Ítems de tipo *trapper*.

| Ítem (key) | Nombre en Zabbix | Tipo | Ejemplo |
|---|---|---|---|
| `n8n.exec.status[<flujo>]` | `n8n: resultado · <flujo>` | Entero (1 = OK, 0 = fallo) | `1` |
| `n8n.exec.duration[<flujo>]` | `n8n: duración · <flujo>` | Flotante (s) | `3.4` |
| `n8n.exec.action[<flujo>]` | `n8n: última acción · <flujo>` | Texto | `docker start msmotos-app` |
| `n8n.recovery.count[<tipo>]` | `n8n: recuperaciones · <tipo>` | Entero (contador) | `2` |
| `n8n.recovery.seconds[<tipo>]` | `n8n: tiempo hasta la recuperación · <tipo>` | Flotante (s) | `142` |
| `n8n.rejected` | `n8n: acciones rechazadas` | Entero | `0` |
| `n8n.escalated` | `n8n: escalamientos a una persona` | Entero | `1` |

**Valores de `<flujo>`:** `servicio`, `contenedor`, `capacidad`, `red-interfaz`, `red-puerto`, `red-equipo`.
**Valores de `<tipo>`:** `contenedor`, `servicio`, `interfaz`, `puerto`, `equipo`.

`n8n.recovery.seconds` mide desde que Zabbix creó el problema hasta que lo cerró: es el número que comprueba el RNF-02 (recuperación en menos de 5 minutos).

**Los nombres importan:** el tablero [`monitoreo/grafana/ip2-automatizacion.json`](../../monitoreo/grafana/ip2-automatizacion.json) filtra por nombre (`/^n8n: /`) y por host (`/^Automatizaci/`), no por clave.

## 7. Notificaciones

| Canal | Uso | Configuración |
|---|---|---|
| Telegram | Canal principal (inmediato) | Bot creado con @BotFather, agregado a un grupo del equipo; token y chat ID guardados como credenciales de n8n |
| Correo | Respaldo y registro formal | Cuenta dedicada con contraseña de aplicación SMTP (puerto 587/465) |

Formato del mensaje: ver [monitoreo.md §4](monitoreo.md#4-contenido-mínimo-de-una-alerta-rnf-05).

**Riesgo R-04:** si la red de la universidad bloquea Telegram o SMTP, se detecta en la primera visita al laboratorio (IP2-13).
