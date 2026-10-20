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
const Highlight = preload("res://scenes/highlight.gd")

@export var inspectable_id: String = ""
# Overrides opcionales: si quedan vacíos, se usan los del catálogo.
@export var object_name_override: String = ""
@export_multiline var description_override: String = ""
# Descripción condicional: si `fact_requires` NO está descubierto se usa
# `description_locked`; si lo está, `description_unlocked`.
@export var fact_requires: String = ""
@export_multiline var description_locked: String = ""
@export_multiline var description_unlocked: String = ""
# Hecho que se descubre al inspeccionar (vacío = no descubre nada). Admite
# varios hechos separados por comas.
@export var fact_to_discover: String = ""
# Color del resaltado. Los objetos blancos muy iluminados (p. ej. el plato)
# necesitan un amarillo más saturado para no verse casi blancos.
@export var highlight_color: Color = Highlight.DEFAULT_COLOR

var is_highlighted: bool = false
var meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("examinable")
	meshes = Highlight.collect_meshes(self)
	# Un collider agregado debajo del modelo (p. ej. la heladera) no tiene
	# meshes propios: se resalta el modelo al que pertenece.
	if meshes.is_empty() and get_parent() != null:
		meshes = Highlight.collect_meshes(get_parent())


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
	for fact_id in fact_to_discover.split(",", false):
		var trimmed := fact_id.strip_edges()
		if trimmed != "":
			Global.discover_fact(trimmed)


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
	if is_highlighted or meshes.is_empty():
		return
	is_highlighted = true
	Highlight.set_highlighted(meshes, true, highlight_color)


func unhighlight() -> void:
	if not is_highlighted:
		return
	is_highlighted = false
	Highlight.set_highlighted(meshes, false)
