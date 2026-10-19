extends RefCounted

# Resaltado amarillo de los objetos clicables (examinables, pizarrón, ascensor).
# Se aplica a todos los meshes visibles del objeto, no sólo al primero, para
# que los modelos armados con varias piezas se resalten completos.
#
# Reemplaza el material (material_override), igual que los nodos del mapa: un
# overlay sobre la misma geometría empata en profundidad, queda tapado por los
# materiales transparentes y no se nota sobre los objetos blancos.

const PREVIOUS_META := &"highlight_previous_override"
const DEFAULT_COLOR := Color(1, 1, 0.6)

# Un material por color de resaltado.
static var _materials := {}


static func collect_meshes(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node
		if mesh.is_visible_in_tree():
			meshes.append(mesh)
	return meshes


static func set_highlighted(meshes: Array[MeshInstance3D], on: bool, color: Color = DEFAULT_COLOR) -> void:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = Color(1, 0.9, 0.3)
		material.emission_energy_multiplier = 0.5
		_materials[color] = material
	for mesh in meshes:
		if not is_instance_valid(mesh):
			continue
		if on:
			if not mesh.has_meta(PREVIOUS_META):
				mesh.set_meta(PREVIOUS_META, mesh.material_override)
			mesh.material_override = _materials[color]
		elif mesh.has_meta(PREVIOUS_META):
			mesh.material_override = mesh.get_meta(PREVIOUS_META)
			mesh.remove_meta(PREVIOUS_META)
