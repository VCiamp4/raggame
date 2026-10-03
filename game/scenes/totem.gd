extends StaticBody3D

const HEIGHT := 1.7
const RADIUS := 0.35


func _ready() -> void:
	add_to_group("totem")
	collision_layer = 3
	collision_mask = 0
	_build()


func _build() -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS * 0.6
	mesh.bottom_radius = RADIUS
	mesh.height = HEIGHT
	mesh.radial_segments = 6
	mesh_instance.mesh = mesh
	mesh_instance.position.y = HEIGHT * 0.5

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.08, 0.04)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.55, 0.15)
	material.emission_energy_multiplier = 0.8
	mesh_instance.material_override = material
	add_child(mesh_instance)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	shape.shape = capsule
	shape.position.y = HEIGHT * 0.5
	add_child(shape)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 1.2
	light.omni_range = 4.0
	light.position.y = HEIGHT * 0.9
	add_child(light)
