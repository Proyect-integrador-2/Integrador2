# Diseño de identidad y acceso con Active Directory

Tareas: IP2-78 (diseño), IP2-79 (controlador de dominio), IP2-80 (políticas), IP2-81 (integración), IP2-82 (monitoreo) e IP2-83 (prueba). Borrador para el E2 (05 oct 2026).

El profesor pidió el 21 set 2026 agregar **Active Directory para la validación de usuarios y la seguridad**. Responde a OE-9, RF-21, RF-22 y RNF-09.

## 1. Qué resuelve

Hoy cada herramienta tiene sus propias cuentas locales: Proxmox, Zabbix, Grafana, n8n, el SSH de las VMs y el servidor Windows. Eso significa contraseñas repartidas, sin política común y sin forma de quitarle el acceso a alguien de una sola vez.

Con un dominio, **el personal de TI tiene una sola cuenta** y cada herramienta pregunta al dominio si esa persona puede entrar y con qué permisos.

**Los clientes de MS Motos no entran al dominio.** Siguen usando su cuenta del portal, que vive en la base de datos de la aplicación. El dominio es solo para quien administra la plataforma.

## 2. El dominio

| Dato | Valor |
|---|---|
| Nombre del dominio | `ip2.local` |
| Nombre NetBIOS | `IP2` |
| Controlador de dominio | `dc01.ip2.local` |
| VM | `vm-dc`, Windows Server 2022 (evaluación), 2 vCPU · 4 GB RAM · 60 GB |
| IP | 10.10.30.17/24 (VLAN 30), gateway 10.10.30.1 |
| Roles | **AD DS** (directorio) y **DNS** (resolución del dominio) |
| Nivel funcional | Windows Server 2016 (suficiente y compatible) |

**Por qué `.local` y no un dominio real:** la plataforma es interna y no se publica en Internet, así que no hace falta un dominio comprado. Se documenta como decisión.

**DNS:** el controlador de dominio es el DNS de las máquinas unidas al dominio, y reenvía a 8.8.8.8 lo que no sea del dominio.

## 3. Unidades organizativas y cuentas

```
ip2.local
├── OU=IP2
│   ├── OU=Usuarios      → una cuenta por integrante del equipo
│   ├── OU=Servicios     → cuentas de servicio (consultas LDAP)
│   └── OU=Equipos       → las máquinas unidas al dominio
```

| Cuenta | Tipo | Para qué |
|---|---|---|
| `stiff.aleman`, `alexander.jimenez`, `jeffrey.herrera`, `alvaro.alvarez`, `angel.gallardo` | Personal | Una por integrante; nadie comparte cuenta |
| `svc-ldap` | Servicio | Solo lectura del directorio; la usan Zabbix, Grafana y Proxmox para consultar usuarios y grupos |
| `Administrador` del dominio | Integrada | Solo para administrar el dominio; no se usa en el día a día |

## 4. Grupos y permisos

| Grupo | Quién | Qué puede hacer |
|---|---|---|
| **GG-IP2-Administradores** | Stiff, Alexander, Angel | Acceso total: Proxmox, servidor Windows, SSH de las VMs, edición en Zabbix y Grafana |
| **GG-IP2-Operadores** | Jeffrey, Álvaro | Solo lectura en Zabbix y Grafana: ven tableros y alertas, no cambian configuración |

Los permisos se dan **al grupo, nunca a la persona**. Agregar a alguien al equipo es meterlo al grupo; sacarlo es quitarlo de ahí.

## 5. Cómo valida cada sistema

| Sistema | Mecanismo | Configuración | Quién entra |
|---|---|---|---|
| Servidor Windows de la app (`vm-app-win`) | Unido al dominio | El grupo de administradores se agrega a *Administradores locales* | Administradores |
| Proxmox | **Dominio de autenticación de tipo Active Directory** | Servidor `dc01.ip2.local`, base `OU=IP2`, cuenta `svc-ldap`; cada grupo se asocia a un rol de Proxmox | Administradores (rol `Administrator`) |
| Zabbix | **Autenticación LDAP** | Host `dc01.ip2.local`, usuario de enlace `svc-ldap`; los grupos del dominio se mapean a grupos de usuarios de Zabbix | Administradores (edición) y operadores (solo lectura) |
| Grafana | **Autenticación LDAP** (`ldap.toml`) | Mismo servidor y cuenta; `group_mappings`: administradores → `Admin`, operadores → `Viewer` | Igual que Zabbix |
| VMs Linux (SSH) | **SSSD** unido al dominio (`realm join`) | Solo el grupo de administradores puede iniciar sesión; `sudo` para ese grupo | Administradores |
| n8n | **Cuenta local** | La validación contra LDAP es de la edición de pago | Se documenta como exclusión del alcance |

## 6. Política de contraseñas y bloqueo (RNF-09)

Se aplica con una política de grupo (GPO) sobre el dominio:

| Regla | Valor | Por qué |
|---|---|---|
| Longitud mínima | 12 caracteres | Requerimiento RNF-09 |
| Complejidad | Activada | Mayúsculas, minúsculas, números o símbolos |
| Vigencia máxima | 90 días | Rotación razonable para el periodo del proyecto |
| Historial | 5 contraseñas | Evita reutilizar la anterior |
| Bloqueo de cuenta | A los **5 intentos fallidos** | Requerimiento RNF-09 |
| Duración del bloqueo | 15 minutos | Frena la fuerza bruta sin dejar a nadie fuera todo el día |
| Auditoría | Inicios de sesión correctos y fallidos | Alimenta el monitoreo de seguridad |

## 7. Monitoreo del controlador de dominio (IP2-82)

| Qué | Cómo | Trigger |
|---|---|---|
| Disponibilidad de la VM y sus servicios (AD DS, DNS, Kerberos) | Plantilla *Windows by Zabbix agent* + estado de servicios | **T15**: servicio del dominio caído → High |
| Inicios de sesión fallidos | Ítem sobre el registro de seguridad de Windows (evento 4625) | **T16**: más de 10 en 5 minutos → Warning |
| Cuentas bloqueadas | Evento 4740 | **T17**: cualquier bloqueo → Warning con el nombre de la cuenta |

Estas alertas **solo notifican**: ninguna acción automática toca cuentas de usuario.

## 8. Riesgo R-14: si el controlador de dominio cae

Si el dominio no responde, nadie podría entrar a las herramientas. Por eso:

1. **Cada herramienta conserva una cuenta local de emergencia** (*break-glass*), con contraseña larga guardada fuera del repositorio, en `red/secrets/` o en el gestor del equipo.
2. **Respaldo diario del controlador de dominio** en Proxmox, con una restauración probada antes del E3.
3. **Zabbix vigila el dominio** (T15) para que la caída se sepa de inmediato.

## 9. Orden de implementación (E3)

1. **IP2-79** · Crear `vm-dc`, instalar AD DS y DNS, promover el dominio, crear unidades organizativas, cuentas y grupos.
2. **IP2-80** · Aplicar la GPO de contraseñas y bloqueo, y probarla con una cuenta de prueba.
3. **IP2-81** · Integrar en este orden: servidor Windows → Proxmox → Zabbix → Grafana → SSH de las VMs Linux. **Antes de cada integración, comprobar que la cuenta local de emergencia funciona.**
4. **IP2-82** · Monitorear el controlador y sus eventos de seguridad.
5. **IP2-83** (E4) · Probar el acceso por grupos: un administrador edita, un operador solo ve, y una cuenta sin grupo es rechazada en cada herramienta.

## 10. Evidencia para el entregable

| Evidencia | Dónde |
|---|---|
| Captura de *Usuarios y equipos de Active Directory* con las unidades y los grupos | 05 Evidencias |
| Captura de la política de grupo aplicada (`gpresult`) | 05 Evidencias |
| Inicio de sesión con una cuenta del dominio en cada herramienta | 05 Evidencias |
| Cuenta sin grupo rechazada, con el mensaje de error | 06 Pruebas (IP2-83) |
| Alerta de Zabbix por inicios de sesión fallidos | 05 Evidencias |
