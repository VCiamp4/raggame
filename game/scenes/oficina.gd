extends StaticBody3D

@export var location_name: String = "oficina"
@export_file("*.tscn") var scene_path: String = "res://scenes/oficina.gd"
@export var rotation_speed: float = 0.5

var is_highlighted: bool = false
var mesh_instance: MeshInstance3D


func _ready() -> void:
	add_to_group("nodo_mapa")
	mesh_instance = _find_mesh(self)


func _process(delta: float) -> void:
	rotate_y(rotation_speed * delta)


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
	mat.emission_energy_multiplier = 0.5
	mesh_instance.material_overlay = mat


func unhighlight() -> void:
	if not is_highlighted or mesh_instance == null:
		return
	is_highlighted = false
	mesh_instance.material_overlay = null


func get_location_name() -> String:
	return location_name


func get_scene_path() -> String:
	return scene_path
