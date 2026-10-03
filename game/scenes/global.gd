extends Node

const DEFAULT_DIFFICULTY := {
	"id": "standard",
	"name": "Estándar",
	"tagline": "Equilibrio entre pistas y presión",
	"planned_effects": {
		"clue_window": 1.0,
		"llm_temperature_bias": 0.0,
		"npc_tolerance": 1.0
	}
}

var accused_id: String = ""
var accused_name: String = ""
var difficulty_profile: Dictionary = DEFAULT_DIFFICULTY.duplicate(true)
var hint_uses_spent: int = 0
var hint_cooldown_ready_time: float = 0.0


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
	hint_cooldown_ready_time = 0.0


var session_id: String = str(Time.get_unix_time_from_system()) + "-" + str(randi())
