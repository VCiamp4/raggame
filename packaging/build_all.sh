#!/usr/bin/env bash
# One-command distribution build for the current platform.
#
#   bash packaging/build_all.sh
#
# It freezes the backend, exports the game for Linux and Windows, and assembles
# the per-platform packages under dist/. See DISTRIBUTION.md for prerequisites.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

DIST="${ROOT}/dist"

echo "==> 1/3  Backend congelado (PyInstaller)"
bash packaging/build_backend.sh

echo "==> 2/3  Exportando el juego (Linux + Windows)"
bash packaging/export_game.sh

echo "==> 3/3  Ensamblando los paquetes"
mkdir -p "${DIST}/linux/game" "${DIST}/linux/backend" \
         "${DIST}/windows/game" "${DIST}/windows/backend"

mv -f "${DIST}/linux/ragame.x86_64" "${DIST}/linux/game/ragame.x86_64"
mv -f "${DIST}/windows/ragame.exe"  "${DIST}/windows/game/ragame.exe"
cp -f packaging/raggame.sh  "${DIST}/linux/raggame.sh"
cp -f packaging/raggame.bat "${DIST}/windows/raggame.bat"
chmod +x "${DIST}/linux/raggame.sh"

# The frozen backend is host-platform specific; place it in that package.
case "$(uname -s)" in
	Linux*)
		mv -f "${DIST}/raggame-backend" "${DIST}/linux/backend/raggame-backend"
		;;
	MINGW* | MSYS* | CYGWIN*)
		mv -f "${DIST}/raggame-backend.exe" "${DIST}/windows/backend/raggame-backend.exe"
		;;
	*)
		echo "AVISO: plataforma desconocida; ensambla el backend a mano."
		;;
esac

echo
echo ">> Listo. Paquetes:"
echo "   ${DIST}/linux   $( [ -f "${DIST}/linux/backend/raggame-backend" ] && echo '(completo)' || echo '(falta el backend)' )"
echo "   ${DIST}/windows $( [ -f "${DIST}/windows/backend/raggame-backend.exe" ] && echo '(completo)' || echo '(falta raggame-backend.exe: construilo en Windows)' )"
