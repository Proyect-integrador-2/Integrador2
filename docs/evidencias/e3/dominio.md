# Integración con el dominio y prueba de acceso por grupos

Tareas: IP2-81 (integración con Active Directory) e IP2-83 (prueba PR-13). Hecho y probado a distancia el 14 de octubre de 2026. Responde al criterio CA-15: el personal de TI entra con su cuenta del dominio, según su grupo.

## 1. Cómo se valida cada herramienta

| Herramienta | Mecanismo | Administradores (`GG-IP2-Administradores`) | Operadores (`GG-IP2-Operadores`) | Cuenta de emergencia |
|---|---|---|---|---|
| Proxmox | Dominio de autenticación "ip2" de tipo Active Directory; los miembros de los dos grupos se sincronizan cada hora | Rol Administrator | Rol PVEAuditor (solo ver) | `root@pam` |
| Zabbix | Directorio LDAP con alta automática en el primer inicio de sesión | Admin role, con escritura sobre el grupo *Integrador II* | User role, solo lectura | `Admin` (local) |
| Grafana | LDAP con roles por grupo | Admin | Viewer | `admin` (local) |
| SSH de las 5 VM Linux | SSSD contra el dominio | Entran con su contraseña del dominio y tienen `sudo` | No entran | `ip2`, solo con llave |
| Servidor Windows de la app | `vm-app-win` unida al dominio | Administradores locales | No administran | `Administrator` local |
| n8n | Cuenta local | — | — | La validación por LDAP es de la edición de pago (excluido desde el diseño) |

Todas las herramientas consultan el dominio por **LDAPS** (puerto 636). El certificado del controlador lo firmó la autoridad interna del laboratorio ([`ca-interna.sh --dc`](../../../infra/proxmox/ca-interna.sh)), y cada herramienta solo acepta ese certificado: las contraseñas no viajan en claro.

Para consultar el directorio, las herramientas usan la cuenta de servicio `svc-ldap`, de solo lectura. Su contraseña pasó del controlador a cada equipo por tuberías, sin mostrarse. No está en el repositorio.

| Script | Qué configura |
|---|---|
| [`infra/vm-dc/certificado-ldaps.ps1`](../../../infra/vm-dc/certificado-ldaps.ps1) | El certificado LDAPS del controlador |
| [`infra/proxmox/dominio-proxmox.sh`](../../../infra/proxmox/dominio-proxmox.sh) | Proxmox |
| [`infra/vm-zabbix/configurar-zabbix.py`](../../../infra/vm-zabbix/configurar-zabbix.py) y `ldap.conf` | Zabbix |
| [`infra/vm-grafana/ldap.toml`](../../../infra/vm-grafana/ldap.toml) | Grafana |
| [`infra/proxmox/dominio-linux.sh`](../../../infra/proxmox/dominio-linux.sh) | El SSH de cada VM Linux |
| [`infra/vm-app-win/unir-dominio.ps1`](../../../infra/vm-app-win/unir-dominio.ps1) | El servidor Windows |

## 2. Prueba PR-13

Tres cuentas de prueba creadas con [`cuentas-prueba.ps1`](../../../infra/vm-dc/cuentas-prueba.ps1), con contraseñas aleatorias que las pruebas tomaron del controlador sin mostrarlas:

| Cuenta | Grupo |
|---|---|
| `prueba.admin` | GG-IP2-Administradores |
| `prueba.operador` | GG-IP2-Operadores |
| `prueba.singrupo` | Ninguno del proyecto |

| Herramienta | Qué se probó | `prueba.admin` | `prueba.operador` | `prueba.singrupo` |
|---|---|---|---|---|
| Proxmox | Inicio de sesión por la API y permisos sobre `/` | Entra; puede encender y apagar VM | Entra; solo puede ver | Rechazada (401) |
| Zabbix | Inicio de sesión por la API; crear y borrar una macro en un host | Entra; puede modificar | Entra; "No permissions" al modificar | Rechazada |
| Grafana | Inicio de sesión y rol | Entra como Admin | Entra como Viewer | Rechazada (401) |
| SSH de las 5 VM Linux | Inicio de sesión con contraseña y `sudo` | Entra en las 5; `sudo` da root | Rechazada en las 5 | Rechazada en las 5 |
| `vm-app-win` | Ejecutar un comando por WinRM | Ejecuta como `ip2\prueba.admin` | Rechazada | Rechazada |

**Resultado: cumple.** En cada herramienta un administrador administra, un operador solo ve y una cuenta sin grupo es rechazada.

## 3. Diferencias con el diseño

| Diseño | Lo que se hizo | Por qué |
|---|---|---|
| VMs Linux unidas al dominio con `realm join` | SSSD consulta el dominio por LDAPS, sin unir la VM | No necesita Kerberos ni que las VMs usen el DNS del controlador; si el dominio cae, la VM sigue funcionando y la cuenta `ip2` sigue entrando |
| Zabbix con autenticación LDAP | Además, el dominio pasó a ser el método por defecto | Zabbix solo da de alta a un usuario nuevo en ese caso. `Admin` y la cuenta con la que Grafana lee Zabbix quedaron fijadas como locales |
| LDAP (puerto 389) | LDAPS (puerto 636) con certificado de la autoridad interna | Que las contraseñas no viajen en claro |

## 4. Contraseñas de los integrantes

Las cuentas personales nacieron con una contraseña temporal marcada como "cambiar en el primer inicio de sesión". El 14 de octubre, al entrar con la primera cuenta real, se vio que esa marca no funciona con este diseño: mientras está puesta, el dominio rechaza la validación por LDAP, que es la que usan Proxmox, Zabbix, Grafana y el SSH de las VM Linux. La persona no puede entrar a ninguna herramienta ni, por tanto, llegar a cambiar la contraseña.

Se resolvió así:

| Integrante | Qué se hizo |
|---|---|
| Quien administra | Puso su propia contraseña desde una sesión en el controlador, escribiéndola sin que se mostrara (`Read-Host -AsSecureString` y `Set-ADAccountPassword`) |
| Los otros cuatro | [`nueva-clave.ps1`](../../../infra/vm-dc/nueva-clave.ps1) les puso una contraseña aleatoria de 16 caracteres, sin la marca, y las guardó en un archivo del controlador que solo leen los administradores. Se comprobó que las cuatro validan por LDAPS. Cada una se entrega por privado |

`configurar-dominio.ps1` ya crea las cuentas sin esa marca. Las contraseñas vencen a los 90 días, después del cierre del proyecto.

## 5. Pendiente

| Qué | Tarea |
|---|---|
| Entregar a cada integrante su contraseña y que entre a las herramientas de su grupo | IP2-79 |
| Borrar las tres cuentas de prueba al terminar el proyecto | IP2-83 |
| Capturas de los inicios de sesión en el navegador (Proxmox, Zabbix, Grafana) | IP2-81 |
