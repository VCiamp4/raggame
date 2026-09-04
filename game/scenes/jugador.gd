extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const ChatInterfacesRes = preload("res://data/chat_interfaces.gd")
const FALL_RESET_HEIGHT := -5.0

@onready var anim_player: AnimationPlayer = $Walking/AnimationPlayer
@onready var walking: Node3D = $Walking
@onready var dialogue_ui: CanvasLayer = $DialogueUI
@onready var camera: Camera3D = $Camera3D

const EXAMINE_DISTANCE = 3.0
var highlighted_object: Node = null
var nearby_pizarron: Node = null

var nearby_npc: Node = null
var in_dialogue: bool = false
var spawn_transform: Transform3D
var fade_layer: CanvasLayer
var fade_rect: ColorRect


func _ready() -> void:
	spawn_transform = global_transform
	add_to_group("player")
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.has_signal("player_entered_range"):
			npc.player_entered_range.connect(_on_npc_entered_range)
			npc.player_exited_range.connect(_on_npc_exited_range)
	dialogue_ui.text_submitted.connect(_on_text_submitted)
	dialogue_ui.close_requested.connect(_on_dialogue_close_requested)
	_create_fade_overlay()



func _physics_process(delta: float) -> void:
	if in_dialogue:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	
	# Gravedad
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	# Movimiento
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		walking.rotation.y = atan2(direction.x, direction.z)
		if anim_player and not anim_player.is_playing():
			anim_player.play("mixamo_com")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		if anim_player and anim_player.is_playing():
			anim_player.pause()
	
	move_and_slide()
	if global_position.y < FALL_RESET_HEIGHT:
		_reset_to_spawn()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not in_dialogue:
		if nearby_npc != null:
			_open_dialogue()
		elif highlighted_object != null and highlighted_object.is_in_group("pizarron"):
			highlighted_object.interact()
		elif nearby_pizarron != null:
			nearby_pizarron.interact()
	elif event.is_action_pressed("examine") and not in_dialogue:
		if highlighted_object != null:
			if highlighted_object.is_in_group("pizarron"):
				highlighted_object.interact()
			else:
				_examine_object(highlighted_object)
		elif nearby_pizarron != null:
			nearby_pizarron.interact()
	elif event.is_action_pressed("ui_quit_dialogue") and in_dialogue:
		_close_dialogue()
	
	# Click izquierdo también examina (compatibilidad con mouse)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if highlighted_object != null and not in_dialogue:
				if highlighted_object.is_in_group("pizarron"):
					highlighted_object.interact()   # abre el lineup
				else:
					_examine_object(highlighted_object)   # copa: muestra texto


# ---------- NPCs (con LLM) ----------

func _open_dialogue() -> void:
	in_dialogue = true
	var profile = ChatInterfacesRes.profile_for(nearby_npc.npc_id)
	dialogue_ui.apply_profile(profile)
	dialogue_ui.hide_prompt()
	var display_name = profile.get("display_name", nearby_npc.npc_name)
	if display_name == "":
		display_name = nearby_npc.npc_name
	dialogue_ui.show_dialogue(display_name)
	dialogue_ui.set_input_enabled(true)   # input visible para escribirle al NPC


func _close_dialogue() -> void:
	in_dialogue = false
	dialogue_ui.hide_dialogue()
	if nearby_npc != null:
		dialogue_ui.show_prompt(nearby_npc.npc_name)


func _on_dialogue_close_requested() -> void:
	if in_dialogue:
		_close_dialogue()


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
	_update_prompt()


func _on_npc_exited_range(npc: Node) -> void:
	if nearby_npc == npc:
		nearby_npc = null
		_update_prompt()


# ---------- Objetos examinables (sin LLM) ----------

func _process(_delta: float) -> void:
	if in_dialogue:
		_clear_highlight()
		nearby_pizarron = null
		return
	_check_examinable_under_mouse()
	_update_nearby_pizarron()


func _check_examinable_under_mouse() -> void:
	var ray_origin: Vector3
	var ray_dir: Vector3
	if InputManager.using_controller:
		# Con mando no hay cursor: el rayo sale del centro de la pantalla.
		var center := get_viewport().get_visible_rect().size / 2.0
		ray_origin = camera.project_ray_origin(center)
		ray_dir = camera.project_ray_normal(center)
	else:
		var mouse_pos = get_viewport().get_mouse_position()
		ray_origin = camera.project_ray_origin(mouse_pos)
		ray_dir = camera.project_ray_normal(mouse_pos)
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
		# Detecta tanto examinables (copa) como el pizarrón
		if collider.is_in_group("examinable") or collider.is_in_group("pizarron"):
			var dist = global_position.distance_to(collider.global_position)
			if dist <= EXAMINE_DISTANCE:
				found = collider
	
	if found != highlighted_object:
		_clear_highlight()
		if found != null:
			found.highlight()
			highlighted_object = found
		_update_prompt()


func _update_nearby_pizarron() -> void:
	var previous := nearby_pizarron
	var closest: Node = null
	var best_distance := EXAMINE_DISTANCE
	for node in get_tree().get_nodes_in_group("pizarron"):
		if node is Node3D:
			var distance := global_position.distance_to(node.global_position)
			if distance <= EXAMINE_DISTANCE and distance < best_distance:
				best_distance = distance
				closest = node
	nearby_pizarron = closest
	if previous != nearby_pizarron:
		_update_prompt()


func _clear_highlight() -> void:
	if highlighted_object != null:
		highlighted_object.unhighlight()
		highlighted_object = null
		if not in_dialogue:
			_update_prompt()


func _reset_to_spawn() -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	if fade_layer == null:
		_create_fade_overlay()


func _create_fade_overlay() -> void:
	if fade_layer != null and is_instance_valid(fade_layer):
		return
	fade_layer = CanvasLayer.new()
	fade_layer.layer = 99
	fade_rect = ColorRect.new()
	fade_rect.color = Color.BLACK
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.modulate.a = 1.0
	fade_layer.add_child(fade_rect)
	add_child(fade_layer)
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", 0.0, 0.8)
	tween.finished.connect(func():
		if is_instance_valid(fade_layer):
			fade_layer.queue_free()
		fade_layer = null
		fade_rect = null
	)


# ------------------------------------------------------------
# PROMPT DE INTERACCIÓN
# ------------------------------------------------------------
# Decide qué mostrar en el cartel según el contexto:
#
#     1. Objeto examinable bajo el cursor/mira -> "[F]/(X) Examinar X"
#     2. NPC cerca                             -> "[E]/(A) Hablar con X"
#     3. Nada cerca                            -> oculta el cartel
# ------------------------------------------------------------

func _update_prompt() -> void:
	if in_dialogue:
		return
	if highlighted_object != null:
		var label := _interaction_label(highlighted_object)
		var action_name := "examine"
		var verb := "Examinar"
		if highlighted_object.is_in_group("pizarron"):
			action_name = "interact"
			verb = "Abrir"
		dialogue_ui.show_prompt(label, verb, action_name)
	elif nearby_pizarron != null:
		var board_label := _interaction_label(nearby_pizarron)
		dialogue_ui.show_prompt(board_label, "Abrir", "interact")
	elif nearby_npc != null:
		var profile = ChatInterfacesRes.profile_for(nearby_npc.npc_id)
		var display_name = profile.get("display_name", nearby_npc.npc_name)
		if display_name == "":
			display_name = nearby_npc.npc_name
		dialogue_ui.apply_profile(profile)
		dialogue_ui.show_prompt(display_name)
	else:
		dialogue_ui.hide_prompt()


func _examine_object(obj: Node) -> void:
	in_dialogue = true
	_clear_highlight()
	dialogue_ui.hide_prompt()
	var label := _interaction_label(obj)
	dialogue_ui.show_dialogue(label)
	# Mostramos solo la descripción (sin "Vos:" ni input, no hay LLM acá)
	dialogue_ui.start_npc_response(label)
	dialogue_ui.append_npc_chunk(obj.get_description())
	dialogue_ui.finish_npc_response()
	dialogue_ui.set_input_enabled(false)


func _interaction_label(target: Node) -> String:
	if target == null:
		return ""
	if target.has_method("get_interaction_label"):
		var custom = target.get_interaction_label()
		if typeof(custom) == TYPE_STRING and custom != "":
			return custom
	var prop_value = target.get("object_name")
	if typeof(prop_value) == TYPE_STRING and prop_value != "":
		return prop_value
	return target.name
