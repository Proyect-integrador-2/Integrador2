# Diseño del RPA / monitoreo sintético

Tareas: IP2-55 (diseño) e IP2-76 (cliente sintético). Borrador para el E2 (05 oct 2026).

El profesor pidió (21 set 2026) que el RPA mida la **experiencia del cliente**, con el tipo de experiencia definido en los requerimientos (RF-16 a RF-18). El usuario sintético es un cliente de MS Motos que usa el portal de clientes, no un empleado del taller.

## 1. Herramienta: Robot Framework + Browser Library

| Criterio | **Robot Framework + Browser** | OpenRPA |
|---|---|---|
| Sistema operativo | ✅ Linux sin interfaz gráfica (corre en `vm-rpa`) | ❌ Windows con escritorio |
| Ejecución programada | ✅ `systemd timer` o `cron` | ⚠️ Requiere OpenFlow |
| Versionado en Git | ✅ Archivos de texto `.robot` | ⚠️ Flujos en formato propio |
| Medición por paso | ✅ `output.xml` con tiempos de cada palabra clave | ⚠️ Manual |
| Motor del navegador | Playwright (Chromium) | Selenium/IE/Chrome según versión |

**Decisión:** Robot Framework con Browser Library. Corre en una VM Linux sin escritorio, se programa con el sistema operativo, y el código y sus resultados quedan versionados.

## 2. El cliente sintético

Una cuenta de **cliente** dedicada, *Cliente Sintético RPA*, que crea el script de carga inicial (IP2-76) en las dos instancias de la aplicación:

| Dato | Valor |
|---|---|
| Correo | `SEED_RPA_EMAIL` (por defecto `rpa@taller.local`); la contraseña va en `SEED_RPA_PASSWORD`, fuera de Git |
| Portal habilitado | Sí, con `password_hash` y el correo marcado como verificado, porque la app corre sin servicio de correo |
| Moto de prueba | Una moto con historial de servicios y una orden de trabajo, para que el recorrido de consulta siempre tenga datos |
| Primer ingreso | La bienvenida del portal ya marcada como vista, para que no tape la pantalla en cada ejecución |

Así su actividad se distingue en los logs y se puede desactivar sin afectar a nadie. Hoy `seed-usuarios.js` crea un usuario de **recepción** para el RPA; IP2-76 lo reemplaza por este cliente.

## 3. Recorridos

Cada recorrido corre contra las **dos instancias**: Linux (`vm-app`, Docker Compose) y Windows Server 2022 (servicio de Windows).

### 3.1 Consulta del cliente (RF-16) · cada 5 minutos

| Paso | Acción en el portal | Validación | Alerta |
|---|---|---|---|
| `abrir` | Cargar `/portal/login` | Se muestra el formulario de ingreso | — |
| `login` | Correo y contraseña del cliente sintético | Se muestra `/portal/inicio` | — |
| `inicio` | Leer el resumen de inicio | Aparecen el nombre del cliente y su resumen | — |
| `motos` | Abrir `/portal/motos` y el historial de la moto de prueba (`/portal/moto/:id/historial`) | La moto y al menos un servicio aparecen | — |
| `ordenes` | Revisar el estado de sus órdenes de trabajo | La orden de prueba aparece con su estado | — |
| `logout` | Cerrar sesión | Vuelve a `/portal/login` | — |

**Alerta si** falla cualquier paso o el recorrido completo tarda más de **10 s**.

### 3.2 Agendar una cita (RF-17) · cada 30 minutos

| Paso | Acción en el portal | Validación |
|---|---|---|
| `login` | Ingresar como el cliente sintético | Se muestra `/portal/inicio` |
| `elegir` | Abrir `/portal/agendar`, elegir sucursal y servicio | Se cargan sucursales y servicios |
| `reservar` | Consultar la disponibilidad y reservar el próximo espacio libre | La app confirma la cita |
| `verificar` | Abrir `/portal/mis-citas` | La cita recién creada aparece |
| `cancelar` | Cancelar esa cita desde su detalle | La cita queda cancelada |
| `logout` | Cerrar sesión | Vuelve a `/portal/login` |

**Alerta si** falla cualquier paso o el recorrido completo tarda más de **20 s**.

**Por qué se cancela en el mismo recorrido:** para que el robot nunca ocupe un espacio real de la agenda del taller. Si el recorrido falla después de `reservar`, un paso de limpieza al final (*teardown* de Robot Framework) cancela la cita que haya quedado abierta.

## 4. Resultados enviados a Zabbix

Un host por instancia, `msmotos-rpa-linux` y `msmotos-rpa-windows`, en el grupo **Integrador II**. Ítems tipo *trapper*, enviados con `zabbix_sender` al terminar cada ejecución. El recorrido va como parámetro de la clave y al final del nombre:

| Ítem (key) | Nombre en Zabbix | Tipo | Ejemplo |
|---|---|---|---|
| `rpa.status[consulta]` | `RPA: resultado · consulta` | Entero (1 = OK, 0 = fallo) | `1` |
| `rpa.duration.total[consulta]` | `RPA: duración total · consulta` | Flotante (s) | `6.84` |
| `rpa.step[consulta,login]` … | `RPA: duración del paso login · consulta` … | Flotante (s) | `1.92` |
| `rpa.failed_step[consulta]` | `RPA: paso fallido · consulta` | Texto | `motos` (vacío si todo OK) |
| `rpa.error[consulta]` | `RPA: último error · consulta` | Texto | `Element "text=Honda CB190R" not found` |

Los mismos cinco ítems existen con `agendar` en lugar de `consulta`.

**Los nombres importan:** los paneles de Grafana ([monitoreo/grafana/](../../monitoreo/grafana/)) filtran por **nombre** con expresiones como `/^RPA: resultado/` y por host con `/rpa/`. Con este esquema los dos hosts y los dos recorridos caen en los paneles existentes sin tocarlos; el dashboard *Experiencia del cliente* solo necesita separar las series por host y por recorrido.

### Triggers

| # | Trigger | Condición | Severidad |
|---|---|---|---|
| T12 | RPA falló | `rpa.status[*]` = 0 en la última ejecución | High, con el paso y el error en la alerta |
| T13 | Consulta lenta | `rpa.duration.total[consulta]` > 10 s | Warning |
| T13 | Agendamiento lento | `rpa.duration.total[agendar]` > 20 s | Warning |
| T14 | RPA sin datos | Sin resultados de consulta en 15 min o de agendamiento en 75 min | Warning (el propio RPA dejó de correr) |

Ver también [monitoreo.md](monitoreo.md). T13 es un solo trigger con los dos umbrales.

## 5. Ejecución

| Tema | Decisión |
|---|---|
| Programación | Dos `systemd timer`: consulta cada 5 min y agendamiento cada 30 min, desfasados para no coincidir |
| Tiempo máximo por ejecución | 60 s; si se excede, se marca como fallo en el paso en curso |
| Evidencia en caso de fallo | Captura de pantalla del paso fallido, guardada 7 días en `vm-rpa` |
| Credenciales | Archivo de entorno en `vm-rpa` con permisos 600, fuera de Git |
| Ubicación en la red | `vm-rpa` en VLAN 30. **Mejora opcional:** un segundo agente en la VLAN 20 para medir exactamente desde la red de los usuarios |

## 6. Compatibilidad con la app

| Tema | Situación |
|---|---|
| Captcha (Cloudflare Turnstile) | Desactivado: no se configuran `TURNSTILE_SECRET` ni la site key en el despliegue interno |
| Correo de la app | Sin servicio de correo (`RESEND_API_KEY` vacía): el cliente sintético lo crea el script de carga con el correo ya verificado, nunca por el registro del portal |
| Límite de intentos de ingreso | `/api/portal/login` comparte el límite de autenticación: 30 intentos por IP cada 15 min. El RPA hace unos 3,5 ingresos cada 15 min por instancia, y cada instancia tiene su propio límite |
| Límite general de la API | 600 solicitudes por minuto por IP; un recorrido hace unas pocas decenas |
| Verificación en dos pasos | La cuenta del cliente sintético no la activa |
