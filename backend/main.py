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

    def generate():
        reply = ""
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
