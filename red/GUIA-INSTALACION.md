# Guía de instalación en el laboratorio

**Lunes 12 de octubre de 2026** · Integrador II · tareas IP2-32, IP2-93, IP2-27 e IP2-28

Los bloques grises se pegan tal cual en el equipo. Lo <mark>resaltado en amarillo</mark> son notas: **no se pega**.

Orden: primero el servidor, porque con él queda el acceso desde la casa. **Si el tiempo no alcanza, los pasos 4 a 7 se hacen después por la consola remota.** Los pasos 1 a 3 solo se pueden hacer ahí.

<figure><img src="../docs/diagramas/arquitectura-fisica.png" alt="Arquitectura física"><figcaption>Cableado del proyecto. Faltan en el dibujo los tres cables del acceso remoto: están en la tabla del paso 1</figcaption></figure>

## 1. Cables

| Desde | Hacia | Para qué |
|---|---|---|
| R1 **Gi0/0/0** | Punto de red de la U | Salida a Internet del proyecto |
| R1 **Gi0/0/1** | SW1 **Gi0/1** | Troncal |
| SW1 **Gi0/2** | Servidor, **tarjeta 1** | Troncal hacia las VMs |
| Servidor, **tarjeta 2** | Punto de red de la U | Acceso remoto, sin pasar por R1 |
| Servidor, USB | R1, consola USB | Se queda conectado |
| Servidor, USB | SW1, consola RJ45 | Se queda conectado |
| PC-ADMIN | SW1 **Fa0/1** | Administración |
| PC-CLIENTE | SW1 **Fa0/5** | Usuario de prueba |

<mark>Se necesitan DOS puntos de red de la U: uno para R1 y otro para el servidor. Si solo hay uno, usar el switch pequeño</mark>

<mark>Antes de tocar nada: confirmar con el profesor cuál router, switch y servidor son del grupo, y etiquetarlos</mark>

## 2. Servidor: Proxmox

<mark>En el BIOS: virtualización activada y "encender al volver la corriente" (AC Power Recovery: On)</mark>

Arrancar desde el USB e instalar con los valores por defecto, salvo:

| Pantalla | Valor |
|---|---|
| País y zona horaria | Costa Rica |
| Contraseña de root | Fuerte. No se anota en el repositorio |
| Interfaz de gestión | La tarjeta conectada a la **red de la U**. Aceptar la IP que propone |
| Nombre | `pve.ip2.local` |

Al terminar, en el teclado del servidor, entrar como root y correr:

```
curl -fsSLo preparar.sh https://raw.githubusercontent.com/Proyect-integrador-2/Integrador2/main/infra/acceso-remoto/preparar-proxmox.sh
bash preparar.sh
```

<mark>La dirección del primer comando va en UNA sola línea, sin espacios: raw.githubusercontent.com/Proyect-integrador-2/Integrador2/main/infra/acceso-remoto/preparar-proxmox.sh</mark>

<mark>El segundo comando lista las tarjetas de red. Para saber cuál es cuál: desconectar un cable y volver a correrlo; la que pasa a "down" es la de ese cable</mark>

```
bash preparar.sh --oob TARJETA-DE-LA-U --lab TARJETA-DEL-SWITCH
```

<mark>Ejemplo: bash preparar.sh --oob eno2 --lab eno1. Al final muestra un código QR: escanearlo con el celular e iniciar sesión en Tailscale con la cuenta del proyecto</mark>

Después, en la consola de Tailscale → Machines → `pve-ip2` → Edit route settings: **aprobar las cuatro redes 10.10.x.0/24**.

<mark>El servidor queda en 10.10.30.10. El panel se abre en https://10.10.30.10:8006</mark>

Datos para el inventario (anotarlos o tomarles foto):

```
pveversion
lscpu | grep -E 'Model name|^CPU\(s\)'
free -h
lsblk -d -o NAME,SIZE,MODEL
dmidecode -s system-product-name
dmidecode -s system-serial-number
```

## 3. Consolas y prueba del acceso remoto

En el servidor:

```
consola
consola asignar r1 /dev/serial/by-id/PUERTO-DEL-ROUTER
consola asignar sw1 /dev/serial/by-id/PUERTO-DEL-SWITCH
consola r1
```

<mark>El primer comando lista los puertos; el que dice Cisco es el del router. Dentro de la consola: Enter para ver el prompt. Para salir: Ctrl-A y luego Ctrl-X</mark>

<mark>En cada equipo escribir "enable". Si pide una contraseña que nadie conoce, hay que recuperarla AHÍ: necesita apagar y encender el equipo</mark>

Desde la portátil, en PowerShell, para entrar sin contraseña de ahí en adelante:

```
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@10.10.30.10 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

**No irse sin comprobar esto**, con la portátil en los datos del celular (no en la red de la U):

| | Prueba | Esperado |
|---|---|---|
| ☐ | `ping 10.10.30.10` | Responde |
| ☐ | Abrir `https://10.10.30.10:8006` | Panel de Proxmox |
| ☐ | `ssh root@10.10.30.10` | Entra sin pedir contraseña |
| ☐ | `consola r1` y `consola sw1` | Prompt de cada equipo |
| ☐ | `reboot` del servidor | Vuelve solo a Tailscale |
| ☐ | Desconectar y reconectar la corriente | Enciende solo y vuelve a Tailscale |
| ☐ | Foto del rack con etiquetas y cables | Evidencia |

## 4. Switch SW1

<mark>Catalyst WS-C2960-24TT-L. Por consola: 9600 baudios, 8N1, sin control de flujo</mark>

Primero, ver qué tiene y qué imagen trae:

```
enable
show version
show running-config
```

<mark>Solo si el equipo ya está confirmado como del grupo y trae configuración vieja, borrarla:</mark>

```
write erase
delete flash:vlan.dat
reload
```

Cuando termine de arrancar:

```
enable
configure terminal
```

<mark>Cambiar las dos contraseñas marcadas CAMBIAR-. La versión con las contraseñas ya puestas está en la portátil: red/secrets/SW1-listo.txt</mark>

```
hostname SW1
no ip domain-lookup
ip domain-name integrador2.local
service password-encryption
enable secret CAMBIAR-ENABLE-SECRET
username admin privilege 15 secret CAMBIAR-ADMIN-SECRET
banner motd ^Acceso restringido - Integrador II - Solo personal autorizado^
```

<mark>Las cuatro VLAN del proyecto y la nativa sin uso. Administración es la 40, ya no la 10</mark>

```
vlan 20
 name USUARIOS
vlan 30
 name SERVIDORES
vlan 40
 name ADMINISTRACION
vlan 99
 name GESTION
vlan 999
 name NATIVA-SIN-USO
```

<mark>Gi0/1 va al router R1, puerto Gi0/0/1</mark>

```
interface GigabitEthernet0/1
 description Trunk hacia R1 Gi0/0/1
 switchport mode trunk
 switchport trunk native vlan 999
 switchport trunk allowed vlan 20,30,40,99,999
 switchport nonegotiate
 no shutdown
```

<mark>Gi0/2 va a la tarjeta 1 del servidor: la del laboratorio, no la que va a la red de la U</mark>

```
interface GigabitEthernet0/2
 description Trunk hacia Servidor Proxmox (bridge con VLAN)
 switchport mode trunk
 switchport trunk native vlan 999
 switchport trunk allowed vlan 30,99,999
 switchport nonegotiate
 no shutdown
```

<mark>Fa0/1 a Fa0/4. Aquí se conecta PC-ADMIN, en Fa0/1</mark>

```
interface range FastEthernet0/1 - 4
 description Acceso VLAN 40 - Administracion
 switchport mode access
 switchport access vlan 40
 switchport nonegotiate
 spanning-tree portfast
 spanning-tree bpduguard enable
 no shutdown
```

<mark>Fa0/5 a Fa0/12. Aquí se conecta PC-CLIENTE, en Fa0/5</mark>

```
interface range FastEthernet0/5 - 12
 description Acceso VLAN 20 - Usuarios
 switchport mode access
 switchport access vlan 20
 switchport nonegotiate
 switchport port-security
 switchport port-security maximum 2
 switchport port-security violation restrict
 switchport port-security mac-address sticky
 spanning-tree portfast
 spanning-tree bpduguard enable
 no shutdown
```

<mark>En el laboratorio no se usan: el servidor entra por el troncal Gi0/2</mark>

```
interface range FastEthernet0/13 - 20
 description Acceso VLAN 30 - Servidores
 switchport mode access
 switchport access vlan 30
 switchport nonegotiate
 spanning-tree portfast
 spanning-tree bpduguard enable
 no shutdown
```

<mark>Quedan apagados</mark>

```
interface range FastEthernet0/21 - 24
 description Sin uso
 switchport mode access
 switchport access vlan 999
 shutdown
```

<mark>La IP del switch queda en 10.10.99.2</mark>

```
interface Vlan1
 no ip address
 shutdown
interface Vlan99
 description Gestion del switch
 ip address 10.10.99.2 255.255.255.0
 no shutdown
ip default-gateway 10.10.99.1
```

<mark>Antes, verificar con show version que la imagen diga k9. Si no lo dice, crypto key da error: saltar este bloque y anotarlo</mark>

```
access-list 40 remark SSH solo desde Administracion
access-list 40 permit 10.10.40.0 0.0.0.255
crypto key generate rsa general-keys modulus 2048
ip ssh version 2
line console 0
 login local
 exec-timeout 10 0
 logging synchronous
line vty 0 15
 login local
 transport input ssh
 access-class 40 in
 exec-timeout 10 0
```

<mark>SIN ENSAYAR. Pegarlo de último y por partes. Si un comando responde % Invalid input, anotarlo y seguir con el siguiente</mark>

```
no ip http server
no ip http secure-server
service timestamps log datetime msec
logging buffered 16384 informational
login block-for 120 attempts 5 within 60
login quiet-mode access-class 40
login on-failure log
login on-success log
ip dhcp snooping
ip dhcp snooping vlan 20
no ip dhcp snooping information option
ip arp inspection vlan 20
interface GigabitEthernet0/1
 ip dhcp snooping trust
 ip arp inspection trust
interface range FastEthernet0/5 - 12
 ip dhcp snooping limit rate 15
 storm-control broadcast level 5.00
 storm-control action trap
```

<mark>Cambiar la comunidad marcada CAMBIAR-. Los dos últimos comandos guardan la configuración</mark>

```
access-list 20 remark SNMP solo desde Zabbix
access-list 20 permit host 10.10.30.12
snmp-server community CAMBIAR-SNMP-COMMUNITY RO 20
snmp-server location Laboratorio UTN - Rack Integrador II
snmp-server contact Equipo Integrador II
end
write memory
```


Comprobar:

```
show vlan brief
show interfaces trunk
show ip interface brief
```

<mark>Esperado: VLAN 20, 30, 40, 99 y 999 creadas; Gi0/1 y Gi0/2 en trunk; Vlan99 con 10.10.99.2</mark>

## 5. Router R1

<mark>Cisco ISR 4221. Esperar a que termine de arrancar ANTES de pegar: si se pega mientras arranca, las direcciones caen en la interfaz equivocada</mark>

```
enable
show version
show running-config
```

<mark>Solo si trae configuración vieja y el equipo es del grupo:</mark>

```
write erase
reload
```

Cuando termine de arrancar:

```
enable
configure terminal
```

<mark>Cambiar las dos contraseñas marcadas CAMBIAR-. La versión con las contraseñas ya puestas está en la portátil: red/secrets/R1-listo.txt</mark>

```
hostname R1
no ip domain-lookup
ip domain-name integrador2.local
service password-encryption
enable secret CAMBIAR-ENABLE-SECRET
username admin privilege 15 secret CAMBIAR-ADMIN-SECRET
banner motd ^Acceso restringido - Integrador II - Solo personal autorizado^
```

<mark>Gi0/0/0 va al punto de red de la U. Toma la IP por DHCP</mark>

```
interface GigabitEthernet0/0/0
 description WAN - Red de la universidad
 ip address dhcp
 ip nat outside
 no cdp enable
 no ip proxy-arp
 no shutdown
```

<mark>Gi0/0/1 va a SW1 Gi0/1. Una subinterfaz por VLAN; la .1 de cada red es su gateway</mark>

```
interface GigabitEthernet0/0/1
 description Trunk hacia SW1 Gi0/1
 no ip address
 no shutdown
interface GigabitEthernet0/0/1.40
 description VLAN 40 - ADMINISTRACION
 encapsulation dot1Q 40
 ip address 10.10.40.1 255.255.255.0
 ip nat inside
interface GigabitEthernet0/0/1.20
 description VLAN 20 - USUARIOS
 encapsulation dot1Q 20
 ip address 10.10.20.1 255.255.255.0
 ip nat inside
 ip access-group ACL-USUARIOS-IN in
interface GigabitEthernet0/0/1.30
 description VLAN 30 - SERVIDORES
 encapsulation dot1Q 30
 ip address 10.10.30.1 255.255.255.0
 ip nat inside
interface GigabitEthernet0/0/1.99
 description VLAN 99 - GESTION
 encapsulation dot1Q 99
 ip address 10.10.99.1 255.255.255.0
 ip nat inside
interface GigabitEthernet0/0/1.999
 description VLAN 999 - NATIVA SIN USO
 encapsulation dot1Q 999 native
```

<mark>Solo los usuarios reciben IP automática, de la .100 a la .200</mark>

```
ip dhcp excluded-address 10.10.20.1 10.10.20.99
ip dhcp excluded-address 10.10.20.201 10.10.20.254
ip dhcp pool VLAN20-USUARIOS
 network 10.10.20.0 255.255.255.0
 default-router 10.10.20.1
 dns-server 8.8.8.8
 exit
```

<mark>Los usuarios solo llegan a la aplicación (10.10.30.11 y 10.10.30.16, puertos 80 y 443) y a Internet</mark>

```
ip access-list extended ACL-USUARIOS-IN
 remark DHCP hacia el router
 permit udp any any eq bootps
 remark Ping al gateway (diagnostico basico)
 permit icmp 10.10.20.0 0.0.0.255 host 10.10.20.1
 remark Unico servicio permitido: la aplicacion web, en sus dos ambientes
 remark   10.10.30.11 = instancia Linux (contenedores) | 10.10.30.16 = instancia Windows Server (RF-19)
 permit tcp 10.10.20.0 0.0.0.255 host 10.10.30.11 eq www
 permit tcp 10.10.20.0 0.0.0.255 host 10.10.30.11 eq 443
 permit tcp 10.10.20.0 0.0.0.255 host 10.10.30.16 eq www
 permit tcp 10.10.20.0 0.0.0.255 host 10.10.30.16 eq 443
 remark Respuestas a conexiones iniciadas por Administracion (soporte remoto)
 permit tcp 10.10.20.0 0.0.0.255 10.10.40.0 0.0.0.255 established
 permit icmp 10.10.20.0 0.0.0.255 10.10.40.0 0.0.0.255 echo-reply
 remark Bloqueo de redes internas
 deny ip 10.10.20.0 0.0.0.255 10.10.40.0 0.0.0.255
 deny ip 10.10.20.0 0.0.0.255 10.10.30.0 0.0.0.255
 deny ip 10.10.20.0 0.0.0.255 10.10.99.0 0.0.0.255
 remark Bloqueo de acceso al router por sus otras IP
 deny ip 10.10.20.0 0.0.0.255 host 10.10.40.1
 deny ip 10.10.20.0 0.0.0.255 host 10.10.30.1
 deny ip 10.10.20.0 0.0.0.255 host 10.10.99.1
 remark Internet
 permit ip 10.10.20.0 0.0.0.255 any
 exit
```

<mark>Las cuatro redes salen a Internet con la IP de la WAN</mark>

```
ip access-list standard ACL-NAT-INTERNAS
 permit 10.10.40.0 0.0.0.255
 permit 10.10.20.0 0.0.0.255
 permit 10.10.30.0 0.0.0.255
 permit 10.10.99.0 0.0.0.255
 exit
ip nat inside source list ACL-NAT-INTERNAS interface GigabitEthernet0/0/0 overload
```

<mark>SSH al router solo desde la red de Administración</mark>

```
ip access-list standard ACL-SSH-ADMIN
 permit 10.10.40.0 0.0.0.255
 exit
crypto key generate rsa general-keys modulus 2048
ip ssh version 2
line console 0
 login local
 exec-timeout 10 0
 logging synchronous
line vty 0 4
 login local
 transport input ssh
 access-class ACL-SSH-ADMIN in
 exec-timeout 10 0
```

<mark>SIN ENSAYAR. Pegarlo de último y por partes. Si un comando responde % Invalid input, anotarlo y seguir con el siguiente</mark>

```
no ip http server
no ip http secure-server
service timestamps log datetime msec
logging buffered 16384 informational
security passwords min-length 10
login block-for 120 attempts 5 within 60
login quiet-mode access-class ACL-SSH-ADMIN
login on-failure log
login on-success log
```

<mark>Cambiar la comunidad marcada CAMBIAR-. Los dos últimos comandos guardan la configuración</mark>

```
ip access-list standard ACL-SNMP-ZABBIX
 permit host 10.10.30.12
 exit
snmp-server community CAMBIAR-SNMP-COMMUNITY RO ACL-SNMP-ZABBIX
snmp-server location Laboratorio UTN - Rack Integrador II
snmp-server contact Equipo Integrador II
end
write memory
```


Comprobar:

```
show ip interface brief
show ip route
ping 8.8.8.8
show ip nat translations
```

<mark>Esperado: Gi0/0/0 con una IP de la U; las subinterfaces .20, .30, .40 y .99 con su .1; el ping responde</mark>

## 6. Computadoras

PC-ADMIN (en SW1 Fa0/1):

```
IP:       10.10.40.10
Máscara:  255.255.255.0
Gateway:  10.10.40.1
DNS:      8.8.8.8
```

PC-CLIENTE (en SW1 Fa0/5):

```
Todo en automático (DHCP)
```

<mark>PC-CLIENTE debe recibir sola una dirección entre 10.10.20.100 y 10.10.20.200</mark>

Servidor Proxmox: `10.10.30.10`. Lo deja puesto el script del paso 2.

## 7. Pruebas

| # | Desde | Prueba | Esperado |
|---|---|---|---|
| V1 | PC-CLIENTE | `ipconfig` | IP 10.10.20.100 o superior |
| V3 | PC-CLIENTE | `ping 10.10.30.10` | ❌ No responde |
| V4 | PC-CLIENTE | `ping 10.10.40.10` | ❌ No responde |
| V5 | PC-CLIENTE | `ping 10.10.99.2` | ❌ No responde |
| V6 | PC-ADMIN | `ping 10.10.30.10` y a la IP de PC-CLIENTE | ✅ Responde |
| V7 | PC-ADMIN | `ssh -l admin 10.10.99.2` | ✅ Pide la contraseña |
| V8 | PC-CLIENTE | `ping 8.8.8.8` | ✅ Responde |
| — | PC-ADMIN | Abrir `https://10.10.30.10:8006` | ✅ Panel de Proxmox |
| — | PC-CLIENTE | Abrir `https://10.10.30.10:8006` | ❌ No abre |

<mark>La aplicación todavía no está en el servidor: http://10.10.30.11 se prueba cuando existan las VMs</mark>

Tomarle foto o captura a cada resultado: son la evidencia de las pruebas A-01 a A-03 del Entregable 3.
