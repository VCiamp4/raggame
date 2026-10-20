#!/usr/bin/env bash
# Arranca todo lo necesario para desarrollar/probar RAGame en local:
#   1) Ollama (contenedor, con los modelos de ./ollama_models) en el puerto 11435
#   2) El indice de embeddings (backend/rag/embeddings.npz) si falta
#   3) El backend FastAPI en 127.0.0.1:8000 (lo que consume el juego)
#
# Uso:  ./run_backend.sh
#        OLLAMA_PORT=11435 ./run_backend.sh     # elegir otro puerto de Ollama
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

OLLAMA_PORT="${OLLAMA_PORT:-11435}"
EMBEDDING_MODEL="${EMBEDDING_MODEL:-qwen3-embedding:4b}"

# --- 1) Ollama (contenedor) --------------------------------------------------
if curl -sf "http://localhost:${OLLAMA_PORT}/api/tags" >/dev/null 2>&1; then
	echo ">> Ollama ya responde en el puerto ${OLLAMA_PORT}."
else
	echo ">> Iniciando Ollama en el puerto ${OLLAMA_PORT} ..."
	docker rm -f npc-ollama >/dev/null 2>&1 || true
	docker run -d --name npc-ollama -p "${OLLAMA_PORT}:11434" \
		-v "$PWD/ollama_models:/root/.ollama" \
		-e OLLAMA_HOST=0.0.0.0:11434 \
		ollama/ollama:latest >/dev/null
	for _ in $(seq 1 30); do
		curl -sf "http://localhost:${OLLAMA_PORT}/api/tags" >/dev/null 2>&1 && break
		sleep 1
	done
	curl -sf "http://localhost:${OLLAMA_PORT}/api/tags" >/dev/null 2>&1 \
		|| { echo "ERROR: Ollama no respondio en ${OLLAMA_PORT}." >&2; exit 1; }
fi
export OLLAMA_URL="http://localhost:${OLLAMA_PORT}"
export EMBEDDING_MODEL

# --- 2) Entorno de Python + indice de embeddings -----------------------------
if [ ! -x ".build-venv/bin/python" ]; then
	echo ">> Creando entorno .build-venv e instalando dependencias ..."
	python3 -m venv .build-venv
	.build-venv/bin/pip install --upgrade pip
	.build-venv/bin/pip install -r backend/requirements.txt
fi
# Reconstruye el indice si falta o si ya no coincide con los chunks actuales.
INDEX_OK=0
if [ -f backend/rag/embeddings.npz ]; then
	if .build-venv/bin/python -c '
import glob, json, sys
import numpy as np
ids = set()
for f in glob.glob("story/chunks/*.json"):
    for c in json.load(open(f, encoding="utf-8"))["chunks"]:
        ids.add(c["chunk_id"])
idx = set(np.load("backend/rag/embeddings.npz")["chunk_ids"].tolist())
sys.exit(0 if ids == idx else 1)
'; then
		INDEX_OK=1
	fi
fi
if [ "${INDEX_OK}" = "0" ]; then
	echo ">> Indice de embeddings faltante o desactualizado; construyendo (puede tardar) ..."
	.build-venv/bin/python backend/scripts/build_embeddings.py
fi

# --- 3) Backend --------------------------------------------------------------
if [ -f backend/.env ]; then
	set -a; . backend/.env; set +a
else
	echo "AVISO: no existe backend/.env; se usa el proveedor por defecto (ollama)." >&2
fi

# Los logs del backend (incluidos los tiempos del pipeline) se muestran en la
# terminal y además se guardan en este archivo.
LOG_FILE="${RAGAME_BACKEND_LOG:-${XDG_CONFIG_HOME:-$HOME/.config}/raggame/backend.log}"
mkdir -p "$(dirname "${LOG_FILE}")"

echo ">> Backend en http://127.0.0.1:8000  (OLLAMA_URL=${OLLAMA_URL})"
echo ">> Logs en ${LOG_FILE}"
exec > >(tee "${LOG_FILE}") 2>&1
exec .build-venv/bin/python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
