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
