# Entregable 2 — Análisis y diseño de la solución

Entrega del **lunes 5 de octubre de 2026** (15 % del curso). Responde la sección 8.2 de la guía del proyecto: arquitectura física y lógica, comparación de alternativas y justificación de las tecnologías, organizado alrededor de las cinco preguntas orientadoras.

| Archivo | Para qué |
|---|---|
| **[E2-Analisis-y-diseno.pdf](E2-Analisis-y-diseno.pdf)** | **El PDF que se entrega**: portada, 15 secciones y los tres diagramas en páginas horizontales (26 páginas) |
| [E2-documento-completo.md](E2-documento-completo.md) | Fuente del PDF. Consolida los diseños de `docs/diseno/` y `red/` |
| [portada.json](portada.json) | Datos de la portada |

Los diagramas viven en [`docs/diagramas/`](../../diagramas/), cada uno con su fuente editable `.drawio` y su `.png`:

| Diagrama | Responde |
|---|---|
| `arquitectura-fisica` | Qué se cablea con qué: router, switch, servidor y las siete VMs |
| `arquitectura-logica` | Cómo se segmenta la red y qué tráfico está permitido |
| `flujo-monitoreo` | Qué vigila Zabbix, qué recupera n8n y qué solo alerta |

`arquitectura-general` es el diagrama del E1 y queda como historia: ya no refleja el diseño.

## Regenerar el PDF

Después de cambiar el Markdown o algún diagrama (requiere `pip install markdown` y Microsoft Edge):

```powershell
python scripts/md-a-pdf.py docs/entregables/e2/E2-Analisis-y-diseno.pdf `
  --portada docs/entregables/e2/portada.json `
  --titulo "Entregable 2 - Análisis y diseño de la solución" `
  docs/entregables/e2/E2-documento-completo.md
```

Las imágenes se referencian con ruta relativa al Markdown y el script las incrusta en el PDF. Un bloque `<div class="figura-h">` pone el título y el diagrama juntos en una página horizontal.

**Exportar un diagrama a PNG** después de editar el `.drawio`: draw.io de la Microsoft Store ya no deja lanzarse por su ruta directa, así que se invoca dentro del contexto del paquete:

```powershell
$pkg = Get-AppxPackage draw.io.draw.ioDiagrams
$exe = Join-Path $pkg.InstallLocation 'app\draw.io.exe'
$d = "docs\diagramas"
Invoke-CommandInDesktopPackage -PackageFamilyName $pkg.PackageFamilyName -AppId 'draw.io.draw.ioDiagrams' `
  -Command $exe -Args "--export --format png --scale 2 --border 20 --output `"$PWD\$d\arquitectura-fisica.png`" `"$PWD\$d\arquitectura-fisica.drawio`""
```

El comando vuelve enseguida y el PNG aparece unos segundos después.

## Pendiente antes de entregar

- **Revisión por dos integrantes**, como se hizo con el E1.
- **Publicarlo en Confluence** (02 Entregables → *E2 · Análisis y diseño de la solución*) y subir los tres PNG a *03 Diseño*. El conector de Atlassian no sube imágenes: los PNG se arrastran a mano.
- Si antes del 5 de octubre se repiten las validaciones de Packet Tracer o se conoce la RAM del servidor, actualizar las secciones 5.5, 10, 12 y 13 y regenerar el PDF.
