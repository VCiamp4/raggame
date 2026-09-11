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


func set_difficulty(profile: Dictionary) -> void:
	if profile.is_empty():
		difficulty_profile = DEFAULT_DIFFICULTY.duplicate(true)
		return
	difficulty_profile = profile.duplicate(true)


func current_difficulty() -> Dictionary:
	return difficulty_profile.duplicate(true)


func reset_difficulty() -> void:
	difficulty_profile = DEFAULT_DIFFICULTY.duplicate(true)
