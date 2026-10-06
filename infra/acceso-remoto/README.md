# Administración remota del laboratorio

Tarea: IP2-93. El profesor autorizó el 5 oct 2026 trabajar el servidor, el router y el switch a distancia.

**La idea:** una sola visita al laboratorio para dejar el servidor con Proxmox, con salida propia a Internet y con las consolas de R1 y SW1 conectadas. De ahí en adelante, todo se hace desde la casa.

> **Estado:** el script se probó en modo simulación (genera bien los archivos), pero **nunca ha corrido en un Proxmox real** y la sintaxis del cortafuegos no se pudo validar fuera del servidor. La primera corrida es la de la visita: por eso se hace en la consola física y guarda una copia de la red anterior.

## 1. Cómo queda

```
 Casa: portátil con Tailscale y MobaXterm
        │  túnel cifrado
        ▼
 Red de la universidad ───────────────┐
        │                             │
   tarjeta 2 (DHCP)              Gi0/0/0 (WAN)
 ┌───────────────┐                 ┌──────┐
 │  Servidor     │── USB consola ──│  R1  │
 │  Proxmox      │                 └──┬───┘ Gi0/0/1
 │  + Tailscale  │── USB consola ──┐  │ troncal
 └──────┬────────┘              ┌──┴──┴─┐
   tarjeta 1 (troncal) ─────────│  SW1  │ Gi0/2
                                └───────┘
```

| Camino | Para qué | Depende de R1 y SW1 |
|---|---|---|
| Tarjeta 2 → red de la universidad | Por aquí sale Tailscale. Es el acceso **fuera de banda** | No |
| Cables de consola USB → R1 y SW1 | Entrar a los equipos de red aunque estén sin configurar o mal configurados | No |
| Tarjeta 1 → SW1 Gi0/2 | La red del proyecto: troncal con las VLAN, VMs en la VLAN 30 | Sí |

**Por qué dos caminos:** en el diseño, el servidor sale a Internet por R1. Si el túnel dependiera de eso, un error al configurar R1 o el troncal desde la casa dejaría a todos afuera hasta volver al laboratorio. Con la tarjeta 2 y las consolas, un error en la red se corrige desde la casa.

## 2. Antes de la visita

| | Qué | Detalle |
|---|---|---|
| ☐ | **Tailscale en la portátil** | En la consola de Tailscale, *Add device* → Windows. Iniciar sesión con la cuenta del proyecto |
| ☐ | **Verificación en dos pasos** en esa cuenta | Es la llave de entrada al laboratorio |
| ☐ | **USB con Proxmox VE** | ISO de proxmox.com/downloads, grabada con Rufus en modo DD o con balenaEtcher |
| ☐ | **Dos cables de consola** | USB mini-B para el R1 (el ISR 4221 trae puerto de consola USB) y RJ45 → USB para el SW1 |
| ☐ | **Cables UTP**, al menos cuatro | Ver el cableado del paso 3 |
| ☐ | Un **switch pequeño sin gestión** | Por si solo hay un punto de red de la universidad: se necesitan dos (R1 y el servidor) |
| ☐ | Cinta y marcador | Etiquetar equipos y cables |
| ☐ | El celular con datos | Para la prueba final, que se hace **sin** la red de la universidad |

## 3. En el laboratorio, en orden

### 3.1 Equipos, BIOS y cables

1. Acordar con el profesor cuál router, switch y servidor son del grupo, y **etiquetarlos** (riesgo R-01).
2. En el BIOS del servidor: virtualización activada (VT-x o AMD-V) y **"encender al volver la corriente"** (*AC Power Recovery: On*). Sin eso, un corte de luz deja el servidor apagado y el acceso remoto muerto.
3. Cablear y etiquetar:

| Desde | Hacia | Nota |
|---|---|---|
| Servidor, tarjeta 2 | Punto de red de la universidad | Fuera de banda |
| R1 Gi0/0/0 | Punto de red de la universidad | WAN del proyecto |
| R1 Gi0/0/1 | SW1 Gi0/1 | Troncal |
| SW1 Gi0/2 | Servidor, tarjeta 1 | Troncal |
| Servidor, USB | R1, consola USB | Se queda conectado |
| Servidor, USB | SW1, consola RJ45 | Se queda conectado |

### 3.2 Instalar Proxmox

Arrancar desde el USB e instalar con los valores por defecto, salvo:

| Pantalla | Valor |
|---|---|
| País y zona horaria | Costa Rica |
| Contraseña de root | Fuerte, y **no** se anota en el repositorio ni en Confluence |
| Interfaz de gestión | La tarjeta conectada a la **red de la universidad**; aceptar la IP que propone |
| Nombre | `pve.ip2.local` |

Así el servidor queda con Internet apenas arranca, que es lo que se necesita para el paso siguiente.

### 3.3 Correr el script

En el teclado del servidor, como root:

```bash
curl -fsSLo preparar.sh https://raw.githubusercontent.com/Proyect-integrador-2/Integrador2/main/infra/acceso-remoto/preparar-proxmox.sh
bash preparar.sh                         # lista las tarjetas
bash preparar.sh --oob eno2 --lab eno1   # con los nombres reales
```

Para saber cuál tarjeta es cuál: desconectar un cable y volver a listar; la que pasa a `down` es la de ese cable.

El script deja la red como en el diagrama, cierra la tarjeta fuera de banda, instala Tailscale y muestra un **código QR**: se escanea con el celular y se inicia sesión con la cuenta del proyecto.

Después, en la consola de Tailscale → *Machines* → `pve-ip2` → *Edit route settings*: **aprobar las cuatro redes** `10.10.x.0/24`.

### 3.4 Consolas

```bash
consola                                    # lista los puertos serie
consola asignar r1  /dev/serial/by-id/...  # el que dice Cisco es el del router
consola asignar sw1 /dev/serial/by-id/...
consola r1                                 # Enter para ver el prompt. Salir: Ctrl-A y luego Ctrl-X
```

En cada equipo, entrar a modo privilegiado con `enable`. **Si pide una contraseña que nadie conoce, la recuperación se hace ahí mismo**: necesita apagar y encender el equipo, y eso no se puede hacer desde la casa.

### 3.5 Llave SSH e inventario

Desde la portátil (PowerShell), para entrar sin contraseña de ahí en adelante:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@10.10.30.10 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

Y los datos que le faltan al inventario (IP2-14) y al dimensionamiento (IP2-31):

```bash
pveversion; lscpu | grep -E 'Model name|^CPU\(s\)'; free -h; lsblk -d -o NAME,SIZE,MODEL
dmidecode -s system-product-name; dmidecode -s system-serial-number
```

### 3.6 No irse sin comprobar esto

Con la portátil conectada a los **datos del celular**, no a la red de la universidad:

| | Prueba | Esperado |
|---|---|---|
| ☐ | `ping 10.10.30.10` | Responde |
| ☐ | Abrir `https://10.10.30.10:8006` | Panel de Proxmox |
| ☐ | `ssh root@10.10.30.10` | Entra sin pedir contraseña |
| ☐ | `consola r1` y `consola sw1` | Prompt de cada equipo |
| ☐ | `reboot` del servidor | Vuelve a aparecer en línea en Tailscale sin tocar nada |
| ☐ | Desconectar y reconectar la corriente del servidor | Enciende solo y vuelve a Tailscale |
| ☐ | Foto del rack con las etiquetas y los cables | Evidencia, y referencia si alguien los mueve |

## 4. Desde la casa

| Qué | Cómo |
|---|---|
| Panel de Proxmox | `https://10.10.30.10:8006` en el navegador |
| Terminal del servidor | MobaXterm → *Session* → SSH → `10.10.30.10`, usuario `root`, con la llave privada |
| Consola de R1 o SW1 | En esa terminal: `tmux new -A -s red` y adentro `consola r1` |
| VMs y consolas web | Por su IP de la VLAN 30, cuando existan |

**Reglas para tocar la red a distancia:**

1. Siempre dentro de `tmux`: si se cae la conexión, la sesión de consola sigue abierta.
2. Pegar la configuración **por bloques pequeños**. La consola va a 9600 baudios y pierde caracteres si se pega todo de golpe.
3. Antes de un cambio riesgoso en un equipo ya configurado: `reload in 10`. Si todo salió bien, `reload cancel` y `write memory`. Si se perdió el control, el equipo vuelve solo a la configuración guardada.
4. Las configuraciones con contraseñas reales (`red/secrets/*-listo.txt`) viajan por el túnel, nunca por el repositorio.

## 5. Controles de seguridad

El acceso remoto es una entrada nueva a la plataforma. Estos controles la acotan y van a la sección de seguridad del E3:

| Control | Cómo |
|---|---|
| Quién entra | Solo las cuentas invitadas a la red de Tailscale del proyecto. Cada dispositivo aparece en la consola y se puede retirar |
| Autenticación | La cuenta con verificación en dos pasos, y SSH solo con llave |
| Tarjeta fuera de banda cerrada | No acepta conexiones entrantes: solo las respuestas a lo que el servidor inició (`/etc/ip2-oob.nft`) |
| Sin atajos | El servidor no reenvía tráfico entre la universidad y el laboratorio en ningún sentido. Las VMs siguen saliendo por R1 |
| Origen identificable | Todo lo remoto llega al laboratorio como `10.10.30.10` |
| Cortar el acceso | `tailscale down` en el servidor, o quitar el equipo en la consola de Tailscale |
| Al terminar el proyecto | Se retira el servidor de Tailscale y se desconecta la tarjeta 2 |

**Lo que este acceso cambia en el diseño del E2:** para administrar por SSH desde la casa, además de por consola, R1 y SW1 deben aceptar al servidor como origen de administración:

```
! R1
ip access-list standard ACL-SSH-ADMIN
 permit host 10.10.30.10
! SW1
access-list 40 permit host 10.10.30.10
```

Lo mismo en el firewall de cada VM (sección 11.3 del E2): `10.10.30.10` se suma a la VLAN 40 como origen permitido de administración.

## 6. Si algo falla

| Síntoma | Qué revisar |
|---|---|
| El script avisa que no hay salida a Internet | El cable de la tarjeta 2 y que ese punto de red entregue dirección por DHCP. Probar con otro punto |
| Tailscale no conecta | Que la red de la universidad no lo bloquee: `tailscale netcheck`. Si lo bloquea, avisar al profesor antes de buscar alternativas |
| La red del servidor quedó mal tras el script | `cp /etc/network/interfaces.antes-ip2-<fecha> /etc/network/interfaces` y `ifreload -a` |
| Desde la casa responde Tailscale pero no `10.10.30.10` | Las rutas sin aprobar en la consola de Tailscale |
| `consola` no lista puertos | Los cables USB; `dmesg | tail` muestra si el sistema los vio |
| El servidor no vuelve tras un corte de luz | El ajuste del BIOS del paso 3.1 |
