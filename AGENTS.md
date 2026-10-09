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

Game title currently shown: "EL DEPARTAMENTO" (provisional). Repo remote:
`git@github.com:VCiamp4/raggame.git`.

The repository is a monorepo (there is a remote branch `monorepo-restructure`)
that mixes four concerns:

| Directory      | Role                                                        |
| -------------- | ----------------------------------------------------------- |
| `game/`        | Godot 4.7 project (the actual playable client)              |
| `backend/`     | FastAPI service: RAG retrieval + LLM streaming              |
| `story/`       | Narrative source, NPC personas, and the retrieval corpus    |
| `benchmarks/`  | Offline retrieval benchmark (corpus, fixtures, scripts)     |

The live Godot project is `game/project.godot`. Do not assume the root is a
Godot project.

## 2. Current status (as of the latest commit `90990a9`, branch `rag-integration-v2`)

- The RAG backend is functional and reasonably mature: fact-gated retrieval,
  streaming answers, per-session memory, two chat providers (Ollama / OpenAI).
- The story corpus is complete (15 scenes, 151 atomic chunks, 41 `fact_id`s,
  ~195 benchmark cases).
- The Godot game is **partially integrated**: movement, map navigation,
  examine-object UI, a code-built dialogue UI, and a streaming HTTP client to the
  backend all exist, but the detective scenes are **not yet wired to the real
  NPCs** (see gaps in section 8).
- No automated tests, no CI, no Dockerfile for the backend or the game.
- Many feature branches exist; the working branch is `rag-integration-v2`.

## 3. Repository layout

```
raggame/
├── compose.yaml                     # Ollama service only
├── docker/ollama-entrypoint.sh/     # EMPTY DIRECTORY (broken artifact, see §8)
├── backend/
│   ├── main.py                      # FastAPI app, / and /dialogue_stream
│   ├── config.py                    # Settings dataclass (env-driven)
│   ├── requirements.txt
│   ├── .env.example
│   ├── rag/
│   │   ├── retrieval.py             # loads chunks + embeddings, scoring, focus
│   │   ├── dialogue.py              # personas, system prompt, history, assembly
│   │   ├── game_state.py            # discovered-fact gating (in RAM)
│   │   └── embeddings.npz           # GENERATED, gitignored (must build)
│   └── scripts/build_embeddings.py  # generates rag/embeddings.npz
├── story/
│   ├── source/                      # original PDF + final markdown
│   ├── scenes/                      # 15 scene .md with YAML frontmatter
│   ├── chunks/                      # 15 *.atomic.chunks.json (151 chunks)
│   ├── personajes/                  # 7 one-paragraph persona files
│   └── chunk-connections.html       # standalone fact/chunk graph visualizer
├── benchmarks/retrieval/
│   ├── corpus/retrieval_v1.json     # 161 positive + 34 negative cases
│   ├── fixtures/chunks_v1.json      # frozen 151-chunk snapshot (NO gating)
│   ├── scripts/run_retrieval.py     # runs + threshold sweep -> resultados_raw/
│   └── scripts/report_retrieval.py  # builds resultados/retrieval.html
└── game/
    ├── project.godot                # Godot 4.7, main scene menu_inicio
    ├── menu_inicio.gd               # title screen + vignette shader + audio
    ├── audio/, fonts/               # VCR OSD Mono theme, ambience wav
    ├── assets/                      # PSX/props packs (many .glb/.fbx)
    └── scenes/                      # all .gd + .tscn (see §7)
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
   turn is appended to in-RAM history.
5. Providers: `CHAT_PROVIDER=ollama` (default, `POST /api/chat`) or `openai`
   (`POST /v1/chat/completions`, uses `max_completion_tokens` and
   `reasoning_effort`).

### Key config (`backend/config.py`, overridable via `.env`)

| Setting           | Default              | Notes                                 |
| ----------------- | -------------------- | ------------------------------------- |
| `chat_provider`   | `ollama`             | or `openai`                           |
| `chat_model`      | `gemma4:e4b`         | chat/instruct model                   |
| `embedding_model` | `qwen3-embedding:4b` | fixed in code, not env                |
| `ollama_url`      | `http://localhost:11434` | fixed in code                     |
| `max_chunks`      | `3`                  | retrieved chunks per turn             |
| `min_similarity`  | `0.43`               | retrieval threshold                   |
| `max_history`     | `20`                 | messages kept per (session, npc)      |
| `num_predict`     | `160`                | max output tokens                     |
| `temperature`     | `0.8`                |                                       |

`.env` is gitignored; copy `.env.example` and fill in values. There is currently
**no `.env` in the repo**.

### Important backend caveats

- `CHUNKS = load_chunks()` runs at **import time** and reads
  `backend/rag/embeddings.npz`. If that file is missing, the app crashes on
  startup. It is generated by `backend/scripts/build_embeddings.py`.
- All conversation history and discovered facts live **in process memory**
  (`dialogue.HISTORIES`, `game_state.discovered_facts`). They are lost on
  restart and break under multiple uvicorn workers. No persistence, no locking.
- The system prompt and NPC personas are in **Spanish (Rioplatense)**. Keep
  persona/prompt language consistent when editing.
- `dialogue.save_response()` stores the raw `player_input` in history, while the
  model actually saw it wrapped in `<retrieved_context>` / `<user_message>`.
  This is a known minor inconsistency.
- `game_state.update_fact()` assumes `discovered_facts[session_id]` already
  exists (it is created on first `get_discovered_facts` call via retrieval).
- No CORS middleware (irrelevant for Godot's `HTTPClient`, needed for browsers).

## 5. Story data model

### Scenes (`story/scenes/*.md`)

YAML frontmatter + a `<!-- SOURCE_START --> ... <!-- SOURCE_END -->` body:

- `scene_id` (`SCN-01`..`SCN-15`), `title`, `canonical_lines` (line range in
  `story/source/un-crimen-casi-perfecto-version-final.md`), `locations`,
  `present_entities`, `mentioned_entities`.
- `availability`: milestone gate, e.g. `M00_CASE_OPEN`,
  `M10_POISONING_CONFIRMED`, `INSPECT_POLICY`, `M30_ICE_HYPOTHESIS`,
  `M50_PABLO_FRIDGE_LINK`, `M81_VICTORY`.
- `index_policy`: `investigation` or `resolution`.

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

- `fact_id` is `null` for support chunks; 41 distinct `CL-*` facts exist.
- 13 of the 15 chunk files use `necessary_facts`/`sufficient_facts` gating.
- Chunks are **hand-authored, committed artifacts**. There is no script that
  regenerates chunks from `story/scenes/`; keep them in sync manually.

### Personas (`story/personajes/*.md`)

Seven NPCs, each a single Spanish paragraph: `criada`, `esteban`, `juan`,
`pablo`, `portero`, `quimica`, `tecnico_heladera`. `dialogue.PERSONAJES_FILES`
maps `npc_id` -> filename; adding an NPC requires editing that map **and**
creating the file.

### Graph

`story/chunk-connections.html` is a self-contained visualization of the
chunk/fact graph (necessary/sufficient edges, knowledge holders). It is a dev
aid, not used at runtime.

## 6. Retrieval benchmark

- Corpus `benchmarks/retrieval/corpus/retrieval_v1.json`: 195 cases
  (161 positive = 108 fact + 53 support; 34 negative). Each case has `npc_id`,
  `known_facts`, `query`, `expected_focus`.
- Fixtures `fixtures/chunks_v1.json`: frozen 151-chunk snapshot **with empty
  gating**, used so benchmark results are comparable. Because gating is empty,
  the benchmark does **not** exercise `game_state.is_available` semantics.
- `run_retrieval.py` computes ranking metrics (Hit@1, Hit@3, MRR), a threshold
  sweep, and worst-case tables. Focus strategies: `top1` and `fact_top3`
  (`first_fact_in_top3`). Output goes to `resultados_raw/` (gitignored).
- `report_retrieval.py` renders `resultados/retrieval.html` (gitignored).
- Fixture embeddings (`fixtures/embeddings_*.npz`) are gitignored and must be
  generated with `build_embeddings.py --model ... --out ...`.
- Run `run_retrieval.py --validate-only` first to sanity-check the corpus
  without calling Ollama.

## 7. Godot game

- Engine: **Godot 4.7**, Forward Plus, Jolt Physics. Autoload: `Global`
  (`game/scenes/global.gd`) holding `accused_id`, `accused_name`, and a random
  `session_id` generated once per launch.
- Input action `interact` = physical key `E` (physical_keycode 69).
- Scene flow: `menu_inicio` -> `mapa_menu` (4 spinning `nodo_mapa` nodes:
  comisaria, laboratorio, oficina, departamento) -> location scenes. In
  `dpto`/`Hall` there is a `pizarron` that opens `reconocimiento` (suspect
  selection) -> `veredicto` (typewriter ending).
- `npc.gd` (`Node3D`): exports `npc_id`/`npc_name`, uses `HTTPClient` to stream
  from `127.0.0.1:8000/dialogue_stream`, emits `response_chunk` /
  `response_completed`.
- `jugador.gd` (`CharacterBody3D`): WASD movement, `E` to talk, raycast to
  highlight/examine objects (`copa` shows a description, no LLM), elevator and
  pizarron interaction.
- `dialogue_ui.gd` builds the whole chat UI in code (no `.tscn` layout),
  appends streamed chunks, disables input while streaming.
- `veredicto.gd`: typewriter ending keyed by `Global.accused_id`.

### Godot conventions

- GDScript, tabs for indentation.
- Several UIs (`dialogue_ui.gd`, `menu_inicio.gd`, `reconocimiento.gd`) are
  constructed programmatically rather than in the editor.
- Keep the PSX/horror aesthetic (VCR OSD Mono font, dark palette, vignette +
  grain shader in `menu_inicio.gd`).

## 8. Known gaps, bugs, and missing pieces

These are the highest-value things to know before making changes.

### Integration / wiring

1. **The game is not wired to the real NPCs.** The only scene instancing
   `npc.tscn` is `campo.tscn`, and it does **not** override `npc_id`/`npc_name`,
   so it uses the default `"Aldric"` — which does not exist in the backend
   persona map. The detective scenes (`comisaria`, `laboratorio`, `dpto`,
   `Hall`) contain no LLM NPCs. To make the game playable end-to-end, NPC
   instances must be added with `npc_id` matching `PERSONAJES_FILES`
   (`criada`, `esteban`, `juan`, `pablo`, `portero`, `quimica`,
   `tecnico_heladera`).
2. **Broken map navigation paths:**
   - `laboratorio.gd` -> `res://scenes/laboratorio.gd` (wrong extension, should
     be `.tscn`).
   - `oficina.gd` -> `res://scenes/oficina.gd` (wrong extension).
   - `departamento.gd` -> `"scenes/Hall.tscn"` (missing `res://` prefix).
   - `reconocimiento.gd` exit -> `res://scenes/hall.tscn` (lowercase `h`);
     the file is `Hall.tscn` — this fails on case-sensitive filesystems.
3. **Duplicate dialogue UI:** both `game/scenes/dialogue_ui.gd` and
   `game/scenes/DialogueUI.gd` exist with identical content. Confirm which one
   `DialogueUI.tscn` uses and delete the other.
4. **Editor leftovers:** `game/scenes/jugador.tscn102336247.tmp`,
   `game/scenes/elevador.tscn` vs `ascensor`, and `.godot/` caches should not be
   edited by hand.

### Backend / infra

5. **`embeddings.npz` is required but gitignored.** Backend import fails until
   `python backend/scripts/build_embeddings.py` is run against a running Ollama
   with the embedding model pulled.
6. **In-memory state only** (history + discovered facts). No DB, no persistence,
   not multi-worker safe.
7. **No automated tests and no CI.** The only test-like tooling is the retrieval
   benchmark.
8. **Docker is incomplete.** `compose.yaml` starts only Ollama. There is no
    Dockerfile for the backend or the game, and no service wiring the backend.
    `docker/ollama-entrypoint.sh` is an **empty directory** (a mistake; the
    intent was a script). `LLAMA_ARG_SWA_FULL=1` is set on the Ollama container
    but is not a documented Ollama environment variable, so it is likely
    ignored.
9. **No chunk build pipeline.** Chunks and their gating are hand-authored; the
    benchmark fixtures are a separate frozen copy with gating stripped, so the
    two can drift.
10. **No embedding cache**; every request re-embeds the player input.

## 9. How to run

Prerequisites: Python 3.12, Godot 4.7, and Ollama (local or via Docker). The
backend imports use the `backend.*` package, so **run from the repo root**.

```bash
# 1. Ollama (Docker) — or run `ollama serve` locally
docker compose up -d
# pull models (names are configurable; defaults below)
ollama pull qwen3-embedding:4b
ollama pull gemma4:e4b

# 2. Configure backend (optional)
cp backend/.env.example backend/.env   # then edit

# 3. Build the embedding index (required once, and after chunk changes)
python backend/scripts/build_embeddings.py
#   optional: --model qwen3-embedding:4b --chunks story/chunks --out backend/rag/embeddings.npz

# 4. Run the API
uvicorn backend.main:app --host 127.0.0.1 --port 8000

# 5. Run the game
godot --path game          # or open game/project.godot in the editor
```

Benchmark:

```bash
python benchmarks/retrieval/scripts/run_retrieval.py --validate-only
python backend/scripts/build_embeddings.py \
  --chunks benchmarks/retrieval/fixtures/chunks_v1.json \
  --out benchmarks/retrieval/fixtures/embeddings_qwen3-embedding:4b.npz
python benchmarks/retrieval/scripts/run_retrieval.py
python benchmarks/retrieval/scripts/report_retrieval.py
```

There is no lint/typecheck/test command configured in the repo. If you add one,
document it here.

## 10. Working conventions

- Do not commit generated artifacts: `backend/rag/embeddings.npz`,
  `benchmarks/**/embeddings_*.npz`, `benchmarks/**/resultados*/`, `.env`,
  `.godot/`, `ollama_models/`.
- Commit messages follow a loose Conventional Commits style
  (`feat:`, `fix:`, `refactor:`), often in English with Spanish domain terms.
- Domain language is Spanish. Prompts, personas, story, and UI strings should
  stay in Spanish unless a task explicitly says otherwise.
- The story/retrieval data is the source of truth for NPC knowledge. When adding
  or changing facts, update the scene frontmatter, the chunk JSON (including
  `knowledge_holders`, `necessary_facts`, `sufficient_facts`, and `fact_id`),
  rebuild embeddings, and re-run the benchmark.
- Prefer editing existing files; keep changes scoped.
