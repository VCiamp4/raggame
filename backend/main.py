from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import json
import os
import requests
import threading
from collections import defaultdict
from pathlib import Path

app = FastAPI()

OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434").rstrip("/")
OLLAMA_URL = f"{OLLAMA_BASE_URL}/api/chat"
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "gemma4:e4b")
OLLAMA_KEEP_ALIVE = os.environ.get("OLLAMA_KEEP_ALIVE", "2m")
OLLAMA_NUM_CTX = int(os.environ.get("OLLAMA_NUM_CTX", "1536"))
OLLAMA_NUM_PREDICT = int(os.environ.get("OLLAMA_NUM_PREDICT", "160"))
OLLAMA_TEMPERATURE = float(os.environ.get("OLLAMA_TEMPERATURE", "0.35"))
OLLAMA_TOP_P = float(os.environ.get("OLLAMA_TOP_P", "0.9"))

# Ollama tiene además OLLAMA_MAX_LOADED_MODELS=1 y OLLAMA_NUM_PARALLEL=1 en el
# contenedor. Este lock evita que dos requests del backend intenten cambiar el
# modelo o el contexto al mismo tiempo antes de llegar a ese límite.
MODEL_LOCK = threading.Lock()

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

# Los personajes del caso viven en archivos editables para que el guion y la
# personalidad usada por el modelo no se desincronicen.
PERSONAS_DIR = Path(__file__).resolve().parent.parent / "crimen-casi-perfecto-scripts" / "guiones" / "v1"
STORY_NPCS = {
    "criada": "criada.md",
    "esteban": "esteban.md",
    "juan": "juan.md",
    "pablo": "pablo.md",
    "portero": "portero.md",
    "quimico": "quimico.md",
    "tecnico_heladera": "tecnico_heladera.md",
}

for npc_id, filename in STORY_NPCS.items():
    NPC_PERSONAS[npc_id] = (PERSONAS_DIR / filename).read_text(encoding="utf-8")


# Memoria de conversación en RAM, por (session_id, npc_id)
HISTORIES = defaultdict(list)
MAX_HISTORY = int(os.environ.get("OLLAMA_MAX_HISTORY", "20"))  # ≈10 turnos


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
        "model": OLLAMA_MODEL,
        "messages": [
            {"role": "system", "content": persona},
            *history[-MAX_HISTORY:],
            user_msg,
        ],
        "stream": True,
        "think": False,
        "keep_alive": OLLAMA_KEEP_ALIVE,
        "options": {
            "num_ctx": OLLAMA_NUM_CTX,
            "num_predict": OLLAMA_NUM_PREDICT,
            "temperature": OLLAMA_TEMPERATURE,
            "top_p": OLLAMA_TOP_P,
        }
    }

    def generate():
        reply = ""
        with MODEL_LOCK:
            with requests.post(OLLAMA_URL, json=payload, stream=True, timeout=(5, 300)) as r:
                r.raise_for_status()
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
