# raggame — Project Context

Authoritative map for AI assistants. Keep this file up to date.

## 1. Snapshot

- Godot 4.6 Forward Plus detective prototype (first-person, Spanish text input) that reenacts “Un crimen casi perfecto”. UX focuses on keyboard/controller parity, diegetic hubs, and PSX-era styling.
- FastAPI backend proxies to a local Ollama runtime. Today’s entrypoint still uses the older keyword-driven `DialogueService` while a more complete Hybrid RAG stack lives under `backend/rag/` but is not wired yet.
- Narrative data comes from the `story/` atomic chunk set (15 scenes × 162 facts) plus editorial scripts in `crimen-casi-perfecto-scripts/`.
- Analytics and balancing artifacts are captured in `findings/` (HTML reports, JSON benchmarks) and compose files spin up Ollama with both chat (`gemma4:e4b`) and embedding (`embeddinggemma-300m`) models.
- Several subsystems are half-migrated: the Godot client no longer sends HTTP requests, backend `/health` and `/` routes reference undefined helpers, and the README describes endpoints that do not exist yet.

## 2. Repository map

```
.gitignore
README.md                 ← docs claim a full RAG API; code hasn’t caught up
AGENTS.md                 ← this file
compose.yaml, compose.ollama.yaml   ← single-service Ollama setups (port 11434)
backend/
  main.py                 ← FastAPI app using DialogueService (legacy flow)
  requirements.txt        ← FastAPI 0.136, Pydantic 2.13, Requests 2.34, etc.
  rag/                    ← Config, corpus loader, HybridIndex, Ollama client, session state
  scripts/                ← build_embeddings.py (NPZ) + build_rag_index.py (SQLite index)
  data/                   ← canonical question maps (q1 + q2 frozen)
crimen-casi-perfecto-scripts/
  guiones/v2              ← per-character personas
  knowledge_base/         ← editorial scene breakdowns / references
  paso-a-paso-juego.md    ← full clue walkthrough
game/
  project.godot           ← main config (main scene = menu_inicio.tscn)
  menu_inicio.gd          ← all-code title UI + difficulty overlay + ambience
  scenes/                 ← player, NPC, locations, lineup, verdict, hub nodes
  data/                   ← Chat interface resource, hint catalog, clue definitions
  scripts/systems/        ← autoload singletons (event_manager, input_manager, pistas.md draft)
  ui/                     ← NotificationManager (toast stack)
  audio/, fonts/, assets/ ← imported ambience + VCR font + heavy PSX packs & docs
story/
  chunks/                 ← 15 *.atomic.chunks.json (retrieval facts)
  personas/, scenes/, source/  ← text personas + markdown plots + original PDFs
findings/                 ← HTML/JSON benchmark reports + shared CSS
assets/                   ← placeholder folder at repo root (currently empty)
```

## 3. Godot client

### Flow & scenes

- `menu_inicio.tscn` instantiates everything via script: title, subtitle, audio loop, vignette shader, and a modal difficulty picker (`Global.set_difficulty`). `Jugar` goes to `mapa_menu.tscn`, `Salir` quits.
- `mapa_menu.tscn` is a 3D evidence board. Nodes with `nodo_mapa` script (e.g., `comisaria`, `Hall`, `laboratorio`, `oficina`, `salida_mapa`) rotate, highlight on hover, and expose `get_scene_path()` so `_enter_location` can call `change_scene_to_file`.
- Core playable scenes: `Hall.tscn` (Criada, Esteban, Juan), `comisaria.tscn` (safe room + `pizarron` trigger to lineup), `laboratorio.tscn` (props only), `dpto.tscn` (crime scene + Forense NPC + examinables). `campo.tscn` remains as an older testing area.
- The lineup path is `pizarron.gd` → `reconocimiento.tscn` (select suspect) → `veredicto.tscn` (typewriter ending controlled by `Global.accused_id`).

### Autoloads, input & systems

- `Global` stores `accused_id`, `accused_name`, and the active difficulty profile; it now also seeds a random `session_id` string per boot.
- `EventManager` (scripts/systems/event_manager.gd) holds clue activation state, emits `event_activated`, exposes `activate_event/has_event/reset_events/get_event_history`, and loads metadata from `data/events/events.gd`. `check_input` normalizes the entire prompt and only matches exact keyword strings.
- `InputManager` tracks the most recent device (keyboard/mouse vs controller), emits `device_changed`, and provides glyph helpers used throughout the UI.
- `NotificationManager` builds a top-right toast stack; `show_clue_notification(event_id)` resolves summaries via `EventManager` and prepends “Pista encontrada”.
- `data/hints/hints.gd` (HintCatalog) maps clue IDs to expanded hints, with a default fallback shown by the “Pistas” button in the HUD.

### Player, UI & interactions

- `jugador.gd` (CharacterBody3D) handles movement, ray-based highlighting (collision mask 2, bodies only), NPC proximity, pizarrón/exit detection, “Pistas” overlay, and fade-in/out resets. It instantiates `DialogueUI` and a `CanvasLayer` hint button.
- When the player submits text, `EventManager.check_input` runs first and then the message streams through `nearby_npc.request_response`, so dialogue now reflects the FastAPI/Ollama response instead of a placeholder line.
- Highlight logic allows examining `copa`-style StaticBody3D nodes, interacting with `pizarron`/`salida_mapa`, or opening NPC prompts. Examining objects opens the dialogue panel in read-only mode and prints `get_description()`.
- `DialogueUI` builds the entire chat HUD procedurally: header (NPC name, close button, “Salir” hint), dynamic “keyword” reminders derived from the clue catalog, scrollable RichText history, LineEdit input, and floating prompt label. It reacts to `InputManager` to swap glyphs and updates placeholder text per NPC profile from `data/chat_interfaces.gd`.

### NPCs & interactables

- `npc.gd` sets up interaction areas, optional nameplates, recolor-able outfits, and a manual `HTTPClient` loop for streaming `/dialogue_stream`. `jugador.gd` connects to `response_chunk/response_completed` on demand each time it sends a question.
- `pizarron.gd` and `salida_mapa.gd` share the highlight/interaction pattern used by examinables.
- `copa.gd` demonstrates an examinable object (group `examinable`, `object_name`, highlight overlay, multiline description).
- `mapa_menu` node scripts (`oficina.gd`, `laboratorio.gd`, etc.) provide `get_scene_path` + `get_location_name`; defaults point to actual `.tscn` scenes.

## 4. Backend & retrieval

### FastAPI entrypoint (`backend/main.py`)

- Defines `/dialogue_stream` only; `/` and `/health` are present but reference undefined names (`HybridIndex`, `SETTINGS`, `_require_service`) and will raise when invoked. There is no `/sessions`, `/accuse`, or reset endpoint despite README claims.
- `DialogueService` (backend/rag/dialogue.py) loads personas from `story/personajes/*.md`, enforces shared rules (Rioplatense Spanish, 1–3 sentences, stay in character), keeps `(session_id, npc_id)` histories (last 20 messages), and prepends a `<retrieved_context>` block built from `retrieve_chunks`.
- `backend/rag/retrieval.py` is the active retriever: loads the 162 atomic chunks plus locally-generated embeddings from `backend/rag/embeddings.npz`, filters by `knowledge_holders`, availability facts (`necessary_facts`, `sufficient_facts`), computes cosine similarity via fresh query embeddings from Ollama’s `/api/embed`, and enforces `MAX_CHUNKS = 3`, `MIN_SIMILARITY = 0.5`. Discovered facts are tracked in-memory by `backend/rag/game_state.py`.
- Scripts expect you to run `backend/scripts/build_embeddings.py` against a live embedding model to (re)create `backend/rag/embeddings.npz`. The artifact is gitignored.

### Hybrid index stack (not wired yet)

- `backend/rag/` also contains a production-ready pipeline: `config.Settings` (env-driven), `corpus.Corpus` (validates chunk schema + canonical q1), `index.HybridIndex` (SQLite store with BM25 + dense retrieval, q2 weighting, calibrated raw-score gating), `state.SessionStore` (derives clues & milestones), and `service.RAGService` (creates streaming payloads with bounded history).
- `backend/scripts/build_rag_index.py` builds the SQLite index (embeddinggemma-only) using `backend/data/canonical_questions*.json` plus the frozen q2 map. Nothing calls `RAGService` from FastAPI yet, so this stack is effectively unused.

### Runtime & docs

- `compose.yaml` now brings up two services: `npc-ollama` (official Ollama image with `docker/ollama-entrypoint.sh` that auto-pulls `gemma4:e4b` + `embeddinggemma-300m`) and `rag-backend` (FastAPI container built from `Dockerfile.backend`). `compose.ollama.yaml` remains available if you only need the Ollama daemon.
- `backend/requirements.txt` pins FastAPI 0.136, Requests 2.34, Uvicorn 0.49, Numpy 2.5, etc.
- README.md currently documents an evolved RAG backend (`/health`, `/sessions/default`, `/accuse`, persistent index) that does not match the live code; treat it as a forward-looking spec.

## 5. Narrative assets & findings

- `story/chunks/*.atomic.chunks.json` contain the 162 atomic facts (retrieval_text, q1/q2, fact IDs, availability filters). `story/personajes/*.md` store short personas for Criada, Esteban, Juan, Pablo, Portero, Químico y Técnico.
- `story/scenes/*.md` outline each chronological beat; `story/source/` holds PDFs (e.g., Roberto Arlt scans).
- `crimen-casi-perfecto-scripts/knowledge_base/` ties case facts to scenes, while `guiones/v2/*.md` are the scripts consumed by the backend.
- `findings/` captures a trail of HTML/JSON reports (retrieval/BM25 benchmarks, prompt temperature sweeps, holdout validations). `findings/index.html` acts as a landing page.

## 6. Operations

1. **Docker quickstart** — Ensure `backend/rag/embeddings.npz` exists (run `python -m backend.scripts.build_embeddings` once), then start everything with `docker compose up -d --build`. This launches `npc-ollama` (auto-downloads `gemma4:e4b` + `embeddinggemma-300m`) and `rag-backend` (FastAPI on port 8000). Stop with `docker compose down`. Use `compose.ollama.yaml` if you only need the Ollama daemon. `scripts/run_game.sh` automates this flow (spinning up `npc-ollama`, generating embeddings inside the backend container if needed, waiting for readiness) and launches Godot once the backend reports “Application startup complete”; closing Godot (or running `./scripts/run_game.sh stop`) tears everything down.
2. **Manual environment (optional)**
   ```bash
   python -m venv backend/venv
   backend/venv/bin/pip install -r backend/requirements.txt
   backend/venv/bin/python -m backend.scripts.build_embeddings  # required for DialogueService
   backend/venv/bin/python -m backend.scripts.build_rag_index --force  # optional HybridIndex
   backend/venv/bin/uvicorn backend.main:app --host 127.0.0.1 --port 8000
   ```
   `/dialogue_stream` works; `/` and `/health` still crash due to missing helpers.
3. **Open Godot** — Launch `game/project.godot` with Godot 4.6 Forward Plus / Jolt enabled.

## 7. Current issues & gaps

1. **Legacy DialogueService still powers runtime** — Godot now streams through `/dialogue_stream`, but that endpoint still uses the minimalist `DialogueService` + NPZ embeddings instead of the HybridIndex/RAGService stack.
2. **Broken FastAPI metadata routes** — The `/` route references `HybridIndex.metadata_from(SETTINGS.index_path)` without importing `HybridIndex` or defining `SETTINGS`, and `/health` calls `_require_service()` which doesn’t exist. Hitting either endpoint throws `NameError`.
3. **README vs code drift** — Docs describe `/sessions/default`, `/accuse`, durable state, and the HybridIndex runtime, but `backend/main.py` only exposes `/dialogue_stream`. Expect confusion until the new service lands.
4. **Dual retrieval stacks** — Legacy NPZ embeddings (`retrieve_chunks`) and the newer SQLite HybridIndex live side by side. Only the old stack is wired, but build instructions for both are sprinkled around.
5. **Keyword matching is exact** — `EventManager.check_input` lowercases and trims but requires the entire player message to equal a keyword. Despite comments mentioning substring search, partial matches never fire clues.
6. **Temp + unused files** — `game/scenes/jugador.tscn102336247.tmp` remains in git, and `game/scripts/systems/pistas.md` is still empty.
7. **Lighting & art debt** — `Hall.tscn` still lacks a valid area light (Godot logs removal on load), resulting in a dark main scene.
8. **Backend state volatility** — Both the DialogueService history and `game_state` facts live in RAM; restarting FastAPI wipes progress and there’s no `/reset` endpoint yet.

## 8. Status (2026-09-14)

- Menu refactor landed: the title screen, difficulty overlay, and vignette shader are all script-driven; ambience loops at -20 dB on the Music bus.
- Player camera tweaks keep focus on interior spaces, hints/keyword UI were added, and the dialogue flow once again streams real responses from `/dialogue_stream`.
- Next concrete wins: fix the FastAPI metadata endpoints, decide whether to migrate `/dialogue_stream` onto `RAGService` or drop the unused HybridIndex code, and revisit EventManager’s keyword matching + Hall lighting debt.

Use this file as the canonical reference before touching the repo.
