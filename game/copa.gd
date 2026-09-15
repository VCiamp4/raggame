extends StaticBody3D

@export_multiline var description: String = "Una copa de whisky a medio terminar. El líquido ámbar todavía despide un aroma intenso. Hay una marca de labios en el borde."
@export var object_name: String = "Copa de whisky"

var is_highlighted: bool = false
var original_materials: Array = []
var mesh_instance: MeshInstance3D


func _ready() -> void:
	add_to_group("examinable") 
	mesh_instance = _find_mesh(self)
	print(">> Script de copa cargado. Grupos: ", get_groups())


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
	# Aplicar un material de resaltado (emisión)
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


func get_description() -> String:
	return description
