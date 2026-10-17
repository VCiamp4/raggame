#!/usr/bin/env bash
# RAGame launcher / installer (Linux).
#
# Every run asks how the language model should run (OpenAI API key or local
# Ollama) unless the user chose "don't ask again", in which case the saved
# choice is reused. Then it installs the needed models and starts the backend
# and the game.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/raggame"
CONFIG_FILE="${CONFIG_DIR}/config.env"
BACKEND_BIN="${RAGAME_BACKEND_BIN:-${APP_DIR}/backend/raggame-backend}"
GAME_BIN="${RAGAME_GAME_BIN:-${APP_DIR}/game/ragame.x86_64}"

EMBEDDING_MODEL="qwen3-embedding:4b"
CHAT_MODEL_LOCAL="gemma4:e4b"
CHAT_MODEL_API="gpt-6-luna"

mkdir -p "${CONFIG_DIR}"

choose_mode() {
	echo "=================================================="
	echo "  RAGame"
	echo "=================================================="
	echo "Como queres ejecutar el modelo de lenguaje?"
	echo "  1) Con una API key (OpenAI)  [chat en la nube, embeddings locales]"
	echo "  2) Localmente (Ollama)       [todo en tu maquina]"
	printf "Opcion [1/2]: "
	read -r opt || true
	case "${opt:-1}" in
		2)
			MODE="local"
			CHAT_PROVIDER="ollama"
			CHAT_MODEL="${CHAT_MODEL_LOCAL}"
			OPENAI_API_KEY=""
			;;
		*)
			MODE="api"
			CHAT_PROVIDER="openai"
			CHAT_MODEL="${CHAT_MODEL_API}"
			printf "Ingresa tu OPENAI_API_KEY: "
			read -rs key || true
			echo
			OPENAI_API_KEY="${key}"
			;;
	esac
}

save_config() {
	cat > "${CONFIG_FILE}" <<EOF
# Config de RAGame (generada por el instalador). Borrala para reconfigurar.
RAGAME_MODE=${MODE}
RAGAME_ASK=${RAGAME_ASK}
CHAT_PROVIDER=${CHAT_PROVIDER}
CHAT_MODEL=${CHAT_MODEL}
OPENAI_API_KEY=${OPENAI_API_KEY}
EMBEDDING_MODEL=${EMBEDDING_MODEL}
OLLAMA_URL=${OLLAMA_URL}
EOF
	chmod 600 "${CONFIG_FILE}"
	echo ">> Configuracion guardada en ${CONFIG_FILE}"
}

RAGAME_ASK=1
OLLAMA_URL="http://localhost:11434"
if [ -f "${CONFIG_FILE}" ]; then
	# shellcheck disable=SC1090
	source "${CONFIG_FILE}"
fi

# Se pregunta siempre, salvo que el usuario haya elegido "no volver a preguntar".
if [ ! -f "${CONFIG_FILE}" ] || [ "${RAGAME_ASK:-1}" != "0" ]; then
	choose_mode
	printf "Volver a preguntar la proxima vez? [S/n]: "
	read -r again || true
	case "${again:-S}" in
		[nN]*) RAGAME_ASK=0 ;;
		*) RAGAME_ASK=1 ;;
	esac
	save_config
	# shellcheck disable=SC1090
	source "${CONFIG_FILE}"
fi

export CHAT_PROVIDER CHAT_MODEL OPENAI_API_KEY EMBEDDING_MODEL OLLAMA_URL

# Embeddings always run through Ollama (also in API-key mode), so it is required.
if ! command -v ollama >/dev/null 2>&1; then
	echo ">> Ollama no esta instalado; intentando instalarlo ..."
	if ! curl -fsSL https://ollama.com/install.sh | sh; then
		echo "ERROR: no se pudo instalar Ollama automaticamente."
		echo "Instalalo desde https://ollama.com/download y volve a intentar."
		exit 1
	fi
fi

ollama_up() { curl -sf "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; }

OLLAMA_STARTED=0
if ollama_up; then
	echo ">> Ollama ya esta corriendo."
else
	echo ">> Iniciando Ollama ..."
	ollama serve >"${CONFIG_DIR}/ollama.log" 2>&1 &
	OLLAMA_PID=$!
	OLLAMA_STARTED=1
	for _ in $(seq 1 60); do ollama_up && break; sleep 1; done
	if ! ollama_up; then
		echo "ERROR: Ollama no respondio. Ver ${CONFIG_DIR}/ollama.log"
		exit 1
	fi
fi

pull_model() {
	local model="$1"
	# The ollama CLI reads OLLAMA_HOST, so mirror the configured OLLAMA_URL.
	local host="${OLLAMA_URL#*://}"
	if OLLAMA_HOST="${host}" ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "${model}"; then
		echo ">> ${model} ya instalado."
	else
		echo ">> Descargando ${model} (puede tardar varios minutos) ..."
		OLLAMA_HOST="${host}" ollama pull "${model}"
	fi
}

pull_model "${EMBEDDING_MODEL}"
if [ "${CHAT_PROVIDER}" = "ollama" ]; then
	pull_model "${CHAT_MODEL}"
else
	echo ">> Modo API: se omite la descarga del modelo de chat."
fi

BACKEND_PORT="${BACKEND_PORT:-8000}"
echo ">> Iniciando backend en 127.0.0.1:${BACKEND_PORT} ..."
BACKEND_HOST=127.0.0.1 BACKEND_PORT="${BACKEND_PORT}" \
	"${BACKEND_BIN}" >"${CONFIG_DIR}/backend.log" 2>&1 &
BACKEND_PID=$!

cleanup() {
	echo ">> Cerrando RAGame ..."
	kill "${BACKEND_PID}" 2>/dev/null || true
	if [ "${OLLAMA_STARTED}" = "1" ]; then kill "${OLLAMA_PID}" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM

for _ in $(seq 1 60); do
	curl -sf "http://127.0.0.1:${BACKEND_PORT}/" >/dev/null 2>&1 && break
	if ! kill -0 "${BACKEND_PID}" 2>/dev/null; then
		echo "ERROR: el backend se cerro. Ver ${CONFIG_DIR}/backend.log"
		exit 1
	fi
	sleep 1
done

echo ">> Iniciando el juego ..."
"${GAME_BIN}" "$@"
