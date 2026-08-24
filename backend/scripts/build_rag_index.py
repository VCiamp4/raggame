#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import requests

from backend.rag.config import Settings
from backend.rag.corpus import Corpus
from backend.rag.index import HybridIndex
from backend.rag.ollama import OllamaClient


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Construye el índice persistente de chunks atómicos con Ollama."
    )
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Recalcula los embeddings aunque el índice actual sea compatible.",
    )
    parser.add_argument(
        "--index",
        type=Path,
        help="Ruta explícita del índice; por defecto usa RAG_INDEX_PATH.",
    )
    parser.add_argument(
        "--canonical-questions-two",
        type=Path,
        help=(
            "Mapa q2 alternativo; por defecto usa "
            "RAG_CANONICAL_QUESTIONS_TWO_PATH."
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    settings = Settings.from_env()

    corpus = Corpus.load(settings.scenes_dir)
    client = OllamaClient(
        settings.embed_base_url,
        timeout_seconds=settings.request_timeout_seconds,
    )
    try:
        models = client.model_names()
    except requests.RequestException as error:
        print(
            f"No se pudo conectar al Ollama de embeddings en {settings.embed_base_url}: {error}",
            file=sys.stderr,
        )
        return 2

    if settings.embedding_model not in models:
        print(
            f"Falta el modelo {settings.embedding_model!r} en {settings.embed_base_url}. "
            f"Modelos disponibles: {sorted(models)}",
            file=sys.stderr,
        )
        return 2

    index = HybridIndex.build(
        corpus=corpus,
        path=args.index or settings.index_path,
        embedding_client=client,
        embedding_model=settings.embedding_model,
        embedding_keep_alive=settings.embed_keep_alive,
        batch_size=args.batch_size,
        force=args.force,
        dense_candidates=settings.dense_candidates,
        support_chunks=settings.support_chunks,
        min_dense_similarity=settings.min_dense_similarity,
        canonical_questions_two_path=(
            args.canonical_questions_two or settings.canonical_questions_two_path
        ),
    )
    description = index.describe()
    print(
        "Índice listo: "
        f"{description['chunks']} chunks, dimensión {description['dimension']}, "
        f"modelo {description['embedding_model']}, archivo {description['path']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
