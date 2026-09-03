extends StaticBody3D

var is_highlighted: bool = false
var mesh_instance: MeshInstance3D


func _ready() -> void:
	add_to_group("pizarron")
	mesh_instance = _find_mesh(self)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result = _find_mesh(child)
		if result:
			return result
	return null


func highlight() -> void:
	if is_highlighted or mesh_instance == null:
		return
	is_highlighted = true
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.9, 0.3)
	mat.emission_energy_multiplier = 0.4
	mesh_instance.material_overlay = mat


func unhighlight() -> void:
	if not is_highlighted or mesh_instance == null:
		return
	is_highlighted = false
	mesh_instance.material_overlay = null


func interact() -> void:
	get_tree().change_scene_to_file("res://scenes/reconocimiento.tscn")
