extends Node

const DEFAULT_DIFFICULTY := {
	"id": "standard",
	"name": "Estándar",
	"tagline": "Equilibrio entre pistas y presión",
	"hint_limit": -1
}

const Accusations = preload("res://data/accusations.gd")

# Lo emite npc.gd cuando el backend registra un hecho nuevo en la sesión.
signal fact_discovered(fact_id: String)
# Un hecho nuevo completó las pruebas necesarias para acusar a este sospechoso.
signal suspect_unlocked(suspect_id: String)

var accused_id: String = ""
var accused_name: String = ""
var difficulty_profile: Dictionary = DEFAULT_DIFFICULTY.duplicate(true)
var hint_uses_spent: int = 0
var last_hint_fact_id: String = ""
# Transcripción de cada conversación (por NPC), para que sobreviva al cambio
# de escena (el jugador/diálogo se reinstancian en cada locación).
var chat_transcripts: Dictionary = {}
# Hechos descubiertos en esta sesión, usados como conjunto (fact_id -> true).
var discovered_facts: Dictionary = {}

const LINEUP_SCENE := "res://scenes/reconocimiento.tscn"
# Desde dónde se abrió la rueda de reconocimiento, para volver ahí si el
# jugador sale sin acusar: {"scene", "transform", "model_yaw"}.
var lineup_return: Dictionary = {}


# Abre la rueda de reconocimiento recordando la escena y el lugar del jugador.
func open_lineup(player: Node3D) -> void:
	lineup_return = {
		"scene": player.owner.scene_file_path,
		"transform": player.global_transform,
		"model_yaw": player.model.rotation.y,
	}
	get_tree().change_scene_to_file(LINEUP_SCENE)


func leave_lineup() -> void:
	get_tree().change_scene_to_file(lineup_return.get("scene", "res://scenes/mapa_menu.tscn"))


func _ready() -> void:
	fact_discovered.connect(_on_fact_discovered)


func _on_fact_discovered(fact_id: String) -> void:
	var before := {}
	for suspect_id in Accusations.SUSPECTS:
		before[suspect_id] = Accusations.can_accuse(suspect_id, discovered_facts)
	discovered_facts[fact_id] = true
	for suspect_id in Accusations.SUSPECTS:
		if not before[suspect_id] and Accusations.can_accuse(suspect_id, discovered_facts):
			suspect_unlocked.emit(suspect_id)


func has_fact(fact_id: String) -> bool:
	return discovered_facts.has(fact_id)


# Registra un hecho descubierto fuera del diálogo (p. ej. un objeto
# inspeccionable): avisa al backend y emite `fact_discovered`.
func discover_fact(fact_id: String) -> void:
	if fact_id == "" or discovered_facts.has(fact_id):
		return
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


var session_id: String = _new_session_id()


func _new_session_id() -> String:
	return str(Time.get_unix_time_from_system()) + "-" + str(randi())


# Empieza una partida nueva: otra sesión para el backend (historial y hechos
# limpios) y se borra todo el estado de la partida anterior.
func new_game() -> void:
	session_id = _new_session_id()
	accused_id = ""
	accused_name = ""
	chat_transcripts = {}
	discovered_facts = {}
	lineup_return = {}
	reset_difficulty()
