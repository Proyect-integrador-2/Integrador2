# Entregable 1 — Planteamiento y gestión del proyecto

Respaldo versionado del Entregable 1 (**21 de setiembre de 2026**). Nació como plan B cuando el conector de Atlassian dejó de responder; **ya todo está publicado en Confluence**, así que estos archivos quedan como copia fuera de Atlassian y como fuente para exportar el PDF si hiciera falta.

| Archivo | Para qué |
|---|---|
| **[E1-Planteamiento-y-gestion.pdf](E1-Planteamiento-y-gestion.pdf)** | **El PDF que se entrega**: portada, las 12 secciones de la guía y los anexos A (cronograma de 61 tareas), B (registro de riesgos) y C (desglose de la EDT) |
| [E1-documento-completo.md](E1-documento-completo.md) | **El entregable entero, autosuficiente.** Si Confluence no vuelve a tiempo: pegar en Google Docs o Word y exportar a PDF |
| [matriz-responsables.md](matriz-responsables.md) | Copia de 01 Gestión → **Matriz de responsables** |
| [cronograma-tabla.md](cronograma-tabla.md) | Copia de la tabla de 61 tareas del **Cronograma detallado** |
| [portada-e-integrantes.md](portada-e-integrantes.md) | Copia de la sección 1 (portada e integrantes) |

| [anexos.md](anexos.md) · [portada.json](portada.json) | Fuentes de los anexos y de la portada del PDF |

**Regenerar el PDF** después de cambiar cualquier fuente (requiere `pip install markdown` y Microsoft Edge):

```powershell
python scripts/md-a-pdf.py docs/entregables/e1/E1-Planteamiento-y-gestion.pdf `
  --portada docs/entregables/e1/portada.json `
  docs/entregables/e1/E1-documento-completo.md docs/entregables/e1/anexos.md
```

El mismo script sirve para los entregables E2 a E5: cambian los Markdown y la portada.

## Qué ya está publicado y no hace falta tocar

Alcance y objetivos, Requerimientos, EDT, Registro de riesgos, Inventario de recursos, el *Cronograma detallado y plan de seguimiento* (todo salvo los nombres en la tabla) y el *E1 · Documento de entrega* completo (todo salvo la tabla de integrantes de la sección 1).

## Lo que sigue pendiente, y no depende de estos archivos

- Invitar a los cuatro integrantes a GitHub, Jira y Confluence, y asignarles sus tareas en Jira.
- Crear en Jira los *releases* E1–E5 y los sprints semanales, y adjuntar la captura de la vista Cronograma.
- Inventario del hardware de la universidad (requiere la visita al laboratorio).
- Revisión cruzada del documento por dos integrantes y exportación a PDF.
