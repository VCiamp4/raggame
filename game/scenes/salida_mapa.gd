extends StaticBody3D

@export var object_name: String = "Regresar al tablón"
@export_file("*.tscn") var target_scene_path: String = "res://scenes/mapa_menu.tscn"
@export var rotation_speed: float = 0.0

var is_highlighted: bool = false
var mesh_instance: MeshInstance3D


func _ready() -> void:
    add_to_group("salida_mapa")
    mesh_instance = _find_mesh(self)


func _process(delta: float) -> void:
    if rotation_speed != 0.0:
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
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(1, 1, 0.7)
    mat.emission_enabled = true
    mat.emission = Color(1, 0.9, 0.4)
    mat.emission_energy_multiplier = 0.6
    mesh_instance.material_overlay = mat


func unhighlight() -> void:
    if not is_highlighted or mesh_instance == null:
        return
    is_highlighted = false
    mesh_instance.material_overlay = null


func get_interaction_label() -> String:
    return object_name


func interact() -> void:
    _return_to_menu()


func _return_to_menu() -> void:
    if target_scene_path == "":
        push_warning("No hay escena de destino configurada para la salida al mapa")
        return
    get_tree().change_scene_to_file(target_scene_path)
