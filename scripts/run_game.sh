#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

EMBEDDINGS_FILE="$PROJECT_ROOT/backend/rag/embeddings.npz"

require_cmd() {
	local name="$1"
	if ! command -v "$name" >/dev/null 2>&1; then
		echo "[run_game] Missing required command: $name" >&2
		return 1
	fi
	return 0
}

ACTION="${1:-start}"

if [ "$ACTION" = "stop" ]; then
	require_cmd docker || exit 1
	echo "[run_game] Stopping docker compose stack"
	docker compose down
	exit 0
fi

echo "[run_game] Checking prerequisites"
MISSING=0

require_cmd docker || MISSING=1
if ! command -v godot4 >/dev/null 2>&1 && ! command -v godot >/dev/null 2>&1 && [ -z "${GODOT_BIN:-}" ]; then
	echo "[run_game] Need Godot executable (godot4/godot) or set GODOT_BIN." >&2
	MISSING=1
fi
if ! command -v curl >/dev/null 2>&1; then
	echo "[run_game] Missing required command: curl" >&2
	MISSING=1
fi

if [ "$MISSING" -eq 1 ]; then
	echo "[run_game] Install the missing dependencies above and re-run." >&2
	exit 1
fi

ensure_ollama() {
	echo "[run_game] Ensuring npc-ollama service is up"
	docker compose up -d npc-ollama
	for _ in $(seq 1 60); do
		if curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
			return
		fi
		sleep 2
	done
	echo "[run_game] Ollama service did not respond on port 11434" >&2
	exit 1
}

run_embeddings() {
	echo "[run_game] Building rag-backend image (if needed)"
	docker compose build rag-backend >/dev/null
	echo "[run_game] Generating embeddings inside container"
	docker compose run --rm --no-deps \
		-e OLLAMA_EMBED_URL=http://npc-ollama:11434/api/embed \
		rag-backend python -m backend.scripts.build_embeddings
}

STACK_STARTED=0
GODOT_PID=""

cleanup() {
	if [ -n "$GODOT_PID" ] && kill -0 "$GODOT_PID" >/dev/null 2>&1; then
		kill "$GODOT_PID" >/dev/null 2>&1 || true
		wait "$GODOT_PID" >/dev/null 2>&1 || true
	fi
	if [ "$STACK_STARTED" -eq 1 ]; then
		echo "[run_game] Shutting down docker compose stack"
		docker compose down >/dev/null 2>&1 || true
	fi
}

handle_signal() {
	echo "[run_game] Interrupt received, cleaning up..."
	exit 1
}

trap cleanup EXIT
trap handle_signal INT TERM

if [ ! -f "$EMBEDDINGS_FILE" ]; then
	ensure_ollama
	run_embeddings
else
	echo "[run_game] Found embeddings artifact at $EMBEDDINGS_FILE"
fi

echo "[run_game] Starting docker compose stack"
docker compose up -d --build
STACK_STARTED=1

echo "[run_game] Waiting for rag-backend to finish startup"
READY=0
for _ in $(seq 1 60); do
	if docker compose logs --no-color --tail=20 rag-backend 2>/dev/null | grep -q "Application startup complete"; then
		READY=1
		break
	fi
	sleep 2
done

if [ "$READY" -eq 0 ]; then
	echo "[run_game] Backend did not report ready state within timeout. Check 'docker compose logs rag-backend'." >&2
	exit 1
fi

GODOT_CMD=""
if [ -n "${GODOT_BIN:-}" ]; then
	GODOT_CMD="$GODOT_BIN"
elif command -v godot4 >/dev/null 2>&1; then
	GODOT_CMD="godot4"
elif command -v godot >/dev/null 2>&1; then
	GODOT_CMD="godot"
else
	echo "[run_game] Could not find Godot executable. Set GODOT_BIN or install godot4." >&2
	exit 1
fi

echo "[run_game] Launching Godot client with $GODOT_CMD"
"$GODOT_CMD" --path "$PROJECT_ROOT/game" &
GODOT_PID=$!
wait "$GODOT_PID"
GODOT_STATUS=$?
GODOT_PID=""

echo "[run_game] Godot exited with status $GODOT_STATUS"
echo "[run_game] Bringing down docker compose stack"
docker compose down
STACK_STARTED=0

exit "$GODOT_STATUS"
