extends Node

const DEFAULT_DIFFICULTY := {
	"id": "standard",
	"name": "Estándar",
	"tagline": "Equilibrio entre pistas y presión",
	"hint_limit": -1
}

# Lo emite npc.gd cuando el backend registra un hecho nuevo en la sesión.
signal fact_discovered(fact_id: String)

var accused_id: String = ""
var accused_name: String = ""
var difficulty_profile: Dictionary = DEFAULT_DIFFICULTY.duplicate(true)
var hint_uses_spent: int = 0
var last_hint_fact_id: String = ""
# Transcripción de cada conversación (por NPC), para que sobreviva al cambio
# de escena (el jugador/diálogo se reinstancian en cada locación).
var chat_transcripts: Dictionary = {}
# Hechos descubiertos en esta partida (para gating de objetos, etc.).
var discovered_facts: Dictionary = {}


func _ready() -> void:
	fact_discovered.connect(_on_fact_discovered_local)


func _on_fact_discovered_local(fact_id: String) -> void:
	discovered_facts[fact_id] = true


func has_fact(fact_id: String) -> bool:
	return discovered_facts.has(fact_id)


# Registra un hecho descubierto fuera del diálogo (p. ej. un objeto
# inspeccionable): lo guarda, avisa al backend y emite la señal.
func discover_fact(fact_id: String) -> void:
	if fact_id == "" or discovered_facts.has(fact_id):
		return
	discovered_facts[fact_id] = true
	_notify_backend(fact_id)
	fact_discovered.emit(fact_id)


func _notify_backend(fact_id: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request(
		"http://127.0.0.1:8000/discover",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify({"session_id": session_id, "fact_id": fact_id}),
	)


func set_difficulty(profile: Dictionary) -> void:
	if profile.is_empty():
		difficulty_profile = DEFAULT_DIFFICULTY.duplicate(true)
		reset_hint_state()
		return
	difficulty_profile = profile.duplicate(true)
	reset_hint_state()


func current_difficulty() -> Dictionary:
	return difficulty_profile.duplicate(true)


func reset_difficulty() -> void:
	difficulty_profile = DEFAULT_DIFFICULTY.duplicate(true)
	reset_hint_state()


func reset_hint_state() -> void:
	hint_uses_spent = 0
	last_hint_fact_id = ""


var session_id: String = str(Time.get_unix_time_from_system()) + "-" + str(randi())
