# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for the RAGame backend.
#
# Produces a single executable ("raggame-backend" / "raggame-backend.exe") that
# contains the FastAPI app, its Python dependencies, the story data and the
# precomputed embedding index. Configuration is read from environment variables
# at runtime (see backend/config.py), so no files need to be edited on the
# target machine.

import os

from PyInstaller.utils.hooks import collect_submodules

ROOT = os.path.abspath(os.path.join(SPECPATH, ".."))

# uvicorn/fastapi load several submodules dynamically; collect them explicitly.
hiddenimports = (
    collect_submodules("uvicorn")
    + collect_submodules("fastapi")
    + collect_submodules("starlette")
    + collect_submodules("anyio")
    + collect_submodules("pydantic")
)

# The backend locates these relative to its own modules, which PyInstaller maps
# inside the bundle, so the on-disk layout under _MEIPASS must mirror the repo.
datas = [
    (os.path.join(ROOT, "story", "chunks"), "story/chunks"),
    (os.path.join(ROOT, "story", "personajes"), "story/personajes"),
    (os.path.join(ROOT, "story", "hints.json"), "story"),
    (os.path.join(ROOT, "backend", "rag", "embeddings.npz"), "backend/rag"),
]

a = Analysis(
    [os.path.join(ROOT, "packaging", "backend_entry.py")],
    pathex=[ROOT],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="raggame-backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
