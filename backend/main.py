from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import json
import requests
from backend.config import settings
from backend.rag.dialogue import DialogueService

app = FastAPI()
dialogue_service = DialogueService()


class DialogueRequest(BaseModel):
    npc_id: str
    player_input: str
    session_id: str = "default"


@app.get("/")
def root():
    return {"status": "ok", "message": "Servidor RAG-NPC andando"}


@app.post("/dialogue_stream")
def dialogue_stream(req: DialogueRequest):
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

    def generate():
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

            with requests.post(
                "https://api.openai.com/v1/chat/completions",
                headers=headers,
                json=payload,
                stream=True,
                timeout=(5, 300),
            ) as r:
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
                            reply += chunk
                            yield chunk
                        reason = choice["finish_reason"]
                        if reason and reason != "stop":
                            raise RuntimeError(f"OpenAI completion stopped: {reason}")
                if not completed:
                    raise RuntimeError("OpenAI stream ended before completion")
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
            with requests.post(f"{settings.ollama_url}/api/chat", json=payload, stream=True, timeout=(5, 300)) as r:
                for line in r.iter_lines():
                    if not line:
                        continue
                    data = json.loads(line)
                    chunk = data.get("message", {}).get("content", "")
                    if chunk:
                        reply += chunk
                        yield chunk
                    if data.get("done", False):
                        break
        # Recién guardamos el turno (pregunta + respuesta) cuando terminó bien.
        dialogue_service.save_response(
            session_id=req.session_id,
            npc_id=req.npc_id,
            player_input=req.player_input,
            response=reply,
        )

    return StreamingResponse(generate(), media_type="text/plain")
