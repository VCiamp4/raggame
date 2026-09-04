extends CanvasLayer

const DEFAULT_PLAYER_COLOR := Color(0.533, 0.8, 1.0)
const DEFAULT_NPC_COLOR := Color(1.0, 0.878, 0.502)
const EventCatalogRes = preload("res://data/events/events.gd")

var panel: ColorRect
var name_label: Label
var exit_hint: Label
var scroll_container: ScrollContainer
var history_label: RichTextLabel
var input_field: LineEdit
var prompt_label: Label
var keyword_panel: VBoxContainer
var keyword_labels: Array = []

signal text_submitted(text: String)
signal close_requested

var current_npc_response: String = ""
var _prompt_target_name: String = ""
var _prompt_verb: String = "Hablar con"
var _prompt_action: String = "interact"
var _placeholder_label: String = "Escribí algo y presioná"
var _player_label: String = "Vos"
var _player_color: Color = DEFAULT_PLAYER_COLOR
var _npc_color: Color = DEFAULT_NPC_COLOR
var _current_profile: Dictionary = {}
var close_button: Button


func _ready() -> void:
	InputManager.device_changed.connect(_on_device_changed)

	# Panel de fondo del diálogo
	panel = ColorRect.new()
	panel.color = Color(0, 0, 0, 0.85)
	panel.anchor_left = 0
	panel.anchor_right = 1
	panel.anchor_top = 0.55
	panel.anchor_bottom = 1
	panel.offset_left = 40
	panel.offset_right = -40
	panel.visible = false
	add_child(panel)

	# Margen interior del panel
	var margin_container := MarginContainer.new()
	margin_container.anchor_right = 1.0
	margin_container.anchor_bottom = 1.0
	margin_container.add_theme_constant_override("margin_left", 20)
	margin_container.add_theme_constant_override("margin_top", 15)
	margin_container.add_theme_constant_override("margin_right", 20)
	margin_container.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin_container)

	# Contenedor vertical principal
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	margin_container.add_child(main_vbox)

	# Header: Nombre del NPC y botón de salir
	var header_hbox := HBoxContainer.new()
	main_vbox.add_child(header_hbox)

	name_label = Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	header_hbox.add_child(name_label)

	exit_hint = Label.new()
	exit_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	exit_hint.add_theme_font_size_override("font_size", 16)
	exit_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	exit_hint.visible = false
	header_hbox.add_child(exit_hint)

	close_button = Button.new()
	close_button.text = "X"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.tooltip_text = "Cerrar diálogo"
	close_button.pressed.connect(_on_close_pressed)
	header_hbox.add_child(close_button)

	# Panel dinámico de palabras clave
	keyword_panel = VBoxContainer.new()
	main_vbox.add_child(keyword_panel)

	# Historial scrolleable (se expande para ocupar el espacio restante)
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll_container)

	history_label = RichTextLabel.new()
	history_label.bbcode_enabled = true
	history_label.fit_content = true
	history_label.scroll_active = false
	history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_label.add_theme_font_size_override("normal_font_size", 18)
	scroll_container.add_child(history_label)

	# Campo de entrada de texto
	input_field = LineEdit.new()
	input_field.placeholder_text = "Escribí algo y presioná Enter..."
	input_field.add_theme_font_size_override("font_size", 18)
	input_field.text_submitted.connect(_on_text_submitted)
	main_vbox.add_child(input_field)

	# Indicador flotante de interacción ([E] Hablar)
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


func apply_profile(profile: Dictionary) -> void:
	_current_profile = profile.duplicate(true)
	_player_color = _current_profile.get("player_color", DEFAULT_PLAYER_COLOR)
	_npc_color = _current_profile.get("npc_color", DEFAULT_NPC_COLOR)
	_prompt_verb = _current_profile.get("prompt_verb", _prompt_verb)
	_prompt_action = _current_profile.get("prompt_action", _prompt_action)
	_placeholder_label = _current_profile.get("placeholder", _placeholder_label)
	_player_label = _current_profile.get("player_label", _player_label)
	var accent_color: Color = _current_profile.get("accent_color", name_label.get_theme_color("font_color", "Label"))
	name_label.add_theme_color_override("font_color", accent_color)


func show_dialogue(npc_name: String) -> void:
	name_label.text = npc_name
	panel.show()
	input_field.text = ""
	input_field.placeholder_text = _placeholder_label + " " + InputManager.action_glyph() + "..."
	input_field.editable = true
	input_field.grab_focus()
	_update_keywords()
	_exit_hint_update()


func hide_dialogue() -> void:
	panel.hide()
	input_field.release_focus()
	exit_hint.visible = false
	_clear_keywords()


func is_open() -> bool:
	return panel.visible


func add_player_message(_npc_name: String, text: String) -> void:
	var color := _player_color.to_html(false)
	var line = "[color=#%s][b]%s:[/b][/color] %s\n" % [color, _player_label, text]
	history_label.append_text(line)
	_scroll_to_bottom()


func start_npc_response(npc_name: String) -> void:
	current_npc_response = ""
	var color := _npc_color.to_html(false)
	history_label.append_text("[color=#%s][b]%s:[/b][/color] " % [color, npc_name])
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


func show_prompt(target_name: String, verb: String = "", action: String = "") -> void:
	_prompt_target_name = target_name
	var resolved_verb = verb if verb != "" else _current_profile.get("prompt_verb", "Hablar con")
	var resolved_action = action if action != "" else _current_profile.get("prompt_action", "interact")
	_prompt_verb = resolved_verb
	_prompt_action = resolved_action
	prompt_label.text = InputManager.action_glyph(resolved_action) + " " + resolved_verb + " " + target_name
	prompt_label.show()


func hide_prompt() -> void:
	_prompt_target_name = ""
	prompt_label.hide()


func _on_device_changed(_using_controller: bool) -> void:
	if panel.visible:
		input_field.placeholder_text = _placeholder_label + " " + InputManager.action_glyph("interact") + "..."
	if _prompt_target_name != "":
		prompt_label.text = InputManager.action_glyph(_prompt_action) + " " + _prompt_verb + " " + _prompt_target_name
	_exit_hint_update()


func _on_text_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return
	text_submitted.emit(text)
	input_field.text = ""
	input_field.editable = false


func _exit_hint_update() -> void:
	if exit_hint == null:
		return
	if not panel.visible:
		exit_hint.visible = false
		return
	var glyph := InputManager.action_glyph("ui_quit_dialogue")
	exit_hint.text = "%s Salir o clic en X" % glyph
	exit_hint.visible = true


func _clear_keywords() -> void:
	for label in keyword_labels:
		if is_instance_valid(label):
			label.queue_free()
	keyword_labels.clear()


func _update_keywords() -> void:
	_clear_keywords()
	var npc_id: String = _current_profile.get("npc_id", "")
	if npc_id == "":
		return
	var lookup_id := npc_id.capitalize()
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


func _on_close_pressed() -> void:
	close_requested.emit()
