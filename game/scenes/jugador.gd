extends CharacterBody3D

const SPEED = 3.0
const JUMP_VELOCITY = 4.5
const TURN_SPEED = 10.0
const FALL_DISTANCE = 1.0
const CAMERA_OFFSET = Vector3(0.0, 1.8, 3.2)
const CAMERA_LOOK_HEIGHT = 0.9
const MAPA_SCENE = "res://scenes/mapa_menu.tscn"

@onready var anim_player: AnimationPlayer = $Walking/AnimationPlayer
@onready var model: Node3D = $Walking
@onready var dialogue_ui: CanvasLayer = $DialogueUI
@onready var camera: Camera3D = $Camera3D

@export var retrato_jugador: Texture2D

const EXAMINE_DISTANCE = 6.0
const INTERACT_DISTANCE = 5.0
const TOTEM_DISTANCE = 3.0
const CLICKABLE_GROUPS := ["examinable", "pizarron", "ascensor"]
@export var totem_offset: Vector3 = Vector3(1.2, 0.0, 0.0)
var highlighted_object: Node = null
var nearby_clickable: Node = null
var nearby_totem: Node = null

var nearby_npc: Node = null
var in_dialogue: bool = false
var model_base_yaw: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("player")
	spawn_position = global_position
	camera.top_level = true
	model_base_yaw = model.rotation.y
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.has_signal("player_entered_range"):
			npc.player_entered_range.connect(_on_npc_entered_range)
			npc.player_exited_range.connect(_on_npc_exited_range)
	dialogue_ui.text_submitted.connect(_on_text_submitted)
	_spawn_totem.call_deferred()
	# Diferido: los grupos se pueblan en el _ready de cada objeto, que puede
	# correr después que el del jugador (p. ej. el pizarron en comisaria.tscn).
	_debug_list_clickables.call_deferred()


func _spawn_totem() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var target := spawn_position + totem_offset
	var query := PhysicsRayQueryParameters3D.create(
		target + Vector3.UP, target + Vector3.DOWN * 10.0)
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.has("position"):
		target.y = result["position"].y
	var totem := StaticBody3D.new()
	totem.set_script(load("res://scenes/totem.gd"))
	parent.add_child(totem)
	totem.global_position = target


func _physics_process(delta: float) -> void:
	if global_position.y < spawn_position.y - FALL_DISTANCE:
		_respawn()
		return

	if in_dialogue:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	
	# Gravedad
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	# Movimiento
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var local_dir := Vector3(input_dir.x, 0, input_dir.y)
	var direction := (transform.basis * local_dir).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		# El personaje gira para mirar hacia donde se mueve.
		var target_yaw := model_base_yaw + atan2(-local_dir.x, -local_dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, TURN_SPEED * delta)
		if anim_player and not anim_player.is_playing():
			anim_player.play("mixamo_com")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		if anim_player and anim_player.is_playing():
			anim_player.pause()
	
	move_and_slide()


func _respawn() -> void:
	velocity = Vector3.ZERO
	global_position = spawn_position


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not in_dialogue:
		if nearby_npc != null:
			_open_dialogue()
		elif nearby_clickable != null:
			_trigger_clickable(nearby_clickable)
	elif event.is_action_pressed("ui_cancel"):
		if in_dialogue:
			_close_dialogue()
		elif nearby_totem != null:
			get_tree().change_scene_to_file(MAPA_SCENE)
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if highlighted_object != null and not in_dialogue:
				if highlighted_object.is_in_group("pizarron"):
					highlighted_object.interact()
				elif highlighted_object.is_in_group("ascensor"):
					highlighted_object.interact()   
				else:
					_examine_object(highlighted_object)   # copa: muestra texto


# ---------- NPCs (con LLM) ----------

func _open_dialogue() -> void:
	in_dialogue = true
	dialogue_ui.hide_prompt()
	dialogue_ui.show_dialogue(nearby_npc.npc_name)
	dialogue_ui.set_input_enabled(true)
	dialogue_ui.mostrar_retratos(retrato_jugador, nearby_npc.get_retrato())  # input visible para escribirle al NPC


func _close_dialogue() -> void:
	in_dialogue = false
	dialogue_ui.hide_dialogue()
	dialogue_ui.ocultar_retratos()
	if nearby_npc != null:
		dialogue_ui.show_prompt(nearby_npc.npc_name)


func _on_text_submitted(text: String) -> void:
	if nearby_npc == null:
		return
	
	# Mostrar lo que dijo el jugador en el historial
	dialogue_ui.add_player_message(nearby_npc.npc_name, text)
	# Iniciar línea del NPC (queda esperando los chunks)
	dialogue_ui.start_npc_response(nearby_npc.npc_name)
	
	# Conectar señales de streaming
	if not nearby_npc.response_chunk.is_connected(_on_response_chunk):
		nearby_npc.response_chunk.connect(_on_response_chunk)
	if not nearby_npc.response_completed.is_connected(_on_response_completed):
		nearby_npc.response_completed.connect(_on_response_completed, CONNECT_ONE_SHOT)
	
	nearby_npc.request_response(text)


func _on_response_chunk(text: String) -> void:
	dialogue_ui.append_npc_chunk(text)


func _on_response_completed() -> void:
	if nearby_npc != null and nearby_npc.response_chunk.is_connected(_on_response_chunk):
		nearby_npc.response_chunk.disconnect(_on_response_chunk)
	dialogue_ui.finish_npc_response()
	dialogue_ui.set_input_enabled(true)


func _on_npc_entered_range(npc: Node) -> void:
	nearby_npc = npc
	if not in_dialogue:
		dialogue_ui.show_prompt(npc.npc_name)


func _on_npc_exited_range(npc: Node) -> void:
	if nearby_npc == npc:
		nearby_npc = null
		if not in_dialogue:
			dialogue_ui.hide_prompt()


# ---------- Objetos examinables (sin LLM) ----------

func _process(_delta: float) -> void:
	_update_camera()
	if in_dialogue:
		_clear_highlight()
		return
	_check_examinable_under_mouse()
	_update_nearby_clickable()
	_update_nearby_totem()
	_update_prompt()


func _update_nearby_clickable() -> void:
	var closest: Node = null
	var closest_dist := INTERACT_DISTANCE
	for group in CLICKABLE_GROUPS:
		for obj in get_tree().get_nodes_in_group(group):
			var dist := global_position.distance_to(_clickable_anchor(obj))
			if dist <= closest_dist:
				closest_dist = dist
				closest = obj
	nearby_clickable = closest


func _update_nearby_totem() -> void:
	var closest: Node = null
	var closest_dist := TOTEM_DISTANCE
	for totem in get_tree().get_nodes_in_group("totem"):
		var dist := global_position.distance_to(_clickable_anchor(totem))
		if dist <= closest_dist:
			closest_dist = dist
			closest = totem
	nearby_totem = closest


func _update_prompt() -> void:
	if nearby_npc != null:
		dialogue_ui.show_prompt(nearby_npc.npc_name)
	elif nearby_clickable != null:
		dialogue_ui.show_interact_prompt(_clickable_display_name(nearby_clickable))
	elif nearby_totem != null:
		dialogue_ui.show_map_prompt()
	else:
		dialogue_ui.hide_prompt()


func _clickable_anchor(obj: Node) -> Vector3:
	var shape := _find_collision_shape(obj)
	if shape != null:
		return shape.global_position
	return obj.global_position


func _find_collision_shape(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node
	for child in node.get_children():
		var result := _find_collision_shape(child)
		if result != null:
			return result
	return null


func _clickable_display_name(obj: Node) -> String:
	var display = obj.get("object_name")
	if display != null and str(display) != "":
		return str(display)
	return obj.name


func _trigger_clickable(obj: Node) -> void:
	if (obj.is_in_group("pizarron") or obj.is_in_group("ascensor")) and obj.has_method("interact"):
		obj.interact()
	else:
		_examine_object(obj)


func _update_camera() -> void:
	var cam_basis := global_transform.basis.orthonormalized()
	camera.global_position = global_position + cam_basis * CAMERA_OFFSET
	camera.look_at(global_position + Vector3.UP * CAMERA_LOOK_HEIGHT, Vector3.UP)


func _check_examinable_under_mouse() -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var ray_end = ray_origin + ray_dir * 100.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 2
	var result = space_state.intersect_ray(query)
	
	var found: Node = null
	if result and result.has("collider"):
		var collider = result["collider"]
		if collider.is_in_group("examinable") or collider.is_in_group("pizarron") or collider.is_in_group("ascensor"):
			var dist = global_position.distance_to(collider.global_position)
			print(">> Distancia al objeto: ", dist, " | límite: ", EXAMINE_DISTANCE)
			if dist <= EXAMINE_DISTANCE:
				found = collider
				print(">> PASÓ el chequeo de distancia")
				
	if found != highlighted_object:
		_clear_highlight()
		if found != null:
			found.highlight()
			highlighted_object = found


func _clear_highlight() -> void:
	if highlighted_object != null:
		highlighted_object.unhighlight()
		highlighted_object = null


func _examine_object(obj: Node) -> void:
	in_dialogue = true
	_clear_highlight()
	dialogue_ui.hide_prompt()
	dialogue_ui.show_dialogue(obj.object_name)
	# Mostramos solo la descripción (sin "Vos:" ni input, no hay LLM acá)
	dialogue_ui.start_npc_response(obj.object_name)
	dialogue_ui.append_npc_chunk(obj.get_description())
	dialogue_ui.finish_npc_response()
	dialogue_ui.set_input_enabled(false)


# ---------- Debug: detección de objetos clicables ----------

func _debug_list_clickables() -> void:
	print(">> ==== Detección de objetos clicables ====")
	var bodies := _collect_layer2_bodies(get_tree().current_scene)
	var clickables := 0
	var scanned := 0
	for body in bodies:
		if body.is_in_group("totem"):
			continue
		scanned += 1
		if _is_clickable(body):
			clickables += 1
			print(">> [CLICABLE] ", body.get_path(), " -> ", _describe_click_event(body))
		else:
			print(">> [no] ", body.get_path(), " (capa 2, sin evento de clic)")
	print(">> Total en capa 2: ", scanned, " | clicables: ", clickables)
	print(">> ======================================")


func _collect_layer2_bodies(root: Node) -> Array:
	var found: Array = []
	if root == null:
		return found
	if root is CollisionObject3D and (root.collision_layer & 2) != 0:
		found.append(root)
	for child in root.get_children():
		found.append_array(_collect_layer2_bodies(child))
	return found


func _is_clickable(node: Node) -> bool:
	for group in CLICKABLE_GROUPS:
		if node.is_in_group(group):
			return true
	return false


func _describe_click_event(node: Node) -> String:
	if node.is_in_group("pizarron"):
		return "interact() -> reconocimiento.tscn"
	if node.is_in_group("ascensor"):
		return "interact() -> " + str(node.get("destino"))
	if node.has_method("get_description"):
		return "examinar() -> " + str(node.get("object_name"))
	return "sin evento"
