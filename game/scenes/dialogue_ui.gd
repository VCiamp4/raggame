extends CanvasLayer

var panel: ColorRect
var name_label: Label
var scroll_container: ScrollContainer
var chat_list: VBoxContainer
var input_field: LineEdit
var prompt_label: Label
var fake_blur: ColorRect
var retrato_jugador: TextureRect
var retrato_npc: TextureRect
var viewport_jugador: SubViewport
var viewport_npc: SubViewport
var close_button: Button

signal text_submitted(text: String)
signal close_requested

var current_npc_response: String = ""
# Cada NPC tiene su conversación como una lista de {speaker, text, player}.
var transcripts := {}
var current_npc := ""
var responding_npc := ""  # a quién pertenece la respuesta que se está recibiendo
var current_bubble_text: RichTextLabel = null  # respuesta NPC en curso
var current_bubble_name := ""

# Estilo de las burbujas de chat.
const PLAYER_BG := Color("26476b")
const NPC_BG := Color("2e2e33")
const SYSTEM_BG := Color("26262c")
const PLAYER_TEXT := Color("e6eef7")
const NPC_TEXT := Color("e8e2d2")
const NAME_PLAYER := Color("9ad0ff")
const NAME_NPC := Color("ffd86b")
const WAIT_COLOR := Color("9a9a9a")
const BUBBLE_FONT := 22
const BUBBLE_MAX_FRACTION := 0.72

# Línea de espera: si el modelo tarda en emitir el primer fragmento, se muestra
# una frase temática del personaje (sin datos del caso) y se quita al llegar.
const WAIT_DELAY_MS := 350
const WAIT_LINES := {
	"Juan": [
		"(se toma su tiempo...)",
		"(se cruza de brazos...)",
		"(decide si vale la pena responderte...)",
	],
	"Esteban": [
		"(duda un momento...)",
		"(ordena sus ideas...)",
		"(elige las palabras con cuidado...)",
	],
	"Pablo": [
		"(te estudia en silencio...)",
		"(mide cada palabra...)",
		"(no aparta la vista de vos...)",
	],
	"La criada": [
		"(se retuerce las manos...)",
		"(baja la mirada...)",
		"(se seca las manos en el delantal...)",
	],
	"El portero": [
		"(lo piensa un momento...)",
		"(repasa los horarios...)",
		"(se rasca la barbilla...)",
	],
	"La forense": [
		"(revisa sus notas...)",
		"(ordena los datos...)",
		"(busca la palabra precisa...)",
	],
}
const WAIT_LINES_DEFAULT := [
	"(lo piensa un momento...)",
	"(tarda en responder...)",
	"(se toma un instante...)",
]
var _wait_token := 0
var _waiting_active := false
var _pending_line := ""
var _last_wait := {}

const BackendError = preload("res://ui/backend_error.gd")
const ERROR_COLOR := "#ff8a80"
const CONTACT_COLOR := "#a0a0a0"
const BEAT_COLOR := "#c9b98f"


func _ready() -> void:
	# Compartimos los transcripts desde el autoload para conservarlos entre escenas.
	transcripts = Global.chat_transcripts
	# Panel de fondo del diálogo
	panel = ColorRect.new()
	panel.color = Color(0, 0, 0, 0.6)
	panel.anchor_left = 0
	panel.anchor_right = 1
	panel.anchor_top = 0.55
	panel.anchor_bottom = 1
	panel.visible = false
	add_child(panel)
	
	# Nombre del NPC arriba
	name_label = Label.new()
	name_label.anchor_left = 0
	name_label.anchor_right = 1
	name_label.offset_left = 20
	name_label.offset_top = 10
	name_label.offset_right = -60
	name_label.offset_bottom = 40
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	panel.add_child(name_label)

	# Botón de cierre "X" (cierra inspección o diálogo)
	close_button = Button.new()
	close_button.text = "X"
	close_button.anchor_left = 1
	close_button.anchor_right = 1
	close_button.offset_left = -45
	close_button.offset_right = -12
	close_button.offset_top = 8
	close_button.offset_bottom = 40
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "Cerrar"
	close_button.add_theme_font_size_override("font_size", 20)
	close_button.pressed.connect(_on_close_pressed)
	panel.add_child(close_button)

	# Historial scrolleable
	scroll_container = ScrollContainer.new()
	scroll_container.anchor_left = 0
	scroll_container.anchor_right = 1
	scroll_container.anchor_top = 0
	scroll_container.anchor_bottom = 1
	scroll_container.offset_left = 20
	scroll_container.offset_right = -20
	scroll_container.offset_top = 45
	scroll_container.offset_bottom = -55
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.add_child(scroll_container)
	
	chat_list = VBoxContainer.new()
	chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_list.add_theme_constant_override("separation", 10)
	scroll_container.add_child(chat_list)
	
	# Campo de texto para escribir abajo (barra fija al pie del panel)
	input_field = LineEdit.new()
	input_field.anchor_left = 0
	input_field.anchor_right = 1
	input_field.anchor_top = 1
	input_field.anchor_bottom = 1
	input_field.offset_left = 20
	input_field.offset_right = -20
	input_field.offset_top = -46
	input_field.offset_bottom = -14
	input_field.placeholder_text = "Escribí algo y presioná Enter..."
	input_field.add_theme_font_size_override("font_size", 24)
	input_field.text_submitted.connect(_on_text_submitted)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0, 0, 0, 0.35)
	input_style.content_margin_left = 10
	input_style.content_margin_right = 10
	input_style.corner_radius_top_left = 6
	input_style.corner_radius_top_right = 6
	input_style.corner_radius_bottom_left = 6
	input_style.corner_radius_bottom_right = 6
	input_field.add_theme_stylebox_override("normal", input_style)
	input_field.add_theme_stylebox_override("focus", input_style)
	input_field.add_theme_stylebox_override("read_only", input_style)
	panel.add_child(input_field)
	# El botón de cierre se mueve al frente para asegurar que reciba el clic
	# por encima de cualquier otro control del panel.
	close_button.move_to_front()
	
	# Fake blur: panel oscuro semitransparente que atenúa el fondo
	fake_blur = ColorRect.new()
	fake_blur.color = Color(0, 0, 0, 0.5)
	fake_blur.anchor_left = 0
	fake_blur.anchor_right = 1
	fake_blur.anchor_top = 0
	fake_blur.anchor_bottom = 0.55
	fake_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fake_blur.visible = false
	add_child(fake_blur)
	
	# Retrato del NPC (izquierda): render 3D del modelo, arriba del panel de texto
	retrato_npc = TextureRect.new()
	retrato_npc.anchor_left = 0
	retrato_npc.anchor_right = 0
	retrato_npc.anchor_top = 0.55
	retrato_npc.anchor_bottom = 0.55
	retrato_npc.offset_left = 20
	retrato_npc.offset_right = 210
	retrato_npc.offset_top = -253
	retrato_npc.offset_bottom = 0
	retrato_npc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	retrato_npc.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	retrato_npc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	retrato_npc.visible = false
	add_child(retrato_npc)

	# Retrato del jugador (derecha): render 3D del modelo, arriba del panel de texto
	retrato_jugador = TextureRect.new()
	retrato_jugador.anchor_left = 1
	retrato_jugador.anchor_right = 1
	retrato_jugador.anchor_top = 0.55
	retrato_jugador.anchor_bottom = 0.55
	retrato_jugador.offset_left = -210
	retrato_jugador.offset_right = -20
	retrato_jugador.offset_top = -253
	retrato_jugador.offset_bottom = 0
	retrato_jugador.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	retrato_jugador.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	retrato_jugador.mouse_filter = Control.MOUSE_FILTER_IGNORE
	retrato_jugador.visible = false
	add_child(retrato_jugador)

	# Viewports 3D que renderizan los modelos (en vez de usar una imagen PNG)
	viewport_npc = _create_character_viewport()
	retrato_npc.texture = viewport_npc.get_texture()
	viewport_jugador = _create_character_viewport()
	retrato_jugador.texture = viewport_jugador.get_texture()
	
	# Cartel "[E] Hablar"
	prompt_label = Label.new()
	prompt_label.anchor_left = 0.5
	prompt_label.anchor_right = 0.5
	prompt_label.anchor_top = 0.6
	prompt_label.anchor_bottom = 0.6
	prompt_label.offset_left = -150
	prompt_label.offset_right = 150
	prompt_label.offset_top = -25
	prompt_label.offset_bottom = 25
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 22)
	prompt_label.add_theme_color_override("font_color", Color.WHITE)
	prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	prompt_label.add_theme_constant_override("shadow_offset_x", 2)
	prompt_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(prompt_label)
	prompt_label.hide()


func show_dialogue(npc_name: String) -> void:
	name_label.text = npc_name
	if npc_name != current_npc:
		current_npc = npc_name
		_rebuild_chat(npc_name)
	panel.show()
	input_field.text = ""
	input_field.editable = true
	input_field.grab_focus()


func hide_dialogue() -> void:
	panel.hide()
	input_field.release_focus()


func clear_history() -> void:
	_clear_chat()
	transcripts.erase(current_npc)
	current_npc_response = ""


func is_open() -> bool:
	return panel.visible


func add_player_message(npc_name: String, text: String) -> void:
	var msgs: Array = transcripts.get(current_npc, [])
	msgs.append({"speaker": "Vos", "text": text, "player": true})
	transcripts[current_npc] = msgs
	_make_bubble("Vos", text, true)
	_scroll_to_bottom()


func start_npc_response(npc_name: String) -> void:
	current_npc_response = ""
	responding_npc = current_npc
	current_bubble_name = npc_name
	current_bubble_text = null
	_pending_line = _waiting_line_for(npc_name)
	_waiting_active = false
	_wait_token += 1
	var token := _wait_token
	get_tree().create_timer(WAIT_DELAY_MS / 1000.0).timeout.connect(func(): _show_waiting_line(token))


func append_npc_chunk(text: String) -> void:
	if _waiting_active:
		_remove_waiting()
	current_npc_response += text
	if responding_npc == current_npc:
		if current_bubble_text == null:
			current_bubble_text = _make_bubble(current_bubble_name, "", false)
		current_bubble_text.text = current_npc_response
		current_bubble_text.add_theme_color_override("default_color", NPC_TEXT)
		_resize_bubble(current_bubble_text)
		_scroll_to_bottom()


func finish_npc_response() -> void:
	if _waiting_active:
		_remove_waiting()
	if responding_npc == current_npc and current_bubble_text != null:
		if current_npc_response.strip_edges() == "":
			_remove_last_bubble()
		else:
			var msgs: Array = transcripts.get(responding_npc, [])
			msgs.append({"speaker": current_bubble_name, "text": current_npc_response, "player": false})
			transcripts[responding_npc] = msgs
	current_bubble_text = null


# Muestra una acción narrada (data/beats.gd) antes de la respuesta del NPC.
func show_beat(text: String) -> void:
	_wait_token += 1
	_waiting_active = false
	if current_bubble_text != null:
		_remove_last_bubble()
		current_bubble_text = null
	var beat_color := Color(BEAT_COLOR)
	var msgs: Array = transcripts.get(responding_npc, [])
	msgs.append({"speaker": "", "text": text, "player": false, "system": true, "color": beat_color})
	transcripts[responding_npc] = msgs
	if responding_npc == current_npc:
		_make_bubble("", text, false, true, beat_color)
		_scroll_to_bottom()


# Muestra un error del turno como mensaje del sistema.
func show_error(message: String) -> void:
	if _waiting_active:
		_remove_waiting()
	if current_bubble_text != null:
		_remove_last_bubble()
		current_bubble_text = null
	var err_color := Color(ERROR_COLOR)
	var text := "%s\n%s" % [message, BackendError.CONTACT]
	var msgs: Array = transcripts.get(responding_npc, [])
	msgs.append({"speaker": "Error", "text": text, "player": false, "system": true, "color": err_color})
	transcripts[responding_npc] = msgs
	if responding_npc == current_npc:
		_make_bubble("Error", text, false, true, err_color)
		_scroll_to_bottom()


func _waiting_line_for(npc_name: String) -> String:
	var lines: Array = WAIT_LINES.get(npc_name, WAIT_LINES_DEFAULT)
	if lines.is_empty():
		return "(lo piensa un momento...)"
	if lines.size() == 1:
		return lines[0]
	var idx := randi() % lines.size()
	if idx == int(_last_wait.get(npc_name, -1)):
		idx = (idx + 1) % lines.size()
	_last_wait[npc_name] = idx
	return lines[idx]


# Muestra la línea de espera solo si el primer fragmento todavía no llegó.
func _show_waiting_line(token: int) -> void:
	if token != _wait_token or _waiting_active or current_npc_response != "":
		return
	_waiting_active = true
	if responding_npc == current_npc:
		if current_bubble_text == null:
			current_bubble_text = _make_bubble(current_bubble_name, "", false)
		current_bubble_text.text = _pending_line
		current_bubble_text.add_theme_color_override("default_color", WAIT_COLOR)
		_resize_bubble(current_bubble_text)
		_scroll_to_bottom()


# Quita la línea de espera de la burbuja en curso.
func _remove_waiting() -> void:
	if not _waiting_active:
		return
	_waiting_active = false
	if responding_npc == current_npc and current_bubble_text != null:
		current_bubble_text.text = ""
		current_bubble_text.add_theme_color_override("default_color", NPC_TEXT)


# --- Burbujas de chat ---
func _clear_chat() -> void:
	for child in chat_list.get_children():
		child.queue_free()
	current_bubble_text = null


func _rebuild_chat(npc_name: String) -> void:
	_clear_chat()
	for msg in transcripts.get(npc_name, []):
		_make_bubble(msg["speaker"], msg["text"], msg["player"], msg.get("system", false), msg.get("color", Color(0, 0, 0, 0)))
	_scroll_to_bottom()


func _remove_last_bubble() -> void:
	var n := chat_list.get_child_count()
	if n > 0:
		chat_list.get_child(n - 1).queue_free()


func _make_bubble(speaker: String, text: String, is_player: bool, is_system: bool = false, color: Color = Color(0, 0, 0, 0)) -> RichTextLabel:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_END if is_player else BoxContainer.ALIGNMENT_BEGIN
	chat_list.add_child(row)

	var bubble := PanelContainer.new()
	var style := StyleBoxFlat.new()
	if is_player:
		style.bg_color = PLAYER_BG
	elif is_system:
		style.bg_color = SYSTEM_BG
	else:
		style.bg_color = NPC_BG
	style.set_corner_radius_all(14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", style)
	row.add_child(bubble)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	bubble.add_child(column)

	var speaker_label := Label.new()
	speaker_label.text = speaker
	speaker_label.visible = speaker != ""
	speaker_label.add_theme_font_size_override("font_size", 15)
	var name_color := NAME_NPC
	if is_player:
		name_color = NAME_PLAYER
	elif is_system:
		name_color = color if color.a > 0.0 else Color(CONTACT_COLOR)
	speaker_label.add_theme_color_override("font_color", name_color)
	column.add_child(speaker_label)

	var text_label := RichTextLabel.new()
	text_label.bbcode_enabled = false
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("normal_font_size", BUBBLE_FONT)
	var text_color := NPC_TEXT
	if is_player:
		text_color = PLAYER_TEXT
	elif is_system and color.a > 0.0:
		text_color = color
	text_label.add_theme_color_override("default_color", text_color)
	text_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	text_label.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	text_label.text = text
	column.add_child(text_label)
	_resize_bubble(text_label)
	return text_label


func _resize_bubble(text_label: RichTextLabel) -> void:
	text_label.custom_minimum_size = Vector2(_bubble_width(text_label), 0)


func _bubble_width(text_label: RichTextLabel) -> float:
	var font := text_label.get_theme_font("normal_font")
	var font_size := text_label.get_theme_font_size("normal_font_size")
	var cap := maxf(200.0, scroll_container.size.x * BUBBLE_MAX_FRACTION - 28.0)
	var widest := 0.0
	for line in text_label.text.split("\n"):
		if line.strip_edges() == "":
			continue
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	if widest < 1.0:
		widest = 140.0
	return clampf(widest, 90.0, cap)


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	var scrollbar = scroll_container.get_v_scroll_bar()
	scroll_container.scroll_vertical = int(scrollbar.max_value)


func set_input_enabled(enabled: bool) -> void:
	input_field.editable = enabled
	input_field.visible = enabled
	if enabled:
		input_field.grab_focus()
		
		
const PORTRAIT_YAW := deg_to_rad(20.0)


func mostrar_modelos(jugador_model_path: String, npc_model_path: String) -> void:
	if _show_model_in_viewport(viewport_jugador, jugador_model_path, PORTRAIT_YAW):
		retrato_jugador.visible = true
	if _show_model_in_viewport(viewport_npc, npc_model_path, -PORTRAIT_YAW):
		retrato_npc.visible = true


func ocultar_retratos() -> void:
	fake_blur.visible = false
	retrato_jugador.visible = false
	retrato_npc.visible = false


func _create_character_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 480)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	add_child(vp)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.66, 0.72)
	env.ambient_light_energy = 0.7
	world_env.environment = env
	vp.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.1
	vp.add_child(key)
	key.look_at_from_position(Vector3(2.5, 6.0, 5.0), Vector3(0, 3.0, 0), Vector3.UP)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.5
	fill.light_color = Color(0.7, 0.8, 1.0)
	vp.add_child(fill)
	fill.look_at_from_position(Vector3(-3.0, 2.5, 3.5), Vector3(0, 3.0, 0), Vector3.UP)

	var holder := Node3D.new()
	holder.name = "Holder"
	vp.add_child(holder)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 30.0
	vp.add_child(cam)
	return vp


func _show_model_in_viewport(vp: SubViewport, model_path: String, yaw: float = 0.0) -> bool:
	if vp == null:
		return false
	var holder: Node3D = vp.get_node_or_null("Holder")
	var cam: Camera3D = vp.get_node_or_null("Camera3D")
	if holder == null or cam == null:
		return false
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	if model_path == "":
		return false
	var packed: PackedScene = load(model_path)
	if packed == null:
		return false
	var model: Node = packed.instantiate()
	holder.add_child(model)
	var aabb := _model_aabb(model)
	if aabb.size == Vector3.ZERO:
		return true
	var center := aabb.get_center()
	# Pies al piso y centrado en X/Z.
	model.position -= Vector3(center.x, aabb.position.y, center.z)
	var height := aabb.size.y
	var target_y := height * 0.88
	var frame_height := height * 0.44
	var dist := frame_height / (2.0 * tan(deg_to_rad(cam.fov * 0.5)))
	# Orbitamos la cámara para que el modelo mire un poco hacia adentro.
	cam.position = Vector3(sin(yaw) * dist, target_y, cos(yaw) * dist)
	cam.look_at(Vector3(0, target_y, 0), Vector3.UP)
	return true


func _model_aabb(node: Node) -> AABB:
	var acc: Array = []
	_collect_aabb(node, Transform3D(), acc)
	if acc.is_empty():
		return AABB()
	return acc[0]


func _collect_aabb(node: Node, xform: Transform3D, acc: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var box: AABB = (xform * mi.transform) * mi.mesh.get_aabb()
			if acc.is_empty():
				acc.append(box)
			else:
				acc[0] = (acc[0] as AABB).merge(box)
	for child in node.get_children():
		if child is Node3D:
			_collect_aabb(child, xform * (child as Node3D).transform, acc)





func show_prompt(npc_name: String) -> void:
	prompt_label.text = "[E] Hablar con " + npc_name
	prompt_label.show()


func show_interact_prompt(object_name: String) -> void:
	prompt_label.text = "Aprieta [E] para interactuar con " + object_name
	prompt_label.show()


func show_map_prompt() -> void:
	prompt_label.text = "Aprieta [ESC] para volver al mapa"
	prompt_label.show()


func hide_prompt() -> void:
	prompt_label.hide()


func _on_close_pressed() -> void:
	close_requested.emit()


# El LineEdit en edición se come el primer Esc (solo deja de editar), así que
# lo atajamos antes de que llegue a la GUI. La libreta, si está abierta, lo
# recibe primero y lo marca como manejado.
func _input(event: InputEvent) -> void:
	if panel.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_requested.emit()


func _on_text_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return
	text_submitted.emit(text)
	input_field.text = ""
	input_field.editable = false
