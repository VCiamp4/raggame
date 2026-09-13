from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import json
import requests
from collections import defaultdict
from backend.dialogue import DialogueService

app = FastAPI()
dialogue_service = DialogueService()

OLLAMA_URL = "http://localhost:11434/api/chat"
MODEL = "gemma4:e4b"

# Memoria de conversación en RAM, por (session_id, npc_id)
HISTORIES = defaultdict(list)
MAX_HISTORY = 20  # últimos N mensajes (≈10 turnos) que se le mandan al modelo


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
        system_prompt = dialogue_service.get_system_prompt(req.npc_id)
    except KeyError:
        raise HTTPException(
            status_code=404,
            detail=f"NPC '{req.npc_id}' no existe",
        )
    
    history = HISTORIES[(req.session_id, req.npc_id)]
    user_msg = {"role": "user", "content": req.player_input}

    payload = {
        "model": MODEL,
        "messages": [
            system_prompt,
            *history[-MAX_HISTORY:],
            user_msg,
        ],
        "stream": True,
        "think": False,
        "options": {
            "num_predict": 160,
            "temperature": 0.8,
        }
    }

    def generate():
        reply = ""
        with requests.post(OLLAMA_URL, json=payload, stream=True, timeout=(5, 300)) as r:
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
        history.append(user_msg)
        history.append({"role": "assistant", "content": reply})

    return StreamingResponse(generate(), media_type="text/plain")
