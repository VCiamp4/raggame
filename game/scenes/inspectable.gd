extends StaticBody3D

# Componente genérico para elementos inspeccionables.
#
# Se puede adjuntar a cualquier StaticBody3D de una escena. A partir del
# inspectable_id busca su información en data/inspectables.gd.
#
# Comportamiento:
#   - Se registra en el grupo "examinable".
#   - Se puede resaltar (highlight/unhighlight) al apuntarlo o acercarse.
#   - Al inspeccionar, el jugador muestra display_name + description en el
#     diálogo de examinación (que se cierra con [E]/[Esc]).

const InspectableCatalogRes = preload("res://data/inspectables.gd")

@export var inspectable_id: String = ""
# Overrides opcionales: si quedan vacíos, se usan los del catálogo.
@export var object_name_override: String = ""
@export_multiline var description_override: String = ""
# Descripción condicional: si `fact_requires` NO está descubierto se usa
# `description_locked`; si lo está, `description_unlocked`.
@export var fact_requires: String = ""
@export_multiline var description_locked: String = ""
@export_multiline var description_unlocked: String = ""
# Hecho que se descubre al inspeccionar (vacío = no descubre nada).
@export var fact_to_discover: String = ""

var is_highlighted: bool = false
var mesh_instance: MeshInstance3D


func _ready() -> void:
	add_to_group("examinable")
	mesh_instance = _find_mesh(self)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.visible:
		return node
	for child in node.get_children():
		var result := _find_mesh(child)
		if result:
			return result
	# Si no hay ningún mesh visible, devolvemos al menos uno (oculto).
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
	return null


# ---------- Interfaz que consume jugador.gd ----------

func get_object_name() -> String:
	if object_name_override != "":
		return object_name_override
	return InspectableCatalogRes.display_name(inspectable_id)


func get_description() -> String:
	if fact_requires != "":
		if Global.has_fact(fact_requires):
			if description_unlocked != "":
				return description_unlocked
		elif description_locked != "":
			return description_locked
	if description_override != "":
		return description_override
	return InspectableCatalogRes.description(inspectable_id)


# Llamado por el jugador al abrir la inspección. Sólo descubre el hecho si la
# descripción desbloqueada está activa (es decir, si `fact_requires` se cumple).
func on_inspected() -> void:
	if fact_to_discover == "":
		return
	if fact_requires != "" and not Global.has_fact(fact_requires):
		return
	Global.discover_fact(fact_to_discover)


# Compatibilidad con código que lee la propiedad "object_name".
func get_object_name_property() -> String:
	return get_object_name()


func _get(property: StringName):
	# Permite que target.get("object_name") funcione aunque no sea un export.
	if property == &"object_name":
		return get_object_name()
	return null


# ---------- Resaltado ----------

func highlight() -> void:
	if is_highlighted or mesh_instance == null:
		return
	is_highlighted = true
	var mat := StandardMaterial3D.new()
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
