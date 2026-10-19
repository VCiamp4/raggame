extends StaticBody3D

@export_file("*.tscn") var destino: String = "res://scenes/departamento.tscn"
@export var object_name: String = "Ascensor"

const Highlight = preload("res://scenes/highlight.gd")

var is_highlighted: bool = false
var meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("ascensor")
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
	if destino != "":
		get_tree().change_scene_to_file(destino)
	else:
		print(">> El ascensor no tiene destino asignado")
