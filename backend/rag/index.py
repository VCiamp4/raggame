from __future__ import annotations

import hashlib
import json
import math
import os
import sqlite3
import struct
import tempfile
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from .corpus import Chunk, Corpus, tokenize
from .ollama import OllamaClient


EMBEDDING_PROTOCOL = "embeddinggemma_query_document"


def _require_embeddinggemma(model: str) -> None:
    if "embeddinggemma" not in model.casefold():
        raise ValueError(
            "El runtime productivo de retrieval solo admite modelos embeddinggemma"
        )


def query_embedding_input(text: str) -> str:
    return f"task: search result | query: {text.strip()}"


def document_embedding_input(text: str) -> str:
    return f"title: none | text: {text.strip()}"


# Palabras funcionales muy frecuentes no deben convertir una pregunta genérica
# (por ejemplo, "¿qué pasó?") en una coincidencia léxica con cualquier chunk.
SPANISH_STOPWORDS = {
    "a",
    "al",
    "algo",
    "como",
    "con",
    "cual",
    "cuando",
    "de",
    "del",
    "donde",
    "el",
    "ella",
    "en",
    "era",
    "es",
    "esa",
    "ese",
    "esto",
    "fue",
    "ha",
    "hay",
    "la",
    "las",
    "le",
    "lo",
    "los",
    "me",
    "mi",
    "no",
    "para",
    "pero",
    "por",
    "porque",
    "que",
    "quien",
    "se",
    "si",
    "sin",
    "su",
    "sus",
    "te",
    "tenia",
    "tenian",
    "tiene",
    "tienen",
    "tener",
    "tu",
    "un",
    "una",
    "usted",
    "vos",
    "y",
    "ya",
}


class IndexNotReadyError(RuntimeError):
    """El índice no existe o no coincide con el corpus/modelo configurado."""


SECOND_CANONICAL_SCHEMA_VERSION = 1
SECOND_CANONICAL_VERSION = "two_questions_v1"
SECOND_CANONICAL_WEIGHT_Q1 = 0.75
SECOND_CANONICAL_WEIGHT_Q2 = 0.25


def _sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_second_canonical_questions(
    path: Path, corpus: Corpus
) -> tuple[dict[str, str], str]:
    """Load and validate the frozen second-question map used by q2 indexes."""

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise IndexNotReadyError(
            f"No se pudo leer el mapa de preguntas secundarias {path}: {error}"
        ) from error
    if (
        payload.get("schema_version") != SECOND_CANONICAL_SCHEMA_VERSION
        or payload.get("version") != SECOND_CANONICAL_VERSION
    ):
        raise IndexNotReadyError(f"Mapa de preguntas secundarias no soportado: {path}")
    questions = payload.get("questions")
    if not isinstance(questions, dict):
        raise IndexNotReadyError(f"El mapa secundario no contiene questions: {path}")
    expected_ids = set(corpus.by_id)
    if len(questions) != 162 or set(questions) != expected_ids:
        raise IndexNotReadyError(
            "El mapa secundario debe contener exactamente los 162 IDs del corpus"
        )
    normalized = {str(key): str(value).strip() for key, value in questions.items()}
    if any(not value for value in normalized.values()):
        raise IndexNotReadyError("El mapa secundario contiene preguntas vacías")
    if len(set(normalized.values())) != len(normalized):
        raise IndexNotReadyError("El mapa secundario contiene preguntas duplicadas")
    if any(normalized[key] == corpus.canonical_questions[key] for key in expected_ids):
        raise IndexNotReadyError(
            "El mapa secundario contiene una pregunta idéntica a la canónica q1"
        )
    try:
        fingerprint = _sha256_file(path)
    except OSError as error:
        raise IndexNotReadyError(
            f"No se pudo calcular el fingerprint de {path}: {error}"
        ) from error
    return normalized, fingerprint


@dataclass(frozen=True)
class ScoredChunk:
    chunk: Chunk
    dense_similarity: float
    fusion_score: float
    canonical_similarity: float


@dataclass(frozen=True)
class RetrievalResult:
    focus: ScoredChunk | None
    support: tuple[ScoredChunk, ...]

    @property
    def context(self) -> tuple[ScoredChunk, ...]:
        if self.focus is None:
            return self.support
        return (self.focus, *self.support)

    @property
    def fact_ids_to_record(self) -> tuple[str, ...]:
        if self.focus is None or not self.focus.chunk.focus_eligible:
            return ()
        return self.focus.chunk.fact_ids


def _normalize_vector(values: Iterable[float]) -> tuple[float, ...]:
    vector = tuple(float(value) for value in values)
    norm = math.sqrt(sum(value * value for value in vector))
    if not vector or norm == 0.0 or not math.isfinite(norm):
        raise ValueError("El modelo devolvió un embedding vacío o inválido")
    return tuple(value / norm for value in vector)


def _pack_vector(vector: tuple[float, ...]) -> bytes:
    return struct.pack(f"<{len(vector)}f", *vector)


def _unpack_vector(blob: bytes, dimension: int) -> tuple[float, ...]:
    expected_size = dimension * 4
    if len(blob) != expected_size:
        raise IndexNotReadyError(
            f"Embedding corrupto: se esperaban {expected_size} bytes y hay {len(blob)}"
        )
    return struct.unpack(f"<{dimension}f", blob)


def _dot(left: tuple[float, ...], right: tuple[float, ...]) -> float:
    if len(left) != len(right):
        raise ValueError(f"Dimensiones incompatibles: {len(left)} != {len(right)}")
    return sum(a * b for a, b in zip(left, right, strict=True))


def _minmax(values: dict[str, float]) -> dict[str, float]:
    if not values:
        return {}
    low = min(values.values())
    high = max(values.values())
    if high == low:
        return {key: 0.0 for key in values}
    return {key: (value - low) / (high - low) for key, value in values.items()}


def _query_tokens(text: str) -> list[str]:
    return [
        token
        for token in tokenize(text)
        if len(token) > 2 and token not in SPANISH_STOPWORDS
    ]


def _bm25(query: str, chunks: list[Chunk]) -> dict[str, float]:
    query_terms = _query_tokens(query)
    if not query_terms or not chunks:
        return {chunk.chunk_id: 0.0 for chunk in chunks}

    documents = {chunk.chunk_id: tokenize(chunk.lexical_text) for chunk in chunks}
    document_frequency: Counter[str] = Counter()
    for tokens in documents.values():
        document_frequency.update(set(tokens).intersection(query_terms))

    average_length = sum(len(tokens) for tokens in documents.values()) / len(documents)
    average_length = max(average_length, 1.0)
    document_count = len(documents)
    k1 = 1.5
    b = 0.75
    scores: dict[str, float] = {}

    for chunk_id, tokens in documents.items():
        frequencies = Counter(tokens)
        score = 0.0
        for term in query_terms:
            frequency = frequencies[term]
            if frequency == 0:
                continue
            df = document_frequency[term]
            inverse_document_frequency = math.log(
                1.0 + (document_count - df + 0.5) / (df + 0.5)
            )
            denominator = frequency + k1 * (
                1.0 - b + b * len(tokens) / average_length
            )
            score += inverse_document_frequency * frequency * (k1 + 1.0) / denominator
        scores[chunk_id] = score
    return scores


class HybridIndex:
    """Índice productivo de pasajes, q1 y q2 con filtros narrativos."""

    def __init__(
        self,
        *,
        corpus: Corpus,
        path: Path,
        embedding_client: OllamaClient,
        embedding_model: str,
        embedding_keep_alive: str,
        dense_candidates: int,
        support_chunks: int,
        min_dense_similarity: float,
        dimension: int,
        vectors: dict[str, tuple[float, ...]],
        canonical_vectors: dict[str, tuple[float, ...]],
        canonical_vectors_two: dict[str, tuple[float, ...]],
        metadata: dict[str, str],
    ):
        self.corpus = corpus
        self.path = path
        self.embedding_client = embedding_client
        self.embedding_model = embedding_model
        self.embedding_keep_alive = embedding_keep_alive
        self.dense_candidates = max(1, dense_candidates)
        self.support_chunks = max(0, support_chunks)
        self.min_dense_similarity = min_dense_similarity
        self.dimension = dimension
        self.vectors = vectors
        self.canonical_vectors = canonical_vectors
        self.canonical_vectors_two = canonical_vectors_two
        self.metadata = metadata

    @classmethod
    def open(
        cls,
        *,
        corpus: Corpus,
        path: Path,
        embedding_client: OllamaClient,
        embedding_model: str,
        embedding_keep_alive: str,
        dense_candidates: int = 8,
        support_chunks: int = 2,
        min_dense_similarity: float = 0.0,
        canonical_questions_two_path: Path,
    ) -> "HybridIndex":
        _require_embeddinggemma(embedding_model)
        if not path.exists():
            raise IndexNotReadyError(
                f"No existe {path}. Ejecutá: python -m backend.scripts.build_rag_index"
            )

        try:
            with sqlite3.connect(path) as connection:
                metadata = dict(connection.execute("SELECT key, value FROM metadata"))
                rows = list(connection.execute("SELECT chunk_id, vector FROM embeddings"))
                canonical_rows = list(
                    connection.execute("SELECT chunk_id, vector FROM canonical_embeddings")
                )
                canonical_two_rows = list(
                    connection.execute(
                        "SELECT chunk_id, vector FROM canonical_embeddings_two"
                    )
                )
        except sqlite3.Error as error:
            raise IndexNotReadyError(
                f"No se pudo leer el índice {path}: {error}. "
                "El índice debe reconstruirse con "
                "python -m backend.scripts.build_rag_index --force"
            ) from error

        expected = {
            "corpus_fingerprint": corpus.fingerprint,
            "embedding_model": embedding_model,
            "chunk_count": str(len(corpus.chunks)),
            "canonical_question_count": str(len(corpus.canonical_questions)),
            "embedding_protocol": EMBEDDING_PROTOCOL,
            "second_canonical_enabled": "1",
            "second_canonical_count": str(len(corpus.chunks)),
            "second_canonical_version": SECOND_CANONICAL_VERSION,
            "second_canonical_q1_weight": str(SECOND_CANONICAL_WEIGHT_Q1),
            "second_canonical_q2_weight": str(SECOND_CANONICAL_WEIGHT_Q2),
        }
        mismatches = {
            key: (metadata.get(key), value)
            for key, value in expected.items()
            if metadata.get(key) != value
        }
        if mismatches:
            details = ", ".join(
                f"{key}={actual!r} (esperado {wanted!r})"
                for key, (actual, wanted) in mismatches.items()
            )
            raise IndexNotReadyError(
                f"El índice está desactualizado: {details}. "
                "Reconstruilo con python -m backend.scripts.build_rag_index --force"
            )
        schema_version = metadata.get("schema_version", "")
        if schema_version != "3":
            raise IndexNotReadyError(
                f"Versión de esquema no soportada: {schema_version!r}"
            )
        metadata_variant = metadata.get("chunk_variant")
        if metadata_variant != corpus.variant:
            raise IndexNotReadyError(
                f"El índice declara chunks {metadata_variant!r}, pero el backend usa "
                f"{corpus.variant!r}. Reconstruilo con python -m backend.scripts.build_rag_index --force"
            )

        try:
            dimension = int(metadata["dimension"])
        except (KeyError, ValueError) as error:
            raise IndexNotReadyError("El índice no declara una dimensión válida") from error

        vectors = {chunk_id: _unpack_vector(blob, dimension) for chunk_id, blob in rows}
        canonical_vectors = {
            chunk_id: _unpack_vector(blob, dimension) for chunk_id, blob in canonical_rows
        }
        canonical_vectors_two = {
            chunk_id: _unpack_vector(blob, dimension)
            for chunk_id, blob in canonical_two_rows
        }
        _, question_fingerprint = load_second_canonical_questions(
            canonical_questions_two_path, corpus
        )
        expected_fingerprint = metadata.get("second_canonical_fingerprint")
        if question_fingerprint != expected_fingerprint:
            raise IndexNotReadyError(
                "El mapa de preguntas secundarias está desactualizado: "
                f"fingerprint={question_fingerprint!r} (esperado {expected_fingerprint!r})"
            )
        missing = set(corpus.by_id).difference(vectors)
        extra = set(vectors).difference(corpus.by_id)
        canonical_missing = set(corpus.by_id).difference(canonical_vectors)
        canonical_extra = set(canonical_vectors).difference(corpus.by_id)
        canonical_two_missing = set(corpus.by_id).difference(canonical_vectors_two)
        canonical_two_extra = set(canonical_vectors_two).difference(corpus.by_id)
        if (
            missing
            or extra
            or canonical_missing
            or canonical_extra
            or canonical_two_missing
            or canonical_two_extra
        ):
            raise IndexNotReadyError(
                "Índice y corpus difieren; "
                f"faltan={sorted(missing)}, sobran={sorted(extra)}, "
                f"canónicas_faltan={sorted(canonical_missing)}, "
                f"canónicas_sobran={sorted(canonical_extra)}, "
                f"q2_faltan={sorted(canonical_two_missing)}, "
                f"q2_sobran={sorted(canonical_two_extra)}"
            )

        return cls(
            corpus=corpus,
            path=path,
            embedding_client=embedding_client,
            embedding_model=embedding_model,
            embedding_keep_alive=embedding_keep_alive,
            dense_candidates=dense_candidates,
            support_chunks=support_chunks,
            min_dense_similarity=min_dense_similarity,
            dimension=dimension,
            vectors=vectors,
            canonical_vectors=canonical_vectors,
            canonical_vectors_two=canonical_vectors_two,
            metadata=metadata,
        )

    @classmethod
    def build(
        cls,
        *,
        corpus: Corpus,
        path: Path,
        embedding_client: OllamaClient,
        embedding_model: str,
        embedding_keep_alive: str,
        batch_size: int = 4,
        force: bool = False,
        dense_candidates: int = 8,
        support_chunks: int = 2,
        min_dense_similarity: float = 0.0,
        canonical_questions_two_path: Path,
    ) -> "HybridIndex":
        _require_embeddinggemma(embedding_model)
        if batch_size < 1:
            raise ValueError("batch_size debe ser mayor que cero")

        if path.exists() and not force:
            try:
                return cls.open(
                    corpus=corpus,
                    path=path,
                    embedding_client=embedding_client,
                    embedding_model=embedding_model,
                    embedding_keep_alive=embedding_keep_alive,
                    dense_candidates=dense_candidates,
                    support_chunks=support_chunks,
                    min_dense_similarity=min_dense_similarity,
                    canonical_questions_two_path=canonical_questions_two_path,
                )
            except IndexNotReadyError:
                pass

        path.parent.mkdir(parents=True, exist_ok=True)
        vectors: dict[str, tuple[float, ...]] = {}
        canonical_vectors: dict[str, tuple[float, ...]] = {}
        canonical_vectors_two: dict[str, tuple[float, ...]] = {}
        second_questions, second_fingerprint = load_second_canonical_questions(
            canonical_questions_two_path, corpus
        )
        chunks = list(corpus.chunks)
        dimension: int | None = None

        for start in range(0, len(chunks), batch_size):
            batch = chunks[start : start + batch_size]
            # The passage representation preserves the atomic fact. q1 and q2
            # are complementary editorial questions for that same fact. The
            # three views help paraphrased player questions match the intended
            # datum without putting either canonical question in chat context.
            inputs = [
                document_embedding_input(chunk.embedding_text)
                for chunk in batch
            ] + [
                query_embedding_input(corpus.canonical_question(chunk.chunk_id))
                for chunk in batch
            ] + [
                query_embedding_input(second_questions[chunk.chunk_id])
                for chunk in batch
            ]
            raw_vectors = embedding_client.embed(
                model=embedding_model,
                inputs=inputs,
                keep_alive=embedding_keep_alive,
            )
            expected_input_count = len(batch) * 3
            if len(raw_vectors) != expected_input_count:
                raise RuntimeError(
                    f"El modelo devolvió {len(raw_vectors)} embeddings para {expected_input_count} entradas"
                )
            first_end = len(batch)
            second_end = first_end * 2
            canonical_raws = raw_vectors[first_end:second_end]
            second_raws = raw_vectors[second_end:]
            for chunk, raw_vector, canonical_raw, second_raw in zip(
                batch,
                raw_vectors[:first_end],
                canonical_raws,
                second_raws,
                strict=True,
            ):
                vector = _normalize_vector(raw_vector)
                canonical_vector = _normalize_vector(canonical_raw)
                if dimension is None:
                    dimension = len(vector)
                elif len(vector) != dimension:
                    raise RuntimeError(
                        f"Dimensión cambiante para {chunk.chunk_id}: {len(vector)} != {dimension}"
                    )
                if len(canonical_vector) != dimension:
                    raise RuntimeError(
                        f"Dimensión canónica cambiante para {chunk.chunk_id}: "
                        f"{len(canonical_vector)} != {dimension}"
                    )
                vectors[chunk.chunk_id] = vector
                canonical_vectors[chunk.chunk_id] = canonical_vector
                second_vector = _normalize_vector(second_raw)
                if len(second_vector) != dimension:
                    raise RuntimeError(
                        f"Dimensión q2 cambiante para {chunk.chunk_id}: "
                        f"{len(second_vector)} != {dimension}"
                    )
                canonical_vectors_two[chunk.chunk_id] = second_vector
            completed = min(start + len(batch), len(chunks))
            print(f"Embeddings: {completed}/{len(chunks)}", flush=True)

        if dimension is None:
            raise RuntimeError("El corpus no contiene chunks")

        metadata = {
            "schema_version": "3",
            "corpus_fingerprint": corpus.fingerprint,
            "chunk_variant": corpus.variant,
            "embedding_model": embedding_model,
            "chunk_count": str(len(chunks)),
            "canonical_question_count": str(len(corpus.canonical_questions)),
            "dimension": str(dimension),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "embedding_protocol": EMBEDDING_PROTOCOL,
            "second_canonical_enabled": "1",
            "second_canonical_fingerprint": second_fingerprint,
            "second_canonical_version": SECOND_CANONICAL_VERSION,
            "second_canonical_count": str(len(second_questions)),
            "second_canonical_q1_weight": str(SECOND_CANONICAL_WEIGHT_Q1),
            "second_canonical_q2_weight": str(SECOND_CANONICAL_WEIGHT_Q2),
        }

        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
        )
        os.close(descriptor)
        temporary_path = Path(temporary_name)
        try:
            with sqlite3.connect(temporary_path) as connection:
                connection.executescript(
                    """
                    CREATE TABLE metadata (
                        key TEXT PRIMARY KEY,
                        value TEXT NOT NULL
                    );
                    CREATE TABLE embeddings (
                        chunk_id TEXT PRIMARY KEY,
                        vector BLOB NOT NULL
                    );
                    CREATE TABLE canonical_embeddings (
                        chunk_id TEXT PRIMARY KEY,
                        vector BLOB NOT NULL
                    );
                    CREATE TABLE canonical_embeddings_two (
                        chunk_id TEXT PRIMARY KEY,
                        vector BLOB NOT NULL
                    );
                    """
                )
                connection.executemany(
                    "INSERT INTO metadata(key, value) VALUES (?, ?)", metadata.items()
                )
                connection.executemany(
                    "INSERT INTO embeddings(chunk_id, vector) VALUES (?, ?)",
                    (
                        (chunk_id, sqlite3.Binary(_pack_vector(vector)))
                        for chunk_id, vector in vectors.items()
                    ),
                )
                connection.executemany(
                    "INSERT INTO canonical_embeddings(chunk_id, vector) VALUES (?, ?)",
                    (
                        (chunk_id, sqlite3.Binary(_pack_vector(vector)))
                        for chunk_id, vector in canonical_vectors.items()
                    ),
                )
                connection.executemany(
                    "INSERT INTO canonical_embeddings_two(chunk_id, vector) VALUES (?, ?)",
                    (
                        (chunk_id, sqlite3.Binary(_pack_vector(vector)))
                        for chunk_id, vector in canonical_vectors_two.items()
                    ),
                )
            os.replace(temporary_path, path)
        finally:
            temporary_path.unlink(missing_ok=True)

        return cls.open(
            corpus=corpus,
            path=path,
            embedding_client=embedding_client,
            embedding_model=embedding_model,
            embedding_keep_alive=embedding_keep_alive,
            dense_candidates=dense_candidates,
            support_chunks=support_chunks,
            min_dense_similarity=min_dense_similarity,
            canonical_questions_two_path=canonical_questions_two_path,
        )

    def retrieve(
        self,
        *,
        question: str,
        npc_id: str,
        facts: set[str],
        milestones: set[str],
    ) -> RetrievalResult:
        available = self.corpus.available_chunks(
            npc_id=npc_id,
            facts=facts,
            milestones=milestones,
        )
        if not available:
            return RetrievalResult(None, ())

        query = query_embedding_input(question)
        raw = self.embedding_client.embed(
            model=self.embedding_model,
            inputs=[query],
            keep_alive=self.embedding_keep_alive,
        )[0]
        query_vector = _normalize_vector(raw)
        if len(query_vector) != self.dimension:
            raise RuntimeError(
                f"El query embedding tiene dimensión {len(query_vector)}; el índice usa {self.dimension}"
            )

        answer_dense = {
            chunk.chunk_id: _dot(query_vector, self.vectors[chunk.chunk_id])
            for chunk in available
        }
        canonical_dense = {
            chunk.chunk_id: _dot(query_vector, self.canonical_vectors[chunk.chunk_id])
            for chunk in available
        }
        canonical_dense_two = {
            chunk.chunk_id: _dot(
                query_vector, self.canonical_vectors_two[chunk.chunk_id]
            )
            for chunk in available
        }

        # Raw confidence is measured before per-query normalization. A value
        # of 0 disables abstention. The production embeddinggemma index uses
        # a calibrated value of 0.50.
        # The all-below check here is only an early exit; after ranking and MMR
        # the same threshold is applied to each selected chunk independently.
        raw_similarity = {
            chunk.chunk_id: max(
                answer_dense[chunk.chunk_id],
                canonical_dense[chunk.chunk_id],
                canonical_dense_two[chunk.chunk_id],
            )
            for chunk in available
        }
        best_raw_similarity = max(raw_similarity.values())
        if (
            self.min_dense_similarity > 0.0
            and best_raw_similarity < self.min_dense_similarity
        ):
            return RetrievalResult(None, ())

        lexical = _bm25(question, available)

        # The candidate pool is the union of the two semantic views, then each
        # view is normalized against all available chunks before taking its
        # stronger signal.
        answer_rank = sorted(
            available,
            key=lambda chunk: answer_dense[chunk.chunk_id],
            reverse=True,
        )
        q1_normalized = _minmax(canonical_dense)
        q2_normalized = _minmax(canonical_dense_two)
        canonical_for_ranking = {
            chunk.chunk_id: (
                SECOND_CANONICAL_WEIGHT_Q1 * q1_normalized[chunk.chunk_id]
                + SECOND_CANONICAL_WEIGHT_Q2 * q2_normalized[chunk.chunk_id]
            )
            for chunk in available
        }
        canonical_rank = sorted(
            available,
            key=lambda chunk: canonical_for_ranking[chunk.chunk_id],
            reverse=True,
        )
        candidate_ids = {
            chunk.chunk_id for chunk in answer_rank[: self.dense_candidates]
        }
        candidate_ids.update(
            chunk.chunk_id for chunk in canonical_rank[: self.dense_candidates]
        )
        if not candidate_ids:
            return RetrievalResult(None, ())

        answer_normalized = _minmax(answer_dense)
        canonical_normalized = _minmax(canonical_for_ranking)
        lexical_normalized = _minmax(lexical)
        corpus_order = {chunk.chunk_id: position for position, chunk in enumerate(available)}
        scored: list[ScoredChunk] = []
        for chunk in available:
            chunk_id = chunk.chunk_id
            if chunk_id not in candidate_ids:
                continue
            relevance = max(answer_normalized[chunk_id], canonical_normalized[chunk_id])
            scored.append(
                ScoredChunk(
                    chunk=chunk,
                    dense_similarity=answer_dense[chunk_id],
                    fusion_score=relevance,
                    canonical_similarity=canonical_for_ranking[chunk_id],
                )
            )

        def ranking_key(item: ScoredChunk) -> tuple[float, float, float, float, float]:
            # The corpus position is the final deterministic tie-break.  It
            # avoids the old ``(score, chunk_id)`` lexicographic accident,
            # which made IDs decide semantically tied results.
            return (
                item.fusion_score,
                max(item.dense_similarity, item.canonical_similarity),
                item.canonical_similarity,
                lexical_normalized[item.chunk.chunk_id],
                -float(corpus_order[item.chunk.chunk_id]),
            )

        scored.sort(key=ranking_key, reverse=True)
        focus = scored[0] if scored else None
        if focus is None:
            return RetrievalResult(None, ())

        allowed_support_facts = set(facts)
        if focus.chunk.focus_eligible:
            allowed_support_facts.update(focus.chunk.fact_ids)
        selected = [focus]
        support_candidates = [
            item
            for item in scored[1:]
            if set(item.chunk.fact_ids).issubset(allowed_support_facts)
        ]
        support: list[ScoredChunk] = []
        # Maximal marginal relevance keeps a second context atom useful rather
        # than repeating the focus.  Editorial parent/neighbor links are
        # stronger redundancy signals than raw cosine alone and are available
        # even when the embedding model gives near-ties to adjacent atoms.
        while support_candidates and len(support) < self.support_chunks:
            def support_key(item: ScoredChunk) -> tuple[float, float, float, float]:
                semantic_redundancy = max(
                    (
                        _dot(
                            self.vectors[item.chunk.chunk_id],
                            self.vectors[chosen.chunk.chunk_id],
                        )
                        for chosen in selected
                    ),
                    default=0.0,
                )
                editorial_redundancy = 0.0
                for chosen in selected:
                    if item.chunk.source.get("parent_chunk_id") == chosen.chunk.source.get(
                        "parent_chunk_id"
                    ):
                        editorial_redundancy = max(editorial_redundancy, 1.0)
                    elif (
                        item.chunk.chunk_id in chosen.chunk.neighbor_ids
                        or chosen.chunk.chunk_id in item.chunk.neighbor_ids
                    ):
                        editorial_redundancy = max(editorial_redundancy, 0.65)
                redundancy = max(semantic_redundancy, editorial_redundancy)
                mmr = 0.70 * item.fusion_score - 0.30 * redundancy
                return (
                    mmr,
                    item.fusion_score,
                    max(item.dense_similarity, item.canonical_similarity),
                    -float(corpus_order[item.chunk.chunk_id]),
                )

            chosen = max(support_candidates, key=support_key)
            support.append(chosen)
            selected.append(chosen)
            support_candidates.remove(chosen)

        # Keep the productive ranking and MMR selection frozen, then discard
        # every selected item whose own raw score is below the calibrated
        # threshold. Preserve order and do not refill vacated slots. If the
        # original focus is filtered, remaining items stay as support instead
        # of being promoted, preserving fact-recording semantics.
        if self.min_dense_similarity > 0.0:
            kept = [
                item
                for item in selected
                if raw_similarity[item.chunk.chunk_id] >= self.min_dense_similarity
            ]
            if kept and kept[0] is focus:
                focus = kept[0]
                support = kept[1:]
            else:
                focus = None
                support = kept
        return RetrievalResult(focus, tuple(support))

    def describe(self) -> dict:
        return {
            "path": str(self.path),
            "embedding_model": self.embedding_model,
            "chunk_variant": self.corpus.variant,
            "dimension": self.dimension,
            "chunks": len(self.vectors),
            "canonical_questions": len(self.canonical_vectors),
            "canonical_questions_two": len(self.canonical_vectors_two),
            "second_canonical_enabled": True,
            "second_canonical_fingerprint": self.metadata.get(
                "second_canonical_fingerprint"
            ),
            "corpus_fingerprint": self.corpus.fingerprint,
            "created_at": self.metadata.get("created_at"),
        }

    @staticmethod
    def metadata_from(path: Path) -> dict[str, str]:
        if not path.exists():
            return {}
        try:
            with sqlite3.connect(path) as connection:
                return dict(connection.execute("SELECT key, value FROM metadata"))
        except sqlite3.Error:
            return {}
