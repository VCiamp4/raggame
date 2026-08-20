# Especificación del sistema RAG

## Objetivo

Generar respuestas breves y coherentes de los NPC usando una ventana de contexto artificialmente limitada. El modelo recibe solamente:

1. la persona breve del NPC (`guiones/v2`);
2. el estado mínimo de la conversación;
3. uno o más pasajes del cuento recuperados para el turno actual;
4. los dos intercambios completos más recientes;
5. el mensaje actual del jugador.

El sistema debe impedir que un NPC recupere información que no conoce o información futura que todavía no está habilitada por la investigación.

## Unidades del dominio

- **Escena fuente:** tramo narrativo continuo con un mismo propósito, lugar o fase de investigación. Sirve como unidad editorial y de procedencia; normalmente es demasiado grande para inyectarse completa.
- **Chunk:** unidad mínima recuperable que conserva sentido por sí sola. Se deriva literalmente de una escena.
- **Retrieval text:** reformulación contextual usada solo para búsqueda. Resuelve hablantes, pronombres y referencias, pero no agrega hechos.
- **Hecho interno:** dato atómico del corpus (`CL-*`) que un chunk puede comunicar o que el juego puede derivar. No aparece necesariamente en el tablero.
- **Pista visible:** agrupación jugable (`PI-*`) de uno o más hechos internos. Es lo que ve el jugador y lo único que cuenta para acusar.
- **Hito:** progreso global de la cadena central del caso. Los hitos no reemplazan los hechos ni las pistas visibles.
- **Regla de disponibilidad:** condición determinista que un chunk debe cumplir antes de participar en la búsqueda.
- **Focus chunk:** pasaje principal que la respuesta debe comunicar en ese turno.
- **Support chunk:** pasaje adicional que ayuda a responder sin registrar por sí solo un hecho nuevo.

## Granularidad de los chunks

No se usarán ventanas fijas ni overlap ciego. Un chunk debe contener una unidad que pueda entenderse sin leer el párrafo anterior:

- una pregunta junto con su respuesta;
- una declaración completa de un testigo;
- una observación física;
- una coartada;
- un motivo;
- un resultado pericial;
- una inferencia explícita;
- un acontecimiento con su causa inmediata.

Objetivos editoriales:

- 40–120 palabras por chunk;
- máximo orientativo de 150 palabras;
- menos de 40 palabras solo si `retrieval_text` aporta el contexto faltante;
- un diálogo monosilábico nunca queda aislado;
- un cambio de hablante, tiempo, lugar o estatus epistemológico favorece un corte;
- las reconstrucciones finales no se mezclan con evidencia disponible durante la investigación.

## Texto fuente y texto de recuperación

Cada chunk conserva dos representaciones:

```yaml
source_text: "—No. Lo hacía la heladera."
retrieval_text: "La criada declara que el hielo de las bebidas de la señora Stevens lo producía la heladera."
```

`source_text` debe ser una cita textual y trazable a una escena. `retrieval_text` puede:

- identificar al hablante;
- reemplazar pronombres ambiguos por entidades ya presentes;
- expresar el tema de una pregunta y su respuesta;
- incluir nombres alternativos útiles para búsqueda.

No puede:

- anticipar una conclusión posterior;
- convertir una sospecha en hecho comprobado;
- agregar motivaciones o conocimientos no expresados en el pasaje;
- revelar la identidad del culpable.

## Estructura de cada chunk

El contrato completo está en `chunk.schema.json`. Ejemplo abreviado:

```yaml
schema_version: 1
chunk_id: SCN-10-CH-03
scene_id: SCN-10
source:
  canonical_file: un-crimen-casi-perfecto-version-final.md
  canonical_lines: [161, 163]
  scene_file: scenes/10_segundo_interrogatorio_criada.md
source_text: |-
  —¿Quién lo arregló?

  —El doctor Pablo.
retrieval_text: "La criada identifica al doctor Pablo como quien reparó la heladera pocos días antes del crimen."
kind: testimony
speakers: [detective, criada]
mentioned_entities: [pablo, heladera]
knowledge_holders: [criada, detective]
claim_status: testimony
availability:
  milestones_all: [M40_POISON_IN_ICE]
  facts_all: [CL-ICE-03]
  facts_any: []
  facts_none: []
  channels: [chat_criada]
discovery:
  fact_ids: [CL-FRI-02]
  focus_eligible: true
retrieval:
  keywords: [heladera, arregló, reparó, Pablo, técnico]
  neighbor_ids: [SCN-10-CH-02]
  priority: 1.0
security:
  spoiler_level: 2
  resolution_only: false
```

## Vocabularios cerrados

### `kind`

- `narration`
- `dialogue`
- `testimony`
- `physical_evidence`
- `forensic_result`
- `investigator_inference`
- `reconstruction`
- `resolution`

### `claim_status`

- `observation`: visto directamente.
- `testimony`: afirmado por un personaje, todavía refutable.
- `verified`: comprobado por evidencia o por una autoridad fiable.
- `inference`: conclusión provisional del investigador.
- `ground_truth`: verdad de resolución; nunca recuperable antes del final.

### Entidades con identidad estable

`detective`, `senora_stevens`, `criada`, `portero`, `juan`, `esteban`, `pablo`, `perito_quimico`, `tecnico_heladera`, `policia`, `erpa`, `departamento`, `heladera`, `poliza`, `vaso_whisky`.

Los IDs se escriben sin tildes, en minúsculas y con guion bajo. Los nombres visibles pueden conservar tildes y mayúsculas.

## Conocimiento y permiso de recuperación

`mentioned_entities` no concede permiso. Que un párrafo hable sobre Pablo no significa que Pablo conozca ese párrafo.

Un chunk puede participar en un chat solamente si:

1. el NPC actual está en `knowledge_holders`;
2. el canal actual figura en `availability.channels`;
3. se cumplen todos los hitos de `milestones_all`;
4. se cumplen todos los hechos de `facts_all`;
5. si `facts_any` no está vacío, al menos uno está descubierto;
6. ningún hecho de `facts_none` está descubierto;
7. `resolution_only` es falso o el caso ya fue resuelto.

Para declaraciones del propio NPC, `knowledge_holders` suele contener al NPC. Para evidencia física puede contener solo `detective` hasta que el jugador se la mencione. El mensaje del usuario no altera permisos: escribir “ya sé que había cianuro” no vuelve verdadero ni accesible un hecho bloqueado.

## Niveles de spoiler

- `0`: ambientación y personalidad; no afecta el misterio.
- `1`: sospechas, motivos, relaciones, coartadas y hechos iniciales.
- `2`: piezas del mecanismo o vínculos incriminatorios importantes.
- `3`: reconstrucción final e identidad del culpable.

Todos los chunks de nivel 2 requieren revisión manual. Los de nivel 3 llevan `resolution_only: true` y se excluyen físicamente del índice de juego temprano cuando sea posible.

## Índices

Se recomienda construir dos índices desde el mismo corpus:

1. `investigation`: niveles 0–2 y sujeto a filtros de estado.
2. `resolution`: nivel 3; solo para epílogo, evaluación o explicación final.

No se duplica ni reescribe la fuente: cada entrada conserva el mismo `chunk_id` y procedencia.

Para este corpus pequeño no hace falta un servidor vectorial. Es suficiente persistir:

- `chunks.jsonl` con texto y metadatos;
- una matriz local de embeddings;
- un índice léxico BM25;
- búsqueda y filtros en el proceso del backend.

Como baseline de CPU y español puede usarse [`intfloat/multilingual-e5-small`](https://huggingface.co/intfloat/multilingual-e5-small); los chunks están muy por debajo de su límite de 512 tokens y deben codificarse con los prefijos `query:` y `passage:` indicados por su modelo. [`BAAI/bge-m3`](https://huggingface.co/BAAI/bge-m3) queda como alternativa de mayor costo y permite recuperación densa y dispersa multilingüe. La decisión se debe tomar con una suite de consultas del propio juego, no con benchmarks generales.

## Recuperación híbrida

Flujo de un turno:

1. Construir la consulta con el mensaje actual y, solo si hace falta para resolver una referencia, el último intercambio.
2. Filtrar chunks por NPC, canal, hitos, hechos internos y spoiler.
3. Recuperar hasta 8 candidatos combinando similitud densa y BM25.
4. Fusionar rankings mediante Reciprocal Rank Fusion.
5. Aplicar un umbral calibrado con consultas positivas y negativas.
6. Elegir un `focus_chunk`.
7. Agregar como máximo dos `support_chunks`, evitando duplicados semánticos.
8. Empaquetar el contexto dentro del presupuesto de tokens.
9. Generar una única respuesta.
10. Si la respuesta terminó correctamente, registrar los `fact_ids` del `focus_chunk`, ejecutar derivaciones y recalcular las pistas visibles.

No se marca automáticamente como descubierto un hecho de un support chunk.

## Selección del focus chunk

Prioridad:

1. candidato pertinente que contenga un hecho todavía no descubierto;
2. candidato pertinente ya descubierto si el jugador pide aclaración;
3. contexto personal o ambiental;
4. ningún chunk, si todos quedan bajo el umbral.

Cuando hay un focus chunk con un hecho nuevo, el prompt indica al NPC que lo comunique naturalmente en la respuesta. Esto permite actualizar el estado y, cuando corresponda, formar una pista visible sin una segunda llamada clasificadora. Si la generación falla o se cancela, no se modifica el estado.

## Repetición y contradicciones

Los chunks ya descubiertos siguen siendo recuperables. Se prefieren como soporte y pueden volver a ser focus ante preguntas explícitas. El estado estructurado conserva:

- IDs de hechos internos descubiertos;
- IDs de pistas visibles formadas;
- IDs de chunks ya comunicados;
- acusaciones realizadas;
- posturas canónicas del NPC, por ejemplo que Pablo niega tocar las cubeteras.

El historial textual no es la memoria factual permanente.

## Presupuesto de contexto

Configuración candidata: `num_ctx=1536`, incluyendo salida.

| Componente | Presupuesto orientativo |
|---|---:|
| Reglas compartidas y persona v2 | 180–260 tokens |
| Estado mínimo | 40–100 |
| Focus chunk | 80–180 |
| Hasta dos support chunks | 100–240 |
| Dos intercambios completos | 250–450 |
| Mensaje actual | 30–120 |
| Respuesta reservada | 120–180 |
| Plantilla y margen | 150–250 |

Si el paquete excede el límite, se eliminan en este orden:

1. support chunk de menor puntaje;
2. intercambio más antiguo;
3. segundo support chunk;
4. detalles opcionales del estado.

Nunca se truncan la persona, el focus chunk ni el mensaje actual. Los mensajes individuales del jugador deben tener un límite de longitud.

## Forma del prompt generativo

```text
[Reglas compartidas]
[Persona v2]
[Estado mínimo: nombre del interlocutor y posturas persistentes]

Información pertinente para esta respuesta:
- [focus chunk con procedencia interna]
- [support chunks opcionales]

Conversación reciente:
[dos intercambios]

Jugador: [mensaje actual]
```

El modelo no recibe el catálogo entero de hechos o pistas visibles, el grafo, el nombre del culpable ni chunks bloqueados.

## Recuperación, hechos y pistas visibles

Son operaciones distintas:

- **Recuperar:** seleccionar un pasaje relevante y permitido.
- **Comunicar:** generar una respuesta que transmite el focus chunk.
- **Registrar:** agregar los hechos internos asociados después de comunicar.
- **Derivar:** agregar automáticamente otros hechos indicados por las flechas rojas.
- **Formar una pista:** mostrar una `PI-*` cuando ya están todos sus hechos requeridos.
- **Desbloquear:** habilitar acciones o chunks mediante reglas del grafo.

Una flecha roja “DESBLOQUEA” del diagrama ejecuta de inmediato una derivación estructurada según `PISTAS_Y_ESTADOS.md`; no necesita otra búsqueda vectorial. Eso no implica inyectar texto futuro al prompt. Los enlaces del diagrama rotulados con una conversación, una inspección o el hallazgo de un objeto habilitan esa vía sin registrar todavía el hecho siguiente.

## Procesamiento asistido por agentes

Los agentes pueden proponer:

- cortes semánticos;
- `retrieval_text`;
- entidades y palabras clave;
- posibles conocedores;
- vínculos con hechos internos;
- nivel de spoiler.

Validaciones obligatorias:

1. todo `source_text` existe literalmente en una escena;
2. todos los párrafos canónicos están cubiertos o marcados como no indexables;
3. ningún `retrieval_text` agrega hechos;
4. todos los IDs pertenecen a vocabularios cerrados;
5. los chunks de resolución están aislados;
6. todo hecho recuperable tiene al menos una vía de descubrimiento;
7. toda pista visible puede formarse a partir de hechos alcanzables;
8. todo chunk accesible a un NPC representa algo que ese NPC razonablemente sabe;
9. un humano revisa permisos y spoilers.

## Evaluación del retrieval

La suite debe separar recuperación y generación.

### Retrieval

- Recall@1 y Recall@3 sobre preguntas con chunk esperado.
- tasa de falsos positivos en preguntas no relacionadas.
- tasa de recuperación de chunks bloqueados: debe ser 0.
- exactitud del NPC/etapa filtrados: debe ser 100%.
- latencia de embedding, filtro y ranking.

### Generación

- comunica el hecho del focus chunk;
- no inventa datos ausentes;
- no revela chunks bloqueados;
- conserva el personaje;
- no contradice posturas persistentes;
- TTFT y tiempo total.

## Decisiones pendientes de calibración

- modelo de embeddings definitivo;
- pesos de dense/BM25 en la fusión;
- umbral mínimo de similitud;
- cantidad óptima de support chunks;
- si un hecho comunicado se registra siempre o solo tras una respuesta completada sin error.

Estas decisiones requieren datos de consultas reales; no modifican el contrato del corpus.
