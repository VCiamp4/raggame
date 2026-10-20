import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
import numpy as np
import requests
from backend.config import settings
from backend.rag.game_state import is_available, update_fact, is_support, get_discovered_facts, discovered_chunks
from backend.timing import log_timing, ollama_load_seconds, now


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
    embeddings: list[list[float]]


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
                    embeddings=chunk_embeddings.tolist(),
                )
            )
    return chunks


def get_embedding(text: str) -> list[float]:
    start = now()
    response = requests.post(
        f"{settings.ollama_url}/api/embed",
        json={"model": settings.embedding_model, "input": [text]},
        timeout=600,
    )
    response.raise_for_status()
    data = response.json()
    load = ollama_load_seconds(data)
    log_timing(
        "embedding",
        now() - start,
        modelo=settings.embedding_model,
        load_s=f"{load:.2f}",
        ya_cargado=(load == 0),
    )
    return data["embeddings"][0]


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
    start = now()
    chunks = []
    for chunk in CHUNKS:
        if is_available(chunk, npc_id, session_id):
            chunks.append(chunk)
    filter_time = now() - start

    if not chunks:
        log_timing("recuperacion", filter_time, candidatos=0)
        return []

    embed_start = now()
    query_embedding = get_embedding(player_input)
    embed_time = now() - embed_start
    scored_chunks = []

    for chunk in chunks:
        score = max(
            cosine_similarity(query_embedding, embedding)
            for embedding in chunk.embeddings
        )
        if score >= settings.min_similarity:
            scored_chunks.append((score, chunk))

    if not scored_chunks:
        log_timing("recuperacion", now() - start, candidatos=len(chunks), elegibles=0)
        return []

    scored_chunks.sort(key=lambda item: item[0], reverse=True)
    fact_chunks = [(score, chunk) for score, chunk in scored_chunks[:3] if chunk.fact_id is not None]
    focus_score, focus = fact_chunks[0] if fact_chunks else scored_chunks[0]
    discovered = get_discovered_facts(session_id)
    for score, chunk in fact_chunks:
        if chunk.fact_id not in discovered and score >= focus_score - settings.new_fact_margin:
            focus = chunk
            break
    retrieved_chunks = [focus]
    for _, candidate in scored_chunks:
        if len(retrieved_chunks) >= settings.max_chunks:
            break
        if candidate is not focus and is_support(focus, candidate, session_id):
            retrieved_chunks.append(candidate)
    update_fact(session_id, focus.fact_id, focus.chunk_id)

    log_timing(
        "recuperacion",
        now() - start,
        candidatos=len(chunks),
        elegibles=len(scored_chunks),
        filtrado_ms=f"{filter_time * 1000:.1f}",
        embedding_ms=f"{embed_time * 1000:.1f}",
        focus=focus.chunk_id,
    )

    retrieved_texts = []
    for chunk in retrieved_chunks:
        retrieved_texts.append(chunk.retrieval_text)
    return retrieved_texts


def keep_said_facts(session_id: str, new_facts: set[str], reply: str) -> set[str]:
    """
    Deshace los hechos nuevos que la respuesta del NPC no llegó a decir y
    devuelve los que quedan descubiertos.
    """
    said = set()
    for fact_id in new_facts:
        chunk = next(c for c in CHUNKS if c.chunk_id == discovered_chunks[session_id][fact_id])
        for sentence in re.split(r"(?<=[.!?…])\s+", reply):
            if sentence and cosine_similarity(get_embedding(sentence), chunk.embeddings[0]) >= settings.said_similarity:
                said.add(fact_id)
                break
    get_discovered_facts(session_id).difference_update(new_facts - said)
    return said
