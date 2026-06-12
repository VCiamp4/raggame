extends CharacterBody3D

const SPEED = 3.0
const JUMP_VELOCITY = 4.5

@onready var anim_player: AnimationPlayer = $Walking/AnimationPlayer
@onready var dialogue_ui: CanvasLayer = $DialogueUI

var nearby_npc: Node = null
var in_dialogue: bool = false


func _ready() -> void:
	add_to_group("player")
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.has_signal("player_entered_range"):
			npc.player_entered_range.connect(_on_npc_entered_range)
			npc.player_exited_range.connect(_on_npc_exited_range)
	# Escuchar cuando el jugador escribe algo
	dialogue_ui.text_submitted.connect(_on_text_submitted)


func _physics_process(delta: float) -> void:
	if in_dialogue:
		# No procesar movimiento mientras está abierto el diálogo
		velocity = Vector3.ZERO
		move_and_slide()
		return
	
	# Gravedad
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	# Movimiento
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
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


func _open_dialogue() -> void:
	in_dialogue = true
	dialogue_ui.hide_prompt()
	dialogue_ui.show_dialogue(nearby_npc.npc_name)


func _close_dialogue() -> void:
	in_dialogue = false
	dialogue_ui.hide_dialogue()
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
