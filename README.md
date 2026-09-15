# Un crimen casi perfecto — juego con NPCs RAG

El juego Godot consulta un backend local que recupera datos atómicos permitidos del cuento con `embeddinggemma-300m` y genera la respuesta del personaje con `gemma4:e4b`. La configuración recomendada usa el índice separado `backend/data/rag_index_atomic_embeddinggemma_two.sqlite3`, con una pregunta canónica q1 y una q2 congelada por chunk, normalizadas y combinadas 0.75/0.25. La personalidad vive en `guiones/v2`; los hechos del caso se recuperan desde los chunks atómicos de las escenas.

Los resultados y decisiones técnicas están resumidos en [findings/index.html](findings/index.html).

## Preparación

Los dos modelos deben existir en Ollama:

```bash
docker exec npc-ollama ollama pull gemma4:e4b
docker exec npc-ollama ollama pull hf.co/unsloth/embeddinggemma-300m-GGUF:Q4_0
```

La configuración reproducible del runtime está en `compose.ollama.yaml`. Admite dos modelos cargados a la vez; el backend mantiene cada uno residente durante 30 minutos y permite separar los endpoints más adelante.

Con el entorno Python ya creado:

```bash
backend/venv/bin/pip install -r backend/requirements.txt
OLLAMA_EMBED_MODEL=hf.co/unsloth/embeddinggemma-300m-GGUF:Q4_0 \
RAG_INDEX_PATH=backend/data/rag_index_atomic_embeddinggemma_two.sqlite3 \
backend/venv/bin/python -m backend.scripts.build_rag_index --force
```

El comando usa los 15 archivos `*.atomic.chunks.json`,
`backend/data/canonical_questions.json` y el mapa congelado
`backend/data/canonical_questions_two.json`. Crea 162 embeddings de pasajes,
162 de q1 y 162 de q2. Ese índice es el único artefacto SQLite operativo del
runtime.
Los chunks no se regeneran durante la construcción del índice.

## Ejecución

Desde la raíz del repositorio:

```bash
backend/venv/bin/uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Después se ejecuta `game/project.godot`. Todos los NPC usan la sesión `default`. El historial conversacional se mantiene separado por NPC, mientras que el estado estructurado de la sesión —hechos descubiertos, pistas e hitos— continúa al cambiar de escena. Ese estado puede desbloquear contexto para otros NPCs, respetando sus permisos narrativos. No se añadió ninguna interfaz nueva.


Endpoints útiles:

- `GET /health`: modelos, índice y NPCs configurados;
- `POST /dialogue_stream`: respuesta de texto en streaming;
- `GET /sessions/default`: hechos, pistas e hitos actuales;
- `POST /sessions/default/reset`: reinicia la partida del backend;
- `POST /accuse`: endpoint exploratorio del backend que valida la regla de dos pistas visibles; todavía no está conectado a una acción o interfaz del juego.

## Configuración

Las variables disponibles están documentadas en `backend/.env.example`. `OLLAMA_CHAT_BASE_URL` y `OLLAMA_EMBED_BASE_URL` son independientes aunque hoy apunten al mismo contenedor. El corpus activo es `atomic`; el único índice operativo es `backend/data/rag_index_atomic_embeddinggemma_two.sqlite3` y usa `backend/data/canonical_questions_two.json`. El runtime rechaza modelos de embeddings ajenos a la familia embeddinggemma y no admite índices q1-only ni esquemas anteriores a q1+q2. El umbral raw 0.50 por chunk seleccionado fue validado para embeddinggemma en el benchmark editorial de 100 consultas. El contexto generativo por defecto es 1536 tokens y el historial conversacional completo se conserva por defecto (`OLLAMA_MAX_HISTORY=0`) por separado para cada NPC; solo guarda la pregunta original del jugador y la respuesta del NPC. El `system` queda estable con reglas y persona; el contexto RAG y la pregunta se agregan únicamente al mensaje `user` del turno actual.
