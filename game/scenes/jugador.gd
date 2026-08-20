extends CharacterBody3D

const SPEED = 3.0
const JUMP_VELOCITY = 4.5

@onready var anim_player: AnimationPlayer = $Walking/AnimationPlayer
@onready var walking: Node3D = $Walking
@onready var dialogue_ui: CanvasLayer = $DialogueUI
@onready var camera: Camera3D = $Camera3D

const EXAMINE_DISTANCE = 3.0
var highlighted_object: Node = null

var nearby_npc: Node = null
var in_dialogue: bool = false


func _ready() -> void:
	add_to_group("player")
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.has_signal("player_entered_range"):
			npc.player_entered_range.connect(_on_npc_entered_range)
			npc.player_exited_range.connect(_on_npc_exited_range)
	dialogue_ui.text_submitted.connect(_on_text_submitted)


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not in_dialogue:
		if nearby_npc != null:
			_open_dialogue()
	elif event.is_action_pressed("ui_cancel") and in_dialogue:
		_close_dialogue()
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if highlighted_object != null and not in_dialogue:
				_examine_object(highlighted_object)


# ---------- NPCs (con LLM) ----------

func _open_dialogue() -> void:
	in_dialogue = true
	dialogue_ui.hide_prompt()
	dialogue_ui.show_dialogue(nearby_npc.npc_name)
	dialogue_ui.set_input_enabled(true)   # input visible para escribirle al NPC


func _close_dialogue() -> void:
	in_dialogue = false
	dialogue_ui.hide_dialogue()
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
	if in_dialogue:
		_clear_highlight()
		return
	_check_examinable_under_mouse()


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
		if collider.is_in_group("examinable"):
			var dist = global_position.distance_to(collider.global_position)
			if dist <= EXAMINE_DISTANCE:
				found = collider
	
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
