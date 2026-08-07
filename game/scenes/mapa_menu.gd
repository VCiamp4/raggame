extends Node3D

@onready var camera: Camera3D = $Camera3D

var highlighted_node: Node = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_check_node_under_mouse()


func _check_node_under_mouse() -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var ray_end = ray_origin + ray_dir * 1000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result = space_state.intersect_ray(query)
	
	var found: Node = null
	if result and result.has("collider"):
		var collider = result["collider"]
		if collider.is_in_group("nodo_mapa"):
			found = collider
	
	if found != highlighted_node:
		if highlighted_node != null:
			highlighted_node.unhighlight()
		highlighted_node = found
		if found != null:
			found.highlight()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if highlighted_node != null:
				_enter_location(highlighted_node)


func _enter_location(node: Node) -> void:
	var path = node.get_scene_path()
	if path != "":
		get_tree().change_scene_to_file(path)
	else:
		print(">> El nodo no tiene escena asignada: ", node.get_location_name())
