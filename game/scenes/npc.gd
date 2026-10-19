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
signal response_beat(text: String)         # acción narrada antes de la respuesta

@onready var interaction_area: Area3D = $InteractionArea

const BackendError = preload("res://ui/backend_error.gd")
const Beats = preload("res://data/beats.gd")

const BACKEND_HOST = "127.0.0.1"
const BACKEND_PORT = 8000
const BACKEND_PATH = "/dialogue_stream"
# Byte que separa la respuesta de los hechos nuevos que el NPC llegó a decir.
const FACT_MARKER := 0x1f

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
	if not is_zero_approx(pose_arms_down):
		_lower_arm(skeleton, "mixamorig_LeftArm", "mixamorig_LeftForeArm", pose_arms_down)
		_lower_arm(skeleton, "mixamorig_RightArm", "mixamorig_RightForeArm", pose_arms_down)
	if not is_zero_approx(pose_spine_turn):
		_rotate_bone(skeleton, "mixamorig_Spine1", Vector3.RIGHT, pose_spine_turn)
	if not is_zero_approx(pose_head_turn):
		_rotate_bone(skeleton, "mixamorig_Head", Vector3.UP, pose_head_turn)
	if not is_zero_approx(pose_hips_turn):
		_rotate_bone(skeleton, "mixamorig_Hips", Vector3.UP, pose_hips_turn)


# Gira el brazo hacia abajo en el plano vertical que lo contiene. El eje se
# calcula en el espacio del esqueleto porque los ejes locales de los huesos
# cambian entre rigs (con un eje fijo, algunos brazos giraban hacia adelante).
func _lower_arm(skeleton: Skeleton3D, arm_name: String, forearm_name: String, degrees: float) -> void:
	var arm := skeleton.find_bone(arm_name)
	var forearm := skeleton.find_bone(forearm_name)
	if arm < 0 or forearm < 0:
		return
	var arm_pose := skeleton.get_bone_global_pose(arm)
	var direction := (skeleton.get_bone_global_pose(forearm).origin - arm_pose.origin).normalized()
	var down := (skeleton.global_basis.inverse() * Vector3.DOWN).normalized()
	var axis := direction.cross(down)
	if axis.is_zero_approx():
		return
	var local_axis := (arm_pose.basis.orthonormalized().inverse() * axis).normalized()
	var pose := skeleton.get_bone_pose_rotation(arm) * Quaternion(local_axis, deg_to_rad(degrees))
	skeleton.set_bone_pose_rotation(arm, pose)


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
	# Si el turno falló, el backend ya deshizo el hecho que había propuesto.
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

	# El backend avisa en un header qué hecho nuevo debería revelar la respuesta.
	# Algunos llegan con una acción antes de la respuesta (data/beats.gd).
	# Mientras tanto la respuesta se sigue acumulando en la conexión.
	var beat := Beats.for_facts(_focus_facts(http_client.get_response_headers_as_dictionary()))
	if beat != "":
		response_beat.emit(beat)
		await get_tree().create_timer(Beats.BEAT_SECONDS).timeout

	# Leer chunks. Después de un marcador llega el mensaje de error del turno
	# o los hechos nuevos que el NPC llegó a decir (nunca los dos).
	var trailer := PackedByteArray()
	while http_client.get_status() == HTTPClient.STATUS_BODY:
		http_client.poll()
		var chunk := http_client.read_response_body_chunk()
		if not trailer.is_empty():
			trailer.append_array(chunk)
		elif chunk.size() > 0:
			var marker := chunk.find(BackendError.STREAM_MARKER)
			if marker < 0:
				marker = chunk.find(FACT_MARKER)
			if marker >= 0:
				trailer = chunk.slice(marker)
				chunk = chunk.slice(0, marker)
			if chunk.size() > 0:
				response_chunk.emit(chunk.get_string_from_utf8())
		await get_tree().process_frame

	var trailer_text := trailer.slice(1).get_string_from_utf8()
	if not trailer.is_empty() and trailer[0] == BackendError.STREAM_MARKER:
		outcome["error"] = trailer_text
	elif http_client.get_status() == HTTPClient.STATUS_CONNECTION_ERROR:
		outcome["error"] = BackendError.INTERRUPTED
	elif not trailer.is_empty():
		outcome["facts"] = trailer_text.split(",", false)
	return outcome


func _focus_facts(headers: Dictionary) -> PackedStringArray:
	for key in headers:
		if str(key).to_lower() == "x-focus-fact":
			return str(headers[key]).split(",", false)
	return PackedStringArray()
