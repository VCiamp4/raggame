import json
from pathlib import Path


# El orden del archivo es la prioridad: se sugiere la primera pista
# alcanzable cuyo hecho todavía no se descubrió.
HINTS_PATH = Path(__file__).resolve().parents[2] / "story" / "hints.json"
HINTS = json.loads(HINTS_PATH.read_text(encoding="utf-8"))["hints"]

discovered_facts = {}

def get_discovered_facts(session_id: str) -> set[str]:
    """
    Devuelve el conjunto de hechos descubiertos por el jugador en la sesión especificada.
    """
    if session_id not in discovered_facts:
        discovered_facts[session_id] = set()
    return discovered_facts[session_id]

def update_fact(session_id: str, fact_id: str | None) -> None:
    """
    Actualiza el conjunto de hechos descubiertos por el jugador en la sesión especificada.
    """
    if fact_id is not None:
        discovered_facts[session_id].add(fact_id)

def is_available(chunk, npc_id: str, session_id: str) -> bool:
    """
    Devuelve True si el chunk está disponible para el NPC y la sesión especificados.
    """
    if npc_id not in chunk.knowledge_holders:
        return False
    return is_unlocked(chunk, session_id)

def is_unlocked(chunk, session_id: str) -> bool:
    """
    Devuelve True si los hechos descubiertos en la sesión desbloquean el chunk,
    sin importar qué NPC lo conoce.
    """
    discovered_facts = get_discovered_facts(session_id)
    for fact_id in chunk.necessary_facts:
        if fact_id not in discovered_facts:
            return False
    if not chunk.sufficient_facts:
        return True
    for fact_id in chunk.sufficient_facts:
        if fact_id in discovered_facts:
            return True
    return False

def is_support(focus, candidate, session_id: str) -> bool:
    """
    Devuelve True si el candidate es un chunk de soporte para el focus.
    """
    discovered_facts = get_discovered_facts(session_id).copy()
    if candidate.fact_id is None:
        return True
    if focus.fact_id is not None:
        discovered_facts.add(focus.fact_id)
    return candidate.fact_id in discovered_facts

def next_hint(session_id: str, with_npc: bool, chunks) -> dict | None:
    """
    Devuelve la pista del hecho más prioritario que el jugador puede descubrir
    ahora y todavía no descubrió, o None si no queda ninguno.
    """
    discovered = get_discovered_facts(session_id)
    for hint in HINTS:
        fact_id = hint["fact_id"]
        if fact_id in discovered:
            continue
        if any(chunk.fact_id == fact_id and is_unlocked(chunk, session_id) for chunk in chunks):
            text = hint["text_with_npc"] if with_npc else hint["text"]
            return {"fact_id": fact_id, "text": text}
    return None
