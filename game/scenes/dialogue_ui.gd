extends CanvasLayer

const EventCatalogRes = preload("res://data/events/events.gd")

var panel: ColorRect
var name_label: Label
var keyword_panel: VBoxContainer
var keyword_labels: Array = []
var scroll_container: ScrollContainer
var history_label: RichTextLabel
var input_field: LineEdit
var prompt_label: Label
var fake_blur: ColorRect
var retrato_jugador: TextureRect
var retrato_npc: TextureRect
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

	# Palabras clave del NPC actual (ayuda para el input exacto)
	keyword_panel = VBoxContainer.new()
	keyword_panel.anchor_left = 0
	keyword_panel.anchor_right = 1
	keyword_panel.offset_left = 20
	keyword_panel.offset_right = -20
	keyword_panel.offset_top = 44
	keyword_panel.offset_bottom = 44
	keyword_panel.add_theme_constant_override("separation", 2)
	panel.add_child(keyword_panel)
	
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
	
	# Retrato del jugador (izquierda)
	retrato_jugador = TextureRect.new()
	retrato_jugador.anchor_left = 0
	retrato_jugador.anchor_bottom = 1
	retrato_jugador.offset_left = -80
	retrato_jugador.offset_top = -215
	retrato_jugador.offset_bottom = -180
	retrato_jugador.offset_right = 320
	retrato_jugador.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	retrato_jugador.mouse_filter = Control.MOUSE_FILTER_IGNORE
	retrato_jugador.visible = false
	add_child(retrato_jugador)
	
	# Retrato del NPC (derecha)
	retrato_npc = TextureRect.new()
	retrato_npc.anchor_left = 1
	retrato_npc.anchor_right = 1
	retrato_npc.anchor_bottom = 1
	retrato_npc.offset_left = -320
	retrato_npc.offset_right = -20
	retrato_npc.offset_top = -175
	retrato_npc.offset_bottom = -180
	retrato_npc.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	retrato_npc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	retrato_npc.visible = false
	add_child(retrato_npc)
	
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
	_update_keywords()


func hide_dialogue() -> void:
	panel.hide()
	input_field.release_focus()
	_clear_keywords()


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
		
		
func mostrar_retratos(tex_jugador: Texture2D, tex_npc: Texture2D) -> void:
	#fake_blur.visible = true
	if tex_jugador:
		retrato_jugador.texture = tex_jugador
		retrato_jugador.visible = true
	if tex_npc:
		retrato_npc.texture = tex_npc
		retrato_npc.visible = true


func ocultar_retratos() -> void:
	fake_blur.visible = false
	retrato_jugador.visible = false
	retrato_npc.visible = false


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


func _update_keywords() -> void:
	_clear_keywords()
	if _current_npc_id == "":
		return
	var lookup_id := _current_npc_id.capitalize()
	var clues: Array = EventCatalogRes.clues_for_character(lookup_id)
	for clue in clues:
		var keywords: Array = clue.get("keywords", [])
		if keywords.is_empty():
			continue
		var label := Label.new()
		label.text = "Keywords: %s" % ", ".join(keywords)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
		keyword_panel.add_child(label)
		keyword_labels.append(label)
	if keyword_panel != null:
		keyword_panel.offset_bottom = keyword_panel.offset_top + keyword_panel.get_combined_minimum_size().y
	if scroll_container != null:
		scroll_container.offset_top = keyword_panel.offset_bottom + 6


func _clear_keywords() -> void:
	for label in keyword_labels:
		if is_instance_valid(label):
			label.queue_free()
	keyword_labels.clear()
	if keyword_panel != null:
		keyword_panel.offset_bottom = keyword_panel.offset_top
	if scroll_container != null:
		scroll_container.offset_top = 45


func _on_close_pressed() -> void:
	close_requested.emit()


func _on_text_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return
	text_submitted.emit(text)
	input_field.text = ""
	input_field.editable = false
