import json
import math
from dataclasses import dataclass
from pathlib import Path
import numpy as np
import requests
from backend.config import settings
from backend.rag.game_state import is_available, update_fact, is_support


CHUNKS_DIR = Path(__file__).resolve().parents[2] / "story" / "chunks"
EMBEDDINGS_PATH = Path(__file__).resolve().parent / "embeddings.npz"

@dataclass
class Chunk:
    chunk_id: str
    retrieval_text: str
    knowledge_holders: list[str]
    questions: dict[str, str]
    source_excerpt: str
    fact_id: str | None
    necessary_facts: list[str]
    sufficient_facts: list[str]
    retrieval_embedding: list[float]
    q1_embedding: list[float]
    q2_embedding: list[float]


def load_chunks() -> list[Chunk]:
    with np.load(EMBEDDINGS_PATH) as data:
        embeddings = {}
        for chunk_id, chunk_embeddings in zip(
            data["chunk_ids"], data["embeddings"]
        ):
            embeddings[chunk_id] = chunk_embeddings

    chunks = []
    for path in sorted(CHUNKS_DIR.glob("*.json")):
        for raw_chunk in json.loads(path.read_text(encoding="utf-8"))["chunks"]:
            chunk_embeddings = embeddings[raw_chunk["chunk_id"]]
            chunks.append(
                Chunk(
                    **raw_chunk,
                    retrieval_embedding=chunk_embeddings[0].tolist(),
                    q1_embedding=chunk_embeddings[1].tolist(),
                    q2_embedding=chunk_embeddings[2].tolist(),
                )
            )
    return chunks


def get_embedding(text: str) -> list[float]:
    response = requests.post(
        f"{settings.ollama_url}/api/embed",
        json={"model": settings.embedding_model, "input": [text]},
        timeout=600,
    )
    response.raise_for_status()
    return response.json()["embeddings"][0]


def cosine_similarity(left: list[float], right: list[float]) -> float:
    numerator = 0.0
    left_squared_length = 0.0
    right_squared_length = 0.0

    for left_value, right_value in zip(left, right):
        numerator += left_value * right_value
        left_squared_length += left_value * left_value
        right_squared_length += right_value * right_value

    left_length = math.sqrt(left_squared_length)
    right_length = math.sqrt(right_squared_length)
    return numerator / (left_length * right_length)


CHUNKS = load_chunks()


def retrieve_chunks(npc_id: str, player_input: str, session_id: str) -> list[str]:
    chunks = []
    for chunk in CHUNKS:
        if is_available(chunk, npc_id, session_id):
            chunks.append(chunk)

    if not chunks:
        return []

    query_embedding = get_embedding(player_input)
    scored_chunks = []

    for chunk in chunks:
        score = max(
            cosine_similarity(query_embedding, chunk.retrieval_embedding),
            cosine_similarity(query_embedding, chunk.q1_embedding),
            cosine_similarity(query_embedding, chunk.q2_embedding),
        )
        if score >= settings.min_similarity:
            scored_chunks.append((score, chunk))

    if not scored_chunks:
        return []

    scored_chunks.sort(key=lambda item: item[0], reverse=True)
    focus = next(
        (chunk for _, chunk in scored_chunks[:3] if chunk.fact_id is not None),
        scored_chunks[0][1],
    )
    retrieved_chunks = [focus]
    for _, candidate in scored_chunks:
        if len(retrieved_chunks) >= settings.max_chunks:
            break
        if candidate is not focus and is_support(focus, candidate, session_id):
            retrieved_chunks.append(candidate)
    update_fact(session_id, focus.fact_id)

    retrieved_texts = []
    for chunk in retrieved_chunks:
        retrieved_texts.append(chunk.retrieval_text)
    return retrieved_texts
