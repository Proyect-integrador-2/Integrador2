# -*- coding: utf-8 -*-
"""Genera los tres diagramas del E2 en formato draw.io.

  arquitectura-fisica.drawio   que se cablea con que (router, switch, servidor, VMs)
  arquitectura-logica.drawio   VLAN, direccionamiento y trafico permitido
  flujo-monitoreo.drawio       que vigila Zabbix y que recupera n8n

Los .drawio quedan como fuente editable en docs/diagramas/.
"""
import html
import io
import sys

sys.stdout.reconfigure(encoding="utf-8")
DEST = (r"C:\Users\stiff\OneDrive\Documents\Universidad\III Cuatrimestre 2026"
        r"\Integrador 2\Proyecto\docs\diagramas")

# Paleta: una por VLAN, la misma en los tres diagramas
C = {
    "v10": ("#dae8fc", "#6c8ebf"),   # Administracion
    "v20": ("#fff2cc", "#d6b656"),   # Usuarios
    "v30": ("#d5e8d4", "#82b366"),   # Servidores
    "v99": ("#e1d5e7", "#9673a6"),   # Gestion
    "wan": ("#f5f5f5", "#666666"),
    "net": ("#ffffff", "#36393d"),   # equipos de red
    "win": ("#ffffff", "#0078d4"),   # VMs Windows
    "lin": ("#ffffff", "#82b366"),   # VMs Linux
    "zbx": ("#f8cecc", "#b85450"),
    "n8n": ("#ffe6cc", "#d79b00"),
}
OK, NO, INFO, MON = "#2e7d32", "#c62828", "#1f5fa8", "#6d4c41"


class Diagrama:
    def __init__(self, nombre, ancho, alto):
        self.nombre, self.ancho, self.alto = nombre, ancho, alto
        self.celdas, self.n = [], 2

    def _id(self):
        self.n += 1
        return f"c{self.n}"

    def caja(self, texto, x, y, w, h, relleno="#ffffff", borde="#36393d",
             extra="", tam=12, negrita=False, padre="1"):
        i = self._id()
        estilo = (f"rounded=1;whiteSpace=wrap;html=1;arcSize=6;fillColor={relleno};"
                  f"strokeColor={borde};fontSize={tam};fontColor=#1d2330;"
                  f"{'fontStyle=1;' if negrita else ''}{extra}")
        self.celdas.append(
            f'<mxCell id="{i}" value="{html.escape(texto, quote=True)}" style="{estilo}" '
            f'vertex="1" parent="{padre}"><mxGeometry x="{x}" y="{y}" width="{w}" '
            f'height="{h}" as="geometry"/></mxCell>')
        return i

    def zona(self, titulo, x, y, w, h, clave):
        """Contenedor con el titulo arriba a la izquierda (una VLAN, el servidor)."""
        relleno, borde = C[clave]
        return self.caja(titulo, x, y, w, h, relleno, borde,
                         "verticalAlign=top;align=left;spacingLeft=10;spacingTop=6;"
                         "strokeWidth=2;container=0;", tam=13, negrita=True)

    def nube(self, texto, x, y, w, h):
        i = self._id()
        estilo = ("ellipse;shape=cloud;whiteSpace=wrap;html=1;fillColor=#f5f5f5;"
                  "strokeColor=#666666;fontSize=12;fontColor=#1d2330;")
        self.celdas.append(
            f'<mxCell id="{i}" value="{html.escape(texto, quote=True)}" style="{estilo}" '
            f'vertex="1" parent="1"><mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" '
            f'as="geometry"/></mxCell>')
        return i

    def texto(self, texto, x, y, w, h, tam=11, extra=""):
        i = self._id()
        estilo = (f"text;html=1;whiteSpace=wrap;align=left;verticalAlign=top;"
                  f"fontSize={tam};fontColor=#1d2330;{extra}")
        self.celdas.append(
            f'<mxCell id="{i}" value="{html.escape(texto, quote=True)}" style="{estilo}" '
            f'vertex="1" parent="1"><mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" '
            f'as="geometry"/></mxCell>')
        return i

    def flecha(self, origen, destino, texto="", color="#36393d", punteada=False,
               ancho=2, sale=None, entra=None, puntos=(), doble=False, pos=None):
        """sale/entra: (x, y) relativos 0..1 sobre la caja; puntos: quiebres absolutos."""
        i = self._id()
        estilo = (f"edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;strokeColor={color};"
                  f"strokeWidth={ancho};fontSize=11;fontColor={color};"
                  f"labelBackgroundColor=#ffffff;endArrow=block;endFill=1;")
        if doble:
            estilo += "startArrow=block;startFill=1;"
        if punteada:
            estilo += "dashed=1;dashPattern=6 4;"
        if sale:
            estilo += f"exitX={sale[0]};exitY={sale[1]};exitDx=0;exitDy=0;"
        if entra:
            estilo += f"entryX={entra[0]};entryY={entra[1]};entryDx=0;entryDy=0;"
        geo = '<mxGeometry relative="1" as="geometry">'
        if pos is not None:
            geo = f'<mxGeometry x="{pos}" relative="1" as="geometry">'
        if puntos:
            geo += '<Array as="points">' + "".join(
                f'<mxPoint x="{px}" y="{py}"/>' for px, py in puntos) + "</Array>"
        geo += "</mxGeometry>"
        self.celdas.append(
            f'<mxCell id="{i}" value="{html.escape(texto, quote=True)}" style="{estilo}" '
            f'edge="1" parent="1" source="{origen}" target="{destino}">{geo}</mxCell>')
        return i

    def guardar(self):
        xml = (f'<mxfile host="drawio"><diagram name="{self.nombre}" id="{self.nombre}">'
               f'<mxGraphModel dx="1400" dy="900" grid="1" gridSize="10" guides="1" '
               f'page="1" pageScale="1" pageWidth="{self.ancho}" pageHeight="{self.alto}" '
               f'background="#ffffff"><root><mxCell id="0"/><mxCell id="1" parent="0"/>'
               + "".join(self.celdas) + "</root></mxGraphModel></diagram></mxfile>")
        ruta = f"{DEST}\\{self.nombre}.drawio"
        io.open(ruta, "w", encoding="utf-8").write(xml)
        print("escrito:", ruta, f"({len(self.celdas)} celdas)")


# ---------------------------------------------------------------------------
# 1. Arquitectura fisica
# ---------------------------------------------------------------------------
d = Diagrama("arquitectura-fisica", 1400, 960)
d.texto("<b>Arquitectura física</b> · qué se cablea con qué", 20, 10, 700, 30, tam=18)
d.texto("Equipo real del laboratorio (inventario IP2-14, fotos del 21 set 2026)",
        20, 40, 700, 20, tam=11, extra="fontColor=#555555;")

nube = d.nube("Red de la universidad<br>(salida a Internet)", 560, 70, 280, 100)
r1 = d.caja("<b>R1</b> · Cisco ISR 4221<br>IOS XE · router-on-a-stick, NAT/PAT, DHCP",
            550, 220, 300, 64, *C["net"], tam=12)
sw1 = d.caja("<b>SW1</b> · Catalyst WS-C2960-24TT-L<br>IOS 12.2(50)SE5 · 24 Fa + 2 Gi",
             550, 360, 300, 64, *C["net"], tam=12)

d.flecha(nube, r1, "Gi0/0/0 · WAN por DHCP", color=INFO, sale=(0.5, 0.92), entra=(0.5, 0))
d.flecha(r1, sw1, "Gi0/0/1 ↔ Gi0/1 · trunk 802.1Q<br>VLAN 20, 30, 40, 99 · nativa 999",
         color=INFO, ancho=3, sale=(0.5, 1), entra=(0.5, 0))

padm = d.caja("<b>PC-ADMIN</b><br>VLAN 40 · 10.10.40.10", 60, 470, 200, 56, *C["v10"])
pcli = d.caja("<b>PC-CLIENTE</b><br>VLAN 20 · IP por DHCP", 60, 580, 200, 56, *C["v20"])
d.flecha(sw1, padm, "Fa0/1 · acceso VLAN 40", sale=(0, 0.35), entra=(0.5, 0),
         puntos=[(160, 382)])
d.flecha(sw1, pcli, "Fa0/5 · acceso VLAN 20", sale=(0, 0.75), entra=(1, 0.5),
         puntos=[(380, 408), (380, 608)])

srv = d.zona("Servidor físico · <b>Proxmox VE</b> · gestión 10.10.30.10:8006",
             480, 490, 880, 420, "v30")
d.flecha(sw1, srv, "Gi0/2 · trunk VLAN 30, 99", color=INFO, ancho=3,
         sale=(0.83, 1), entra=(0.46, 0))
d.caja("<b>vmbr0</b> · bridge <i>VLAN aware</i> · cada VM con tag 30",
       500, 530, 840, 34, "#ffffff", "#82b366", tam=12)

lin = [
    ("vm-app", ".11", "Ubuntu 24.04<br>Docker: MS Motos + MySQL<br>Nginx (systemd)", "2 vCPU · 4 GB"),
    ("vm-zabbix", ".12", "Ubuntu 24.04<br>Zabbix + PostgreSQL", "2 vCPU · 4 GB"),
    ("vm-grafana", ".13", "Ubuntu 24.04<br>Grafana + plugin Zabbix", "1 vCPU · 2 GB"),
    ("vm-n8n", ".14", "Ubuntu 24.04<br>n8n (Docker)", "2 vCPU · 2 GB"),
    ("vm-rpa", ".15", "Ubuntu 24.04<br>Robot Framework<br>+ Chromium", "2 vCPU · 4 GB"),
]
for k, (n, ip, s, r) in enumerate(lin):
    d.caja(f"<b>{n}</b><br>10.10.30{ip}<br><font style='font-size:10px'>{s}</font>"
           f"<br><font color='#555555' style='font-size:10px'>{r}</font>",
           500 + k * 170, 585, 158, 138, *C["lin"], tam=11)

win = [
    ("vm-app-win", ".16", "Windows Server 2022<br>MS Motos como servicio<br>+ MySQL (RF-19)"),
    ("vm-dc", ".17", "Windows Server 2022<br>Active Directory + DNS<br>dc01.ip2.local (RF-21)"),
]
for k, (n, ip, s) in enumerate(win):
    d.caja(f"<b>{n}</b><br>10.10.30{ip}<br><font style='font-size:10px'>{s}</font>"
           f"<br><font color='#555555' style='font-size:10px'>2 vCPU · 4 GB</font>",
           500 + k * 170, 740, 158, 138, *C["win"], tam=11, extra="strokeWidth=2;")

d.texto("<b>Total asignado</b><br>13 vCPU · 24 GB RAM · 290 GB<br>"
        "<font color='#555555'>+ 2 GB y 20 GB para Proxmox.<br>"
        "Si la RAM real no alcanza, se aplica el plan<br>de ajuste por capacidad del servidor.</font>",
        860, 750, 470, 110, tam=12)

d.texto("<b>Leyenda</b><br>"
        "<font color='#1f5fa8'>━━</font> troncal 802.1Q (varias VLAN)<br>"
        "<font color='#36393d'>━━</font> puerto de acceso (una VLAN)<br>"
        "<font color='#82b366'>▢</font> VM Linux &nbsp; <font color='#0078d4'>▢</font> VM Windows",
        60, 700, 330, 90, tam=11)
d.guardar()


# ---------------------------------------------------------------------------
# 2. Arquitectura logica: segmentacion y trafico permitido
# ---------------------------------------------------------------------------
d = Diagrama("arquitectura-logica", 1400, 860)
d.texto("<b>Arquitectura lógica</b> · segmentación y tráfico permitido", 20, 10, 800, 30, tam=18)
d.texto("Todo el tráfico entre VLAN pasa por R1 (router-on-a-stick): cada VLAN tiene su subinterfaz "
        "y su gateway .1. La ACL <b>ACL-USUARIOS-IN</b> se aplica en la entrada de Gi0/0/1.20.",
        20, 40, 1300, 20, tam=11, extra="fontColor=#555555;")

inet = d.nube("Internet", 600, 70, 200, 90)
r1 = d.caja("<b>R1</b> · gateway .1 de cada VLAN<br>NAT/PAT · DHCP de la VLAN 20 · ACL",
            560, 195, 280, 60, *C["net"])
d.flecha(r1, inet, "NAT/PAT (overload) por Gi0/0/0", color=INFO, sale=(0.5, 0), entra=(0.5, 0.92))

z10 = d.zona("VLAN 40 · ADMINISTRACIÓN<br><font style='font-weight:normal'>10.10.40.0/24</font>",
             40, 320, 330, 170, "v10")
adm = d.caja("<b>PC-ADMIN</b> · 10.10.40.10<br>IP fija", 70, 400, 270, 50, "#ffffff", C["v10"][1])

z20 = d.zona("VLAN 20 · USUARIOS<br><font style='font-weight:normal'>10.10.20.0/24 · DHCP .100–.200</font>",
             40, 560, 330, 250, "v20")
cli = d.caja("<b>PC-CLIENTE</b><br>clientes y empleados del taller", 70, 640, 270, 70,
             "#ffffff", C["v20"][1])
d.texto("<font color='#2e7d32'><b>✔ solo TCP 80/443</b></font><br>hacia las dos instancias<br>de MS Motos",
        70, 725, 270, 60, tam=11)

z99 = d.zona("VLAN 99 · GESTIÓN<br><font style='font-weight:normal'>10.10.99.0/24</font>",
             1030, 320, 330, 170, "v99")
svi = d.caja("<b>SW1</b> · SVI 10.10.99.2<br>SSH y SNMP del switch", 1060, 400, 270, 50,
             "#ffffff", C["v99"][1])

d.zona("VLAN 30 · SERVIDORES<br><font style='font-weight:normal'>10.10.30.0/24 · IP fijas</font>",
       430, 320, 560, 490, "v30")
nodos30 = {}
filas = [
    ("proxmox", "Proxmox · .10", "panel de gestión :8006", 460, 390),
    ("graf", "vm-grafana · .13", "5 dashboards", 720, 390),
    ("zbx", "vm-zabbix · .12", "monitoreo · único origen SNMP", 460, 480),
    ("n8n", "vm-n8n · .14", "automatización", 720, 480),
    ("app", "<b>vm-app</b> · .11", "App Linux (Docker) · 80/443", 460, 610),
    ("rpa", "vm-rpa · .15", "cliente sintético", 720, 610),
    ("appwin", "<b>vm-app-win</b> · .16", "App Windows (servicio) · 80/443", 460, 700),
    ("dc", "<b>vm-dc</b> · .17", "<font color='#c62828'>AD + DNS · no visible a usuarios</font>", 720, 700),
]
for clave, t, s_, x, y in filas:
    publico = clave in ("app", "appwin")
    nodos30[clave] = d.caja(
        f"{t}<br><font color='#555555' style='font-size:10px'>{s_}</font>", x, y, 240, 62,
        "#e8f5e9" if publico else "#ffffff", OK if publico else C["v30"][1],
        extra="strokeWidth=3;" if publico else "", tam=12)
d.texto("<b>Visibles para usuarios:</b> solo las dos instancias de MS Motos (borde verde).",
        460, 568, 510, 24, tam=11)

# Trafico de usuarios: flechas cortas por el pasillo entre zonas
d.flecha(cli, nodos30["app"], "", color=OK, ancho=3, sale=(1, 0.3),
         entra=(0, 0.5), puntos=[(400, 661), (400, 641)])
d.flecha(cli, nodos30["appwin"], "", color=OK, ancho=3, sale=(1, 0.7),
         entra=(0, 0.5), puntos=[(415, 689), (415, 731)])
d.flecha(cli, adm, "✘ bloqueado", color=NO, punteada=True, sale=(0.85, 0), entra=(0.85, 1))

# Administracion
d.flecha(adm, svi, "✔ administración: acceso total · SSH solo desde la VLAN 40 (ACL-SSH-ADMIN)",
         color=INFO, sale=(0.85, 0), entra=(0.5, 0), puntos=[(300, 290), (1195, 290)])

d.texto("<b>Leyenda</b><br>"
        "<font color='#2e7d32'>━━</font> permitido para usuarios<br>"
        "<font color='#c62828'>╌╌</font> bloqueado por la ACL<br>"
        "<font color='#1f5fa8'>━━</font> administración",
        1040, 540, 320, 90, tam=11)
d.texto("<b>Bloqueado para la VLAN 20:</b> VLAN 40, VLAN 99, el resto de la VLAN 30 "
        "(incluido el controlador de dominio) y las IP del router en otras VLAN.",
        1040, 640, 320, 70, tam=11)
d.texto("<b>Por qué VLAN 99 y 999:</b> la gestión del switch no comparte red con los usuarios, "
        "y la nativa de los trunks es la 999 (sin uso), no la 1: evita el salto de VLAN por "
        "doble etiquetado.", 1040, 720, 320, 90, tam=11)
d.guardar()


# ---------------------------------------------------------------------------
# 3. Flujo de monitoreo y automatizacion
# ---------------------------------------------------------------------------
d = Diagrama("flujo-monitoreo", 1500, 900)
d.texto("<b>Monitoreo y automatización</b> · qué se vigila y qué se recupera solo",
        20, 10, 900, 30, tam=18)

fuentes = [
    ("Router R1 y switch SW1", "SNMP · interfaces 30 s"),
    ("Servidor Proxmox", "API HTTP · token de solo lectura"),
    ("VMs Linux (5)", "Zabbix agent 2"),
    ("VMs Windows (2)", "agente Windows · servicio MSMotos,<br>eventos 4625 / 4740 del dominio"),
    ("Contenedores y Nginx", "plugin Docker · systemd · 30 s"),
    ("MS Motos (2 instancias)", "escenarios web /api/health"),
    ("RPA (2 recorridos × 2 instancias)", "trapper · tiempo por paso"),
]
cajas_f = []
for k, (t, s) in enumerate(fuentes):
    cajas_f.append(d.caja(f"<b>{t}</b><br><font color='#555555' style='font-size:10px'>{s}</font>",
                          30, 80 + k * 100, 290, 70, "#ffffff", MON))

zbx = d.caja("<b>Zabbix</b> · vm-zabbix<br>ítems, umbrales y triggers T01–T17",
             470, 330, 250, 110, *C["zbx"], tam=13)
for c in cajas_f:
    d.flecha(c, zbx, "", color=MON, ancho=1.5, sale=(1, 0.5), entra=(0, 0.5))

graf = d.caja("<b>Grafana</b> · vm-grafana<br>5 dashboards: general, técnico,<br>red, experiencia y automatización",
              880, 80, 280, 84, "#ffffff", "#f57c00")
d.flecha(zbx, graf, "API de Zabbix (consulta)", color="#f57c00", sale=(0.5, 0),
         entra=(0, 0.5), puntos=[(595, 122)])

n8n = d.caja("<b>n8n</b> · vm-n8n<br>valida token, lista permitida<br>y límite de intentos",
             880, 330, 280, 110, *C["n8n"], tam=13)
d.flecha(zbx, n8n, "webhook con token<br>+ tag <i>remediation</i>", color="#d79b00", ancho=3,
         sale=(1, 0.35), entra=(0, 0.35))
d.flecha(n8n, zbx, "acknowledge +<br>métricas de ejecución", color="#d79b00", punteada=True,
         sale=(0, 0.75), entra=(1, 0.75))

acc = [
    ("vm-app", "SSH n8n-ops: <i>docker start msmotos-app</i><br>o <i>systemctl restart nginx</i>"),
    ("vm-app-win", "WinRM: <i>Start-Service MSMotos</i>"),
    ("R1 / SW1", "SSH n8n-net: reiniciar interfaz,<br>reactivar puerto, reload con respaldo"),
]
for k, (t, s) in enumerate(acc):
    c = d.caja(f"<b>{t}</b><br><font style='font-size:10px'>{s}</font>",
               1250, 250 + k * 110, 230, 80, "#ffffff", OK, extra="strokeWidth=2;")
    d.flecha(n8n, c, "", color=OK, ancho=2, sale=(1, 0.5), entra=(0, 0.5))
d.texto("<font color='#2e7d32'><b>Se recupera solo</b></font>", 1250, 215, 230, 24, tam=12)

tel = d.caja("<b>Telegram + correo</b><br>host, problema, severidad, hora,<br>acción y resultado (RNF-05)",
             880, 560, 280, 84, "#ffffff", INFO)
d.flecha(n8n, tel, "toda alerta, se haya<br>actuado o no", color=INFO, sale=(0.5, 1), entra=(0.5, 0))

d.caja("<font color='#2e7d32'><b>Se recupera solo</b></font> · causa conocida y acción que no destruye nada<br>"
       "T01 contenedor detenido · T03 Nginx detenido · T03-W servicio Windows detenido<br>"
       "T09 interfaz de acceso caída · T09b puerto err-disabled · T11 equipo de red saturado > 10 min",
       30, 790, 700, 80, "#e8f5e9", OK, extra="align=left;spacingLeft=10;", tam=11)
d.caja("<font color='#c62828'><b>Solo alerta</b></font> · hay que investigar antes de actuar<br>"
       "T06–T08 CPU, RAM, disco (el PDF prohíbe ampliar recursos) · T09-G enlace de gestión<br>"
       "T02 contenedor unhealthy · T04–T05 app · T10 enlace saturado · T11b equipo sin respuesta<br>"
       "T12–T14 RPA · T15–T17 dominio",
       760, 780, 720, 96, "#ffebee", NO, extra="align=left;spacingLeft=10;", tam=11)
d.texto("<b>Límites (RNF-10):</b> primero la acción menor · máx. 3 intentos cada 10 min por objetivo · "
        "1 reload por equipo por hora · si no se recupera, escala a una persona",
        470, 680, 700, 50, tam=11)
d.guardar()


# ---------------------------------------------------------------------------
# 4. Flujo de comunicacion: recorrido de una peticion y de la administracion
# ---------------------------------------------------------------------------
d = Diagrama("flujo-comunicacion", 1500, 760)
d.texto("<b>Flujo de comunicación</b> · recorrido de una petición y de la administración", 20, 10, 1000, 30, tam=18)
d.texto("Los números siguen el camino de un cliente que abre MS Motos. Los flujos entre herramientas "
        "(Zabbix, n8n, Grafana, RPA) están en la figura del monitoreo.", 20, 40, 1300, 20, tam=11,
        extra="fontColor=#555555;")

inet = d.nube("Internet", 560, 60, 180, 78)
cli = d.caja("<b>PC-CLIENTE</b><br>VLAN 20 · DHCP", 30, 180, 160, 64, *C["v20"])
sw = d.caja("<b>SW1</b><br>Fa0/5 acceso VLAN 20<br>troncales Gi0/1 y Gi0/2", 290, 180, 170, 64, *C["net"])
r1 = d.caja("<b>R1</b> · Gi0/0/1.20<br><b>ACL-USUARIOS-IN</b><br>enruta a la VLAN 30", 560, 180, 180, 64, *C["net"])
pve = d.caja("<b>Proxmox</b><br>vmbr0 · etiqueta 30", 840, 180, 150, 64, *C["v30"])

d.flecha(r1, inet, "NAT/PAT · Gi0/0/0", color=INFO, sale=(0.5, 0), entra=(0.5, 0.9))
d.flecha(cli, sw, "", color=OK, ancho=3, sale=(1, 0.5), entra=(0, 0.5))
d.flecha(sw, r1, "", color=OK, ancho=3, sale=(1, 0.5), entra=(0, 0.5))
d.flecha(r1, pve, "", color=OK, ancho=3, sale=(1, 0.5), entra=(0, 0.5))
etiq = "align=center;fontColor=#2e7d32;"
d.texto("① HTTP<br>80/443", 190, 146, 100, 34, tam=11, extra=etiq)
d.texto("② troncal<br>etiqueta 20", 460, 146, 100, 34, tam=11, extra=etiq)
d.texto("③ la ACL lo permite<br>etiqueta 30", 735, 146, 110, 34, tam=11, extra=etiq)

d.zona("vm-app · 10.10.30.11 · Linux", 1040, 110, 450, 200, "v30")
ngx = d.caja("<b>Nginx</b><br>systemd · :80", 1060, 180, 120, 64, "#ffffff", C["v30"][1])
app = d.caja("<b>msmotos-app</b><br>contenedor :3000", 1215, 180, 130, 64, "#ffffff", C["v30"][1])
db = d.caja("<b>msmotos-db</b><br>MySQL :3306", 1375, 180, 105, 64, "#ffffff", C["v30"][1])
d.texto("⑤ Nginx reenvía a 127.0.0.1:3000 · ⑥ MySQL por la red Docker <b>msmotos-backend</b>, "
        "datos en el volumen <b>msmotos-db-data</b>", 1060, 256, 420, 40, tam=10, extra="fontColor=#555555;")
d.flecha(pve, ngx, "", color=OK, ancho=3, sale=(1, 0.5), entra=(0, 0.5))
d.texto("④ .11:80", 990, 186, 60, 20, tam=11, extra=etiq)
d.flecha(ngx, app, "", color=OK, ancho=2, sale=(1, 0.5), entra=(0, 0.5))
d.flecha(app, db, "", color=OK, ancho=2, sale=(1, 0.5), entra=(0, 0.5))

d.zona("vm-app-win · 10.10.30.16 · Windows Server", 1040, 340, 450, 130, "win")
svc = d.caja("<b>Servicio MSMotos</b><br>Node.js · :80", 1060, 395, 190, 56, "#ffffff", C["win"][1])
my = d.caja("<b>MySQL</b><br>127.0.0.1:3306", 1290, 395, 180, 56, "#ffffff", C["win"][1])
d.flecha(pve, svc, "", color=OK, ancho=3, sale=(0.75, 1), entra=(0, 0.5), puntos=[(952, 423)])
d.texto("④ .16:80", 960, 396, 70, 20, tam=11, extra=etiq)
d.flecha(svc, my, "", color=OK, ancho=2, sale=(1, 0.5), entra=(0, 0.5))

bloq = d.caja("<font color='#c62828'><b>✘ Bloqueado para la VLAN 20</b></font><br>VLAN 40, VLAN 99, el resto de la VLAN 30 "
              "(incluido <b>vm-dc</b>) y las IP del router en otras VLAN", 30, 340, 430, 76, "#ffebee", NO, tam=11)
d.flecha(cli, bloq, "", color=NO, punteada=True, sale=(0.5, 1), entra=(0.19, 0))

adm = d.caja("<b>PC-ADMIN</b><br>VLAN 40 · 10.10.40.10", 30, 540, 170, 64, *C["v10"])
dest = d.caja("<b>Administración</b> (solo desde la VLAN 40, enrutado por R1)<br>"
              "SSH 22 a R1 y SW1 (10.10.99.2) · Proxmox 8006 · Zabbix 80 · Grafana 3000 · n8n 5678 · "
              "Escritorio remoto 3389 a las VMs Windows · SSH 22 a las VMs Linux",
              500, 520, 990, 104, "#ffffff", INFO, tam=12, extra="align=left;spacingLeft=12;")
d.flecha(adm, dest, "acceso total a la infraestructura", color=INFO, ancho=2, sale=(1, 0.5), entra=(0, 0.5))

d.texto("<b>Leyenda</b> · <font color='#2e7d32'>━━</font> petición de un cliente · "
        "<font color='#c62828'>╌╌</font> bloqueado por la ACL · "
        "<font color='#1f5fa8'>━━</font> administración y salida a Internet",
        30, 670, 1100, 24, tam=11)
d.guardar()
