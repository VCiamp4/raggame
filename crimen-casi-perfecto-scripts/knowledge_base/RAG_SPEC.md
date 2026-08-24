# Especificación del sistema RAG

## Objetivo

Generar respuestas breves y coherentes de los NPC usando una ventana de contexto artificialmente limitada. El modelo recibe solamente:

1. un `system` estable con las reglas comunes y la persona breve del NPC (`guiones/v2`);
2. el historial completo de turnos ya terminados, en orden, con solo el texto del jugador y la respuesta del NPC;
3. un mensaje `user` del turno actual que contiene `<retrieved_context>` y `<user_message>`;
4. el estado narrativo aplicado como filtros (sus IDs no se inyectan al modelo).

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

En los chunks atómicos, `source_text` y `retrieval_text` son el mismo dato
breve, trazable mediante `source_excerpt`, `parent_chunk_id` y
`canonical_lines`. `retrieval_text` puede:

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
chunk_id: SCN-10-AT-03
scene_id: SCN-10
source:
  canonical_file: un-crimen-casi-perfecto-version-final.md
  canonical_lines: [155, 165]
  scene_file: scenes/10_segundo_interrogatorio_criada.md
  parent_chunk_id: SCN-10-CH-02
source_text: "La heladera había fallado unos días antes."
retrieval_text: "La heladera había fallado unos días antes."
kind: testimony
speakers: [detective, criada]
mentioned_entities: [criada, pablo, heladera]
knowledge_holders: [criada]
claim_status: testimony
availability:
  milestones_all: [M40_POISON_IN_ICE]
  facts_all: [CL-ICE-03, CL-CRI-05]
  facts_any: []
  facts_none: []
  channels: [chat_criada]
discovery:
  fact_ids: [CL-FRI-01]
  focus_eligible: true
retrieval:
  keywords: [heladera, falló, arregló, reparó, Pablo]
  neighbor_ids: [SCN-10-AT-02, SCN-10-AT-04]
  priority: 1.5
security:
  spoiler_level: 2
  resolution_only: false
variant: atomic
source_excerpt: "Le pregunté entonces si el aparato había tenido algún problema recientemente. Contestó que sí, que unos días antes había dejado de funcionar correctamente."
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
7. `resolution_only` es falso; los chats de NPC nunca reciben la resolución, ni siquiera después de acusar.

Para declaraciones del propio NPC, `knowledge_holders` suele contener al NPC. Para evidencia física puede contener solo `detective` hasta que el jugador se la mencione. El mensaje del usuario no altera permisos: escribir “ya sé que había cianuro” no vuelve verdadero ni accesible un hecho bloqueado.

## Niveles de spoiler

- `0`: ambientación y personalidad; no afecta el misterio.
- `1`: sospechas, motivos, relaciones, coartadas y hechos iniciales.
- `2`: piezas del mecanismo o vínculos incriminatorios importantes.
- `3`: reconstrucción final e identidad del culpable.

Todos los chunks de nivel 2 requieren revisión manual. Los de nivel 3 llevan `resolution_only: true` y se excluyen del conjunto candidato antes de calcular similitudes. Pueden persistirse en el mismo SQLite para una futura ruta separada de epílogo.

## Índice implementado

El índice vive en `backend/data/rag_index_atomic_embeddinggemma_two.sqlite3`.
Contiene los 162 vectores atómicos de pasaje y dos conjuntos de 162 vectores de
preguntas canónicas en `float32`, junto con versión de esquema, modelo,
dimensión y huellas SHA-256. Las preguntas q1 están en
`backend/data/canonical_questions.json` y las q2 en
`backend/data/canonical_questions_two.json`; ambas fueron congeladas y
revisadas editorialmente. Si cambia un chunk, una pregunta o el modelo configurado,
el backend rechaza el índice viejo en vez de mezclar versiones.

El modelo elegido es `hf.co/unsloth/embeddinggemma-300m-GGUF:Q4_0` mediante
`/api/embed` de Ollama:

- documentos atómicos: únicamente `retrieval_text` y palabras clave; el `source_excerpt` largo queda fuera del embedding;
- preguntas canónicas: q1 y q2 específicas y complementarias por átomo, embebidas con la misma instrucción de consulta;
- consultas: `task: search result | query: <pregunta>`;
- documentos: `title: none | text: <retrieval_text>\nPalabras clave: <keywords>`;
- dimensión conservada: 768; no se aplica reducción.

No hace falta un servidor vectorial para 162 entradas. SQLite aporta persistencia y validación; la similitud coseno y BM25 se calculan en memoria sobre el subconjunto permitido. Los chunks de resolución también tienen representación persistida para un futuro epílogo, pero se excluyen antes del ranking de cualquier chat de NPC.

### Corpus indexado

El único corpus activo es `atomic`: 162 chunks derivados de las mismas 15
escenas. Cada `retrieval_text` contiene un único dato breve (normalmente una
oración). La metadata de permisos, hechos y spoilers se conserva en el JSON;
`source_excerpt` mantiene el pasaje editorial completo para auditoría, pero no
se usa para embeddings ni se inyecta en el prompt.

El corpus se renderiza en el prompt como datos breves, sin anteponer
`claim_status`, voces, lectura desambiguada ni el texto fuente largo.

Para construir o reconstruir el índice:

```bash
python3 -m backend.scripts.build_rag_index --force
```

El comando lee los 15 archivos `*.atomic.chunks.json` existentes y pide los
embeddings por lotes. Sin `--force`, reutiliza un índice cuya huella y modelo
coincidan.

## Recuperación híbrida

Flujo de un turno:

1. Construir la consulta únicamente con la pregunta actual. El historial queda disponible para generación, pero nunca contamina el embedding de retrieval.
2. Filtrar chunks por NPC, canal, hitos, hechos internos y spoiler.
3. Formar la unión de los top-8 por similitud al pasaje y los top-8 por similitud a la pregunta canónica.
4. Normalizar pasaje, q1 y q2 dentro de los chunks disponibles. Combinar las señales canónicas como `0,75*q1 + 0,25*q2` y usar `max(pasaje, canónica_combinada)` como relevancia. Antes de eso, si el mejor `max(pasaje, q1, q2)` raw es menor que `0,50`, devolver contexto vacío.
5. Elegir un `focus_chunk` con desempate determinista por orden semántico/corpus, nunca por `chunk_id`.
6. Seleccionar hasta dos `support_chunk` mediante MMR (`lambda=0,70`), penalizando padres y vecinos repetidos; solo pueden contener hechos ya descubiertos o hechos del propio focus.
7. Empaquetar el contexto dentro del presupuesto de tokens.
8. Generar una única respuesta.
9. Si la respuesta terminó correctamente, registrar los `fact_ids` del `focus_chunk`, ejecutar derivaciones y recalcular las pistas visibles.

No se marca automáticamente como descubierto un hecho de un support chunk.

## Selección del focus chunk

El ranking no bonifica hechos nuevos ni penaliza hechos ya descubiertos: el
estado decide disponibilidad, no relevancia. Puede devolverse contexto vacío si
no hay chunks permitidos o si ninguno de los elementos seleccionados alcanza el
umbral raw. Si la generación termina correctamente, se registran los
`fact_ids` del focus; si falla o se cancela, no se modifica el estado.

## Repetición y contradicciones

Los chunks ya descubiertos siguen siendo recuperables y pueden volver a ser focus ante preguntas explícitas. Para los apoyos, MMR penaliza repetir el mismo padre o vecinos; la seguridad de hechos sigue prevaleciendo sobre la diversidad. El estado estructurado conserva:

- IDs de hechos internos descubiertos;
- IDs de pistas visibles formadas;
- acusación y desenlace;
- posturas canónicas del NPC, por ejemplo que Pablo niega tocar las cubeteras.

El historial textual no es la memoria factual permanente.

## Presupuesto de contexto

Configuración candidata: `num_ctx=1536`, incluyendo salida.

| Componente | Presupuesto orientativo |
|---|---:|
| Reglas compartidas y persona v2 (prefijo estable) | 180–260 tokens |
| Estado narrativo (aplicado fuera del prompt) | 0 |
| Historial completo de turnos anteriores | variable |
| `<retrieved_context>` actual | 80–360 |
| `<user_message>` actual | 30–120 |
| Respuesta reservada | 120–180 |
| Plantilla y margen | 150–250 |

`OLLAMA_MAX_HISTORY=0` conserva todo el historial. Un valor positivo limita la
cantidad de mensajes enviados, pero puede romper antes el prefijo cacheable.
El límite físico sigue siendo `num_ctx`; por eso una partida larga debe
calibrarse con consultas reales y, si hace falta, reducir el número de chunks
o configurar un límite explícito de historial.

Si se implementa una poda por contexto, se deben eliminar turnos completos y
desde el más antiguo:

1. turno más antiguo;
2. support chunk del turno actual;
3. detalles opcionales del estado.

Nunca se truncan la persona ni el mensaje actual. Los mensajes individuales del
jugador deben tener un límite de longitud.

## Forma del prompt generativo

```text
[SYSTEM]
Reglas comunes
Persona v2

[HISTORY]
[user turn 1, solo el texto original del jugador]
[assistant turn 1]
...
[user turn N-1, solo el texto original del jugador]
[assistant turn N-1]

[CURRENT TURN]
<retrieved_context>
Datos disponibles si hacen falta; no es necesario usar ninguno.
- [focus chunk con procedencia interna]
- [support chunks opcionales]
</retrieved_context>
<user_message>
[mensaje actual]
</user_message>
```

El modelo no recibe el catálogo entero de hechos o pistas visibles, el grafo, el nombre del culpable ni chunks bloqueados.

Los códigos `CL-*`, `PI-*` y `M*` no se envían al modelo. Solo determinan qué
datos pueden participar. `claim_status` queda fuera del prompt: se envía
únicamente el dato atómico recuperado y las reglas generales del personaje
piden conservar la cautela de su redacción.

## Runtime y concurrencia

Generación y embeddings tienen endpoints configurables por separado:

- `OLLAMA_CHAT_BASE_URL`
- `OLLAMA_EMBED_BASE_URL`

Hoy ambos pueden apuntar al mismo Ollama. En ese caso el backend serializa las llamadas para evitar que dos solicitudes compitan dentro del mismo runtime; `OLLAMA_MAX_LOADED_MODELS=2` permite mantener `gemma4:e4b` y `hf.co/unsloth/embeddinggemma-300m-GGUF:Q4_0` residentes.

Cada request establece `keep_alive=30m`. El historial se conserva completo por
defecto (`OLLAMA_MAX_HISTORY=0`). El contexto recuperado es efímero: solo se
agrega al mensaje `user` del turno actual. Al confirmar una respuesta se guarda
en la sesión el par `{role: user, content: pregunta_original}` y
`{role: assistant, content: respuesta}`. Así el historial no duplica pasajes,
no filtra metadata de retrieval y conserva un prefijo estable para la caché.
Un valor positivo de `OLLAMA_MAX_HISTORY` habilita un límite explícito.

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

1. todo chunk atómico conserva su procedencia en `source_excerpt` y `canonical_lines`;
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

- Hit@1, Hit@3 y MRR sobre preguntas con gold editorial de uno o más átomos; la evaluación de las respuestas queda para revisión manual separada.
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

## Decisiones ya calibradas

- el runtime usa embeddinggemma con un gate raw fijo de `0,50`, aplicado antes de la normalización por consulta; en el benchmark editorial de 100 consultas permite abstenerse ante consultas irrelevantes;
- la pregunta canónica complementa, no reemplaza, al pasaje original;
- el segundo support se limita por MMR y por seguridad de hechos para evitar repetir el mismo dato o adelantar pistas.

Los hechos del focus se registran únicamente después de que la respuesta termina sin error. Estas calibraciones no modifican el contrato del corpus.
