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
