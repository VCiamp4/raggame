from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


NPC_CHANNELS = {
    "criada": "chat_criada",
    "portero": "chat_portero",
    "juan": "chat_juan",
    "esteban": "chat_esteban",
    "pablo": "chat_pablo",
    "quimico": "chat_perito_quimico",
    "tecnico_heladera": "chat_tecnico_heladera",
}

NPC_KNOWLEDGE_IDS = {
    "criada": "criada",
    "portero": "portero",
    "juan": "juan",
    "esteban": "esteban",
    "pablo": "pablo",
    # El nodo de Godot conserva el ID corto; la base editorial usa el nombre
    # inequívoco para no confundir al perito con cualquier químico.
    "quimico": "perito_quimico",
    "tecnico_heladera": "tecnico_heladera",
}


def normalize_text(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text.casefold())
    without_accents = "".join(
        char for char in decomposed if not unicodedata.combining(char)
    )
    return re.sub(r"\s+", " ", without_accents).strip()


def tokenize(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", normalize_text(text))


@dataclass(frozen=True)
class Chunk:
    chunk_id: str
    source: dict[str, Any]
    source_text: str
    retrieval_text: str
    mentioned_entities: tuple[str, ...]
    knowledge_holders: tuple[str, ...]
    availability: dict[str, tuple[str, ...]]
    fact_ids: tuple[str, ...]
    focus_eligible: bool
    keywords: tuple[str, ...]
    neighbor_ids: tuple[str, ...]
    resolution_only: bool
    variant: str

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> "Chunk":
        required = {
            "schema_version",
            "chunk_id",
            "scene_id",
            "source",
            "source_text",
            "retrieval_text",
            "kind",
            "speakers",
            "mentioned_entities",
            "knowledge_holders",
            "claim_status",
            "availability",
            "discovery",
            "retrieval",
            "security",
            "variant",
        }
        missing = required.difference(raw)
        if missing:
            raise ValueError(f"{raw.get('chunk_id', '<sin id>')} carece de {sorted(missing)}")
        availability = raw["availability"]
        discovery = raw["discovery"]
        retrieval = raw["retrieval"]
        security = raw["security"]
        return cls(
            chunk_id=raw["chunk_id"],
            source=raw["source"],
            source_text=raw["source_text"],
            retrieval_text=raw["retrieval_text"],
            mentioned_entities=tuple(raw["mentioned_entities"]),
            knowledge_holders=tuple(raw["knowledge_holders"]),
            availability={
                "milestones_all": tuple(availability["milestones_all"]),
                "facts_all": tuple(availability["facts_all"]),
                "facts_any": tuple(availability["facts_any"]),
                "facts_none": tuple(availability["facts_none"]),
                "channels": tuple(availability["channels"]),
            },
            fact_ids=tuple(discovery["fact_ids"]),
            focus_eligible=bool(discovery["focus_eligible"]),
            keywords=tuple(retrieval["keywords"]),
            neighbor_ids=tuple(retrieval["neighbor_ids"]),
            resolution_only=bool(security["resolution_only"]),
            variant=str(raw["variant"]),
        )

    @property
    def embedding_text(self) -> str:
        keywords = ", ".join(self.keywords)
        return f"{self.retrieval_text}\nPalabras clave: {keywords}"

    @property
    def lexical_text(self) -> str:
        entities = " ".join(entity.replace("_", " ") for entity in self.mentioned_entities)
        return f"{self.retrieval_text} {' '.join(self.keywords)} {entities}"

    def is_available(
        self,
        *,
        npc_id: str,
        facts: set[str],
        milestones: set[str],
    ) -> bool:
        actual_channel = NPC_CHANNELS.get(npc_id)
        knowledge_id = NPC_KNOWLEDGE_IDS.get(npc_id, npc_id)
        if knowledge_id not in self.knowledge_holders:
            return False
        if actual_channel not in self.availability["channels"]:
            return False
        if self.resolution_only:
            return False
        if not set(self.availability["milestones_all"]).issubset(milestones):
            return False
        if not set(self.availability["facts_all"]).issubset(facts):
            return False
        facts_any = set(self.availability["facts_any"])
        if facts_any and not facts_any.intersection(facts):
            return False
        if set(self.availability["facts_none"]).intersection(facts):
            return False
        return True


class Corpus:
    def __init__(
        self,
        chunks: Iterable[Chunk],
        canonical_questions: dict[str, str],
    ):
        self.chunks = tuple(chunks)
        actual_variants = {chunk.variant for chunk in self.chunks}
        if actual_variants != {"atomic"}:
            raise ValueError(
                f"Solo se admite la variante atomic; se encontraron {sorted(actual_variants)}"
            )
        self.variant = "atomic"
        self.by_id = {chunk.chunk_id: chunk for chunk in self.chunks}
        if len(self.by_id) != len(self.chunks):
            raise ValueError("Hay chunk_id duplicados")
        for chunk in self.chunks:
            unknown_neighbors = set(chunk.neighbor_ids).difference(self.by_id)
            if unknown_neighbors:
                raise ValueError(
                    f"{chunk.chunk_id} refiere vecinos inexistentes: {unknown_neighbors}"
                )
        expected_ids = set(self.by_id)
        questions = canonical_questions
        if set(questions) != expected_ids:
            missing = sorted(expected_ids.difference(questions))
            extra = sorted(set(questions).difference(expected_ids))
            raise ValueError(
                "Las preguntas canónicas no coinciden con el corpus: "
                f"faltan={missing[:5]}, sobran={extra[:5]}"
            )
        if any(
            not isinstance(question, str) or not question.strip()
            for question in questions.values()
        ):
            raise ValueError("Cada chunk debe tener una pregunta canónica no vacía")
        self.canonical_questions = {key: value.strip() for key, value in questions.items()}

    @classmethod
    def load(
        cls,
        scenes_dir: Path,
        canonical_questions_path: Path | None = None,
    ) -> "Corpus":
        all_paths = sorted(scenes_dir.glob("[0-9][0-9]_*.chunks.json"))
        paths = [path for path in all_paths if path.name.endswith(".atomic.chunks.json")]
        if not paths:
            raise FileNotFoundError(f"No hay archivos .atomic.chunks.json en {scenes_dir}")
        chunks: list[Chunk] = []
        seen_scenes: set[str] = set()
        for path in paths:
            payload = json.loads(path.read_text(encoding="utf-8"))
            scene_id = payload["scene_id"]
            if scene_id in seen_scenes:
                raise ValueError(f"Escena duplicada: {scene_id}")
            seen_scenes.add(scene_id)
            for raw in payload["chunks"]:
                if raw["scene_id"] != scene_id:
                    raise ValueError(f"Chunk {raw['chunk_id']} en archivo de escena incorrecto")
                chunks.append(Chunk.from_dict(raw))
        if len(paths) != 15:
            raise ValueError(f"Se esperaban 15 archivos de chunks y se encontraron {len(paths)}")
        if canonical_questions_path is not None:
            questions_path = canonical_questions_path
        else:
            questions_path = (
                Path(__file__).resolve().parents[1]
                / "data"
                / "canonical_questions.json"
            )
        try:
            questions_payload = json.loads(questions_path.read_text(encoding="utf-8"))
        except FileNotFoundError as error:
            raise FileNotFoundError(
                f"Falta el índice editorial de preguntas canónicas: {questions_path}"
            ) from error
        if questions_payload.get("schema_version") != 1:
            raise ValueError(f"Versión de preguntas canónicas no soportada: {questions_path}")
        questions = questions_payload.get("questions")
        if not isinstance(questions, dict):
            raise ValueError(f"{questions_path} no contiene un mapa questions válido")
        return cls(
            chunks,
            {str(key): str(value) for key, value in questions.items()},
        )

    @property
    def fingerprint(self) -> str:
        digest = hashlib.sha256()
        for chunk in self.chunks:
            digest.update(chunk.chunk_id.encode("utf-8"))
            digest.update(b"\0")
            digest.update(chunk.embedding_text.encode("utf-8"))
            digest.update(b"\0")
            digest.update(self.canonical_questions[chunk.chunk_id].encode("utf-8"))
            digest.update(b"\0")
        return digest.hexdigest()

    def canonical_question(self, chunk_id: str) -> str:
        return self.canonical_questions[chunk_id]

    def available_chunks(
        self,
        *,
        npc_id: str,
        facts: set[str],
        milestones: set[str],
    ) -> list[Chunk]:
        return [
            chunk
            for chunk in self.chunks
            if chunk.is_available(npc_id=npc_id, facts=facts, milestones=milestones)
        ]
