extends Node3D

@export var npc_id: String = ""
@export var npc_name: String = ""
@export var clothes_texture: Texture2D
@export var session_id: String = "default"
@export var backend_host: String = "127.0.0.1"
@export var backend_port: int = 8000
@export var show_name_label: bool = true

signal player_entered_range(npc: Node)
signal player_exited_range(npc: Node)
signal response_chunk(text: String)
signal response_completed()

@onready var interaction_area: Area3D = $InteractionArea

const BACKEND_PATH = "/dialogue_stream"
const NPC_COLLIDER_RADIUS := 0.35
const NPC_COLLIDER_HEIGHT := 3.2
const LABEL_VERTICAL_OFFSET := 0.4

var http_client: HTTPClient
var is_streaming: bool = false
var name_label: Label3D = null


func _ready() -> void:
	add_to_group("npc")
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	if clothes_texture != null:
		_apply_clothes_texture()
	_add_collision()
	_update_name_label()


# ------------------------------------------------------------
# COLISIÓN FÍSICA DEL NPC
# ------------------------------------------------------------
# Creamos un StaticBody3D con cápsula como hija del NPC.
#
# ¿Por qué StaticBody3D y no CharacterBody3D?
# Porque por ahora los NPCs están quietos. Si más adelante se
# mueven o son empujables, se cambia por AnimatableBody3D.
#
# La cápsula está centrada en su propio origen, así que la subimos
# media altura para que los pies apoyen en y=0, igual que el modelo.
# ------------------------------------------------------------

func _add_collision() -> void:

	var body := StaticBody3D.new()
	body.name = "CollisionBody"

	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"

	var capsule := CapsuleShape3D.new()
	capsule.radius = NPC_COLLIDER_RADIUS
	capsule.height = NPC_COLLIDER_HEIGHT
	shape_node.shape = capsule

	shape_node.position.y = NPC_COLLIDER_HEIGHT / 2.0

	body.add_child(shape_node)
	add_child(body)


func _apply_clothes_texture() -> void:
	var mesh_instance := _find_mesh(self)
	if mesh_instance == null or mesh_instance.mesh == null:
		push_warning("NPC %s: no se encontró mesh para aplicar la textura" % npc_name)
		return
	var mat := mesh_instance.get_active_material(0)
	if mat == null:
		return
	var dup: Material = mat.duplicate()
	if dup is BaseMaterial3D:
		dup.albedo_texture = clothes_texture
	mesh_instance.set_surface_override_material(0, dup)


func _ensure_name_label() -> void:
	if not show_name_label:
		if name_label and is_instance_valid(name_label):
			name_label.queue_free()
		name_label = null
		return
	if name_label and is_instance_valid(name_label):
		return
	name_label = Label3D.new()
	name_label.name = "NameLabel"
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_label.pixel_size = 0.01
	add_child(name_label)


func _update_name_label() -> void:
	_ensure_name_label()
	if name_label == null:
		return
	name_label.text = npc_name
	name_label.position = Vector3(0, NPC_COLLIDER_HEIGHT + LABEL_VERTICAL_OFFSET, 0)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.mesh != null:
		return node
	for child in node.get_children():
		var result := _find_mesh(child)
		if result != null:
			return result
	return null


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_entered_range.emit(self)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_exited_range.emit(self)


func request_response(player_input: String) -> void:
	if is_streaming:
		return
	_start_stream(player_input)


func _start_stream(player_input: String) -> void:
	is_streaming = true
	http_client = HTTPClient.new()
	var err = http_client.connect_to_host(backend_host, backend_port)
	if err != OK:
		_finish_with_error("[Error de conexión con el backend]")
		return
	
	# Esperar conexión
	while http_client.get_status() == HTTPClient.STATUS_CONNECTING or \
		  http_client.get_status() == HTTPClient.STATUS_RESOLVING:
		http_client.poll()
		await get_tree().process_frame
	
	if http_client.get_status() != HTTPClient.STATUS_CONNECTED:
		_finish_with_error("[No se pudo conectar con el backend]")
		return
	
	# Mandar request POST
	var body = JSON.stringify({
		"npc_id": npc_id,
		"player_input": player_input,
		"session_id": session_id
	})
	var headers = [
		"Content-Type: application/json",
		"Content-Length: " + str(body.to_utf8_buffer().size())
	]
	err = http_client.request(HTTPClient.METHOD_POST, BACKEND_PATH, headers, body)
	if err != OK:
		_finish_with_error("[No se pudo enviar el mensaje]")
		return
	
	# Esperar respuesta inicial
	while http_client.get_status() == HTTPClient.STATUS_REQUESTING:
		http_client.poll()
		await get_tree().process_frame
	
	if http_client.get_status() != HTTPClient.STATUS_BODY:
		_finish_with_error("[El backend devolvió una respuesta vacía]")
		return

	var response_code = http_client.get_response_code()
	if response_code < 200 or response_code >= 300:
		var error_body = PackedByteArray()
		while http_client.get_status() == HTTPClient.STATUS_BODY:
			http_client.poll()
			var error_chunk = http_client.read_response_body_chunk()
			if error_chunk.size() > 0:
				error_body.append_array(error_chunk)
			await get_tree().process_frame
		var detail = error_body.get_string_from_utf8()
		var parsed = JSON.parse_string(detail)
		if parsed is Dictionary and parsed.has("detail"):
			detail = str(parsed["detail"])
		_finish_with_error("[Error del backend %d: %s]" % [response_code, detail])
		return
	
	# Leer chunks
	while http_client.get_status() == HTTPClient.STATUS_BODY:
		http_client.poll()
		var chunk = http_client.read_response_body_chunk()
		if chunk.size() > 0:
			var text = chunk.get_string_from_utf8()
			response_chunk.emit(text)
		await get_tree().process_frame
	
	_finish_stream()


func _finish_with_error(message: String) -> void:
	response_chunk.emit(message)
	_finish_stream()


func _finish_stream() -> void:
	is_streaming = false
	if http_client != null:
		http_client.close()
	response_completed.emit()
