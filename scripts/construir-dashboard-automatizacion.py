# -*- coding: utf-8 -*-
"""Construye monitoreo/grafana/ip2-automatizacion.json (IP2-77).

Reutiliza como plantilla los paneles ya probados de los otros tableros, para no
inventar el formato del plugin de Zabbix: los filtros van como expresión regular
y sobre el NOMBRE del ítem, nunca sobre la clave (ver monitoreo/grafana/README.md).
"""
import copy
import io
import json
import sys

sys.stdout.reconfigure(encoding="utf-8")
BASE = (r"C:\Users\stiff\OneDrive\Documents\Universidad\III Cuatrimestre 2026"
        r"\Integrador 2\Proyecto\monitoreo\grafana")

exp = json.load(io.open(BASE + r"\ip2-experiencia.json", encoding="utf-8"))
gen = json.load(io.open(BASE + r"\ip2-general.json", encoding="utf-8"))

P = {p["title"]: p for p in exp["panels"]}
G = {p["title"]: p for p in gen["panels"]}

t_stat_ok = P["Ultima ejecucion del RPA"]                  # stat con mapeo OK/FALLO
t_stat_pct = P["Tasa de exito del RPA (24 h)"]             # stat porcentaje
t_texto = P["Ultimo paso fallido y su error"]              # tabla desde consulta Text
t_serie = P["Duracion total del recorrido del RPA"]        # timeseries con umbral
t_triggers = G["Historial de eventos y recuperaciones automaticas"]


def target(panel_plantilla, host, item, indice=0, funciones=None):
    """Copia un target de la plantilla y le cambia los filtros."""
    t = copy.deepcopy(panel_plantilla["targets"][indice])
    t["host"] = {"filter": host}
    t["item"] = {"filter": item}
    t["group"] = {"filter": "Integrador II"}
    if funciones is not None:
        t["functions"] = funciones
    return t


def panel(plantilla, pid, titulo, desc, grid, targets, ajustes=None):
    p = copy.deepcopy(plantilla)
    p["id"] = pid
    p["title"] = titulo
    p["description"] = desc
    p["gridPos"] = grid
    p["targets"] = targets
    if ajustes:
        ajustes(p)
    return p


HOST = "/^Automatizaci/"   # nombre visible del host: "Automatización (n8n)"
RPA = "/rpa/"

paneles = []

# 1 · ¿Corrió lo que tenía que correr?
paneles.append(panel(
    t_stat_ok, 1,
    "Resultado del ultimo flujo de n8n",
    "Items trapper n8n.exec.status de cada flujo (servicio, contenedor, capacidad y los tres de red). Ver automatizacion.md seccion 6.",
    {"h": 6, "w": 8, "x": 0, "y": 0},
    [target(t_stat_ok, HOST, "/^n8n: resultado/")],
    lambda p: p["options"].update({"textMode": "value_and_name", "orientation": "horizontal"})))

# 2 · ¿Cuánto trabajó la automatización?
def _recuperaciones(p):
    p["options"]["reduceOptions"]["calcs"] = ["sum"]
    p["options"].update({"textMode": "value_and_name", "orientation": "horizontal",
                         "colorMode": "value", "graphMode": "none"})
    d = p["fieldConfig"]["defaults"]
    d.pop("max", None)
    d.pop("min", None)
    d.pop("unit", None)
    d["decimals"] = 0
    d["thresholds"] = {"mode": "absolute", "steps": [{"color": "blue", "value": None}]}


paneles.append(panel(
    t_stat_pct, 2,
    "Recuperaciones automaticas en el periodo, por tipo",
    "Suma de n8n.recovery.count por tipo: contenedor, servicio, interfaz, puerto y equipo.",
    {"h": 6, "w": 8, "x": 8, "y": 0},
    [target(t_stat_pct, HOST, "/^n8n: recuperaciones/", funciones=[])],
    _recuperaciones))


# 3 · ¿Hay algo que la automatización no logró arreglar?
def _pendientes(p):
    p["options"]["reduceOptions"]["calcs"] = ["sum"]
    p["options"].update({"textMode": "value_and_name", "orientation": "horizontal",
                         "colorMode": "background", "graphMode": "none"})
    d = p["fieldConfig"]["defaults"]
    d.pop("max", None)
    d.pop("min", None)
    d.pop("unit", None)
    d["decimals"] = 0
    d["thresholds"] = {"mode": "absolute",
                       "steps": [{"color": "green", "value": None}, {"color": "red", "value": 1}]}


paneles.append(panel(
    t_stat_pct, 3,
    "Acciones rechazadas y escalamientos a una persona",
    "n8n.rejected (accion fuera de la lista permitida o limite de intentos) y n8n.escalated. En verde cuando son cero.",
    {"h": 6, "w": 8, "x": 16, "y": 0},
    [target(t_stat_pct, HOST, "/^n8n: (acciones rechazadas|escalamientos)/", funciones=[])],
    _pendientes))


# 4 · ¿Se cumple el compromiso de recuperación? (RNF-02: menos de 5 minutos)
def _tiempo(p):
    d = p["fieldConfig"]["defaults"]
    d["unit"] = "s"
    d["thresholds"] = {"mode": "absolute",
                       "steps": [{"color": "green", "value": None}, {"color": "red", "value": 300}]}
    d["custom"]["drawStyle"] = "bars"
    d["custom"]["fillOpacity"] = 60


paneles.append(panel(
    t_serie, 4,
    "Tiempo desde la deteccion hasta la recuperacion",
    "n8n.recovery.seconds. El umbral rojo son 300 s: el RNF-02 compromete recuperar en menos de 5 minutos.",
    {"h": 9, "w": 12, "x": 0, "y": 6},
    [target(t_serie, HOST, "/^n8n: tiempo hasta la recuperaci.n/")],
    _tiempo))


# 5 · ¿El monitoreo sintético está corriendo?
def _rpa(p):
    d = p["fieldConfig"]["defaults"]
    d.pop("unit", None)
    d["decimals"] = 0
    d["max"] = 1
    d["min"] = 0
    d["thresholds"] = {"mode": "absolute",
                       "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]}
    d["custom"]["drawStyle"] = "bars"
    d["custom"]["fillOpacity"] = 80
    d["custom"]["thresholdsStyle"] = {"mode": "off"}


paneles.append(panel(
    t_serie, 5,
    "Ejecuciones del RPA (1 = OK, 0 = fallo)",
    "Item RPA: resultado de los dos recorridos en las dos instancias. Si la barra desaparece, el RPA dejo de correr (trigger T14).",
    {"h": 9, "w": 12, "x": 12, "y": 6},
    [target(t_serie, RPA, "/^RPA: resultado/")],
    _rpa))

# 6 · ¿Qué hizo exactamente en la última ejecución?
paneles.append(panel(
    t_texto, 6,
    "Ultima accion de cada flujo",
    "Items de texto n8n.exec.action (consulta de tipo Text: solo se resuelve en el navegador, ver README).",
    {"h": 7, "w": 12, "x": 0, "y": 15},
    [target(t_texto, HOST, "/^n8n: (.ltima acci.n|duraci.n)/")]))

# 7 · Historial de eventos con su recuperación
paneles.append(panel(
    t_triggers, 7,
    "Eventos que dispararon una accion automatica",
    "Problemas del grupo Integrador II con su hora de inicio y de cierre: la evidencia de que la recuperacion funciono.",
    {"h": 7, "w": 12, "x": 12, "y": 15},
    [copy.deepcopy(t_triggers["targets"][0])]))

dash = {
    "annotations": copy.deepcopy(exp.get("annotations", {"list": []})),
    "description": "Los procesos automaticos estan funcionando? Flujos de n8n y ejecuciones del RPA. Tarea IP2-77.",
    "editable": True,
    "fiscalYearStartMonth": 0,
    "graphTooltip": 1,
    "links": copy.deepcopy(exp["links"]),
    "panels": paneles,
    "preload": False,
    "refresh": "1m",
    "schemaVersion": exp["schemaVersion"],
    "tags": ["ip2", "integrador2"],
    "templating": copy.deepcopy(exp.get("templating", {"list": []})),
    "time": {"from": "now-24h", "to": "now"},
    "timepicker": {},
    "timezone": "browser",
    "title": "IP2 - Automatizacion (n8n y RPA)",
    "uid": "ip2-automatizacion",
    "version": 1,
    "weekStart": "",
}

destino = BASE + r"\ip2-automatizacion.json"
io.open(destino, "w", encoding="utf-8", newline="\n").write(
    json.dumps(dash, ensure_ascii=False, indent=2) + "\n")

# Comprobaciones
d = json.load(io.open(destino, encoding="utf-8"))
print("paneles:", len(d["panels"]))
for p in d["panels"]:
    t = p["targets"][0]
    print(" ", p["id"], p["type"], "|", p["title"], "| host:", t.get("host", {}).get("filter"),
          "| item:", t.get("item", {}).get("filter"))
    assert p["datasource"]["uid"] == "zabbix"
    for tg in p["targets"]:
        for f in tg.get("functions", []):
            for v in f.get("params", []):
                assert isinstance(v, str), (p["title"], f)
print("uid:", d["uid"], "| tags:", d["tags"])
