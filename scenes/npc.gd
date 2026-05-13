extends Node3D

@export var npc_id: String = "c3-p0"
@export var npc_name: String = "c3-p0"

signal player_entered_range(npc: Node)
signal player_exited_range(npc: Node)
signal response_received(text: String)

@onready var interaction_area: Area3D = $InteractionArea

const BACKEND_URL = "http://localhost:8000/dialogue"
var http_request: HTTPRequest


func _ready() -> void:
	add_to_group("npc")
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	
	# Creamos un HTTPRequest hijo para hacer las llamadas al backend.
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_entered_range.emit(self)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_exited_range.emit(self)


func request_response(player_input: String) -> void:
	var body = {
		"npc_id": npc_id,
		"player_input": player_input,
		"session_id": "default"
	}
	var headers = ["Content-Type: application/json"]
	var json_body = JSON.stringify(body)
	var err = http_request.request(BACKEND_URL, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		response_received.emit("[Error al contactar al servidor]")


func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		response_received.emit("[Error " + str(response_code) + "]")
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null or not json.has("response"):
		response_received.emit("[Respuesta inválida]")
		return
	
	response_received.emit(json["response"])
