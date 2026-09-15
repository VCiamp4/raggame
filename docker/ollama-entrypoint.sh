#!/bin/sh
set -eu

MODEL_CHAT=${OLLAMA_MODEL:-gemma4:e4b}
MODEL_EMBED=${OLLAMA_EMBED_MODEL:-hf.co/unsloth/embeddinggemma-300m-GGUF:Q4_0}

ensure_model() {
	model="$1"
	if [ -z "$model" ]; then
		return
	fi
	echo "[ollama-entrypoint] Ensuring model $model"
	ollama pull "$model" || true
}

shutdown() {
	if kill -0 "$SERVER_PID" 2>/dev/null; then
		kill "$SERVER_PID"
		wait "$SERVER_PID"
	fi
}

trap shutdown INT TERM

ollama serve &
SERVER_PID=$!

until ollama list >/dev/null 2>&1; do
	echo "[ollama-entrypoint] Waiting for Ollama daemon"
	sleep 2
done

ensure_model "$MODEL_CHAT"
ensure_model "$MODEL_EMBED"

wait "$SERVER_PID"
