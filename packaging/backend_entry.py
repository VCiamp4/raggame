"""Entry point for the frozen (PyInstaller) RAGame backend.

Runs the FastAPI app with uvicorn. All configuration comes from environment
variables so the installer/launcher can pick the chat provider and models
without editing any file.
"""

import os

import uvicorn


def main() -> None:
    host = os.environ.get("BACKEND_HOST", "127.0.0.1")
    port = int(os.environ.get("BACKEND_PORT", "8000"))
    log_level = os.environ.get("LOG_LEVEL", "info")

    # Imported here (after PyInstaller has unpacked its bundle) so the backend's
    # data paths, which are derived from __file__, resolve inside the bundle.
    from backend.main import app

    uvicorn.run(app, host=host, port=port, log_level=log_level)


if __name__ == "__main__":
    main()
