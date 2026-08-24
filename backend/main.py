from __future__ import annotations

import threading
from collections import defaultdict

import requests
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from backend.rag.config import Settings
from backend.rag.index import HybridIndex, IndexNotReadyError
from backend.rag.service import RAGService, history_turn


app = FastAPI(title="Un crimen casi perfecto - NPC RAG", version="2.0")
SETTINGS = Settings.from_env()

_SERVICE: RAGService | None = None
_SERVICE_LOCK = threading.Lock()
_HISTORY_LOCK = threading.RLock()
HISTORIES: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)


class DialogueRequest(BaseModel):
    npc_id: str = Field(min_length=1, max_length=64)
    player_input: str = Field(min_length=1, max_length=1000)
    session_id: str = Field(default="default", min_length=1, max_length=100)


class AccusationRequest(BaseModel):
    npc_id: str = Field(min_length=1, max_length=64)
    session_id: str = Field(default="default", min_length=1, max_length=100)


def _service() -> RAGService:
    global _SERVICE
    if _SERVICE is not None:
        return _SERVICE
    with _SERVICE_LOCK:
        if _SERVICE is None:
            _SERVICE = RAGService.create(SETTINGS)
    return _SERVICE


def _require_service() -> RAGService:
    try:
        return _service()
    except (IndexNotReadyError, FileNotFoundError, ValueError) as error:
        raise HTTPException(status_code=503, detail=str(error)) from error


@app.get("/")
def root() -> dict:
    index_metadata = HybridIndex.metadata_from(SETTINGS.index_path)
    return {
        "status": "ok",
        "message": "Servidor RAG-NPC configurado",
        "chat_model": SETTINGS.chat_model,
        "embedding_model": SETTINGS.embedding_model,
        "index_present": bool(index_metadata),
        "index_chunks": int(index_metadata.get("chunk_count", "0")),
    }


@app.get("/health")
def health() -> dict:
    service = _require_service()
    try:
        result = service.health()
    except requests.RequestException as error:
        raise HTTPException(status_code=503, detail=f"Ollama no responde: {error}") from error
    if not result["ready"]:
        raise HTTPException(status_code=503, detail=result)
    return result


@app.post("/dialogue_stream")
def dialogue_stream(req: DialogueRequest) -> StreamingResponse:
    service = _require_service()
    if req.npc_id not in service.personas:
        raise HTTPException(status_code=404, detail=f"NPC '{req.npc_id}' no existe")

    key = (req.session_id, req.npc_id)
    with _HISTORY_LOCK:
        conversation = HISTORIES[key]
        if SETTINGS.max_history_messages > 0:
            history = list(conversation[-SETTINGS.max_history_messages :])
        else:
            history = list(conversation)

    try:
        prepared = service.prepare_dialogue(
            session_id=req.session_id,
            npc_id=req.npc_id,
            player_input=req.player_input,
            history=history,
        )
    except requests.RequestException as error:
        raise HTTPException(
            status_code=503,
            detail=f"No se pudo generar el embedding de la consulta: {error}",
        ) from error
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

    def generate():
        reply_parts: list[str] = []
        completed = False
        try:
            for text in service.stream(prepared):
                reply_parts.append(text)
                yield text
            completed = True
        finally:
            # Un corte de red o error de Ollama no debe descubrir pistas ni
            # contaminar el historial con una respuesta incompleta.
            if completed:
                reply = "".join(reply_parts).strip()
                if reply:
                    with _HISTORY_LOCK:
                        conversation = HISTORIES[key]
                        conversation.extend(history_turn(prepared, reply))
                        if SETTINGS.max_history_messages > 0:
                            del conversation[: -SETTINGS.max_history_messages]
                    service.commit_response(prepared)

    return StreamingResponse(
        generate(),
        media_type="text/plain; charset=utf-8",
        headers={"Cache-Control": "no-store"},
    )


@app.get("/sessions/{session_id}")
def session_state(session_id: str) -> dict:
    service = _require_service()
    return service.sessions.snapshot(session_id)


@app.post("/sessions/{session_id}/reset")
def reset_session(session_id: str) -> dict:
    service = _require_service()
    state = service.sessions.reset(session_id)
    with _HISTORY_LOCK:
        for key in [key for key in HISTORIES if key[0] == session_id]:
            del HISTORIES[key]
    return state.snapshot()


@app.post("/accuse")
def accuse(req: AccusationRequest) -> dict:
    service = _require_service()
    if req.npc_id not in {"criada", "juan", "esteban", "pablo"}:
        raise HTTPException(status_code=422, detail="Ese personaje no puede ser acusado")
    try:
        state = service.sessions.accuse(req.session_id, req.npc_id)
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    return state.snapshot()
