# Diseño del RPA / monitoreo sintético

Tarea: IP2-55. Borrador para el E2 (05 oct 2026).

## 1. Herramienta: Robot Framework + Browser Library

| Criterio | **Robot Framework + Browser** | OpenRPA |
|---|---|---|
| Sistema operativo | ✅ Linux sin interfaz gráfica (corre en `vm-rpa`) | ❌ Windows con escritorio |
| Ejecución programada | ✅ `systemd timer` o `cron` | ⚠️ Requiere OpenFlow |
| Versionado en Git | ✅ Archivos de texto `.robot` | ⚠️ Flujos en formato propio |
| Medición por paso | ✅ `output.xml` con tiempos de cada palabra clave | ⚠️ Manual |
| Motor del navegador | Playwright (Chromium) | Selenium/IE/Chrome según versión |

**Decisión:** Robot Framework con Browser Library. Corre en una VM Linux sin escritorio, se programa con el sistema operativo, y el código y sus resultados quedan versionados.

## 2. Operación sintética

Se usa una cuenta propia, `rpa@taller.local` con rol recepción, sembrada por `seed-usuarios.js`. Así su actividad se distingue en los logs y se puede desactivar sin afectar a nadie.

| Paso | Acción | Validación | Métrica |
|---|---|---|---|
| 1. `abrir` | Cargar `http://10.10.30.11/` | La pantalla de login se muestra | `rpa.step[abrir]` (ms) |
| 2. `login` | Ingresar correo y contraseña del usuario RPA | Se muestra el panel de recepción | `rpa.step[login]` (ms) |
| 3. `consulta` | Abrir Clientes y buscar "Cliente Sintético RPA" | El cliente aparece en la lista | `rpa.step[consulta]` (ms) |
| 4. `registro` | Registrar una nota de visita en la ficha del cliente sintético (sin crear clientes nuevos) | El registro queda guardado | `rpa.step[registro]` (ms) |
| 5. `logout` | Cerrar sesión | Vuelve a la pantalla de login | `rpa.step[logout]` (ms) |

**Por qué no se crea un cliente nuevo en cada ejecución:** con una ejecución cada 5 minutos serían 288 clientes falsos por día. El registro se hace sobre la misma ficha sintética. La acción exacta se define al construir el script con la app corriendo (IP2-56).

## 3. Resultados enviados a Zabbix

Host `msmotos-rpa`, ítems tipo *trapper*, enviados con `zabbix_sender` al terminar cada ejecución:

| Ítem (key) | Nombre en Zabbix | Tipo | Ejemplo |
|---|---|---|---|
| `rpa.status` | `RPA: resultado de la última ejecución` | Entero (1 = OK, 0 = fallo) | `1` |
| `rpa.duration.total` | `RPA: duración total` | Flotante (s) | `6.84` |
| `rpa.step[abrir]` … `rpa.step[logout]` | `RPA: duración del paso abrir` … `logout` | Flotante (s) | `1.92` |
| `rpa.failed_step` | `RPA: paso fallido` | Texto | `consulta` (vacío si todo OK) |
| `rpa.error` | `RPA: último error` | Texto | `Element "text=Cliente Sintético RPA" not found` |

**Los nombres importan:** los paneles de Grafana ya creados ([monitoreo/grafana/](../../monitoreo/grafana/)) filtran los ítems por **nombre**, no por clave, así que al crear los ítems trapper hay que usar exactamente estos nombres para que el tablero *IP2 · Experiencia del usuario* se llene solo. El host debe llamarse `msmotos-rpa` y estar en el grupo **Integrador II**.

Triggers asociados: T12 (falló), T13 (lento) y T14 (sin datos). Ver [monitoreo.md](monitoreo.md).

## 4. Ejecución

| Tema | Decisión |
|---|---|
| Frecuencia | Cada 5 minutos (`systemd timer`) |
| Tiempo máximo por ejecución | 60 s; si se excede, se marca como fallo en el paso en curso |
| Evidencia en caso de fallo | Captura de pantalla del paso fallido guardada 7 días en `vm-rpa` |
| Credenciales | Archivo de entorno en `vm-rpa` con permisos 600, fuera de Git |
| Ubicación en la red | `vm-rpa` en VLAN 30. **Mejora opcional:** un segundo agente en la VLAN 20 para medir exactamente desde la red de los usuarios |

## 5. Compatibilidad con la app

| Tema | Situación |
|---|---|
| Captcha (Cloudflare Turnstile) | Desactivado: no se configuran `TURNSTILE_SECRET` ni site key en el despliegue interno |
| Correo de la app | Sin servicio de correo (`RESEND_API_KEY` vacía): el RPA entra con la cuenta que crea el perfil `seed`, nunca por el registro del portal |
| Límite de intentos de login | 10/min y 60/hora por correo; 30 por IP cada 15 min. El RPA hace 3 cada 15 min: dentro del límite |
| Verificación en dos pasos | La cuenta RPA no la activa |
