extends Resource
class_name HintCatalog

const DEFAULT_HINT := "Todavía no registraste pistas clave. Hablá con los sospechosos y examina la escena para desbloquear indicios."

const HINTS: Dictionary = {
	"PI-CRI-01": "La criada parece demasiado triste, pero hay un aire de 'alivio' a su alrededor ¿Qué alivio tiene ella de qué no este más la señora Stevens?.",
	"PI-CRI-02": "El whisky parece la clave. Tengo que preguntar quién sirvió ese vaso y encuentra pistas.",
	"PI-JUA-01": "Juan es un ex-convicto. debería encontrar qué sucedió",
	"PI-JUA-02": "Juan era parte de la herencia, debería preguntar por eso y ver si se quiebra su fachada",
	"PI-EST-01": "Según el informe, Esteban es un corredor de seguros. Quizás debería indagar sobre si tiene algún trato",
	"PI-EST-02": "Recordá el último almuerzo familiar. Pregunta qué pasó esa tarde.",
	"PI-EST-03": "No olvides que Esteban también cobraba. Preguntale por porcentajes y beneficiarios.",
	"PI-PAB-01": "En Erpa manejan químicos delicados. Hacelo hablar de protocolos y reactivos para saber qué tenía a mano.",
	"PI-PAB-02": "La herencia estaba a punto de ser desigual. Invitalo a explicar porqué iba a cobrar más y como reaccionaron sus hermanos.",
	"PI-PAB-03": "Pablo arregló la heladera durante largo tiempo. Preguntale qué era lo qué reparó",
	"PI-PAB-04": "Encontramos el químico potente que estaba en el vaso en el laboratorio donde trabajaba Pablo, pregunta por eso.",
	"PI-GLO-01": "La forense asegura que las botellas y vasos de la casa estaban limpios. Si no estaba en el vaso ni en el alcohol ¿De dónde salió el veneno?.",
	"PI-GLO-02": "La mayoría de los homicidios ocurren por dinero, amor o amor al dinero. Debería indagar sobre si la muerte de la señora Stevens beneficia a alguien",
	"PI-GLO-03": "Todo apunta al hielo. Averiguá quién tocó la cubetera y por qué alguien necesitaba apagar y encender la heladera.",
	"PI-GLO-04": "La avería era mínima. Preguntá al técnico qué pieza cambió para saber quién tuvo excusa para abrir la heladera.",
}


static func hint_for_event(event_id: String) -> String:
	var text: String = str(HINTS.get(event_id, ""))
	return text.strip_edges()


static func default_hint() -> String:
	return DEFAULT_HINT
