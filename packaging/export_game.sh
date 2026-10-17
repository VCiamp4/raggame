#!/usr/bin/env bash
# Exports the Godot game for Linux and Windows into dist/.
#
# Installs the matching Godot export templates (once) and produces:
#   dist/linux/ragame.x86_64 (+ .pck)
#   dist/windows/ragame.exe   (+ .pck)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GODOT="${GODOT:-godot}"
GODOT_RELEASE="4.7.2-stable"
TEMPLATE_VERSION="4.7.2.stable"
DIST="${ROOT}/dist"
TPZ_URL="https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE}/Godot_v${GODOT_RELEASE}_export_templates.tpz"

TEMPLATES_DIR="${HOME}/.local/share/godot/export_templates/${TEMPLATE_VERSION}"
if [ ! -f "${TEMPLATES_DIR}/linux_release.x86_64" ]; then
	echo ">> Instalando export templates ${TEMPLATE_VERSION} en ${TEMPLATES_DIR} ..."
	TMP="$(mktemp -d)"
	curl -L --fail -o "${TMP}/templates.tpz" "${TPZ_URL}"
	mkdir -p "${TEMPLATES_DIR}"
	python3 -m zipfile -e "${TMP}/templates.tpz" "${TMP}/x"
	cp -a "${TMP}/x/templates/." "${TEMPLATES_DIR}/"
	rm -rf "${TMP}"
fi

mkdir -p "${DIST}/linux" "${DIST}/windows"

echo ">> Exportando Linux ..."
"${GODOT}" --headless --path "${ROOT}/game" --export-release "Linux" "${DIST}/linux/ragame.x86_64"

echo ">> Exportando Windows ..."
"${GODOT}" --headless --path "${ROOT}/game" --export-release "Windows Desktop" "${DIST}/windows/ragame.exe"

echo ">> Listo. Binarios en ${DIST}"
ls -lh "${DIST}/linux" "${DIST}/windows"
