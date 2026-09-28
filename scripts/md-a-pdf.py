#!/usr/bin/env python3
"""Convierte los Markdown de un entregable en un PDF listo para subir.

Une los archivos en orden, les pone portada y los imprime con Microsoft Edge en
modo headless, así el PDF no depende de que Confluence exporte bien.

Uso:
    python scripts/md-a-pdf.py salida.pdf --portada portada.json doc.md anexos.md

Requiere: pip install markdown
"""
import argparse
import base64
import html
import json
import pathlib
import re
import subprocess
import sys
import tempfile

import markdown

EDGE = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
]

CSS = """
@page { size: A4; margin: 18mm 16mm 18mm 16mm;
        @bottom-center { content: counter(page) " / " counter(pages); font: 8.5pt 'Segoe UI', sans-serif; color: #666; } }
@page horizontal { size: A4 landscape; margin: 12mm 12mm 14mm 12mm; }
* { box-sizing: border-box; }
body { font: 10.5pt/1.45 'Segoe UI', Calibri, Arial, sans-serif; color: #1d2330; }
h1 { font-size: 19pt; margin: 0 0 4pt; color: #0b3a6f; }
h2 { font-size: 14pt; margin: 20pt 0 6pt; padding-bottom: 3pt; color: #0b3a6f;
     border-bottom: 1.5pt solid #0b3a6f; break-after: avoid; }
h3 { font-size: 11.5pt; margin: 14pt 0 4pt; color: #1d2330; break-after: avoid; }
p { margin: 4pt 0 6pt; }
ul, ol { margin: 4pt 0 8pt; padding-left: 18pt; }
li { margin: 1.5pt 0; }
code { font: 9pt Consolas, monospace; background: #eef1f5; padding: 0 2pt; border-radius: 2pt; }
hr { border: 0; border-top: 1pt solid #c9d1dc; margin: 16pt 0; }
table { width: 100%; border-collapse: collapse; margin: 6pt 0 10pt; font-size: 9pt; }
th, td { border: 0.75pt solid #b8c2cf; padding: 3.5pt 5pt; vertical-align: top; text-align: left; }
th { background: #0b3a6f; color: #fff; font-weight: 600; }
tr:nth-child(even) td { background: #f3f6f9; }
tr { break-inside: avoid; }
thead { display: table-header-group; }
blockquote { margin: 8pt 0; padding: 6pt 10pt; background: #fff7e0; border-left: 3pt solid #e0a100; }
.anexo { page: horizontal; }
img { max-width: 100%; height: auto; }
figure { margin: 6pt 0 10pt; break-inside: avoid; }
figcaption { font-size: 9pt; color: #4a5566; text-align: center; margin-top: 4pt; }
.figura-h { page: horizontal; margin: 0; }
.figura-h h2 { margin-top: 0; }
.figura-h img { display: block; margin: 0 auto; max-height: 150mm; }
.anexo table { font-size: 7.6pt; }
.anexo th, .anexo td { padding: 2.5pt 3.5pt; }
.anexo td:nth-child(1), .anexo td:nth-child(4), .anexo td:nth-child(5), .anexo td:nth-child(10) { white-space: nowrap; }
table.ids td:first-child { white-space: nowrap; }
@page :first { @bottom-center { content: none; } }
.portada { height: 250mm; display: flex; flex-direction: column; justify-content: space-between;
           break-after: page; }
.portada .inst { font-size: 12pt; letter-spacing: .08em; text-transform: uppercase; color: #0b3a6f; font-weight: 600; }
.portada .curso { font-size: 11pt; color: #4a5566; margin-top: 2pt; }
.portada .titulo { margin-top: 60mm; }
.portada .titulo .eyebrow { font-size: 11pt; color: #4a5566; text-transform: uppercase; letter-spacing: .06em; }
.portada .titulo h1 { font-size: 26pt; line-height: 1.15; margin: 6pt 0 8pt; }
.portada .titulo .sub { font-size: 13pt; color: #1d2330; }
.portada .equipo h3 { margin: 0 0 6pt; color: #0b3a6f; }
.portada .equipo td, .portada .equipo th { font-size: 10pt; }
.portada .pie { display: flex; justify-content: space-between; font-size: 10.5pt; color: #4a5566;
                border-top: 1.5pt solid #0b3a6f; padding-top: 6pt; }
"""


def portada_html(p):
    filas = "".join(
        f"<tr><td>{html.escape(i['nombre'])}</td><td>{html.escape(i['rol'])}</td>"
        f"<td>{html.escape(i['correo'])}</td></tr>"
        for i in p["integrantes"])
    return f"""
<section class="portada">
  <div>
    <div class="inst">{html.escape(p['institucion'])}</div>
    <div class="curso">{html.escape(p['curso'])}</div>
    <div class="titulo">
      <div class="eyebrow">{html.escape(p['entregable'])}</div>
      <h1>{html.escape(p['titulo'])}</h1>
      <div class="sub">{html.escape(p['subtitulo'])}</div>
    </div>
  </div>
  <div class="equipo">
    <h3>Equipo</h3>
    <table><thead><tr><th>Integrante</th><th>Rol principal</th><th>Correo</th></tr></thead>
    <tbody>{filas}</tbody></table>
  </div>
  <div class="pie"><span>{html.escape(p['profesor'])}</span><span>{html.escape(p['fecha'])}</span></div>
</section>"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("salida")
    ap.add_argument("entradas", nargs="+")
    ap.add_argument("--portada", help="JSON con los datos de la portada")
    ap.add_argument("--titulo", default="Entregable")
    a = ap.parse_args()

    texto = "\n\n".join(pathlib.Path(e).read_text(encoding="utf-8") for e in a.entradas)
    cuerpo = markdown.markdown(texto, extensions=["tables", "md_in_html", "sane_lists"])
    # Solo las tablas cuya primera columna es un identificador (ID o #) la dejan en una línea;
    # si se aplica a todas, una primera columna de texto largo desborda la página y Edge
    # encoge el documento entero para que quepa.
    cuerpo = re.sub(r"<table>(\s*<thead>\s*<tr>\s*<th[^>]*>\s*(?:ID|#)\s*</th>)",
                    r'<table class="ids">\1', cuerpo)
    # El HTML se imprime desde una carpeta temporal: las imagenes con ruta relativa se
    # resuelven contra la carpeta del primer Markdown y se incrustan en el propio PDF.
    base = pathlib.Path(a.entradas[0]).resolve().parent

    def incrustar(m):
        ruta = m.group(2)
        if re.match(r"(?i)(https?:|data:)", ruta):
            return m.group(0)
        archivo = (base / ruta).resolve()
        if not archivo.exists():
            sys.exit(f"Imagen no encontrada: {ruta} (buscada en {archivo})")
        tipo = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
                ".svg": "image/svg+xml"}.get(archivo.suffix.lower(), "application/octet-stream")
        datos = base64.b64encode(archivo.read_bytes()).decode("ascii")
        return f'{m.group(1)}data:{tipo};base64,{datos}{m.group(3)}'

    cuerpo = re.sub(r'(<img[^>]*?src=")([^"]+)(")', incrustar, cuerpo)
    portada = portada_html(json.loads(pathlib.Path(a.portada).read_text(encoding="utf-8"))) if a.portada else ""
    doc = (f"<!doctype html><html lang='es'><head><meta charset='utf-8'><title>{html.escape(a.titulo)}</title>"
           f"<style>{CSS}</style></head><body>{portada}{cuerpo}</body></html>")

    navegador = next((e for e in EDGE if pathlib.Path(e).exists()), None)
    if not navegador:
        sys.exit("No se encontró Edge ni Chrome para imprimir el PDF.")
    salida = pathlib.Path(a.salida).resolve()
    with tempfile.TemporaryDirectory() as tmp:
        fuente = pathlib.Path(tmp) / "entregable.html"
        fuente.write_text(doc, encoding="utf-8")
        subprocess.run([navegador, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                        f"--print-to-pdf={salida}", fuente.as_uri()],
                       check=True, capture_output=True, timeout=120)
    print(f"PDF generado: {salida} ({salida.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
