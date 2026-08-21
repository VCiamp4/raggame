extends Node3D

@export var npc_id: String = "Aldric"
@export var npc_name: String = "Aldric"
@export var clothes_texture: Texture2D

signal player_entered_range(npc: Node)
signal player_exited_range(npc: Node)
signal response_chunk(text: String)       # nuevo: chunk parcial
signal response_completed()                # nuevo: fin de respuesta

@onready var interaction_area: Area3D = $InteractionArea

const BACKEND_HOST = "127.0.0.1"
const BACKEND_PORT = 8000
const BACKEND_PATH = "/dialogue_stream"

var http_client: HTTPClient
var is_streaming: bool = false


func _ready() -> void:
	add_to_group("npc")
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	if clothes_texture != null:
		_apply_clothes_texture()


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
	http_client = HTTPClient.new()
	var err = http_client.connect_to_host(BACKEND_HOST, BACKEND_PORT)
	if err != OK:
		response_chunk.emit("[Error de conexión]")
		response_completed.emit()
		return
	
	# Esperar conexión
	while http_client.get_status() == HTTPClient.STATUS_CONNECTING or \
		  http_client.get_status() == HTTPClient.STATUS_RESOLVING:
		http_client.poll()
		await get_tree().process_frame
	
	if http_client.get_status() != HTTPClient.STATUS_CONNECTED:
		response_chunk.emit("[No se pudo conectar]")
		response_completed.emit()
		return
	
	# Mandar request POST
	var body = JSON.stringify({
		"npc_id": npc_id,
		"player_input": player_input,
		"session_id": "default"
	})
	var headers = [
		"Content-Type: application/json",
		"Content-Length: " + str(body.to_utf8_buffer().size())
	]
	http_client.request(HTTPClient.METHOD_POST, BACKEND_PATH, headers, body)
	
	# Esperar respuesta inicial
	while http_client.get_status() == HTTPClient.STATUS_REQUESTING:
		http_client.poll()
		await get_tree().process_frame
	
	if http_client.get_status() != HTTPClient.STATUS_BODY:
		response_chunk.emit("[Error en respuesta]")
		response_completed.emit()
		return
	
	# Leer chunks
	is_streaming = true
	while http_client.get_status() == HTTPClient.STATUS_BODY:
		http_client.poll()
		var chunk = http_client.read_response_body_chunk()
		if chunk.size() > 0:
			var text = chunk.get_string_from_utf8()
			response_chunk.emit(text)
		await get_tree().process_frame
	
	is_streaming = false
	response_completed.emit()
	http_client.close()
