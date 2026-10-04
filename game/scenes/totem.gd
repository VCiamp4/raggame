extends StaticBody3D

# Tótem de salida al mapa. Se puede instanciar (totem.tscn) y mover en el
# editor. La distancia a la que el jugador puede interactuar se configura
# por instancia con interact_distance.

@export var height: float = 1.7
@export var radius: float = 0.35
@export var interact_distance: float = 3.0
@export var object_name: String = "Salida"

var is_highlighted: bool = false
var mesh_instance: MeshInstance3D


func _ready() -> void:
	add_to_group("totem")
	collision_layer = 3
	collision_mask = 0
	mesh_instance = _find_mesh(self)
	if mesh_instance == null:
		_build()


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result := _find_mesh(child)
		if result:
			return result
	return null


func _build() -> void:
	var mesh_instance_new := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.6
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 6
	mesh_instance_new.mesh = mesh
	mesh_instance_new.position.y = height * 0.5

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.08, 0.04)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.55, 0.15)
	material.emission_energy_multiplier = 0.8
	mesh_instance_new.material_override = material
	add_child(mesh_instance_new)
	mesh_instance = mesh_instance_new

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	shape.shape = capsule
	shape.position.y = height * 0.5
	add_child(shape)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 1.2
	light.omni_range = 4.0
	light.position.y = height * 0.9
	add_child(light)


func get_interact_distance() -> float:
	return interact_distance


func highlight() -> void:
	if is_highlighted or mesh_instance == null:
		return
	is_highlighted = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.9, 0.3)
	mat.emission_energy_multiplier = 0.6
	mesh_instance.material_overlay = mat


func unhighlight() -> void:
	if not is_highlighted or mesh_instance == null:
		return
	is_highlighted = false
	mesh_instance.material_overlay = null
