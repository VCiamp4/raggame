extends Node3D

@export var npc_id: String = "Aldric"
@export var npc_name: String = "Aldric"

@export var retrato: Texture2D

# Pose: rota huesos del esqueleto Mixamo para evitar la pose rígida (T/A-pose).
# Los valores son grados; 0 deja el hueso como está.
@export var pose_arms_down: float = 0.0
@export var pose_spine_turn: float = 0.0
@export var pose_head_turn: float = 0.0
@export var pose_hips_turn: float = 0.0

signal player_entered_range(npc: Node)
signal player_exited_range(npc: Node)
signal response_chunk(text: String)       # nuevo: chunk parcial
signal response_completed()                # nuevo: fin de respuesta
signal response_failed(message: String)    # el turno falló; message es para el jugador

@onready var interaction_area: Area3D = $InteractionArea

const BackendError = preload("res://ui/backend_error.gd")

const BACKEND_HOST = "127.0.0.1"
const BACKEND_PORT = 8000
const BACKEND_PATH = "/dialogue_stream"

var http_client: HTTPClient
var is_streaming: bool = false


func _ready() -> void:
	add_to_group("npc")
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	_apply_pose()


func _apply_pose() -> void:
	var skeleton := _find_skeleton(self)
	if skeleton == null:
		return
	# Ejes locales típicos de un rig Mixamo: bajar los brazos se logra
	# rotando alrededor de Z, con signos opuestos en cada brazo.
	if not is_zero_approx(pose_arms_down):
		_rotate_bone(skeleton, "mixamorig_LeftArm", Vector3.BACK, pose_arms_down)
		_rotate_bone(skeleton, "mixamorig_RightArm", Vector3.BACK, -pose_arms_down)
		_rotate_bone(skeleton, "mixamorig_LeftForeArm", Vector3.BACK, pose_arms_down * 0.35)
		_rotate_bone(skeleton, "mixamorig_RightForeArm", Vector3.BACK, -pose_arms_down * 0.35)
	if not is_zero_approx(pose_spine_turn):
		_rotate_bone(skeleton, "mixamorig_Spine1", Vector3.RIGHT, pose_spine_turn)
	if not is_zero_approx(pose_head_turn):
		_rotate_bone(skeleton, "mixamorig_Head", Vector3.UP, pose_head_turn)
	if not is_zero_approx(pose_hips_turn):
		_rotate_bone(skeleton, "mixamorig_Hips", Vector3.UP, pose_hips_turn)


func _rotate_bone(skeleton: Skeleton3D, bone_name: String, axis: Vector3, degrees: float) -> void:
	var idx := skeleton.find_bone(bone_name)
	if idx < 0:
		return
	var pose := skeleton.get_bone_pose_rotation(idx)
	pose = pose * Quaternion(axis, deg_to_rad(degrees))
	skeleton.set_bone_pose_rotation(idx, pose)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
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

func get_retrato() -> Texture2D:
	return retrato


func get_model_scene_path() -> String:
	var model := _find_instanced_model(self)
	if model != null:
		return model.scene_file_path
	return ""


func _find_instanced_model(node: Node) -> Node3D:
	for child in node.get_children():
		if child is Node3D and child.scene_file_path != "":
			return child
		var found := _find_instanced_model(child)
		if found != null:
			return found
	return null


func _start_stream(player_input: String) -> void:
	is_streaming = true
	var outcome: Dictionary = await _stream(player_input)
	is_streaming = false
	if outcome["error"] != "":
		response_failed.emit(outcome["error"])
	response_completed.emit()
	http_client.close()
	# Si el turno falló, el backend ya deshizo el hecho que había registrado.
	if outcome["error"] == "":
		for fact_id in outcome["facts"]:
			Global.fact_discovered.emit(fact_id)


# Hace el pedido y emite los fragmentos del NPC. Devuelve {"error", "facts"}:
# "error" es el mensaje para el jugador, vacío si la respuesta terminó bien.
func _stream(player_input: String) -> Dictionary:
	var outcome := {"error": "", "facts": PackedStringArray()}
	http_client = HTTPClient.new()
	if http_client.connect_to_host(BACKEND_HOST, BACKEND_PORT) != OK:
		outcome["error"] = BackendError.OFFLINE
		return outcome

	# Esperar conexión
	while http_client.get_status() == HTTPClient.STATUS_CONNECTING or \
		  http_client.get_status() == HTTPClient.STATUS_RESOLVING:
		http_client.poll()
		await get_tree().process_frame

	if http_client.get_status() != HTTPClient.STATUS_CONNECTED:
		outcome["error"] = BackendError.OFFLINE
		return outcome

	# Mandar request POST
	var body = JSON.stringify({
		"npc_id": npc_id,
		"player_input": player_input,
		"session_id": Global.session_id
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
		outcome["error"] = BackendError.OFFLINE
		return outcome

	# Solo un NPC inexistente llega con código de error; el resto, tras el marcador.
	var code := http_client.get_response_code()
	if code != 200:
		var error_body := PackedByteArray()
		while http_client.get_status() == HTTPClient.STATUS_BODY:
			http_client.poll()
			error_body.append_array(http_client.read_response_body_chunk())
			await get_tree().process_frame
		outcome["error"] = BackendError.from_body(code, error_body.get_string_from_utf8())
		return outcome

	# El backend avisa en un header qué hecho nuevo descubrió esta pregunta.
	outcome["facts"] = _new_facts(http_client.get_response_headers_as_dictionary())

	# Leer chunks. Si el turno falla, el mensaje llega después del marcador.
	var stream_error := PackedByteArray()
	var failed_midway := false
	while http_client.get_status() == HTTPClient.STATUS_BODY:
		http_client.poll()
		var chunk := http_client.read_response_body_chunk()
		if failed_midway:
			stream_error.append_array(chunk)
		elif chunk.size() > 0:
			var marker := chunk.find(BackendError.STREAM_MARKER)
			if marker >= 0:
				failed_midway = true
				stream_error.append_array(chunk.slice(marker + 1))
				chunk = chunk.slice(0, marker)
			if chunk.size() > 0:
				response_chunk.emit(chunk.get_string_from_utf8())
		await get_tree().process_frame

	if failed_midway:
		outcome["error"] = stream_error.get_string_from_utf8()
	elif http_client.get_status() == HTTPClient.STATUS_CONNECTION_ERROR:
		outcome["error"] = BackendError.INTERRUPTED
	return outcome


func _new_facts(headers: Dictionary) -> PackedStringArray:
	for key in headers:
		if str(key).to_lower() == "x-new-fact":
			return str(headers[key]).split(",", false)
	return PackedStringArray()
