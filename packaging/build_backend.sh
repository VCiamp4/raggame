#!/usr/bin/env bash
# Builds the frozen backend executable for the current platform into dist/.
#
# It creates an isolated build virtualenv (.build-venv), generates the embedding
# index if needed, then runs PyInstaller with packaging/raggame-backend.spec.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

VENV="${ROOT}/.build-venv"
if [ ! -x "${VENV}/bin/python" ]; then
	echo ">> Creando entorno de build en ${VENV} ..."
	python3 -m venv "${VENV}"
	"${VENV}/bin/pip" install --upgrade pip
	"${VENV}/bin/pip" install -r packaging/requirements-build.txt
fi

# The index must exist and match EMBEDDING_MODEL, so it is baked into the bundle.
if [ ! -f backend/rag/embeddings.npz ]; then
	echo ">> Falta el indice de embeddings; construyendolo (requiere Ollama) ..."
	OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}" \
		"${VENV}/bin/python" backend/scripts/build_embeddings.py
fi

echo ">> Empaquetando el backend con PyInstaller ..."
"${VENV}/bin/pyinstaller" --clean --noconfirm packaging/raggame-backend.spec

echo ">> Listo: ${ROOT}/dist/raggame-backend"
