# raggame — Project Context

Authoritative map for AI assistants. Read this before diving into the repo.

## 1. Overview

**RAGame** is a Godot **4.6** (Forward Plus, Jolt physics) first-person detective prototype. The player types free-form Spanish questions to NPCs; replies stream from a local LLM (Ollama, `qwen2.5:1.5b`) behind a FastAPI backend. The only playable case adapta “Un crimen casi perfecto”: Mrs. Stevens fue envenenada; hermanos Esteban, Juan, Pablo (más Criada y Forense) son sospechosos. A pesar del nombre no hay **Retrieval-Augmented Generation** todavía: todo se resuelve con prompts de persona y pistas activadas por keywords.

## 2. Repository map

```
.gitignore, README.md (placeholder title)
backend/
  main.py              FastAPI → Ollama proxy
  requirements.txt     Frozen deps (FastAPI 0.136, Pydantic 2.13, Uvicorn 0.49, Requests 2.34…)
game/
  project.godot        Engine config (main scene = menu_inicio.tscn)
  menu_inicio.gd       Title screen (Jugar/Salir, ambience, shader overlay)
  scenes/              All scenes + scripts (player, NPCs, UI, locations, lineup, verdict)
  scripts/systems/     event_manager.gd, input_manager.gd, pistas.md (empty)
  data/events/         events.gd (Resource con catálogo de pistas/personajes)
  audio/               Police teletype ambience wav
  fonts/               VCR_OSD_MONO font + theme_horror.tres
  assets/              Imported PSX-style packs + story docs (big)
assets/                Empty at repo root (kept for future)
```

## 3. Gameplay flow (current wiring)

```
menu_inicio.tscn  ← MAIN SCENE (title “EL DEPARTAMENTO”, shader vignette, ambience)
  └─ Jugar → mapa_menu.tscn (3D hub “tablón”) — click rotating models (group nodo_mapa)
        ├─ comisaria.tscn     (police station, has pizarron trigger)
        ├─ laboratorio.tscn   (Pablo’s lab; note hub script default path is wrong)
        ├─ departamento→Hall.tscn (Esteban, Juan, Criada playable scene)
        └─ oficina → ⚠️ default path “res://scenes/oficina.gd” (no scene → broken)
               └─ comisaria’s `pizarron` (group pizarron, collision layer 2) opens
                      reconocimiento.tscn (lineup WIP) → veredicto.tscn (typewriter ending)
```

`campo.tscn` still exists (player + generic Aldric NPC + old DialogueUI), but is only a dev playground.

## 4. Backend (backend/main.py)

- `POST /dialogue_stream` accepts `{npc_id, player_input, session_id="default"}` and proxies to `http://localhost:11434/api/chat` with `model=qwen2.5:1.5b`, `stream=true`, `num_predict=200`, `temperature=0.8`, `think=false`. Response is a plain-text streaming generator.
- Persona prompts defined for **Aldric, Esteban, Juan, Criada, Pablo, Forense**. All enforce Rioplatense Spanish, 1st person, 2–4 sentences (Juan shorter), never break character, admit ignorance.
- Conversation history kept in `HISTORIES[(session_id, npc_id)]` (list of dicts). Cap: last 20 entries. Lives only in RAM—restart wipes everything. Session id is hardcoded `"default"` in npc.gd.
- Run server via `uvicorn main:app --port 8000`. Godot client hardcodes host 127.0.0.1 port 8000.

## 5. Godot architecture

### Autoloads (project.godot `[autoload]`)

- **Global** (`scenes/global.gd`) almacena `accused_id` y `accused_name` para el flujo lineup → veredicto.
- **EventManager**, **InputManager** y **NotificationManager** ya figuran como autoloads; scripts los usan como singletons para pistas, glyphs y toasts.

### Systems scripts (`game/scripts/systems/`)

- `event_manager.gd` — global clue registry. `activated_events` dictionary, signal `event_activated(event_id)`, helpers `activate_event`, `has_event`, `reset_events`, `check_input(text)` (lowercase substring search contra el catálogo). `_build_keyword_map()` se alimenta de `data/events/events.gd`, así que cada entrada nueva en el recurso queda disponible sin tocar código.
- `input_manager.gd` — remembers last input device (keyboard/mouse vs joypad). Emits `device_changed(using_controller)`, and provides `action_glyph(action="interact")` / `cancel_glyph()` returning strings like `[E]`, `(A)`, `[Esc]`, `(B)`.
- `pistas.md` — empty whiteboard for future clue workflow ideas.

### Input configuration

| Action     | Keyboard | Controller |
|------------|----------|------------|
| `interact` | E        | A (button 0)
| `examine`  | F        | X (button 2)
| `ui_quit_dialogue` | F8 (physical key) | Start (button 7)

Movement uses built-in `ui_left/right/up/down`. `ui_cancel` inherits Godot defaults (Esc / B). Physics backend: Jolt. Default font: `fonts/theme_horror.tres` (VCR OSD Mono).

### Core scripts & scenes

- **jugador.tscn / jugador.gd** — player `CharacterBody3D`. Handles movement, animation (`mixamo_com`), prompt display, object highlighting (ray, mask 2, ignores areas), dialogue interactions, and `pizarron` clicks (left mouse triggers lineup). Calls `EventManager.check_input` before sending HTTP requests via nearby NPC.
- **npc.tscn / npc.gd + scenes/npcs/** — base NPC blueprint. Adds itself to group `npc`, spawns a StaticBody3D capsule collider (radius 0.35, height 3.2 local), wires an Area3D for proximity signals, and streams responses via `HTTPClient` (manual `poll()` loop, emits `response_chunk(text)` and `response_completed`). `clothes_texture` duplicates the first mesh material for recolors (Esteban green, Juan blue, Pablo blue, Criada pink, Forense default).
- **dialogue_ui.gd** — CanvasLayer UI instanced inside `jugador.tscn`. Builds panel + name + scrollable `RichTextLabel` + input field + prompt label entirely via code. Integrates InputManager for glyphs and placeholder text. NOTE: `campo.tscn` still instantiates the older `DialogueUI.tscn` + `DialogueUI.gd` pair.
- **copa.gd / copa.tscn** — pattern for examinables: StaticBody3D, group `examinable`, highlight/unhighlight via emission overlay, `get_description()` returns multiline text. `CollisionShape3D` on layer 2 so the player ray can detect it.
- **pizarron.gd** — StaticBody3D, group `pizarron`, highlight/unhighlight, `interact()` → `change_scene_to_file("res://scenes/reconocimiento.tscn")`. Used in comisaria.
- **mapa_menu.gd** — Node3D hub controller: casts mouse ray from Camera3D, highlights nodes in group `nodo_mapa`, loads their `scene_path` on click.
- **menu_inicio.gd** — Creates title UI (labels + buttons) programmatically, plays looping ambience (`game/audio/438135__craigsmith__...wav`) and overlays a shader-based vignette/grain/flicker effect.
- **reconocimiento.gd / hermano_abogado.gd / veredicto.gd** — lineup completo: `reconocimiento.tscn` muestra a Esteban/Juan/Pablo/Criada, permite cancelar o confirmar, y graba la acusación en `Global` antes de cargar el veredicto. `veredicto.gd` mantiene el efecto máquina de escribir y ya tiene finales para Aldric, Esteban, Juan, Pablo, Criada, Mira (culpable real) y Hervé.
- **Hall.tscn** — main playable location: player + Criada/Esteban/Juan. Contains a legacy `AreaLight3D` child under `Carpet_1`; Godot drops it on load (missing light).
- **comisaria.tscn** — estación de policía con pizarrón interactivo (capa 2) que abre el lineup; sirve como sala segura y punto para repasar pistas.
- **laboratorio.tscn** — Pablo’s lab interior (props only). The `laboratorio.gd` hub script defaults to an incorrect `.gd` path but `mapa_menu.tscn` overrides it to `laboratorio.tscn`.
- **dpto.tscn** — apartment crime scene with Forense NPC, victim mesh (`victima.tscn`), and `copa.tscn` examinable.
- **elevador.tscn** — elevator GLB placeholder.

### Groups in use

`player`, `npc`, `examinable`, `pizarron`, `sospechoso`, `nodo_mapa`.

## 6. Story / design references

- `game/assets/crimen-casi-perfecto-scripts/paso-a-paso-juego.md` — enumerates clues:
  - **Criada** — last person to see victim, forced to prepare whisky, abused by Mrs. Stevens.
  - **Esteban** — arranged life insurance 3 months ago, benefits financially, stormed out when Pablo’s inheritance share increased.
  - **Juan** — ex-con sociopath, resents Mrs. Stevens for tipping off police; excited about payday.
  - **Pablo** — closest sibling, repairs appliances (fixed fridge), cyanide present at his lab.
  - Notes cyanide metabolizes quickly; no residue in glasses/bottles.
- `game/assets/crimen-casi-perfecto-scripts/guiones/*.md` — per-character notes (Criada, Esteban, Juan, Pablo, Químico, Técnico heladera, Portero). Useful when wiring future keywords or dialogue beats.
- `BS.-Un-crimen-casi-perfcto.-Arlt-.pdf` — source short story (Spanish, scanned PDF).
- `game/scripts/systems/pistas.md` — empty, intended to document upcoming clue system.

## 7. Known issues & gaps

1. **Clue system sin gameplay** — EventManager activa flags pero aún no hay consecuencias visibles (UI de pistas, gating narrativo, veredicto dinámico). `pistas.md` sigue vacío.
2. **Broken hub paths** — `oficina.gd` y `laboratorio.gd` siguen apuntando por defecto a `.gd` inexistentes; la oficina del mapa aún no carga escena.
3. **Iluminación Hall** — `Hall.tscn` mantiene un `AreaLight3D` obsoleto que Godot elimina; la habitación queda subiluminada.
4. **Stray temp file** — `game/scenes/jugador.tscn102336247.tmp` continúa en el repo como copia redundante.
5. **README vacío** — el README raíz no explica cómo levantar backend ni cliente.
6. **Backend volátil** — historiales viven solo en RAM y comparten session id "default"; reiniciar FastAPI borra el progreso.
7. **Raycast limitado** — `jugador.gd` solo detecta interactuables en colisión/máscara 2 (StaticBody3D); si un nodo usa un Area3D no responderá.
8. **Assets gigantes** — `game/assets/` contiene ZIPs/GLB originales; evitá editarlos a mano para no romper las `.import`.

## 8. Extra notes

- Engine `config/features` lista `"4.6"`; mantenerlo así salvo que se migre todo el proyecto.
- Title screen audio (`game/audio/438135__craigsmith__...wav`) está loopeado en el bus Music a -20 dB.
- Shader overlay in menu produces vignette, film grain, and flicker; keep parameters when restyling.
- `npc.gd` duplicates the first mesh material to apply `clothes_texture`; ensure NPC scenes have a MeshInstance child.
- Git history highlights: monorepo restructure (`game/` + `backend/`), EventManager introduction, controller support, menu/lineup prototype.

Use this file as the canonical reference for high-level context.
