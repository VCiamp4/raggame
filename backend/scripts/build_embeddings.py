import json
import sys
from pathlib import Path

import numpy as np
import requests

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from backend.config import settings

CHUNKS_DIR = Path(__file__).resolve().parents[2] / "story" / "chunks"
EMBEDDINGS_PATH = Path(__file__).resolve().parents[1] / "rag" / "embeddings.npz"


def load_chunks(chunks_path=CHUNKS_DIR):
    chunks_path = Path(chunks_path)
    files = (
        [chunks_path]
        if chunks_path.is_file()
        else sorted(chunks_path.glob("*.json"))
    )
    chunks = []
    for path in files:
        chunks.extend(json.loads(path.read_text(encoding="utf-8"))["chunks"])
    return chunks


def get_embeddings(chunks):
    texts = []
    for chunk in chunks:
        texts.append(chunk["retrieval_text"])
        texts.append(chunk["questions"]["q1"])
        texts.append(chunk["questions"]["q2"])

    response = requests.post(
        f"{settings.ollama_url}/api/embed",
        json={"model": settings.embedding_model, "input": texts},
        timeout=600,
    )
    response.raise_for_status()
    raw_embeddings = response.json()["embeddings"]
    embeddings = []
    for start in range(0, len(raw_embeddings), 3):
        embeddings.append(raw_embeddings[start : start + 3])
    return embeddings


def save_embeddings(chunks, embeddings, embeddings_path, model):
    embeddings_path.parent.mkdir(parents=True, exist_ok=True)
    chunk_ids = []
    for chunk in chunks:
        chunk_ids.append(chunk["chunk_id"])

    np.savez(
        embeddings_path,
        chunk_ids=np.array(chunk_ids),
        embeddings=np.array(embeddings, dtype=np.float32),
        model=np.array(model),
    )


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--chunks", default=CHUNKS_DIR, type=Path)
    parser.add_argument("--out", default=EMBEDDINGS_PATH, type=Path)
    parser.add_argument("--model", default=None)
    args = parser.parse_args()

    if args.model:
        settings.embedding_model = args.model
    chunks = load_chunks(args.chunks)
    embeddings = get_embeddings(chunks)
    save_embeddings(chunks, embeddings, args.out, settings.embedding_model)
    print(f"Modelo: {settings.embedding_model}")


if __name__ == "__main__":
    main()
