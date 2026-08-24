# Base de conocimiento de «Un crimen casi perfecto»

Esta carpeta contiene la fuente canónica y su preparación editorial para el sistema RAG del juego.

## Archivos

- `un-crimen-casi-perfecto-version-final.md`: texto canónico estable. Solo se edita de forma controlada cuando contradice al diagrama autoritativo; el chunking por sí mismo nunca lo reescribe.
- `PISTAS_Y_ESTADOS.md`: hechos internos, pistas visibles, reglas de desbloqueo, hitos narrativos y condición de acusación.
- `RAG_SPEC.md`: arquitectura de recuperación, estructura de chunks, filtros, presupuesto de contexto y flujo de ejecución.
- `chunk.schema.json`: contrato validable para los chunks que se generen a partir de las escenas.
- `chunk.example.json`: instancia mínima y trazable del contrato.
- `scenes/`: partición fiel del texto canónico en escenas narrativas. El texto comprendido entre `SOURCE_START` y `SOURCE_END` se copia literalmente de la versión final.
- `scenes/*.atomic.chunks.json`: un archivo recuperable por cada escena, con 162 datos atómicos, procedencia, permisos y hechos que puede comunicar. Cada `retrieval_text` expresa un dato específico y `source_excerpt` conserva la procedencia editorial larga.
- `backend/data/canonical_questions.json`: una pregunta canónica específica por átomo, revisada editorialmente; se usa como segunda representación del índice y nunca se envía al personaje.

## Contrato editorial de una escena

El frontmatter de cada archivo declara:

- `scene_id` y `title`: identidad estable y nombre editorial;
- `canonical_lines`: tramo de procedencia en el cuento completo;
- `locations`: lugares narrativos, siempre como lista;
- `present_entities`: entidades realmente presentes durante la interacción;
- `mentioned_entities`: entidades nombradas pero no necesariamente presentes;
- `availability`: primera condición que permite usar material de la escena;
- `index_policy`: `investigation` o `resolution`;
- `default_spoiler_level`: valor inicial para sus chunks.

`present_entities` no equivale a `knowledge_holders`. El permiso de conocimiento se decide por chunk porque dos pasajes de una misma escena pueden ser conocidos por personas distintas. Del mismo modo, `availability` es el piso editorial de la escena: cada chunk puede imponer condiciones más estrictas.

## Catálogo de escenas

| ID | Archivo | Función | Disponibilidad | Índice |
|---|---|---|---|---|
| `SCN-01` | `01_hallazgo_y_peritaje_inicial.md` | hallazgo y causa preliminar | `M00_CASE_OPEN` | investigación |
| `SCN-02` | `02_primer_interrogatorio_criada.md` | maltrato, whisky y discusión | `M00_CASE_OPEN` | investigación |
| `SCN-03` | `03_testimonio_portero.md` | diario, criada como última persona en verla y ausencia de visitas | `M00_CASE_OPEN` | investigación |
| `SCN-04` | `04_interrogatorio_juan.md` | rencor, antecedentes, coartada y sospecha sobre Esteban | `M00_CASE_OPEN` | investigación |
| `SCN-05` | `05_interrogatorio_esteban.md` | póliza, beneficiarios, discusión minimizada y coartada | `M00_CASE_OPEN` | investigación |
| `SCN-06` | `06_interrogatorio_pablo.md` | antecedentes, químicos, interés económico y coartada | `M00_CASE_OPEN` | investigación |
| `SCN-07` | `07_poliza_y_confrontacion_esteban.md` | documento, reparto y admisión de la pelea | `INSPECT_POLICY` | investigación |
| `SCN-08` | `08_resultados_negativos_e_hipotesis_hielo.md` | líquidos limpios, humedad e hipótesis | `M10_POISONING_CONFIRMED` | investigación |
| `SCN-09` | `09_cianuro_en_el_hielo.md` | resultado automático del análisis del hielo | `M30_ICE_HYPOTHESIS` | investigación |
| `SCN-10` | `10_segundo_interrogatorio_criada.md` | hábito, falla y reparación de la heladera | `M40_POISON_IN_ICE` | investigación |
| `SCN-11` | `11_confrontacion_a_pablo.md` | admisiones y negativas sobre el congelador | `M50_PABLO_FRIDGE_LINK` | investigación |
| `SCN-12` | `12_inspecciones_tecnica_y_erpa.md` | fusible, oportunidad y cianuro en Erpa | `M50_PABLO_FRIDGE_LINK` | investigación |
| `SCN-13` | `13_reconstruccion_del_metodo.md` | reconstrucción verdadera del crimen | `M81_VICTORY` | resolución |
| `SCN-14` | `14_acusacion_final_a_pablo.md` | confrontación sin confesión | `M81_VICTORY` | resolución |
| `SCN-15` | `15_epilogo.md` | cierre temático | `M81_VICTORY` | resolución |

## Decisiones centrales

1. El cuento completo es la única fuente textual de hechos del caso.
2. Los guiones `v2` contienen personalidad y reglas de actuación, no conocimiento del crimen.
3. Los chunks se derivan del cuento; las preguntas canónicas son un índice editorial paralelo y no cambian el texto recuperable ni se inyectan en el prompt.
4. Los metadatos controlan quién conoce un pasaje y cuándo puede recuperarse. El filtrado ocurre antes de la búsqueda vectorial para impedir spoilers.
5. El estado del juego y la resolución de la acusación son deterministas. El modelo solo representa al personaje.
6. Una sola inferencia generativa produce cada respuesta. No se usa otro LLM como clasificador en tiempo de juego.
7. Los hechos granulares del RAG no son pistas del tablero: se agrupan en 2 pistas para la criada, 2 para Juan, 3 para Esteban y 4 para Pablo.

## Flujo editorial

1. Segmentar el texto en escenas.
2. Proponer dentro de cada escena unidades semánticas autosuficientes.
3. Conservar el pasaje literal como `source_text`.
4. Crear un `retrieval_text` contextualizado para embeddings, sin agregar hechos.
5. Anotar hablantes, conocedores, etapa, hechos internos y nivel de spoiler.
6. Validar el objeto contra `chunk.schema.json`.
7. Revisar manualmente todo chunk con `spoiler_level` 2 o 3.
8. Generar embeddings e indexar.

Los chunks atómicos revisados se mantienen como artefactos editoriales
versionados. Para construir o reconstruir el índice embeddinggemma con q1 y q2:

```bash
OLLAMA_EMBED_MODEL=hf.co/unsloth/embeddinggemma-300m-GGUF:Q4_0 \
RAG_INDEX_PATH=backend/data/rag_index_atomic_embeddinggemma_two.sqlite3 \
python3 -m backend.scripts.build_rag_index \
  --force --canonical-questions-two backend/data/canonical_questions_two.json
```

El comando reutiliza esos JSON y no genera una segunda variante de chunks.

## Autoridad de los datos

La jerarquía canónica es:

1. el diagrama de pistas provisto por el equipo, transcripto y normalizado en `PISTAS_Y_ESTADOS.md`;
2. el cuento final;
3. los guiones y documentos históricos.

Si el cuento contradice el diagrama, se corrige el cuento y se registra la decisión en `PISTAS_Y_ESTADOS.md`. Las adaptaciones de jugabilidad nunca deben introducirse silenciosamente durante el chunking.
