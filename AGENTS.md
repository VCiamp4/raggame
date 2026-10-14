# AGENTS.md — RAGame

Guide for any AI model or developer working on this repository. Read this before
touching code, data, or story files.

## 1. What this project is

`RAGame` is a first-person, PSX-aesthetic detective game built in **Godot 4.7**
(Forward Plus) whose NPCs are powered by an **LLM + RAG** backend written in
**Python / FastAPI**. The player walks around a crime scene, interrogates
suspects/witnesses in free text, and must accuse the correct killer.

The case is an adaptation of the story **"Un crimen casi perfecto"**: Doña
Stevens is poisoned with potassium cyanide. The twist is that the poison was in
the **ice cubes** (from a tampered freezer), not in the whisky. The real culprit
is **Pablo**, the youngest brother (he is a lab worker with access to cyanide and
to the freezer).

Game title currently shown: "EL CRIMEN CASI PERFECTO" (provisional). Repository:
`https://github.com/VCiamp4/raggame`.

The repository is a monorepo that mixes four concerns:

| Directory      | Role                                                        |
| -------------- | ----------------------------------------------------------- |
| `game/`        | Godot 4.7 project (the actual playable client)              |
| `backend/`     | FastAPI service: RAG retrieval + LLM streaming              |
| `story/`       | Narrative source, NPC personas, and the retrieval corpus    |
| `benchmarks/`  | Retrieval and dialogue benchmarks, reports, human judgments |

The live Godot project is `game/project.godot`. Do not assume the root is a
Godot project.

## 2. Current status

- The RAG backend is functional and reasonably mature: fact-gated retrieval,
  streaming answers, per-session memory, two chat providers (Ollama / OpenAI).
- The story corpus has 15 scenes, 151 atomic chunks and 40 distinct `fact_id`s.
  The retrieval benchmark has 195 cases; the dialogue benchmark has 6
  conversations and 28 turns.
- The Godot game is **partially integrated**: movement, map navigation,
  examine-object UI, 3D dialogue portraits, a streaming HTTP client, a notebook,
  hints and difficulty selection exist. All seven backend NPCs have dialogue
  instances in the investigation locations (see §7).
- The accusation lineup has Pablo, Esteban, Juan and Criada. Each has an ending;
  Pablo is the correct accusation.
- Backend-discovered `CL-*` facts are the only clue state; the notebook and
  the "Pistas" button read them. Examined objects do not register facts.
- No automated tests, no CI, no Dockerfile for the backend or the game.

## 3. Repository layout

```
raggame/
├── compose.yaml                     # Ollama service only
├── backend/
│   ├── main.py                      # /, /dialogue_stream, /notebook, /hint
│   ├── config.py                    # Settings dataclass, three env options
│   ├── requirements.txt
│   ├── .env.example
│   ├── rag/
│   │   ├── retrieval.py             # loads chunks + embeddings, scoring, focus
│   │   ├── dialogue.py              # personas, system prompt, history, assembly
│   │   ├── game_state.py            # discovered-fact gating (in RAM), hints
│   │   └── embeddings.npz           # GENERATED, gitignored (must build)
│   └── scripts/build_embeddings.py  # generates rag/embeddings.npz
├── story/
│   ├── source/                      # original PDF + final markdown
│   ├── scenes/                      # 15 scene .md with YAML frontmatter
│   ├── chunks/                      # 15 *.atomic.chunks.json (151 chunks)
│   ├── personajes/                  # 7 one-paragraph persona files
│   ├── hints.json                   # prioritized hints for key facts
│   └── chunk-connections.html       # standalone fact/chunk graph visualizer
├── benchmarks/
│   ├── retrieval/
│   │   ├── corpus/retrieval_v1.json # 161 positive + 34 negative cases
│   │   ├── fixtures/chunks_v1.json  # frozen 151-chunk snapshot, 50 gated chunks
│   │   ├── scripts/run_retrieval.py # ranking + threshold sweep -> resultados_raw/
│   │   └── scripts/report_retrieval.py # builds resultados/retrieval.html
│   └── dialogue/
│       ├── corpus/dialogue_v1.json # 6 conversations, 28 turns
│       ├── scripts/run_dialogue.py # live retrieval + chat -> resultados_raw/
│       ├── scripts/report_dialogue.py # builds resultados/dialogue.html
│       └── resultados_raw/juicios/ # committed human judgments
└── game/
    ├── project.godot                # Godot 4.7, main scene menu_inicio
    ├── menu_inicio.gd               # title, difficulty, about, vignette, audio
    ├── audio/, fonts/               # VCR OSD Mono theme, ambience wav
    ├── assets/                      # PSX/props packs (many .glb/.fbx)
    ├── data/                        # inspectable catalog
    ├── scripts/systems/             # InputManager
    ├── ui/                          # NotificationManager
    └── scenes/                      # gameplay scenes/scripts, including libreta.gd
```

## 4. Backend architecture

### Request flow

1. `POST /dialogue_stream` with `{npc_id, player_input, session_id}`.
2. `DialogueService.get_message()` builds the LLM message list:
   `[system(persona + shared rules), ...history, user(<retrieved_context> + <user_message>)]`.
3. `retrieve_chunks()`:
   - filters chunks by `is_available(chunk, npc_id, session_id)`
     (`npc_id` must be in `knowledge_holders`; all `necessary_facts` must already
     be discovered; if `sufficient_facts` is non-empty, at least one must be
     discovered);
   - embeds the player input with Ollama `/api/embed` (no cache);
   - scores each candidate as `max(cosine(query, retrieval_text), cosine(query, q1), cosine(query, q2))`;
   - keeps scores `>= settings.min_similarity`;
   - picks a "focus" chunk (first of the top 3 with a `fact_id`, else rank 1),
     then appends support chunks while `is_support()`;
   - marks the focus `fact_id` as discovered for the session.
4. The provider stream is forwarded to the client as plain text. On success the
   turn is appended to in-RAM history. If retrieval discovered a new fact, the
   response carries it in an `X-New-Fact` header (comma-separated `fact_id`s).
5. Providers: `CHAT_PROVIDER=ollama` (default, `POST /api/chat`) or `openai`
   (`POST /v1/chat/completions`, uses `max_completion_tokens` and
   `reasoning_effort="none"`).

`GET /notebook/{session_id}` returns a `clues` array with `fact_id` and `text`
for chunks whose facts have been discovered in that backend session.

`GET /hint/{session_id}?with_npc=<bool>` returns `{"hint": {fact_id, text}}`
or `{"hint": null}`. It walks `story/hints.json` in order and returns the first
undiscovered fact with a chunk whose `necessary_facts`/`sufficient_facts` are
satisfied (`game_state.is_unlocked()`, the NPC-independent half of
`is_available()`). `with_npc` selects `text_with_npc` over `text`.

### Key config (`backend/config.py`)

`CHAT_PROVIDER`, `CHAT_MODEL` and `OPENAI_API_KEY` are read from the environment.
The API key defaults to an empty string. The remaining settings are code defaults;
the embedding build script also accepts `--model` for that build.

| Setting           | Default              | Notes                                 |
| ----------------- | -------------------- | ------------------------------------- |
| `chat_provider`   | `ollama`             | or `openai`                           |
| `chat_model`      | `gemma4:e4b`         | chat/instruct model                   |
| `embedding_model` | `qwen3-embedding:4b` | fixed in code, not env                |
| `ollama_url`      | `http://localhost:11434` | fixed in code                     |
| `max_chunks`      | `3`                  | retrieved chunks per turn             |
| `min_similarity`  | `0.43`               | retrieval threshold                   |
| `max_history`     | `20`                 | recent messages sent to the model     |
| `num_predict`     | `160`                | max output tokens                     |
| `temperature`     | `0.8`                |                                       |

For local configuration, copy `backend/.env.example` to `backend/.env` and fill
in the provider/model/API key values. `.env` files are gitignored.

### Important backend caveats

- `CHUNKS = load_chunks()` runs at **import time** and reads
  `backend/rag/embeddings.npz`. If that file is missing, the app crashes on
  startup. It is generated by `backend/scripts/build_embeddings.py`.
- All conversation history and discovered facts live **in process memory**
  (`dialogue_service.HISTORIES` on the app's service instance and
  `game_state.discovered_facts`). They are lost on restart and break under
  multiple uvicorn workers. No persistence, no locking. Stored histories grow
  without a cap; `max_history` only limits the slice included in a model request.
- The system prompt and NPC personas are in **Spanish (Rioplatense)**. Keep
  persona/prompt language consistent when editing.
- `DialogueService.save_response()` stores the raw `player_input` in history,
  while the model saw it wrapped in `<retrieved_context>` / `<user_message>`.
  This is a known minor inconsistency.
- `game_state.update_fact()` assumes `discovered_facts[session_id]` already
  exists (it is created on first `get_discovered_facts` call via retrieval).
- Retrieval records the focus fact before the chat stream succeeds. A failed
  generation can therefore leave a fact in the notebook without a completed turn.
- No CORS middleware (irrelevant for Godot's `HTTPClient`, needed for browsers).

## 5. Story data model

### Scenes (`story/scenes/*.md`)

YAML frontmatter + a `<!-- SOURCE_START --> ... <!-- SOURCE_END -->` body:

- `scene_id` (`SCN-01`..`SCN-15`), `title`, `canonical_lines` (line range in
  `story/source/un-crimen-casi-perfecto-version-final.md`), `locations`,
  `present_entities`, `mentioned_entities`.
- `availability` and `index_policy` (`investigation` or `resolution`) are
  source metadata. Neither is evaluated by the runtime. Retrieval availability
  is defined by the chunk fields below.

### Chunks (`story/chunks/*.atomic.chunks.json`)

One file per scene; 151 chunks total. Each chunk:

```json
{
  "chunk_id": "SCN-01-AT-08",
  "retrieval_text": "La puerta estaba asegurada desde dentro con una cadena de acero.",
  "knowledge_holders": ["criada", "portero"],
  "questions": { "q1": "...", "q2": "..." },
  "source_excerpt": "...",
  "fact_id": "CL-CASE-01",
  "necessary_facts": [],
  "sufficient_facts": []
}
```

- `fact_id` is `null` for support chunks; 40 distinct `CL-*` facts exist.
- 9 of the 15 chunk files contain nonempty `necessary_facts`/`sufficient_facts`;
  50 chunks have fact requirements.
- Chunks are **hand-authored, committed artifacts**. There is no script that
  regenerates chunks from `story/scenes/`; keep them in sync manually.

### Personas (`story/personajes/*.md`)

Seven NPCs, each a single Spanish paragraph: `criada`, `esteban`, `juan`,
`pablo`, `portero`, `forense`, `tecnico_heladera`. `dialogue.PERSONAJES_FILES`
maps `npc_id` -> filename; adding an NPC requires editing that map **and**
creating the file.

### Hints (`story/hints.json`)

An ordered list of `{fact_id, text, text_with_npc}`; order is priority. Only
key facts have hints (method chain, means, motive, locked room); facts without
an entry are never suggested. `text` must not name who to ask; `text_with_npc`
does. `game_state.next_hint()` loads it at import; a `fact_id` that does not
exist in the chunks is silently never suggested.
Changing chunk gates can change when a hint becomes available.

### Game inspectable catalog (`game/data/`)

- `inspectables.gd` defines object names and descriptions shown when examining.
  Examining an object does not contact the backend or register any fact.
- Keep inspectable text consistent with the story chunks.

### Graph

`story/chunk-connections.html` is a self-contained visualization of the
chunk/fact graph (necessary/sufficient edges, knowledge holders). It is a dev
aid, not used at runtime.

## 6. Benchmarks

### Retrieval (`benchmarks/retrieval/`)

- Corpus `benchmarks/retrieval/corpus/retrieval_v1.json`: 195 cases
  (161 positive = 108 fact + 53 support; 34 negative). Each case has `npc_id`,
  `known_facts`, `query`, `expected_focus`.
- Fixture `fixtures/chunks_v1.json`: frozen 151-chunk snapshot with 50 gated
  chunks. The runner filters candidates against each case's `known_facts` using
  its own `chunk_is_available()` function. It checks availability rules without
  directly testing the backend's stateful `game_state.is_available()` function.
- `run_retrieval.py` computes ranking metrics (Hit@1, Hit@3, MRR), a threshold
  sweep, and worst-case tables. Focus strategies: `top1` and `fact_top3`
  (`first_fact_in_top3`). Output goes to `resultados_raw/` (gitignored).
- `report_retrieval.py` renders `resultados/retrieval.html` (gitignored).
- Fixture embeddings (`fixtures/embeddings_*.npz`) are gitignored and must be
  generated with `build_embeddings.py --model ... --out ...`.
- `--corpus`, `--chunks`, `--embeddings`, `--embedding-model`, `--focus` and
  `--run-name` select inputs and runs. With no model/path selection, the runner
  uses all `fixtures/embeddings_*.npz` files and both focus strategies.
- `--validate-only` makes no Ollama requests, but requires installed Python
  dependencies, the backend embedding index and a fixture embedding index.

### Dialogue (`benchmarks/dialogue/`)

- Corpus `corpus/dialogue_v1.json`: 6 conversations, 28 turns.
- `scripts/run_dialogue.py` runs real retrieval and streaming chat, recording
  responses, retrieved chunk IDs, newly discovered facts, retrieval time and
  time to first token. It accepts `--chat-provider`, `--chat-model` and
  `--run-name`; an existing run filename is not overwritten.
- `--validate-only` checks the corpus without contacting a model, but still
  imports the backend and requires its embedding index.
- OpenAI runs require `gpt-6-luna`, an API key and the 28-turn corpus.
- `scripts/report_dialogue.py` builds `resultados/dialogue.html` with context,
  ideal-chunk comparisons and human ratings. Export ratings as `juicios.json`
  into `resultados_raw/juicios/` and regenerate the report to incorporate them.

## 7. Godot game

- Engine: **Godot 4.7**, Forward Plus, Jolt Physics. Autoloads:
  - `Global` (`scenes/global.gd`): accusation, launch session ID, difficulty
    profile and hint usage.
  - `InputManager` (`scripts/systems/input_manager.gd`): last input device and
    input glyph helpers.
  - `NotificationManager` (`ui/notification_manager.gd`): message toasts.
- Input action `interact` = physical key `E` (physical_keycode 69).
- Scene flow: title -> difficulty selection -> `mapa_menu` (4 spinning
  `nodo_mapa` nodes: comisaria, laboratorio, oficina, departamento) -> locations.
  The departamento map icon opens `Hall.tscn`; its elevators lead to `dpto`.
  The board in `comisaria.tscn` opens `reconocimiento` -> `veredicto`.
- The map supports mouse selection, arrow-key focus and `ui_accept` to enter a
  location. Location totems return to the map with `E` or `Esc` when nearby.
- NPC locations and IDs:
  - Comisaría: Juan (`juan`), for his police-station interrogation.
  - Oficina: Esteban (`esteban`), the insurance broker.
  - Laboratorio: Pablo (`pablo`), at the milk-analysis laboratory Erpa.
  - Hall: Portero (`portero`), near the building entrance.
  - Departamento (`dpto`): Criada (`criada`), Forense (`forense`) and Técnico
    (`tecnico_heladera`), with the technician beside the refrigerator.
  Forense examines the crime scene and ice in the apartment. The four lineup
  models in `reconocimiento.tscn` are separate accusation targets.
- `npc.gd` (`Node3D`): exports `npc_id`/`npc_name`, uses `HTTPClient` to stream
  from `127.0.0.1:8000/dialogue_stream`, emits `response_chunk` /
  `response_completed`, then `Global.fact_discovered` for each `X-New-Fact`.
- `jugador.gd` (`CharacterBody3D`): WASD movement, `E` to interact, raycast/mouse
  inspection, elevators, board and totem interactions, and the "Pistas" button.
- `dialogue_ui.gd` builds the whole chat UI in code (no `.tscn` layout),
  appends streamed chunks, disables input while streaming and renders
  player/NPC models in portrait SubViewports.
- `libreta.gd` builds the notebook, queries `/notebook/{session_id}` and groups
  discovered fact text into character pages. It uses backend state exclusively.
  On `Global.fact_discovered` it shows a toast naming the clue's page, a red
  unread badge and a pulse on its icon, and opens on the newest clue's page.
- The "Pistas" button in `jugador.gd` requests `/hint/{session_id}`. Difficulty
  sets `hint_limit` (`-1` unlimited, `0` hides the button) and `hint_names_npc`:
  Fácil and Medio are unlimited, only Fácil names the NPC, Difícil has no
  hints. A use is spent only when the hinted fact differs from
  `Global.last_hint_fact_id`; repeating an undiscovered hint is free.
- `reconocimiento.tscn` has four selectable suspects: Pablo, Esteban, Juan and
  Criada. `veredicto.gd` displays their endings with a typewriter effect;
  `CULPABLE_REAL = "pablo"`.

### Godot conventions

- GDScript, tabs for indentation.
- Several UIs (`dialogue_ui.gd`, `menu_inicio.gd`, `reconocimiento.gd`) are
  constructed programmatically rather than in the editor.
- Keep the PSX/horror aesthetic (VCR OSD Mono font, dark palette, vignette +
  grain shader in `menu_inicio.gd`).

## 8. Known gaps, bugs, and missing pieces

These are the highest-value things to know before making changes.

### Integration / wiring

1. **Demo NPC ID.** `campo.tscn` instances `npc.tscn` without overriding its
   default ID `"Aldric"`, which is absent from the backend persona map.
2. **Hints depend on backend memory.** Discovered facts live in RAM, so a
   backend restart resets hint progress (and the notebook) for every session.
3. **Object discoveries do not reach the backend.** Examining an object (for
   example the office archive with the original policy) registers no `CL-*`
   fact, so it neither unlocks gated chunks nor appears in the notebook.
4. **Map input/transition handling.** `ui_accept` changes scenes before calling
   `get_viewport().set_input_as_handled()`, potentially using a detached viewport.
   Clicking empty map space enters the retained focused location.
5. **Portrait rendering.** `_collect_aabb()` applies child mesh transforms twice;
   SubViewports render with `UPDATE_ALWAYS` even while hidden. Freshly instanced
   portrait models do not inherit world NPC poses.
6. **Duplicate dialogue scripts.** Uppercase `DialogueUI.gd` has diverged and has
   no tracked resource references. Lowercase `dialogue_ui.gd` is used by both
   `jugador.tscn` and `DialogueUI.tscn`; `campo.tscn` uses `DialogueUI.tscn`.
7. **Editor leftovers:** `game/scenes/jugador.tscn102336247.tmp`,
   `game/scenes/elevador.tscn` vs `ascensor`, and `.godot/` caches should not be
   edited by hand.

### Backend / infra

8. **In-memory state only** (history + discovered facts). No DB, no persistence,
   not multi-worker safe.
9. **No automated tests and no CI.** Validation tooling consists of the
   retrieval and dialogue benchmarks.
10. **Docker is incomplete.** `compose.yaml` starts only Ollama. There is no
    Dockerfile or Compose service for the backend or game.
11. **No chunk build pipeline.** Chunks and their gating are hand-authored; the
    benchmark fixture is a separate frozen copy and can drift from live data.
12. **No embedding cache**; every retrieval query with available candidates is
    embedded again.

## 9. How to run

Prerequisites: Python 3.12, Godot 4.7, and Ollama (local or via Docker). The
backend imports use the `backend.*` package, so **run from the repo root**.

```bash
# 1. Python dependencies (use a virtual environment)
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r backend/requirements.txt
```

For step 2, choose Docker or local Ollama. With Docker:

```bash
docker compose up -d
docker compose exec npc-ollama ollama pull qwen3-embedding:4b
docker compose exec npc-ollama ollama pull gemma4:e4b
```

With local Ollama, start `ollama serve` and pull the models in another terminal:

```bash
ollama pull qwen3-embedding:4b
ollama pull gemma4:e4b
```

Then continue from the repo root with the virtual environment active:

```bash
# 3. Configure backend (optional; needed for OpenAI)
cp backend/.env.example backend/.env   # then edit

# 4. Build the embedding index (required once, and after chunk changes)
python backend/scripts/build_embeddings.py
#   optional: --model qwen3-embedding:4b --chunks story/chunks --out backend/rag/embeddings.npz

# 5. Run the API
uvicorn backend.main:app --host 127.0.0.1 --port 8000

# 6. Run the game in another terminal
godot --path game          # or open game/project.godot in the editor
```

For OpenAI chat, set `CHAT_PROVIDER=openai`, a compatible `CHAT_MODEL` and
`OPENAI_API_KEY`. Ollama is still needed for query embeddings.

Retrieval benchmark (after the backend index has been built):

```bash
python backend/scripts/build_embeddings.py \
  --model qwen3-embedding:4b \
  --chunks benchmarks/retrieval/fixtures/chunks_v1.json \
  --out benchmarks/retrieval/fixtures/embeddings_qwen3-embedding:4b.npz
python benchmarks/retrieval/scripts/run_retrieval.py --validate-only \
  --embedding-model qwen3-embedding:4b
python benchmarks/retrieval/scripts/run_retrieval.py
python benchmarks/retrieval/scripts/report_retrieval.py
```

Dialogue benchmark:

```bash
python benchmarks/dialogue/scripts/run_dialogue.py --validate-only
python benchmarks/dialogue/scripts/run_dialogue.py
python benchmarks/dialogue/scripts/report_dialogue.py
```

There is no lint/typecheck/test command configured in the repo. If you add one,
document it here.

## 10. Working conventions

- Do not commit generated indexes, reports or local state:
  `backend/rag/embeddings.npz`, `benchmarks/**/embeddings_*.npz`,
  `benchmarks/**/resultados/`, `.env`, `.godot/`, `ollama_models/`.
  Raw benchmark runs are ignored except the three named dialogue runs and
  `benchmarks/dialogue/resultados_raw/juicios/` explicitly retained in
  `.gitignore`. Preserve those committed inputs; do not broadly unignore runs.
- For agent commits, use `<type>: <short English description>` with a lowercase
  imperative verb and no trailing period; preserve Spanish domain names where
  useful. Label merge commits as merges. Follow `AGENTS.override.md` when present.
- Domain language is Spanish. Prompts, personas, story, and UI strings should
  stay in Spanish unless a task explicitly says otherwise.
- The story/retrieval data is the source of truth for NPC knowledge. When adding
  or changing facts, update the scene frontmatter, the chunk JSON (including
  `knowledge_holders`, `necessary_facts`, `sufficient_facts`, and `fact_id`),
  rebuild embeddings, and re-run the benchmark.
- Prefer editing existing files; keep changes scoped.
