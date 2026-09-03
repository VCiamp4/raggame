from __future__ import annotations

import json
import threading
from collections.abc import Iterator

import requests


_LOCKS_GUARD = threading.Lock()
_LOCKS_BY_URL: dict[str, threading.Lock] = {}


def runtime_lock(base_url: str) -> threading.Lock:
    normalized = base_url.rstrip("/")
    with _LOCKS_GUARD:
        return _LOCKS_BY_URL.setdefault(normalized, threading.Lock())


class OllamaClient:
    def __init__(self, base_url: str, timeout_seconds: int = 600):
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds
        self.lock = runtime_lock(self.base_url)

    def embed(self, *, model: str, inputs: list[str], keep_alive: str) -> list[list[float]]:
        if not inputs:
            return []
        payload = {"model": model, "input": inputs, "keep_alive": keep_alive}
        with self.lock:
            response = requests.post(
                f"{self.base_url}/api/embed",
                json=payload,
                timeout=(5, self.timeout_seconds),
            )
            response.raise_for_status()
            data = response.json()
        embeddings = data.get("embeddings")
        if not isinstance(embeddings, list) or len(embeddings) != len(inputs):
            raise RuntimeError("Ollama devolvió una cantidad inesperada de embeddings")
        return embeddings

    def chat_stream(self, payload: dict) -> Iterator[str]:
        with self.lock:
            with requests.post(
                f"{self.base_url}/api/chat",
                json=payload,
                stream=True,
                timeout=(5, self.timeout_seconds),
            ) as response:
                response.raise_for_status()
                for line in response.iter_lines():
                    if not line:
                        continue
                    data = json.loads(line)
                    chunk = data.get("message", {}).get("content", "")
                    if chunk:
                        yield chunk
                    if data.get("done", False):
                        break

    def model_names(self) -> set[str]:
        response = requests.get(f"{self.base_url}/api/tags", timeout=(5, 30))
        response.raise_for_status()
        return {item["name"] for item in response.json().get("models", [])}
