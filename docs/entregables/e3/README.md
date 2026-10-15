# Entregable 3 — Implementación técnica

Entrega del **lunes 2 de noviembre de 2026** (25 % del curso). Sigue la *Guía de contenido, rúbrica y criterios de aceptación* del E3 (`Documentos de entregas/Entregable_3_Guia_Rubrica_Aceptacion.pdf`): las secciones 1 a 9 son los nueve puntos de contenido obligatorio, la 10 es lo que el profesor pidió además de la guía (Windows Server, Active Directory y seguridad), la 11 trae la tabla A-01 a A-09 y la 12 responde las cinco preguntas orientadoras.

**Es un borrador actualizado al 14 de octubre.** Está escrito con lo que se construyó y probó entre el 12 y el 14 de octubre; hay que actualizarlo con lo que se haga antes de la entrega.

| Archivo | Para qué |
|---|---|
| **[E3-Implementacion-tecnica.pdf](E3-Implementacion-tecnica.pdf)** | El PDF: portada, 14 secciones y el anexo de evidencias (30 páginas) |
| [E3-documento-completo.md](E3-documento-completo.md) | Fuente del PDF. Consolida las actas de `docs/evidencias/e3/` |
| [portada.json](portada.json) | Datos de la portada |

## Regenerar el PDF

Después de cambiar el Markdown o alguna imagen (requiere `pip install markdown` y Microsoft Edge):

```powershell
python scripts/md-a-pdf.py docs/entregables/e3/E3-Implementacion-tecnica.pdf `
  --portada docs/entregables/e3/portada.json `
  --titulo "Entregable 3 - Implementación técnica" `
  docs/entregables/e3/E3-documento-completo.md
```

Las capturas de los tableros de Grafana se vuelven a tomar con `infra/vm-grafana/token-capturas.py` y `monitoreo/grafana/capturas.robot` (las instrucciones están en cada archivo).

## Pendiente antes de entregar

- **A-01**: abrir la aplicación desde PC-CLIENTE, en sus dos instancias, y poner la foto en la sección 2.3. Es la única prueba de aceptación que no cumple todavía.
- Foto del rack con los equipos del grupo.
- Capturas de Zabbix (*Últimos datos* por host) y de *Usuarios y equipos de Active Directory*.
- Actualizar las secciones 4.2, 13 y 14 con lo que se avance (triggers de red, integración con el dominio, cortafuegos).
- Revisión por dos integrantes, como se hizo con el E1 y el E2.
- Subirlo a Confluence (02 Entregables), como el E2.
