# Un crimen casi perfecto — juego con NPCs RAG

El juego Godot consulta un backend local que recupera datos atómicos permitidos del cuento con `embeddinggemma-300m` y genera la respuesta del personaje con `gemma4:e4b`. La configuración recomendada usa el índice separado `backend/data/rag_index_atomic_embeddinggemma_two.sqlite3`, con una pregunta canónica q1 y una q2 congelada por chunk, normalizadas y combinadas 0.75/0.25. La personalidad vive en `guiones/v2`; los hechos del caso se recuperan desde los chunks atómicos de las escenas.

Los resultados y decisiones técnicas están resumidos en [findings/index.html](findings/index.html).

## Docker (recomendado)

1. Generá los embeddings legacy si todavía no existen:
   ```bash
   python -m backend.scripts.build_embeddings  # requiere Ollama local con embeddinggemma
   ```
   Esto crea `backend/rag/embeddings.npz`, necesario para el `DialogueService` actual.
2. Iniciá backend + modelos con Compose:
   ```bash
   docker compose up -d --build
   ```
   El servicio `npc-ollama` usa `docker/ollama-entrypoint.sh` para levantar `ollama serve`,
   esperar a que el daemon responda y descargar automáticamente `gemma4:e4b` y
   `hf.co/unsloth/embeddinggemma-300m-GGUF:Q4_0` dentro de `./ollama_models/`.
   El servicio `rag-backend` se construye a partir de `Dockerfile.backend` y expone FastAPI en `http://127.0.0.1:8000`.
3. Ejecutá `game/project.godot` de manera local. El cliente ya apunta a `127.0.0.1:8000`,
   así que basta con tener los contenedores corriendo para que los NPC respondan.

Apagá todo con `docker compose down`. Si solo necesitás el daemon de Ollama (por ejemplo, para reconstruir índices), podés usar `compose.ollama.yaml`:

```bash
docker compose -f compose.ollama.yaml up -d
```

Ese archivo comparte el mismo entrypoint y auto-descarga de modelos, pero omite el contenedor del backend.

### Script todo-en-uno

Si tenés Docker y Godot instalados en el host podés usar `scripts/run_game.sh`, que:

1. levanta `npc-ollama`, genera `backend/rag/embeddings.npz` dentro del contenedor de backend (no instala dependencias en tu sistema) y vuelve a dejar el daemon corriendo;
2. ejecuta `docker compose up -d --build` y espera a que `rag-backend` imprima “Application startup complete”;
3. lanza Godot (`godot4` o `godot`, configurable via `GODOT_BIN`).

Ejemplo:

```bash
./scripts/run_game.sh
```

El script mantiene los contenedores activos mientras Godot esté abierto y ejecuta `docker compose down` automáticamente al cerrar el juego o al recibir `Ctrl+C`. Si necesitás bajar todo sin abrir Godot, corré `./scripts/run_game.sh stop`. Ajustá `GODOT_BIN=/ruta/a/godot` si tu ejecutable no está en el PATH.

## Configuración manual

Los pasos siguientes siguen siendo útiles si preferís correr todo sin Docker.

1. Levantá Ollama en tu host (o mediante `compose.ollama.yaml`). Luego descargá los modelos:
   ```bash
   docker exec npc-ollama ollama pull gemma4:e4b
   docker exec npc-ollama ollama pull hf.co/unsloth/embeddinggemma-300m-GGUF:Q4_0
   ```
2. Creá el entorno Python:
   ```bash
   python -m venv backend/venv
   backend/venv/bin/pip install -r backend/requirements.txt
   ```
3. (Opcional) Construí el índice híbrido SQLite si querés experimentar con `backend/rag/service.py`:
   ```bash
   OLLAMA_EMBED_MODEL=hf.co/unsloth/embeddinggemma-300m-GGUF:Q4_0 \
   RAG_INDEX_PATH=backend/data/rag_index_atomic_embeddinggemma_two.sqlite3 \
   backend/venv/bin/python -m backend.scripts.build_rag_index --force
   ```
4. Ejecutá el backend manualmente:
   ```bash
   backend/venv/bin/uvicorn backend.main:app --host 127.0.0.1 --port 8000
   ```

Después abrí `game/project.godot`. Todos los NPC usan la sesión `default`. El historial conversacional se mantiene separado por NPC, mientras que el estado estructurado de la sesión —hechos descubiertos, pistas e hitos— continúa al cambiar de escena.


Endpoints útiles:

- `GET /health`: modelos, índice y NPCs configurados;
- `POST /dialogue_stream`: respuesta de texto en streaming;
- `GET /sessions/default`: hechos, pistas e hitos actuales;
- `POST /sessions/default/reset`: reinicia la partida del backend;
- `POST /accuse`: endpoint exploratorio del backend que valida la regla de dos pistas visibles; todavía no está conectado a una acción o interfaz del juego.

## Configuración

Las variables disponibles están documentadas en `backend/.env.example`. `OLLAMA_CHAT_BASE_URL` y `OLLAMA_EMBED_BASE_URL` son independientes aunque hoy apunten al mismo contenedor. El corpus activo es `atomic`; el único índice operativo es `backend/data/rag_index_atomic_embeddinggemma_two.sqlite3` y usa `backend/data/canonical_questions_two.json`. El runtime rechaza modelos de embeddings ajenos a la familia embeddinggemma y no admite índices q1-only ni esquemas anteriores a q1+q2. El umbral raw 0.50 por chunk seleccionado fue validado para embeddinggemma en el benchmark editorial de 100 consultas. El contexto generativo por defecto es 1536 tokens y el historial conversacional completo se conserva por defecto (`OLLAMA_MAX_HISTORY=0`) por separado para cada NPC; solo guarda la pregunta original del jugador y la respuesta del NPC. El `system` queda estable con reglas y persona; el contexto RAG y la pregunta se agregan únicamente al mensaje `user` del turno actual.
