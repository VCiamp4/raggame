extends Node3D

@export var npc_id: String = ""
@export var npc_name: String = ""
@export var session_id: String = "default"
@export var backend_host: String = "127.0.0.1"
@export var backend_port: int = 8000

signal player_entered_range(npc: Node)
signal player_exited_range(npc: Node)
signal response_chunk(text: String)
signal response_completed()

@onready var interaction_area: Area3D = $InteractionArea

const BACKEND_PATH = "/dialogue_stream"

var http_client: HTTPClient
var is_streaming: bool = false


func _ready() -> void:
	add_to_group("npc")
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)


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
