# Distributing RAGame

This document describes how to build a self-contained RAGame package for
**Linux** and **Windows**: an exported Godot game, a **frozen Python backend**
(PyInstaller), and a first-run launcher that installs the required models and
lets the player choose between a **local model (Ollama)** or an **OpenAI API
key**.

The whole thing is assembled into `dist/` and shipped as one folder/archive.
The player needs no Python and no Godot.

## How it fits together

```
dist/
├── linux/
│   ├── raggame.sh                  # Linux launcher/installer
│   ├── backend/raggame-backend     # frozen FastAPI backend (Python bundled)
│   └── game/ragame.x86_64          # Linux export (single file, engine embedded)
└── windows/
    ├── raggame.bat                 # Windows launcher/installer
    ├── backend/raggame-backend.exe # frozen backend (built on Windows)
    └── game/ragame.exe             # Windows export (single file)
```

Each folder is a self-contained package: the launcher sits next to `backend/`
and `game/`. On first run it creates a config under `~/.config/raggame`
(Linux) or `%APPDATA%\raggame` (Windows).

At runtime the launcher:

1. On first run, asks **how to run the model**:
   - `1` **API key (OpenAI)** — chat runs in the cloud; retrieval embeddings
     still run locally (Ollama).
   - `2` **Local (Ollama)** — everything runs on the player's machine.
2. Saves the choice to a config file.
3. Ensures **Ollama** is installed and running.
4. Pulls the models it needs (see below).
5. Starts the frozen backend and then the game.

### Models

The models are **not** bundled in the package (they are several GB); the
launcher pulls them with `ollama pull` on first run.

| Model | Used for | When installed |
| --- | --- | --- |
| `qwen3-embedding:4b` | Retrieval embeddings (always local) | both modes |
| `gemma4:e4b` | Chat | local mode only |
| `gpt-6-luna` | Chat (OpenAI) | never downloaded |

> Note: embeddings always go through Ollama, so **Ollama + `qwen3-embedding:4b`
> are required in both modes**. The “API key” mode only skips the local chat
> model. Making API mode fully local-free would require an OpenAI embeddings
> provider (not implemented).

## Building

Prerequisites on the build machine:

- **Godot 4.7.2** (`godot` on `PATH`).
- **Python 3.12**.
- **Ollama** reachable at `OLLAMA_URL` (default `http://localhost:11434`) with
  `qwen3-embedding:4b` pulled — needed to bake the embedding index into the
  backend bundle.
- Internet access (to download the Godot export templates, ~1.3 GB, once).

### One command (recommended)

From the repository root:

```bash
OLLAMA_URL=http://localhost:11434 bash packaging/build_all.sh
```

`packaging/build_all.sh` runs all the steps below in order — it freezes the
backend, exports the game for Linux and Windows, and assembles both packages
under `dist/` — then prints the resulting package paths. On Linux it produces a
complete `dist/linux`; `dist/windows` gets the game and launcher, and the
`raggame-backend.exe` has to be built on Windows (see below).

### What it runs (equivalently)

```bash
# 1. Frozen backend  ->  dist/raggame-backend
OLLAMA_URL=http://localhost:11434 bash packaging/build_backend.sh

# 2. Godot exports   ->  dist/linux/ragame.x86_64, dist/windows/ragame.exe
bash packaging/export_game.sh

# 3. Assembly is what build_all.sh adds: it moves the exported binaries into
#    dist/<platform>/game/ and copies the launchers into dist/<platform>/.
```

Exports are single self-contained files (the pack is embedded via
`binary_format/embed_pck=true` in `game/export_presets.cfg`), so the player does
**not** need Godot installed.

The result is the `dist/` tree shown above. Archive each package:

```bash
tar -czf raggame-linux.tar.gz   -C dist/linux .
zip  -r raggame-windows.zip     dist/windows
```

### Building the Windows package

Godot can **cross-export Windows from Linux** (the templates include the
Windows target), so `packaging/export_game.sh` produces `dist/windows/ragame.exe`
even on Linux.

The **frozen backend must be built on Windows** to get `raggame-backend.exe`
(the Linux PyInstaller build only produces a Linux binary). On a Windows
machine:

```bat
py -3 -m venv .build-venv
.\.build-venv\Scripts\pip install -r packaging\requirements-build.txt
.\.build-venv\Scripts\python backend\scripts\build_embeddings.py
.\.build-venv\Scripts\pyinstaller --clean --noconfirm packaging\raggame-backend.spec
```

Then copy the built `dist\raggame-backend.exe` into `dist\windows\backend\`
alongside `raggame.bat` (which expects `backend\raggame-backend.exe` and
`game\ragame.exe`). Set `OLLAMA_URL` if your Ollama is not on the default port.

## First-run options in detail

### Option 1 — API key (OpenAI) (Recommended)

- Prompts for `OPENAI_API_KEY` (stored, `chmod 600`, in the launcher config).
- Sets `CHAT_PROVIDER=openai`, `CHAT_MODEL=gpt-6-luna`.
- **Still installs Ollama + `qwen3-embedding:4b` for retrieval**.

### Option 2 — Local (Ollama)

- Sets `CHAT_PROVIDER=ollama`, `CHAT_MODEL=gemma4:e4b`.
- Installs Ollama + both `qwen3-embedding:4b` and `gemma4:e4b`.

To reconfigure, delete the config file and run the launcher again:

- Linux: `~/.config/raggame/config.env`
- Windows: `%APPDATA%\raggame\config.env`

## Configuration

The launcher writes these variables (read by the backend at startup):

| Variable | Local | API-key |
| --- | --- | --- |
| `CHAT_PROVIDER` | `ollama` | `openai` |
| `CHAT_MODEL` | `gemma4:e4b` | `gpt-6-luna` |
| `OPENAI_API_KEY` | — | set |
| `EMBEDDING_MODEL` | `qwen3-embedding:4b` | `qwen3-embedding:4b` |
| `OLLAMA_URL` | `http://localhost:11434` | `http://localhost:11434` |

The game client always connects to the backend on `127.0.0.1:8000`.

## Changing the story or models

The embedding index is **baked into the backend at build time**. If you edit
`story/` or change `EMBEDDING_MODEL`, delete `backend/rag/embeddings.npz`,
rebuild it and rebuild the bundle:

```bash
rm -f backend/rag/embeddings.npz
OLLAMA_URL=http://localhost:11434 bash packaging/build_backend.sh
```

## Troubleshooting

- **“Ollama no esta instalado”.** Install it from
  https://ollama.com/download (the Linux launcher also tries the official
  install script automatically).
- **Player has no internet on first run.** Models cannot be downloaded; pre-pull
  them into the player's Ollama, or ship an `ollama_models/` folder and set
  `OLLAMA_MODELS` to it.
- **Backend exits immediately.** Check the launcher logs
  (`~/.config/raggame/backend.log` on Linux).
- **API-key mode returns OpenAI 404/401.** Wrong/expired key, or a model name
  your account cannot access.
