from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CHAT_MODEL = "gemma4:e4b"
DEFAULT_EMBEDDING_MODEL = "hf.co/unsloth/embeddinggemma-300m-GGUF:Q4_0"
DEFAULT_INDEX_NAME = "rag_index_atomic_embeddinggemma_two.sqlite3"
DEFAULT_CANONICAL_QUESTIONS_TWO = "canonical_questions_two.json"


def _env_int(name: str, default: int) -> int:
    return int(os.environ.get(name, str(default)))


def _env_float(name: str, default: float) -> float:
    return float(os.environ.get(name, str(default)))


@dataclass(frozen=True)
class Settings:
    chat_base_url: str
    embed_base_url: str
    chat_model: str
    embedding_model: str
    chat_keep_alive: str
    embed_keep_alive: str
    num_ctx: int
    num_predict: int
    temperature: float
    top_p: float
    max_history_messages: int
    dense_candidates: int
    support_chunks: int
    min_dense_similarity: float
    request_timeout_seconds: int
    personas_dir: Path
    scenes_dir: Path
    index_path: Path
    canonical_questions_two_path: Path

    @classmethod
    def from_env(cls) -> "Settings":
        base_url = os.environ.get("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
        return cls(
            chat_base_url=os.environ.get("OLLAMA_CHAT_BASE_URL", base_url).rstrip("/"),
            embed_base_url=os.environ.get("OLLAMA_EMBED_BASE_URL", base_url).rstrip("/"),
            chat_model=os.environ.get("OLLAMA_MODEL", DEFAULT_CHAT_MODEL),
            embedding_model=os.environ.get("OLLAMA_EMBED_MODEL", DEFAULT_EMBEDDING_MODEL),
            chat_keep_alive=os.environ.get("OLLAMA_KEEP_ALIVE", "30m"),
            embed_keep_alive=os.environ.get("OLLAMA_EMBED_KEEP_ALIVE", "30m"),
            num_ctx=_env_int("OLLAMA_NUM_CTX", 1536),
            num_predict=_env_int("OLLAMA_NUM_PREDICT", 160),
            temperature=_env_float("OLLAMA_TEMPERATURE", 0.35),
            top_p=_env_float("OLLAMA_TOP_P", 0.9),
            # Cero significa historial completo. Un valor positivo conserva
            # solamente esa cantidad de mensajes y puede usarse como límite
            # operativo si el prompt llega a acercarse a num_ctx.
            max_history_messages=_env_int("OLLAMA_MAX_HISTORY", 0),
            dense_candidates=_env_int("RAG_DENSE_CANDIDATES", 8),
            # The production retriever sends a focus plus up to two diverse,
            # narrative-safe supports. For the selected embeddinggemma index,
            # 0.50 is the calibrated raw-score abstention gate, applied to each
            # selected chunk before per-query normalization, without refill.
            support_chunks=_env_int("RAG_SUPPORT_CHUNKS", 2),
            min_dense_similarity=_env_float("RAG_MIN_DENSE_SIMILARITY", 0.50),
            request_timeout_seconds=_env_int("OLLAMA_REQUEST_TIMEOUT", 600),
            personas_dir=PROJECT_ROOT / "crimen-casi-perfecto-scripts" / "guiones" / "v2",
            scenes_dir=PROJECT_ROOT / "crimen-casi-perfecto-scripts" / "knowledge_base" / "scenes",
            index_path=Path(
                os.environ.get(
                    "RAG_INDEX_PATH",
                    str(PROJECT_ROOT / "backend" / "data" / DEFAULT_INDEX_NAME),
                )
            ),
            canonical_questions_two_path=Path(
                os.environ.get(
                    "RAG_CANONICAL_QUESTIONS_TWO_PATH",
                    str(
                        PROJECT_ROOT
                        / "backend"
                        / "data"
                        / DEFAULT_CANONICAL_QUESTIONS_TWO
                    ),
                )
            ),
        )
