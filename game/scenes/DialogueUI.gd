extends CanvasLayer

var panel: ColorRect
var name_label: Label
var scroll_container: ScrollContainer
var history_label: RichTextLabel
var input_field: LineEdit
var prompt_label: Label

signal text_submitted(text: String)

var current_npc_response: String = ""


func _ready() -> void:
	# Panel de fondo del diálogo
	panel = ColorRect.new()
	panel.color = Color(0, 0, 0, 0.85)
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
	name_label.offset_right = -20
	name_label.offset_bottom = 40
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	panel.add_child(name_label)
	
	# Historial scrolleable (RichTextLabel adentro de ScrollContainer)
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
	panel.add_child(scroll_container)
	
	history_label = RichTextLabel.new()
	history_label.bbcode_enabled = true
	history_label.fit_content = true
	history_label.scroll_active = false
	history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_label.add_theme_font_size_override("normal_font_size", 18)
	scroll_container.add_child(history_label)
	
	# Campo de texto para escribir abajo
	input_field = LineEdit.new()
	input_field.anchor_left = 0
	input_field.anchor_right = 1
	input_field.anchor_bottom = 1
	input_field.offset_left = 20
	input_field.offset_right = -20
	input_field.offset_top = -45
	input_field.offset_bottom = -15
	input_field.placeholder_text = "Escribí algo y presioná Enter..."
	input_field.add_theme_font_size_override("font_size", 18)
	input_field.text_submitted.connect(_on_text_submitted)
	panel.add_child(input_field)
	
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
	panel.show()
	input_field.text = ""
	input_field.editable = true
	input_field.grab_focus()
	# Si querés que cada vez que abrís se borre el historial, descomentá:
	# history_label.text = ""


func hide_dialogue() -> void:
	panel.hide()
	input_field.release_focus()


func is_open() -> bool:
	return panel.visible


func add_player_message(npc_name: String, text: String) -> void:
	# Mensaje del jugador en color claro
	var line = "[color=#88ccff][b]Vos:[/b][/color] " + text + "\n"
	history_label.append_text(line)
	_scroll_to_bottom()


func start_npc_response(npc_name: String) -> void:
	# Línea con el nombre del NPC y espacio para la respuesta
	current_npc_response = ""
	history_label.append_text("[color=#ffe080][b]" + npc_name + ":[/b][/color] ")
	_scroll_to_bottom()


func append_npc_chunk(text: String) -> void:
	# Va agregando texto al final del último mensaje del NPC
	current_npc_response += text
	history_label.append_text(text)
	_scroll_to_bottom()


func finish_npc_response() -> void:
	history_label.append_text("\n")
	_scroll_to_bottom()


func _scroll_to_bottom() -> void:
	# Scroll al fondo en el próximo frame (después de que el layout se actualice)
	await get_tree().process_frame
	var scrollbar = scroll_container.get_v_scroll_bar()
	scroll_container.scroll_vertical = int(scrollbar.max_value)


func set_input_enabled(enabled: bool) -> void:
	input_field.editable = enabled
	if enabled:
		input_field.grab_focus()


func show_prompt(npc_name: String) -> void:
	prompt_label.text = "[E] Hablar con " + npc_name
	prompt_label.show()


func hide_prompt() -> void:
	prompt_label.hide()


func _on_text_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return
	text_submitted.emit(text)
	input_field.text = ""
	input_field.editable = false
