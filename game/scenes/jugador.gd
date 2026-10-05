extends CharacterBody3D

const SPEED = 3.0
const JUMP_VELOCITY = 4.5
const TURN_SPEED = 10.0
const FALL_DISTANCE = 1.0
const CAMERA_OFFSET = Vector3(0.0, 1.8, 3.2)
const CAMERA_LOOK_HEIGHT = 0.9
const MAPA_SCENE = "res://scenes/mapa_menu.tscn"

const HintCatalogRes = preload("res://data/hints/hints.gd")
const HINT_TOOLTIP_DEFAULT := "Mostrar una pista basada en tu progreso"

@onready var anim_player: AnimationPlayer = $Walking/AnimationPlayer
@onready var model: Node3D = $Walking
@onready var dialogue_ui: CanvasLayer = $DialogueUI
@onready var camera: Camera3D = $Camera3D

@export var retrato_jugador: Texture2D

const EXAMINE_DISTANCE = 6.0
const INTERACT_DISTANCE = 2.0
const TOTEM_DISTANCE = 3.0
const CLICKABLE_GROUPS := ["examinable", "pizarron", "ascensor"]
const INSPECT_DISTANCE = 4.0
var highlighted_object: Node = null
var nearby_clickable: Node = null
var nearby_totem: Node = null

var nearby_npc: Node = null
var in_dialogue: bool = false
var inspecting: bool = false
var inspecting_object: Node = null
var model_base_yaw: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO

var hint_layer: CanvasLayer
var hint_button: Button
var hint_cooldown_timer: Timer
var hint_cooldown_seconds: float = 0.0
var hint_uses_limit: int = -1
var hint_remaining_uses: int = -1


func _ready() -> void:
	add_to_group("player")
	spawn_position = global_position
	camera.top_level = true
	model_base_yaw = model.rotation.y
	# Los NPC pueden declararse después del jugador en la escena, por lo que
	# sus _ready (y su entrada al grupo "npc") pueden correr más tarde.
	_connect_npcs.call_deferred()
	dialogue_ui.text_submitted.connect(_on_text_submitted)
	dialogue_ui.close_requested.connect(_on_dialogue_close_requested)
	_create_hint_button()
	_configure_hint_rules()
	# Diferido: los grupos se pueblan en el _ready de cada objeto, que puede
	# correr después que el del jugador (p. ej. el pizarron en comisaria.tscn).
	_debug_list_clickables.call_deferred()


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
	if event.is_action_pressed("interact"):
		# Cerrar inspección abierta con [E].
		if inspecting:
			_close_inspection()
			return
		if not in_dialogue:
			if nearby_npc != null:
				_open_dialogue()
			elif nearby_clickable != null:
				_trigger_clickable(nearby_clickable)
			elif nearby_totem != null:
				_use_totem()
	elif event.is_action_pressed("ui_cancel"):
		if inspecting:
			_close_inspection()
		elif in_dialogue:
			_close_dialogue()
		elif nearby_totem != null:
			_use_totem()
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if inspecting:
				_close_inspection()
			elif highlighted_object != null and not in_dialogue:
				if highlighted_object.is_in_group("pizarron"):
					highlighted_object.interact()
				elif highlighted_object.is_in_group("ascensor"):
					highlighted_object.interact()   
				else:
					_examine_object(highlighted_object)   # copa: muestra texto


# ---------- NPCs (con LLM) ----------

func _connect_npcs() -> void:
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.has_signal("player_entered_range"):
			if not npc.player_entered_range.is_connected(_on_npc_entered_range):
				npc.player_entered_range.connect(_on_npc_entered_range)
			if not npc.player_exited_range.is_connected(_on_npc_exited_range):
				npc.player_exited_range.connect(_on_npc_exited_range)


func _open_dialogue() -> void:
	in_dialogue = true
	dialogue_ui.hide_prompt()
	dialogue_ui.show_dialogue(nearby_npc.npc_name, nearby_npc.npc_id)
	dialogue_ui.set_input_enabled(true)
	dialogue_ui.mostrar_modelos($Walking.scene_file_path, nearby_npc.get_model_scene_path())  # input visible para escribirle al NPC


func _close_dialogue() -> void:
	in_dialogue = false
	dialogue_ui.hide_dialogue()
	dialogue_ui.ocultar_retratos()
	if nearby_npc != null:
		dialogue_ui.show_prompt(nearby_npc.npc_name)


func _on_text_submitted(text: String) -> void:
	if nearby_npc == null:
		return

	# Chequear si el input activa algún evento/pista
	EventManager.check_input(text)

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
	_update_hint_cooldown_display()
	_update_camera()
	if in_dialogue or inspecting:
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
	var closest_dist := INF
	for totem in get_tree().get_nodes_in_group("totem"):
		var reach := TOTEM_DISTANCE
		if totem.has_method("get_interact_distance"):
			reach = totem.get_interact_distance()
		var dist := global_position.distance_to(_clickable_anchor(totem))
		if dist <= reach and dist < closest_dist:
			closest_dist = dist
			closest = totem
	nearby_totem = closest


func _use_totem() -> void:
	get_tree().change_scene_to_file(MAPA_SCENE)


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
	if obj.has_method("get_object_name"):
		var custom = obj.get_object_name()
		if custom != null and str(custom) != "":
			return str(custom)
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
	if obj == null:
		return
	inspecting = true
	inspecting_object = obj
	_clear_highlight()
	dialogue_ui.hide_prompt()

	var title := _inspect_display_name(obj)
	var description := _inspect_description(obj)

	dialogue_ui.clear_history()
	dialogue_ui.show_dialogue(title)
	# Mostramos solo la descripción (sin "Vos:" ni input, no hay LLM acá)
	dialogue_ui.start_npc_response(title)
	dialogue_ui.append_npc_chunk(description)
	dialogue_ui.finish_npc_response()
	dialogue_ui.set_input_enabled(false)

	# Disparar la pista asociada (opcional, una sola vez).
	# Un inspectable sin clue_id simplemente no dispara nada.
	var clue_id := _inspect_clue_id(obj)
	if clue_id != "":
		EventManager.activate_event(clue_id)
		NotificationManager.show_clue_notification(clue_id)


func _close_inspection() -> void:
	inspecting = false
	inspecting_object = null
	dialogue_ui.hide_dialogue()


func _on_dialogue_close_requested() -> void:
	if inspecting:
		_close_inspection()
	elif in_dialogue:
		_close_dialogue()


func _inspect_display_name(obj: Node) -> String:
	if obj.has_method("get_object_name"):
		return obj.get_object_name()
	var display = obj.get("object_name")
	if display != null and str(display) != "":
		return str(display)
	return obj.name


func _inspect_description(obj: Node) -> String:
	if obj.has_method("get_description"):
		return obj.get_description()
	return ""


func _inspect_clue_id(obj: Node) -> String:
	if obj.has_method("get_clue_id"):
		var clue = obj.get_clue_id()
		if clue != null:
			return str(clue)
	return ""


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


# ---------- Pistas ----------

func _create_hint_button() -> void:
	if hint_layer != null and is_instance_valid(hint_layer):
		return
	hint_layer = CanvasLayer.new()
	hint_layer.layer = 90
	add_child(hint_layer)

	hint_button = Button.new()
	hint_button.text = "Pistas"
	hint_button.anchor_left = 1
	hint_button.anchor_right = 1
	hint_button.anchor_top = 0.15
	hint_button.anchor_bottom = 0.15
	hint_button.offset_left = -180
	hint_button.offset_right = -40
	hint_button.offset_top = -30
	hint_button.offset_bottom = 30
	hint_button.focus_mode = Control.FOCUS_NONE
	hint_button.tooltip_text = HINT_TOOLTIP_DEFAULT
	hint_button.theme = null
	hint_button.pressed.connect(_on_hint_button_pressed)
	hint_layer.add_child(hint_button)


func _on_hint_button_pressed() -> void:
	if not _hint_action_allowed():
		return
	var hint_text := _current_hint_text()
	NotificationManager.show_message(hint_text)
	_register_hint_consumption()


func _current_hint_text() -> String:
	var history := EventManager.get_event_history()
	for i in range(history.size() - 1, -1, -1):
		var event_id: String = str(history[i])
		var hint_text := HintCatalogRes.hint_for_event(event_id)
		if hint_text != "":
			return hint_text
	return HintCatalogRes.default_hint()


func _configure_hint_rules() -> void:
	hint_cooldown_seconds = 0.0
	hint_uses_limit = -1
	hint_remaining_uses = -1
	var difficulty := Global.current_difficulty()
	var difficulty_id := str(difficulty.get("id", "standard"))
	match difficulty_id:
		"standard":
			hint_cooldown_seconds = 15.0
		"hardcore":
			hint_uses_limit = 3
		_:
			pass
	if hint_uses_limit > 0:
		var spent := int(clamp(Global.hint_uses_spent, 0, hint_uses_limit))
		hint_remaining_uses = max(hint_uses_limit - spent, 0)
	_ensure_hint_timer()
	_apply_existing_hint_state()
	_refresh_hint_button_state()


func _ensure_hint_timer() -> void:
	if hint_cooldown_timer != null and is_instance_valid(hint_cooldown_timer):
		hint_cooldown_timer.stop()
		return
	hint_cooldown_timer = Timer.new()
	hint_cooldown_timer.one_shot = true
	hint_cooldown_timer.timeout.connect(_on_hint_cooldown_finished)
	add_child(hint_cooldown_timer)


func _apply_existing_hint_state() -> void:
	if hint_cooldown_seconds <= 0.0:
		return
	var ready_time := Global.hint_cooldown_ready_time
	if ready_time <= 0.0:
		return
	var now := Time.get_unix_time_from_system()
	var remaining := ready_time - now
	if remaining > 0.1:
		_begin_hint_cooldown(remaining)
	else:
		Global.hint_cooldown_ready_time = 0.0


func _update_hint_cooldown_display() -> void:
	if hint_cooldown_timer == null:
		return
	if hint_cooldown_timer.is_stopped():
		return
	_refresh_hint_button_state()


func _refresh_hint_button_state() -> void:
	if hint_button == null:
		return
	var button_text := "Pistas"
	var tooltip := HINT_TOOLTIP_DEFAULT
	var disabled := false
	if hint_uses_limit > 0:
		var remaining: int = max(hint_remaining_uses, 0)
		button_text = "Pistas (%d)" % remaining
		tooltip = "Pistas limitadas en esta dificultad."
		if remaining <= 0:
			disabled = true
			tooltip = "Ya usaste todas las pistas disponibles en esta dificultad."
	if hint_cooldown_timer != null and not hint_cooldown_timer.is_stopped():
		disabled = true
		var seconds_left := int(ceil(hint_cooldown_timer.time_left))
		if seconds_left < 1:
			seconds_left = 1
		button_text = "Pistas (%ds)" % seconds_left
		tooltip = "Podés volver a pedir una pista en %d s." % seconds_left
	hint_button.text = button_text
	hint_button.disabled = disabled
	hint_button.tooltip_text = tooltip


func _hint_action_allowed() -> bool:
	if hint_uses_limit > 0 and hint_remaining_uses <= 0:
		return false
	if hint_cooldown_timer != null and not hint_cooldown_timer.is_stopped():
		return false
	return true


func _register_hint_consumption() -> void:
	if hint_uses_limit > 0:
		Global.hint_uses_spent = min(Global.hint_uses_spent + 1, hint_uses_limit)
		hint_remaining_uses = max(hint_uses_limit - Global.hint_uses_spent, 0)
	if hint_cooldown_seconds > 0.0:
		var now := Time.get_unix_time_from_system()
		Global.hint_cooldown_ready_time = now + hint_cooldown_seconds
		_begin_hint_cooldown()
	_refresh_hint_button_state()


func _begin_hint_cooldown(duration: float = -1.0) -> void:
	if hint_cooldown_timer == null:
		return
	var wait_time := hint_cooldown_seconds
	if duration > 0.0:
		wait_time = duration
	if wait_time <= 0.0:
		return
	hint_cooldown_timer.start(wait_time)
	_refresh_hint_button_state()


func _on_hint_cooldown_finished() -> void:
	_refresh_hint_button_state()
