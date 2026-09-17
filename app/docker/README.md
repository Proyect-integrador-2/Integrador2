# Despliegue de MS Motos con Docker

Guía para levantar la aplicación en la **VM de App** (Ubuntu Server) o en una PC de desarrollo.
Tareas relacionadas: IP2-35 (diseño), IP2-36 (Dockerfile), IP2-37 (Compose), IP2-38 (despliegue), IP2-39 (documentación).

## Arquitectura

```
Cliente (VLAN 20) ──HTTP:80──► Nginx (systemd, en la VM)
                                  │ proxy a 127.0.0.1:3000
                                  ▼
                        ┌─ msmotos-app (contenedor) ─┐     red Docker: msmotos-backend
                        │ Express: /api + Angular    │────────────────┐
                        └────────────────────────────┘                ▼
                                                        msmotos-db (MySQL 8.4)
                                                        volumen: msmotos-db-data
```

| Componente | Dónde corre | Por qué |
|---|---|---|
| Nginx | Servicio del sistema (`systemctl`) | Es el "servicio detenido" de la prueba PR-01 |
| `msmotos-app` | Contenedor | Es el "contenedor detenido" de la prueba PR-02 |
| `msmotos-db` | Contenedor con volumen | Los datos sobreviven a reinicios y a `docker compose down` |

## Puertos, redes y persistencia

| Servicio | Puerto | Expuesto a | Notas |
|---|---|---|---|
| Nginx | 80 | Red (VLAN 20 y 10) | Único punto de entrada de usuarios |
| msmotos-app | 3000 | Solo `127.0.0.1` de la VM | Nadie llega directo desde la red |
| msmotos-db | 3306 | Solo la red Docker `msmotos-backend` | No se publica en la VM |

| Volumen | Contenido |
|---|---|
| `msmotos-db-data` | Datos de MySQL. **Borrarlo borra toda la base.** |

## Variables de entorno

Se definen en `app/.env` (copia de [`.env.example`](../.env.example)). Nunca se suben a Git.

| Variable | Obligatoria | Uso |
|---|---|---|
| `DB_PASSWORD` | Sí | Contraseña del usuario de la app en MySQL |
| `MYSQL_ROOT_PASSWORD` | Sí | Contraseña de root de MySQL |
| `JWT_SECRET` | Sí | Firma de sesiones. La app no arranca sin ella |
| `WEB_CONCURRENCY` | No (2) | Procesos de Node; ajustar a las vCPU de la VM |
| `DB_POOL_TOTAL` | No (20) | Conexiones totales a MySQL repartidas entre procesos |
| `DISABLE_CRON` | No (0) | `1` desactiva recordatorios y no-show programados |
| `RESEND_API_KEY` | No | Sin ella **no se envía ningún correo**: el código de verificación queda en el log (ver *Registro de usuarios sin correo*) |
| `MAIL_FROM` | No | Remitente. Con el de prueba de Resend (`onboarding@resend.dev`) solo se entrega al correo dueño de la cuenta |
| `SEED_*_PASSWORD` | Solo para `seed` | Contraseñas de admin, recepción y usuario del RPA |

## Primer despliegue

```bash
cd Integrador2/app
cp .env.example .env
nano .env                                  # completar contraseñas y JWT_SECRET

docker compose up -d --build               # construye la imagen y levanta db + app
docker compose ps                          # ambos deben quedar "healthy"
docker compose run --rm seed               # crea las cuentas (solo la primera vez)
curl http://127.0.0.1:3000/api/health      # {"ok":true,...}
```

Nginx en la VM:

```bash
sudo apt install -y nginx
sudo cp docker/nginx/msmotos.conf /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/msmotos.conf /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
curl http://<IP-de-la-VM>/api/health
```

## Operación

| Acción | Comando |
|---|---|
| Ver estado | `docker compose ps` |
| Logs de la app | `docker compose logs -f app` |
| Reiniciar la app | `docker compose restart app` |
| Actualizar a una versión nueva | `git pull && docker compose up -d --build` |
| Apagar sin borrar datos | `docker compose down` |
| Respaldo de la base | `docker exec msmotos-db sh -c 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" proyecto_taller' > respaldo.sql` |
| Leer un código de verificación | `docker logs msmotos-app --since 3m \| Select-String DEV` |

### Registro de usuarios sin correo

La app envía correos por la API de Resend y el mailer **degrada en silencio**: si `RESEND_API_KEY` está vacía
escribe el código en el log y responde como si lo hubiera enviado, así que la pantalla dice *"revisá tu spam"*
y nunca salió nada. En el despliegue on-premise lo dejamos así a propósito: la red del laboratorio puede no
tener salida a Internet y la demo no debe depender de un servicio externo.

Para crear una cuenta desde el portal, pedir el código en la pantalla de registro y leerlo del log:

```powershell
docker logs msmotos-app --since 3m | Select-String DEV
# 📧 [DEV] Código de verificación para alguien@ejemplo.com: 908314
```

El código vive **10 minutos** y es de un solo uso. Las cuentas que necesita el proyecto (`admin`, recepción y
el usuario del RPA) las crea el perfil `seed` sin pasar por el correo, así que esto solo aplica a cuentas nuevas
del portal de clientes.

## Pruebas realizadas (17 sep 2026, Docker Desktop 29.8 en PC de desarrollo)

| # | Prueba | Resultado |
|---|---|---|
| 1 | Construcción de la imagen | ✅ 116 s la primera vez |
| 2 | Base nueva: esquema + 36 migraciones automáticas | ✅ Sin errores (tras la corrección C1) |
| 3 | Siembra de cuentas y repetición | ✅ Crea 3 cuentas; la segunda vez no duplica |
| 4 | `/api/health` y frontend | ✅ HTTP 200 |
| 5 | Login admin, recepción y RPA; contraseña incorrecta | ✅ Rol correcto; incorrecta → 401 |
| 6 | Datos tras reiniciar `db` y `app` | ✅ Persisten |
| 7 | `docker stop msmotos-app` | ✅ Se detiene en 0,4 s y **no** se levanta solo |
| 8 | Muere un proceso worker | ✅ El proceso principal lo repone; la app sigue respondiendo |
| 9 | Muere el proceso principal | ✅ Docker reinicia el contenedor y la app vuelve en segundos |
| 10 | Sintaxis de `docker/nginx/msmotos.conf` | ✅ `nginx -t` correcto |

### Correcciones hechas a la app de Integrador I

| # | Problema encontrado | Corrección |
|---|---|---|
| C1 | En una base nueva, `auto-migrate.js` creaba un índice sobre `mensajes_internos.tipo` antes de agregar esa columna: la migración abortaba y dejaba sin aplicar el resto (2FA, tareas del mecánico, etc.). En Railway no se notaba porque la base ya existía | Se agrega la columna antes del índice (operación idempotente) |
| C2 | Al recibir SIGTERM, el proceso principal de `cluster.js` detenía los workers pero seguía vivo por el pool de MySQL: el contenedor quedaba "running" sin atender y Docker no lo reponía | Al salir el último worker, el proceso principal termina (código 0 si fue un apagado pedido, 1 si no) |

## Cuidados

- **No ejecutar `npm run migrate` ni `src/db/migrate.js` contra una base con datos**: `schema.sql` empieza con `DROP TABLE`. En Docker el esquema se crea solo la primera vez que el volumen está vacío.
- `docker compose down -v` **borra el volumen** y con él la base completa.
- La política `restart: unless-stopped` levanta la app si se cae sola, pero **no** si alguien la detiene con `docker stop`. Ese caso lo detecta Zabbix y lo recupera n8n.
