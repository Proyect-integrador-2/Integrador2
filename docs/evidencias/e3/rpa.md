# Cliente sintético (RPA) en el laboratorio

Tareas: IP2-56 (recorridos), IP2-57 (programación y envío a Zabbix) e IP2-76 (cliente y datos de prueba). Hecho y probado el 13 de octubre de 2026, a distancia.

El robot usa el portal de MS Motos como lo usaría un cliente desde el celular: abre un navegador real (Chromium), escribe su correo y su contraseña, y toca la pantalla. Corre en `vm-rpa` con Robot Framework 7.5 y la librería Browser 20.6.

## 1. Qué recorre

| Recorrido | Cada cuánto | Pasos | Operación real |
|---|---|---|---|
| Consulta ([`consulta.robot`](../../../rpa/recorridos/consulta.robot)) | 5 minutos | abrir, login, inicio, motos, citas, logout | Entra, lee su resumen, abre el historial de su moto y revisa sus citas |
| Agendar ([`agendar.robot`](../../../rpa/recorridos/agendar.robot)) | 30 minutos | abrir, login, elegir, reservar, verificar, cancelar, logout | **Reserva una cita, comprueba que quedó registrada y la cancela** |

El cliente es una cuenta propia del portal, `cliente.rpa@taller.local`, con una moto (Honda CB190R) y un servicio completado. La crea [`seed-cliente-rpa.js`](../../../app/backend/scripts/seed-cliente-rpa.js) con el correo ya verificado, porque el despliegue no tiene servicio de correo.

| Lo que ve el robot en "Mis Citas" | La cita que reserva, antes de cancelarla |
|---|---|
| ![Mis Citas](rpa/portal-mis-citas.png) | ![Cita agendada](rpa/portal-cita-agendada.png) |

## 2. Resultados de las primeras ejecuciones

| Recorrido | Resultado | Duración | Por paso |
|---|---|---|---|
| Consulta | OK | 4,81 s | abrir 0,46 · login 2,39 · inicio 0,35 · motos 0,66 · citas 0,40 · logout 0,55 |
| Agendar | OK | 10,91 s | abrir 5,73 · login 0,93 · elegir 0,58 · reservar 0,97 · verificar 0,01 · cancelar 1,86 · logout 0,82 |

Las dos quedan bajo sus umbrales (10 s y 20 s). En la base, la cita que creó el robot quedó en estado `cancelado`, así que no ocupa la agenda del taller.

## 3. Qué recibe Zabbix

[`ejecutar.py`](../../../rpa/ejecutar.py) corre el recorrido, mide cada paso y lo envía con `zabbix_sender` al host `msmotos-rpa-linux`: 21 ítems entre los dos recorridos.

| Dato | Ejemplo |
|---|---|
| RPA: resultado · consulta | 1 (OK) o 0 (fallo) |
| RPA: duración total · consulta | 4,81 s |
| RPA: duración del paso login · consulta | 2,39 s |
| RPA: paso fallido · consulta | vacío, o el nombre del paso |
| RPA: último error · consulta | vacío, o el mensaje del navegador |

Zabbix solo acepta estos datos desde `10.10.30.15`. Los 21 ítems recibieron datos, y el tablero *Experiencia del usuario* de Grafana pasó de 3 a 7 paneles con datos.

| Alerta | Condición | Severidad |
|---|---|---|
| T12 El cliente no pudo completar el recorrido | Resultado = 0; la alerta dice en qué paso | Alta |
| T13 Recorrido lento | Consulta > 10 s o agendar > 20 s | Advertencia |
| T14 El robot dejó de reportar | Sin datos de consulta en 15 min o de agendar en 75 min | Advertencia |

## 4. Prueba de fallo

Se detuvo Nginx para ver qué reporta el robot cuando la aplicación no responde.

| Hora | Qué pasó |
|---|---|
| 11:39:04 | `systemctl stop nginx` en `vm-app` |
| 11:39:09 | El robot falla en el paso **abrir** (`ERR_CONNECTION_REFUSED`). Zabbix abre T12 con "Paso: abrir" |
| 11:40:02 | Ejecución programada de las 11:40: falla en el mismo paso |
| 11:40:28 | n8n reinicia Nginx por su cuenta (T03) |
| 11:40:40 | El robot completa el recorrido en 4,68 s. Zabbix cierra T12 |

El robot guardó la captura de pantalla y el registro del fallo en `/opt/rpa/salidas`, donde se conservan 7 días.

## 5. Dos decisiones que cambiaron respecto al diseño

| Diseño | Lo que se hizo | Por qué |
|---|---|---|
| Reservar "el próximo espacio libre" | Reserva la primera hora libre a partir de tres días adelante | La aplicación no deja cancelar una cita con menos de dos horas de anticipación; la primera prueba dejó una cita sin poder cancelar |
| Paso `ordenes` en la consulta | Paso `citas`: abre "Mis Citas" y encuentra el servicio completado | El portal muestra al cliente sus servicios en esa pantalla |

Si el recorrido de agendar falla a medias, `ejecutar.py` cancela por la API cualquier cita que haya quedado abierta y lo anota en el error.

## 6. La instancia de Windows

Desde el 13 de octubre el mismo robot recorre también la aplicación que corre en Windows Server (`http://10.10.30.16`). No cambió ningún recorrido: cada instancia tiene su archivo de variables, su cuenta de cliente sintético y su host en Zabbix.

| | Linux | Windows |
|---|---|---|
| Host en Zabbix | `msmotos-rpa-linux` | `msmotos-rpa-windows` |
| Consulta, cada 5 minutos | Minutos 0, 5, 10… | Minutos 2, 7, 12… |
| Agendar, cada 30 minutos | Minutos 13 y 43 | Minutos 28 y 58 |
| Primera consulta | 4,8 s | 5,2 s |
| Primer agendar | 6,9 s | 7,0 s |

Los minutos están corridos para que los recorridos de una instancia no coincidan con los de la otra. En Windows el robot inició sesión, reservó una cita y la canceló igual que en Linux, y los triggers T12 a T14 existen para las dos instancias.

## 7. Pendiente

| Qué | Tarea |
|---|---|
| Repetir la prueba de fallo con testigos | IP2-61 |
