extends Node3D

@export var npc_name: String = "Aldric"
@export var dialogue_line: String = "Hola, viajero."

signal player_entered_range(npc: Node)
signal player_exited_range(npc: Node)

@onready var interaction_area: Area3D = $InteractionArea

func _ready() -> void:
	add_to_group("npc")
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	print("Algo entró al area: ", body.name, " - es player? ", body.is_in_group("player"))
	if body.is_in_group("player"):
		player_entered_range.emit(self)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_exited_range.emit(self)

func get_response(_player_input: String = "") -> String:
	# Por ahora hardcodeado. Después acá llamamos al backend.
	return dialogue_line
