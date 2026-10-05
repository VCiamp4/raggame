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

@onready var interaction_area: Area3D = $InteractionArea

const BACKEND_HOST = "127.0.0.1"
const BACKEND_PORT = 8000
const BACKEND_PATH = "/dialogue_stream"

var http_client: HTTPClient
var is_streaming: bool = false
var last_focus_fact: String = ""


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
	last_focus_fact = ""
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
		response_chunk.emit("[Error en respuesta]")
		response_completed.emit()
		return

	# El backend informa el fact_id del chunk foco del turno en este header.
	var response_headers := http_client.get_response_headers_as_dictionary()
	for header_name in response_headers:
		if str(header_name).to_lower() == "x-focus-fact":
			last_focus_fact = str(response_headers[header_name])
			break

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
