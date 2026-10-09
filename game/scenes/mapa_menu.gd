extends Node3D

@onready var camera: Camera3D = $Camera3D

const LABEL_HEIGHT := 1.5

const ARROW_ACTIONS := {
	"ui_left": Vector2(-1, 0),
	"ui_right": Vector2(1, 0),
	"ui_up": Vector2(0, -1),
	"ui_down": Vector2(0, 1),
}

var map_nodes: Array = []
var focused_node: Node = null
var label: Label3D
var last_mouse_pos: Vector2 = Vector2.INF


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_label()
	# Los nodos se agregan al grupo en su propio _ready.
	_gather_nodes.call_deferred()


func _gather_nodes() -> void:
	map_nodes = get_tree().get_nodes_in_group("nodo_mapa")
	if map_nodes.size() > 0:
		_set_focus(map_nodes[0])


func _build_label() -> void:
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	label.pixel_size = 0.01
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 1)
	label.modulate = Color(1, 1, 0.8)
	label.visible = false
	add_child(label)


func _process(_delta: float) -> void:
	_update_mouse_focus()
	_update_label()


func _update_mouse_focus() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	if mouse_pos == last_mouse_pos:
		return
	last_mouse_pos = mouse_pos
	var found := _node_under_mouse(mouse_pos)
	if found != null and found != focused_node:
		_set_focus(found)


func _node_under_mouse(mouse_pos: Vector2) -> Node:
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var ray_end := ray_origin + ray_dir * 1000.0

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := space_state.intersect_ray(query)

	if result.is_empty() or not result.has("collider"):
		return null
	# Puede golpear un collider hijo: subimos hasta el nodo_mapa.
	var node: Node = result["collider"]
	while node != null and not node.is_in_group("nodo_mapa"):
		node = node.get_parent()
	if node != null and node.is_in_group("nodo_mapa"):
		return node
	return null


func _set_focus(node: Node) -> void:
	if node == focused_node:
		return
	if focused_node != null and focused_node.has_method("unhighlight"):
		focused_node.unhighlight()
	focused_node = node
	if focused_node != null and focused_node.has_method("highlight"):
		focused_node.highlight()
	if label != null:
		if focused_node != null:
			if focused_node.has_method("get_location_name"):
				label.text = str(focused_node.get_location_name())
			else:
				label.text = str(focused_node.name)
			label.visible = true
		else:
			label.visible = false


func _update_label() -> void:
	if label == null or not label.visible or focused_node == null:
		return
	label.global_position = focused_node.global_position + Vector3(0, LABEL_HEIGHT, 0)


func _unhandled_input(event: InputEvent) -> void:
	for action in ARROW_ACTIONS:
		if event.is_action_pressed(action):
			_move_focus(ARROW_ACTIONS[action])
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("ui_accept"):
		if focused_node != null:
			_enter_location(focused_node)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if focused_node != null:
				_enter_location(focused_node)


func _move_focus(direction: Vector2) -> void:
	if map_nodes.is_empty():
		return
	if focused_node == null:
		_set_focus(map_nodes[0])
		return

	var origin := camera.unproject_position(focused_node.global_position)
	var best: Node = null
	var best_score := INF
	for node in map_nodes:
		if node == focused_node:
			continue
		var delta := camera.unproject_position(node.global_position) - origin
		var dist := delta.length()
		if dist < 1.0:
			continue
		var dot := (delta / dist).dot(direction)
		if dot <= 0.15:
			continue
		# Entre los nodos que están en la dirección pedida, elegimos el más cercano.
		var score := dist
		if score < best_score:
			best_score = score
			best = node
	if best != null:
		_set_focus(best)


func _enter_location(node: Node) -> void:
	var path: String = node.get_scene_path()
	if path != "":
		get_tree().change_scene_to_file(path)
	else:
		print(">> El nodo no tiene escena asignada: ", node.get_location_name())
