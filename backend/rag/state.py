from __future__ import annotations

import threading
from dataclasses import dataclass, field


DERIVATIONS: dict[str, set[str]] = {
    "CL-JUA-02": {"CL-JUA-01"},
    "CL-POL-01": {"CL-JUA-04", "CL-EST-04", "CL-PAB-01"},
    "CL-EST-01": {"CL-PAB-04"},
    "CL-POL-02": {"CL-POL-03"},
    "CL-ICE-01": {"CL-ICE-03"},
    "CL-PAB-03": {"CL-PAB-08"},
}

CLUE_REQUIREMENTS: dict[str, tuple[str | None, set[str]]] = {
    "PI-CRI-01": ("criada", {"CL-CRI-01"}),
    "PI-CRI-02": ("criada", {"CL-CRI-02"}),
    "PI-JUA-01": ("juan", {"CL-JUA-01", "CL-JUA-02"}),
    "PI-JUA-02": ("juan", {"CL-JUA-04"}),
    "PI-EST-01": ("esteban", {"CL-POL-01"}),
    "PI-EST-02": ("esteban", {"CL-EST-01"}),
    "PI-EST-03": ("esteban", {"CL-EST-04"}),
    "PI-PAB-01": ("pablo", {"CL-PAB-03", "CL-PAB-08"}),
    "PI-PAB-02": ("pablo", {"CL-PAB-04"}),
    "PI-PAB-03": ("pablo", {"CL-FRI-02"}),
    "PI-PAB-04": ("pablo", {"CL-ERP-01"}),
    "PI-GLO-01": (None, {"CL-FOR-02"}),
    "PI-GLO-02": (None, {"CL-ICE-03"}),
    "PI-GLO-03": (None, {"CL-TEC-01", "CL-TEC-02"}),
    "PI-GLO-04": (None, {"CL-POR-01", "CL-POR-02"}),
}


@dataclass
class SessionState:
    session_id: str
    discovered_facts: set[str] = field(default_factory=set)
    discovered_clues: set[str] = field(default_factory=set)
    milestones: set[str] = field(default_factory=lambda: {"M00_CASE_OPEN"})
    talked_to: set[str] = field(default_factory=set)
    accusation: str | None = None
    outcome: str = "in_progress"

    def snapshot(self) -> dict:
        return {
            "session_id": self.session_id,
            "discovered_facts": sorted(self.discovered_facts),
            "discovered_clues": sorted(self.discovered_clues),
            "milestones": sorted(self.milestones),
            "talked_to": sorted(self.talked_to),
            "accusation": self.accusation,
            "outcome": self.outcome,
            "accusable_npcs": sorted(
                npc
                for npc in ("criada", "juan", "esteban", "pablo")
                if self.can_accuse(npc)
            ),
        }

    def can_accuse(self, npc_id: str) -> bool:
        count = sum(
            1
            for clue_id in self.discovered_clues
            if CLUE_REQUIREMENTS.get(clue_id, (None, set()))[0] == npc_id
        )
        return self.outcome == "in_progress" and count >= 2


class SessionStore:
    def __init__(self):
        self._states: dict[str, SessionState] = {}
        self._lock = threading.RLock()

    def get(self, session_id: str) -> SessionState:
        with self._lock:
            return self._states.setdefault(session_id, SessionState(session_id=session_id))

    def reset(self, session_id: str) -> SessionState:
        with self._lock:
            state = SessionState(session_id=session_id)
            self._states[session_id] = state
            return state

    def snapshot(self, session_id: str) -> dict:
        with self._lock:
            return self.get(session_id).snapshot()

    def retrieval_context(self, session_id: str) -> tuple[set[str], set[str]]:
        with self._lock:
            state = self.get(session_id)
            return (
                set(state.discovered_facts),
                set(state.milestones),
            )

    def record_response(
        self,
        session_id: str,
        npc_id: str,
        fact_ids: tuple[str, ...],
    ) -> SessionState:
        with self._lock:
            state = self.get(session_id)
            state.talked_to.add(npc_id)
            state.discovered_facts.update(fact_ids)
            self._derive(state)
            return state

    def accuse(self, session_id: str, npc_id: str) -> SessionState:
        with self._lock:
            state = self.get(session_id)
            if state.outcome != "in_progress":
                raise ValueError("La partida ya fue resuelta")
            if not state.can_accuse(npc_id):
                raise ValueError(f"Todavía no hay dos pistas visibles contra {npc_id}")
            state.accusation = npc_id
            state.outcome = "victory" if npc_id == "pablo" else "defeat"
            state.milestones.add("M80_RESOLVED")
            state.milestones.add("M81_VICTORY" if state.outcome == "victory" else "M82_DEFEAT")
            return state

    @staticmethod
    def _derive(state: SessionState) -> None:
        changed = True
        while changed:
            changed = False
            for origin, derived in DERIVATIONS.items():
                if origin in state.discovered_facts:
                    before = len(state.discovered_facts)
                    state.discovered_facts.update(derived)
                    changed = changed or len(state.discovered_facts) != before

        for clue_id, (_, requirements) in CLUE_REQUIREMENTS.items():
            if requirements.issubset(state.discovered_facts):
                state.discovered_clues.add(clue_id)

        facts = state.discovered_facts
        if "CL-FOR-01" in facts:
            state.milestones.add("M10_POISONING_CONFIRMED")
        if "CL-FOR-02" in facts:
            state.milestones.add("M20_LIQUIDS_CLEARED")
        if "CL-ICE-01" in facts:
            state.milestones.add("M30_ICE_HYPOTHESIS")
        if "CL-ICE-03" in facts:
            state.milestones.add("M40_POISON_IN_ICE")
        if "CL-FRI-02" in facts:
            state.milestones.add("M50_PABLO_FRIDGE_LINK")
        if {"CL-ERP-01", "CL-TEC-01"}.issubset(facts):
            state.milestones.add("M60_MEANS_CORROBORATED")
        if any(state.can_accuse(npc) for npc in ("criada", "juan", "esteban", "pablo")):
            state.milestones.add("M70_ACCUSATION_AVAILABLE")
