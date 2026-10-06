# Qué hacer en el laboratorio de la U

Guion de la sesión presencial. El tiempo en el laboratorio es limitado (riesgo R-03), así que los pasos están en orden de prioridad: si hay que cortar, se corta por el final.

Tareas que se cierran con esta visita: IP2-14 (inventario), IP2-27 y IP2-28 (configurar switch y router), IP2-29 (validación).

## 0. Antes de salir de la casa

| | Qué llevar | Por qué |
|---|---|---|
| ☐ | **Cable de consola** RJ45 → USB (y el adaptador si la laptop no tiene puerto serial) | Es la única forma de entrar a equipos sin configurar |
| ☐ | **Driver del cable** ya instalado y probado | El driver Prolific/FTDI a veces pide reiniciar: no se quiere gastar tiempo del laboratorio en eso |
| ☐ | **PuTTY o Tera Term** instalado | Serial, **9600 baudios, 8N1, sin control de flujo** |
| ☐ | Los archivos `red/secrets/R1-listo.txt` y `red/secrets/SW1-listo.txt` **en la laptop o en un USB** | Son las configuraciones con las contraseñas reales. **No están en GitHub**: si se llega con solo el repo, se llega con los `CAMBIAR-` |
| ☐ | Un USB booteable con **Proxmox VE** | Si sobra tiempo y el servidor está libre |
| ☐ | Cables UTP | Para las dos PC y el servidor |
| ☐ | El celular cargado | Todas las evidencias del E2 y E3 son fotos y capturas |

**Pendiente de la casa, no del laboratorio:** guardar `red/packet-tracer/integrador2-red.pkt` y correr las validaciones V1–V11 en Packet Tracer. Es lo que evita descubrir errores de configuración con el reloj corriendo.

## 1. Acordar cuáles equipos son del grupo (riesgo R-01)

En el rack hay **tres ISR 4221 y varios 2960** compartidos entre grupos.

1. Preguntarle al profesor cuál router, cuál switch y cuál servidor le tocan al grupo.
2. **Etiquetarlos** (cinta y marcador) y anotar la posición en el rack.
3. Tomarles foto con la etiqueta puesta.

Sin esto, el trabajo del día se lo puede borrar otro grupo.

## 2. Inventario (IP2-14) — el paso que desbloquea todo lo demás

Conectar la consola y correr:

```
show version
show inventory
show ip interface brief
```

| | Dato | Dónde se usa |
|---|---|---|
| ☐ | **Router:** versión de IOS XE, RAM, licencia | Confirmar el modelo y si la imagen soporta SSH |
| ☐ | **Switch:** versión de IOS y **si la imagen dice `k9`** (p. ej. `c2960-lanbasek9-mz`) | **Sin `k9` no hay SSH.** Se administra por consola y se documenta como limitación |
| ☐ | **Servidor: RAM, núcleos, discos, cantidad de NIC, service tag** | ⚠️ **Es el dato crítico.** De la RAM depende el reparto de las 7 VMs |
| ☐ | Fotos de los tres equipos y de sus etiquetas | Evidencia del E1 y del E2 |

### Qué hacer con el dato de la RAM (decidir ahí mismo)

| RAM del servidor | Qué se hace |
|---|---|
| ≥ 32 GB | Las 7 VMs tal cual el diseño |
| 24–32 GB | Grafana se une a `vm-zabbix` y `vm-rpa` baja a 3 GB |
| 16–24 GB | Además n8n pasa a contenedor dentro de `vm-zabbix` y `vm-app-win` baja a 3 GB |
| < 16 GB | La aplicación Windows y el controlador de dominio se juntan en **una sola VM** |

La tabla completa está en `docs/diseno/virtualizacion.md`. Anotar cuál escenario aplica y avisar al grupo.

## 3. Configurar el switch SW1 (IP2-27)

Primero el switch, porque el router necesita el trunk para que sus subinterfaces sirvan de algo.

1. Consola al switch, `enable`, `configure terminal`.
2. Pegar **`red/secrets/SW1-listo.txt`**, no el del repositorio.
3. Si la imagen **no tiene `k9`**, van a fallar `crypto key generate rsa` e `ip ssh version 2`. No es grave: se salta esa parte, se deja la administración por consola y se anota en el informe.
4. `end` y **`write memory`**.
5. Comprobar: `show vlan brief`, `show interfaces trunk`, `show ip interface brief` (la SVI de la VLAN 99 debe quedar en 10.10.99.2).

## 4. Configurar el router R1 (IP2-28)

> ⚠️ **Esperar a que el router termine de arrancar antes de pegar nada.** El ISR 4221 tarda varios minutos y, si se pega mientras arranca, las líneas `interface ...` se pierden y las direcciones IP caen en la interfaz equivocada. Pasó en el ensayo de Packet Tracer. Se reconoce porque `Gi0/0/0` aparece con una IP de VLAN en vez de la de la WAN.

1. Si aparece el diálogo de configuración inicial, responder **`no`**.
2. `enable`, `configure terminal`.
3. Pegar **`red/secrets/R1-listo.txt`**.
   - Las dos líneas marcadas `(Packet Tracer)` **se dejan comentadas**: en el laboratorio la WAN toma la dirección por DHCP de la red de la universidad y la ruta por defecto llega sola.
4. `end` y **`write memory`**.
5. Comprobar: `show ip interface brief` (las cinco subinterfaces de Gi0/0/1 con su `.1`), `show ip route` (debe existir la ruta por defecto), `show access-lists`.

**Si Gi0/0/0 no recibe dirección por DHCP:** preguntarle al profesor si el puerto de pared necesita registro o VLAN específica. Sin WAN no hay NAT ni salida a Internet, pero todo lo interno sí se puede probar y validar.

## 5. Cablear

| Origen | Puerto | Destino | Puerto |
|---|---|---|---|
| Red de la universidad | — | R1 | **Gi0/0/0** |
| R1 | **Gi0/0/1** | SW1 | Gi0/1 |
| Servidor (Proxmox) | NIC 1 | SW1 | Gi0/2 |
| PC-ADMIN | — | SW1 | Fa0/1 |
| PC-CLIENTE | — | SW1 | Fa0/5 |

PC-ADMIN va con IP fija **10.10.40.10**, máscara 255.255.255.0, gateway 10.10.40.1. PC-CLIENTE se deja en **automático**: la dirección se la da el router.

## 6. Validar (IP2-29) y dejar la evidencia

Las mismas pruebas del ensayo, ahora sobre equipo real. Anotar el resultado de cada una en la tabla de `README.md` §6.

| # | Prueba | Esperado |
|---|---|---|
| V1 | PC-CLIENTE recibe dirección por DHCP | 10.10.20.100 o superior |
| V2 | PC-CLIENTE abre `http://10.10.30.11` | ✅ Responde |
| V3 | PC-CLIENTE hace ping a 10.10.30.12 | ❌ Bloqueado |
| V4 | PC-CLIENTE hace ping a 10.10.40.10 | ❌ Bloqueado |
| V5 | PC-CLIENTE llega a 10.10.99.2 | ❌ Bloqueado |
| V6 | PC-ADMIN alcanza usuarios y servidores | ✅ Responde |
| V7 | PC-ADMIN entra por SSH a SW1 | ✅ Acceso (si hay imagen `k9`) |
| V8 | PC-CLIENTE hace ping a 8.8.8.8 | ✅ Responde por NAT |
| V9 | `show ip nat translations` en R1 | Traducciones activas |
| V10 | PC-CLIENTE abre `http://10.10.30.16` | ✅ Responde (cuando exista la VM Windows) |
| V11 | PC-CLIENTE hace ping a 10.10.30.17 | ❌ Bloqueado (cuando exista el controlador) |

V2, V10 y V11 dependen de que las VMs existan; si el servidor todavía no está montado, se dejan pendientes.

**Evidencia que hay que sacar antes de irse:**

- ☐ `show running-config` del router y del switch, copiado a un archivo de texto
- ☐ Capturas de las validaciones que dieron resultado
- ☐ Fotos del rack con los equipos etiquetados y cableados

## 7. Si sobra tiempo: el servidor

1. Instalar **Proxmox VE** desde el USB.
2. IP de gestión **10.10.30.10/24**, gateway 10.10.30.1.
3. Bridge `vmbr0` con **VLAN aware** activado (el servidor entra por un trunk, no por un puerto de acceso).
4. Comprobar el panel web en `https://10.10.30.10:8006` desde PC-ADMIN.

Crear las VMs no es para esta visita: con Proxmox instalado y alcanzable, se puede seguir desde la casa.

## 8. Al volver

- Pasar los resultados de V1–V11 a `README.md` §6 y hacer commit.
- Subir las fotos y los `show running-config` a Confluence → 05 Evidencias.
- Actualizar la página *Inventario de recursos* (01 Gestión) con los datos del servidor.
- Mover IP2-14, IP2-27, IP2-28 e IP2-29 según lo que se haya logrado.

**Lo que nunca se sube:** contraseñas, el contenido de `red/secrets/` ni los `show running-config` sin limpiar. Antes de publicar cualquier configuración, reemplazar las contraseñas por `CAMBIAR-`.
