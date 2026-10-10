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
