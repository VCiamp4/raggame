import json
from pathlib import Path

import numpy as np
import requests

CHUNKS_DIR = Path(__file__).resolve().parents[2] / "story" / "chunks"
EMBEDDINGS_PATH = Path(__file__).resolve().parents[1] / "rag" / "embeddings.npz"
OLLAMA_URL = "http://localhost:11434/api/embed"
MODEL = "hf.co/unsloth/embeddinggemma-300m-GGUF:Q4_0"


def load_chunks():
    chunks = []
    for path in sorted(CHUNKS_DIR.glob("*.json")):
        chunks.extend(json.loads(path.read_text(encoding="utf-8"))["chunks"])
    return chunks


def get_embeddings(chunks):
    texts = []
    for chunk in chunks:
        texts.append(chunk["retrieval_text"])
        texts.append(chunk["questions"]["q1"])
        texts.append(chunk["questions"]["q2"])

    response = requests.post(
        OLLAMA_URL,
        json={"model": MODEL, "input": texts},
        timeout=600,
    )
    response.raise_for_status()
    raw_embeddings = response.json()["embeddings"]
    embeddings = []
    for start in range(0, len(raw_embeddings), 3):
        embeddings.append(raw_embeddings[start : start + 3])
    return embeddings


def save_embeddings(chunks, embeddings):
    EMBEDDINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    chunk_ids = []
    for chunk in chunks:
        chunk_ids.append(chunk["chunk_id"])

    np.savez(
        EMBEDDINGS_PATH,
        chunk_ids=np.array(chunk_ids),
        embeddings=np.array(embeddings, dtype=np.float32),
    )


def main() -> None:
    chunks = load_chunks()
    embeddings = get_embeddings(chunks)
    save_embeddings(chunks, embeddings)


if __name__ == "__main__":
    main()
