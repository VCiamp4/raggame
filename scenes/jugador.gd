extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

@onready var dialogue_ui: CanvasLayer = $DialogueUI
var nearby_npc: Node = null


func _ready() -> void:
	add_to_group("player")
	# Conectá las señales de cada NPC en la escena.
	for npc in get_tree().get_nodes_in_group("npc"):
		npc.player_entered_range.connect(_on_npc_entered_range)
		npc.player_exited_range.connect(_on_npc_exited_range)


func _physics_process(delta: float) -> void:
	# Gravedad
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Salto
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Movimiento
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()


func _on_npc_entered_range(npc: Node) -> void:
	print(">> Entré al rango de: ", npc.npc_name)
	nearby_npc = npc
	# Acá podrías mostrar un prompt "[E] Hablar con {npc.npc_name}"


func _on_npc_exited_range(npc: Node) -> void:
	if nearby_npc == npc:
		nearby_npc = null
		dialogue_ui.hide_dialogue()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		print(">> Apreté E. nearby_npc = ", nearby_npc)
		if dialogue_ui.is_open():
			print(">> Cerrando diálogo")
			dialogue_ui.hide_dialogue()
		elif nearby_npc != null:
			var response = nearby_npc.get_response()
			print(">> Mostrando: ", response)
			dialogue_ui.show_dialogue(nearby_npc.npc_name, response)
		else:
			print(">> No hay NPC cerca")
