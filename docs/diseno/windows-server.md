# Diseño del despliegue en Windows Server 2022

Tarea: IP2-72 (diseño) e IP2-74 (implementación). Borrador para el E2 (05 oct 2026).

El profesor pidió el 21 set 2026 que MS Motos corra en **un ambiente Linux y uno Windows Server** (RF-19) y que los dos se monitoreen (RF-20). El ambiente Linux ya está probado y contenerizado; este documento define el segundo ambiente.

## 1. Por qué instalación nativa y no contenedores

| Opción | Valoración |
|---|---|
| **Instalación nativa (elegida)** | Node.js y MySQL instalados en Windows, la aplicación registrada como **servicio de Windows**. Muestra un despliegue distinto al de Linux, que es justo lo que pide el requerimiento, y permite comparar los dos ambientes |
| Docker Desktop con contenedores Linux | Sería el mismo despliegue de Linux dentro de una máquina virtual anidada: no aporta nada nuevo y consume más memoria |
| Contenedores de Windows | La imagen base de Windows pesa varios GB y no hay imagen oficial de MySQL para Windows |

**Decisión:** instalación nativa. Así la demostración compara **contenedor detenido** (Linux) contra **servicio de Windows detenido**, con la misma aplicación.

## 2. La máquina virtual

| Dato | Valor |
|---|---|
| Nombre | `vm-app-win` |
| Sistema | Windows Server 2022 Standard, **versión de evaluación** (180 días, gratuita, del Evaluation Center de Microsoft) |
| Instalación | **Server Core con Escritorio** (*Desktop Experience*), porque simplifica la instalación de Node y MySQL |
| IP | 10.10.30.16/24 (VLAN 30), gateway 10.10.30.1 |
| Recursos | 2 vCPU · 4 GB RAM · 60 GB disco |
| Acceso | Escritorio remoto solo desde la VLAN 10 (Administración) |
| Dominio | Unida al dominio de Active Directory (ver [active-directory.md](active-directory.md)) |

## 3. Componentes que se instalan

| Componente | Versión | Cómo se instala | Para qué |
|---|---|---|---|
| Node.js LTS | 22.x (la misma del contenedor) | Instalador MSI oficial | Ejecuta el backend (Express) y sirve el frontend compilado |
| MySQL Server | 8.4 LTS | MySQL Installer for Windows | Base de datos de la instancia Windows |
| NSSM o `sc.exe` | — | Binario en `C:\opt\nssm` | Registra la aplicación como servicio de Windows |
| Agente de Zabbix | 7.0 (MSI) | Instalador oficial | Monitoreo del sistema y del servicio (IP2-75) |

**Sin Nginx en Windows.** En Linux, Nginx es el "servicio" que se detiene en la prueba PR-01. En Windows ese papel lo cumple el propio **servicio de la aplicación**, que es lo que se detiene en la prueba. Node escucha directo en el puerto 80.

## 4. Configuración de la aplicación

Mismo código del repositorio, compilado en la VM (`npm ci` en `frontend` y `backend`, y `npm run build` del frontend).

| Variable | Valor en Windows | Diferencia con Linux |
|---|---|---|
| `NODE_ENV` | `production` | Igual |
| `PORT` | `80` | En Linux es 3000 y Nginx publica el 80 |
| `DB_HOST` / `DB_PORT` | `127.0.0.1` / `3306` | En Linux el host es el contenedor `db` |
| `DB_NAME`, `DB_USER`, `DB_PASSWORD` | Los mismos nombres, **contraseñas distintas** | Cada instancia tiene sus credenciales |
| `JWT_SECRET` | Propio de esta instancia | Sesiones independientes entre ambientes |
| `WEB_CONCURRENCY` | `2` | Igual: `cluster.js` levanta 2 procesos |
| `DISABLE_CRON` | `1` | **Solo la instancia Linux ejecuta las tareas programadas**, para que no se dupliquen recordatorios ni cierres automáticos |
| `RESEND_API_KEY` | Vacía | Igual: sin servicio de correo |

Las variables se guardan en `C:\opt\msmotos\.env`, con permisos solo para el administrador y la cuenta del servicio. **No van a Git.**

## 5. El servicio de Windows

| Tema | Decisión |
|---|---|
| Nombre del servicio | `MSMotos` |
| Comando | `node C:\opt\msmotos\backend\src\cluster.js` |
| Inicio | Automático (arranca con la VM) |
| Cuenta | Cuenta de servicio local con permisos mínimos: leer la carpeta de la aplicación y escuchar en el puerto 80 |
| Recuperación de Windows | **Desactivada** (sin reinicio automático del propio Windows), para que la recuperación la haga n8n y se pueda medir el tiempo, igual que en Linux |
| Registro | Salida estándar a `C:\opt\msmotos\logs\` con rotación semanal |

## 6. Base de datos y datos de prueba

1. Crear la base y el usuario de la aplicación con el esquema del repositorio (el mismo `schema.sql`; **nunca** correr `migrate.js` sobre datos existentes, porque borra tablas).
2. Ejecutar el script de carga inicial: usuarios del taller y el **cliente sintético del RPA** con su moto, historial y orden de prueba (IP2-76).
3. Los datos de las dos instancias son **independientes**: no se replican. Cada una es un ambiente completo por su cuenta.

## 7. Diferencias resumidas entre los dos ambientes

| Tema | Linux (`vm-app`) | Windows (`vm-app-win`) |
|---|---|---|
| Ejecución | Docker Compose: contenedores `msmotos-app` y `db` | Node como servicio de Windows + MySQL instalado |
| Proxy | Nginx como servicio systemd | Ninguno: Node escucha en el 80 |
| Falla que se recupera sola | Contenedor detenido (PR-02) | Servicio de Windows detenido |
| Tareas programadas | Activas | Desactivadas (`DISABLE_CRON=1`) |
| Monitoreo | Agente 2 + plugin de Docker | Agente de Windows + estado del servicio |
| Identidad | SSH con llave, y cuentas del dominio por SSSD | Unida al dominio de Active Directory |

## 8. Monitoreo de esta instancia (IP2-75)

| Qué | Cómo |
|---|---|
| Sistema | Plantilla *Windows by Zabbix agent*: CPU, memoria, disco y servicios |
| Servicio `MSMotos` | Ítem de estado del servicio; **trigger T03-W** si se detiene |
| Aplicación | Escenario web contra `http://10.10.30.16/api/health` y tiempo de respuesta |
| Comparación | El dashboard *General* muestra las dos instancias lado a lado, y el de *Experiencia del cliente* separa los recorridos del RPA por host |

## 9. Riesgos propios de este ambiente

| Riesgo | Mitigación |
|---|---|
| La evaluación de Windows Server vence a los 180 días (marzo 2027) | El proyecto termina el 30 nov 2026; queda dentro del plazo y se documenta en el informe |
| Dos VMs Windows (aplicación y controlador de dominio) suben el consumo de RAM | Depende del inventario del servidor (IP2-14); si la RAM no alcanza, ver el plan de ajuste en [virtualizacion.md](virtualizacion.md) |
| La compilación del frontend en Windows puede diferir | Se compila una sola vez y se comparan los archivos generados con los de Linux |
