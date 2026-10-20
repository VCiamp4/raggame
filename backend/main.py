from fastapi import FastAPI, HTTPException
from fastapi.responses import PlainTextResponse, StreamingResponse
from pydantic import BaseModel
import json
import logging
import requests
from backend.config import settings
from backend.rag.dialogue import DialogueService
from backend.rag.game_state import discovered_chunks, get_discovered_facts, next_hint, update_fact
from backend.rag.retrieval import CHUNKS, keep_said_facts
from backend.timing import log_milestone, log_timing, ollama_load_seconds, now

app = FastAPI()
dialogue_service = DialogueService()


class DialogueRequest(BaseModel):
    npc_id: str
    player_input: str
    session_id: str = "default"


class DiscoverRequest(BaseModel):
    session_id: str
    fact_id: str


# Separa la respuesta del NPC de un mensaje de error para el jugador.
ERROR_MARKER = "\x1e"
# Separa la respuesta del NPC de los hechos nuevos que llegó a decir.
FACT_MARKER = "\x1f"


def error_message(exc: Exception) -> str:
    """
    Explica en español, para el jugador, por qué falló el turno.
    """
    logging.getLogger("uvicorn.error").error("Falló el turno: %r", exc)
    if isinstance(exc, requests.Timeout):
        return "El modelo tardó demasiado en responder."
    if isinstance(exc, requests.ConnectionError):
        return "No se pudo conectar con el modelo. Revisá que Ollama esté abierto y que haya internet."
    if isinstance(exc, requests.HTTPError):
        status = exc.response.status_code
        if status == 401:
            return "La API key de OpenAI no es válida o no está configurada."
        if "insufficient_quota" in exc.response.text:
            return "La cuenta de OpenAI no tiene créditos disponibles."
        if status == 429:
            return "OpenAI está recibiendo demasiados pedidos. Esperá unos segundos y volvé a intentar."
        if status == 404:
            return "No está instalado o disponible el modelo configurado."
        return f"El modelo respondió con un error (código {status})."
    if isinstance(exc, (RuntimeError, requests.exceptions.ChunkedEncodingError)):
        return "El modelo cortó la respuesta antes de terminar."
    return "Ocurrió un error inesperado en el servidor del juego."


@app.get("/")
def root():
    return {"status": "ok", "message": "Servidor RAG-NPC andando"}


@app.get("/notebook/{session_id}")
def notebook(session_id: str):
    discovered = get_discovered_facts(session_id)
    revealed = discovered_chunks.get(session_id, {})
    return {"clues": [
        {"fact_id": chunk.fact_id, "text": chunk.retrieval_text}
        for chunk in CHUNKS
        if chunk.fact_id in discovered and revealed.get(chunk.fact_id) == chunk.chunk_id
    ]}


@app.get("/hint/{session_id}")
def hint(session_id: str, with_npc: bool = False):
    return {"hint": next_hint(session_id, with_npc, CHUNKS)}


@app.post("/discover")
def discover(req: DiscoverRequest):
    # Objetos inspeccionables u otras fuentes fuera del diálogo registran un hecho.
    get_discovered_facts(req.session_id)
    chunk_id = next((c.chunk_id for c in CHUNKS if c.fact_id == req.fact_id), None)
    update_fact(req.session_id, req.fact_id, chunk_id)
    return {"ok": True}


@app.post("/dialogue_stream")
def dialogue_stream(req: DialogueRequest):
    turn_start = now()
    known_facts = set(get_discovered_facts(req.session_id))
    try:
        message = dialogue_service.get_message(
                session_id=req.session_id,
                npc_id=req.npc_id,
                player_input=req.player_input,
            )
    except KeyError:
        raise HTTPException(
            status_code=404,
            detail=f"NPC '{req.npc_id}' no existe",
        )
    except Exception as exc:
        return PlainTextResponse(ERROR_MARKER + error_message(exc))
    context_end = now()
    context_seconds = context_end - turn_start

    def generate():
        first_text = None
        try:
            for chunk in stream_reply():
                # Primer texto que sale hacia el juego: esto es lo que espera el
                # jugador desde que aprieta Enter (sin contar la red cliente).
                if first_text is None:
                    first_text = now()
                    log_milestone(
                        "TEXTO AL JUGADOR",
                        first_text - turn_start,
                        npc=req.npc_id,
                        recuperacion_ms=f"{context_seconds * 1000:.0f}",
                        llm_ms=f"{(first_text - context_end) * 1000:.0f}",
                    )
                yield chunk
        except Exception as exc:
            # El turno falló: no queda guardado ni deja pistas nuevas.
            get_discovered_facts(req.session_id).difference_update(new_facts)
            yield ERROR_MARKER + error_message(exc)
        finally:
            log_timing("turno", now() - turn_start, npc=req.npc_id)

    def stream_reply():
        reply = ""
        if settings.chat_provider == "openai":
            headers = {
                "Authorization": f"Bearer {settings.openai_api_key}",
                "Content-Type": "application/json",
            }
            payload = {
                "model": settings.chat_model,
                "messages": message,
                "stream": True,
                "max_completion_tokens": settings.num_predict,
                "reasoning_effort": "none",
                "temperature": settings.temperature,
            }

            stream_start = now()
            first_token = None
            with requests.post(
                "https://api.openai.com/v1/chat/completions",
                headers=headers,
                json=payload,
                stream=True,
                timeout=(5, 300),
            ) as r:
                if not r.ok:
                    r.content  # lee el motivo antes de cerrar; error_message lo usa
                r.raise_for_status()
                completed = False
                for line in r.iter_lines(decode_unicode=True):
                    if not line or not line.startswith("data:"):
                        continue
                    event_data = line.removeprefix("data:").strip()
                    if event_data == "[DONE]":
                        completed = True
                        break
                    data = json.loads(event_data)
                    if "error" in data:
                        raise RuntimeError(data["error"]["type"])
                    for choice in data.get("choices", []):
                        chunk = choice["delta"].get("content")
                        if chunk:
                            if first_token is None:
                                first_token = now()
                                log_timing(
                                    "chat_primer_token",
                                    first_token - stream_start,
                                    modelo=settings.chat_model,
                                    proveedor="openai",
                                )
                            reply += chunk
                            yield chunk
                        reason = choice["finish_reason"]
                        if reason and reason != "stop":
                            raise RuntimeError(f"OpenAI completion stopped: {reason}")
                if not completed:
                    raise RuntimeError("OpenAI stream ended before completion")
            log_timing(
                "chat_completo",
                now() - stream_start,
                modelo=settings.chat_model,
                proveedor="openai",
            )
        else:
            payload = {
                "model": settings.chat_model,
                "messages": message,
                "stream": True,
                "think": False,
                "options": {
                    "num_predict": settings.num_predict,
                    "temperature": settings.temperature,
                }
            }
            stream_start = now()
            first_token = None
            with requests.post(f"{settings.ollama_url}/api/chat", json=payload, stream=True, timeout=(5, 300)) as r:
                r.raise_for_status()
                for line in r.iter_lines():
                    if not line:
                        continue
                    data = json.loads(line)
                    if "error" in data:
                        raise RuntimeError(data["error"])
                    chunk = data.get("message", {}).get("content", "")
                    if chunk:
                        if first_token is None:
                            first_token = now()
                            log_timing(
                                "chat_primer_token",
                                first_token - stream_start,
                                modelo=settings.chat_model,
                                proveedor="ollama",
                            )
                        reply += chunk
                        yield chunk
                    if data.get("done", False):
                        load = ollama_load_seconds(data)
                        log_timing(
                            "chat_completo",
                            now() - stream_start,
                            modelo=settings.chat_model,
                            proveedor="ollama",
                            load_s=f"{load:.2f}",
                            ya_cargado=(load == 0),
                            eval_s=f"{data.get('eval_duration', 0) / 1_000_000_000:.2f}",
                        )
                        break
        said_facts = keep_said_facts(req.session_id, new_facts, reply)
        # Recién guardamos el turno (pregunta + respuesta) cuando terminó bien.
        dialogue_service.save_response(
            session_id=req.session_id,
            npc_id=req.npc_id,
            player_input=req.player_input,
            response=reply,
        )
        if said_facts:
            yield FACT_MARKER + ",".join(sorted(said_facts))

    # La recuperación ya corrió en get_message: el hecho que propuso viaja en un
    # header antes del texto, y solo queda descubierto si el NPC lo dice.
    headers = {}
    new_facts = get_discovered_facts(req.session_id) - known_facts
    if new_facts:
        headers["X-Focus-Fact"] = ",".join(sorted(new_facts))
    return StreamingResponse(generate(), media_type="text/plain", headers=headers)
