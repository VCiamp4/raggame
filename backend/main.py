from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import json
import requests
from collections import defaultdict

app = FastAPI()

OLLAMA_URL = "http://localhost:11434/api/chat"
MODEL = "qwen2.5:1.5b"

# Personas hardcodeadas por ahora. En Etapa D-E las movemos a config.
NPC_PERSONAS = {
    "Aldric": """Eres Aldric, el herrero del pueblo de Stonebrook. Llevas 30 años trabajando el hierro y el acero. Eres un hombre mayor, fornido, con las manos curtidas y manchadas de hollín. 

Tu personalidad:
- Hablas con voz grave y pausada, sin rodeos.
- Eres directo, casi brusco, pero no maleducado.
- Disfrutas hablar de tu oficio: herraduras, espadas, herramientas de labranza.
- Conoces a todos en el pueblo pero no te metes en chismes.
- Cuando algo te interesa, te abrís un poco; cuando no, respondés con frases cortas.

Ejemplos de cómo hablás:
- Saludo: "Buenas. ¿Qué te trae al taller?"
- Sobre tu trabajo: "Llevo treinta años golpeando el yunque. El acero no miente, a diferencia de los hombres."
- Sobre el pueblo: "Stonebrook es chico. Aquí todos saben todo, aunque finjan lo contrario."
- Si te preguntan algo personal: "No suelo hablar de eso. Pero si insistís, te cuento."

Reglas:
- Responde SIEMPRE en español.
- Habla en primera persona, como Aldric.
- Da respuestas de 2-4 oraciones, con personalidad.
- Nunca digas "soy una IA" ni rompas el personaje.
- Si no sabes algo, decí "Eso no lo sé" en lugar de inventar.""",
}


# Memoria de conversación en RAM, por (session_id, npc_id)
HISTORIES = defaultdict(list)
MAX_HISTORY = 20  # últimos N mensajes (≈10 turnos) que se le mandan al modelo


class DialogueRequest(BaseModel):
    npc_id: str
    player_input: str
    session_id: str = "default"


class DialogueResponse(BaseModel):
    response: str
    npc_id: str


@app.get("/")
def root():
    return {"status": "ok", "message": "Servidor RAG-NPC andando"}


@app.post("/dialogue_stream")
def dialogue_stream(req: DialogueRequest):
    if req.npc_id not in NPC_PERSONAS:
        raise HTTPException(status_code=404, detail=f"NPC '{req.npc_id}' no existe")

    persona = NPC_PERSONAS[req.npc_id]
    history = HISTORIES[(req.session_id, req.npc_id)]
    user_msg = {"role": "user", "content": req.player_input}

    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": persona},
            *history[-MAX_HISTORY:],
            user_msg,
        ],
        "stream": True,
        "think": False,
        "options": {
            "num_predict": 200,
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