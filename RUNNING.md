# Running RAGame locally (backend + Ollama)

The Godot game talks to a FastAPI backend on `127.0.0.1:8000`, which in turn uses
Ollama. The backend is **not** a service, so after a reboot you have to start it
again. `run_backend.sh` does everything.

## One command

```bash
cd ~/Proyectos/raggame
./run_backend.sh
```

It:

1. starts the **Ollama container** (`npc-ollama`) on `localhost:11435`, mounting
   the repo's `./ollama_models` (which has `qwen3-embedding:4b` and `gemma4:e4b`);
2. builds `backend/rag/embeddings.npz` if it's missing;
3. starts the **backend** on `127.0.0.1:8000`, reading `backend/.env`
   (so it uses `CHAT_PROVIDER=openai` / `CHAT_MODEL=gpt-6-luna`).

Leave the terminal open. `Ctrl+C` stops the backend (Ollama keeps running).

Check it's up:

```bash
curl http://127.0.0.1:8000/        # -> {"status":"ok", ...}
```

## Run the game

```bash
godot --path game          # or open game/project.godot in the editor
```

## Manual equivalent (if you prefer)

```bash
cd ~/Proyectos/raggame

# 1) Ollama with the models (skip if it already answers on 11435)
docker run -d --name npc-ollama -p 11435:11434 \
  -v "$PWD/ollama_models:/root/.ollama" -e OLLAMA_HOST=0.0.0.0:11434 ollama/ollama:latest

# 2) Backend
set -a; . backend/.env; set +a
OLLAMA_URL=http://localhost:11435 EMBEDDING_MODEL=qwen3-embedding:4b \
  .build-venv/bin/python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Stop things:

```bash
pkill -f "uvicorn backend.main"   # stop the backend
docker rm -f npc-ollama           # stop Ollama
```

## Troubleshooting

- **The game says it can't connect** → the backend isn't running on `:8000`.
  Start it with `./run_backend.sh`.
- **Ollama / models** → the models live in the `npc-ollama` container
  (`./ollama_models`). The host Ollama on `11434` has none, so the script uses
  `11435`. Embeddings always go through Ollama, even in API-key mode.
- **OpenAI** → `backend/.env` sets `CHAT_PROVIDER=openai`, `CHAT_MODEL=gpt-6-luna`
  and `OPENAI_API_KEY`. Env vars override `.env`.
- **Port 11435 busy** → pick another: `OLLAMA_PORT=11436 ./run_backend.sh`.
- **After a reboot** → just run `./run_backend.sh` again.
