extends StaticBody3D

@export var object_name: String = "Pizarrón"

const Highlight = preload("res://scenes/highlight.gd")

var is_highlighted: bool = false
var meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("pizarron")
	meshes = Highlight.collect_meshes(self)


func highlight() -> void:
	if is_highlighted or meshes.is_empty():
		return
	is_highlighted = true
	Highlight.set_highlighted(meshes, true)


func unhighlight() -> void:
	if not is_highlighted:
		return
	is_highlighted = false
	Highlight.set_highlighted(meshes, false)


func interact() -> void:
	Global.open_lineup(get_tree().get_first_node_in_group("player"))
