extends CanvasLayer

var panel: ColorRect
var name_label: Label
var scroll_container: ScrollContainer
var history_label: RichTextLabel
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
var _current_npc_id: String = ""


func _ready() -> void:
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
	
	history_label = RichTextLabel.new()
	history_label.bbcode_enabled = true
	history_label.fit_content = true
	history_label.scroll_active = false
	history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_label.add_theme_font_size_override("normal_font_size", 24)
	history_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())  
	history_label.add_theme_stylebox_override("focus", StyleBoxEmpty.new()) 
	scroll_container.add_child(history_label)
	
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


func show_dialogue(npc_name: String, npc_id: String = "") -> void:
	name_label.text = npc_name
	_current_npc_id = npc_id
	panel.show()
	input_field.text = ""
	input_field.editable = true
	input_field.grab_focus()


func hide_dialogue() -> void:
	panel.hide()
	input_field.release_focus()


func clear_history() -> void:
	history_label.text = ""
	current_npc_response = ""


func is_open() -> bool:
	return panel.visible


func add_player_message(npc_name: String, text: String) -> void:
	var line = "[color=#88ccff][b]Vos:[/b][/color] " + text + "\n"
	history_label.append_text(line)
	_scroll_to_bottom()


func start_npc_response(npc_name: String) -> void:
	current_npc_response = ""
	history_label.append_text("[color=#ffe080][b]" + npc_name + ":[/b][/color] ")
	_scroll_to_bottom()


func append_npc_chunk(text: String) -> void:
	current_npc_response += text
	history_label.append_text(text)
	_scroll_to_bottom()


func finish_npc_response() -> void:
	history_label.append_text("\n")
	_scroll_to_bottom()


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


func _on_text_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return
	text_submitted.emit(text)
	input_field.text = ""
	input_field.editable = false
