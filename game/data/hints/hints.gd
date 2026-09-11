extends Resource
class_name HintCatalog

const DEFAULT_HINT := "Todavía no registraste pistas clave. Hablá con los sospechosos y examina la escena para desbloquear indicios."

const HINTS: Dictionary = {
	"PI-CRI-01": "La criada se quiebra cuando recordás las humillaciones. Preguntale por episodios concretos y cómo la trataba Stevens en público.",
	"PI-CRI-02": "El whisky y el servicio nocturno esconden detalles. Repasá exactamente quién sirvió el vaso y qué pasó con los cubitos.",
	"PI-JUA-01": "Juan sigue rumiando su condena. Si mencionás a la policía y viejos favores, terminará admitiendo por qué odia a Stevens.",
	"PI-JUA-02": "No le hables de justicia: hablá de dinero. Cuando se siente cerca del premio, cuenta cuánto esperaba cobrar de la póliza.",
	"PI-EST-01": "Esteban conoce cada cláusula. Mostrale los papeles del seguro o cuestioná quién lo gestionó para que admita su rol.",
	"PI-EST-02": "Recordá el almuerzo familiar. Mencioná la discusión y quién salió gritando para que revele el favor hacia Pablo.",
	"PI-EST-03": "No olvides que Esteban también cobraba. Preguntale por porcentajes y beneficiarios para que admita su motivación financiera.",
	"PI-PAB-01": "En Erpa manejan químicos delicados. Hacelo hablar de protocolos y reactivos para saber qué tenía a mano.",
	"PI-PAB-02": "La herencia fue desigual. Si mencionás la mitad que consiguió, explicará cómo convenció a Stevens.",
	"PI-PAB-03": "El arreglo de la heladera es clave. Preguntale por el fusible, el congelador y quién manipuló el hielo días antes.",
	"PI-PAB-04": "El cianuro estaba a su alcance. Vinculá sus labores en Erpa con sustancias controladas para que admita el acceso.",
	"PI-GLO-01": "El forense juró que las botellas estaban limpias. Buscá otro vector: tal vez lo que se derrite dentro del vaso.",
	"PI-GLO-02": "Todo apunta al hielo. Averiguá quién tocó la cubetera y por qué alguien necesitaba apagar y encender la heladera.",
	"PI-GLO-03": "La avería era mínima. Preguntá al técnico qué pieza cambió para saber quién tuvo excusa para abrir la heladera.",
	"PI-GLO-04": "El portero lleva un registro obsesivo. Insistí con horarios y visitas: después de las 19:10 nadie entró sin su permiso."
}


static func hint_for_event(event_id: String) -> String:
	var text: String = str(HINTS.get(event_id, ""))
	return text.strip_edges()


static func default_hint() -> String:
	return DEFAULT_HINT
