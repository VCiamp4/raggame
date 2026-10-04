extends StaticBody3D

@export var location_name: String = "oficina"
@export_file("*.tscn") var scene_path: String = "res://scenes/oficina.tscn"
@export var rotation_speed: float = 0.5

var is_highlighted: bool = false
var meshes: Array = []


func _ready() -> void:
	add_to_group("nodo_mapa")
	meshes = _find_meshes(self)


func _process(delta: float) -> void:
	rotate_y(rotation_speed * delta)


func _find_meshes(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_meshes(child))
	return found


func highlight() -> void:
	if is_highlighted:
		return
	is_highlighted = true
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.9, 0.3)
	mat.emission_energy_multiplier = 0.5
	for mesh in meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = mat


func unhighlight() -> void:
	if not is_highlighted:
		return
	is_highlighted = false
	for mesh in meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null


func get_location_name() -> String:
	return location_name


func get_scene_path() -> String:
	return scene_path
