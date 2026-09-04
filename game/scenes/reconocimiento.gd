extends Node3D

@onready var camera: Camera3D = $Camera3D  # ajustá el path a tu cámara

const PREVIOUS_SCENE := "res://scenes/comisaria.tscn"

var highlighted_suspect: Node = null
var selected_suspect: Node = null

# UI de confirmación (la creamos por código)
var confirm_panel: Panel
var confirm_label: Label

# Header UI (salir con X)
var exit_canvas: CanvasLayer
var exit_hint: Label
var close_button: Button


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_exit_ui()
	_build_confirm_ui()
	if not InputManager.device_changed.is_connected(_on_device_changed):
		InputManager.device_changed.connect(_on_device_changed)
	_update_exit_hint()


func _process(_delta: float) -> void:
	if confirm_panel.visible:
		return  # no detectar mientras el cartel está abierto
	_check_suspect_under_mouse()


func _check_suspect_under_mouse() -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var ray_end = ray_origin + ray_dir * 1000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result = space_state.intersect_ray(query)
	
	var found: Node = null
	if result and result.has("collider"):
		var collider = result["collider"]
		if collider.is_in_group("sospechoso"):
			found = collider
	
	if found != highlighted_suspect:
		if highlighted_suspect != null:
			highlighted_suspect.unhighlight()
		highlighted_suspect = found
		if found != null:
			found.highlight()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_quit_dialogue"):
		if confirm_panel.visible:
			_hide_confirm()  # cerrar cartel
		else:
			_exit_scene()
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if confirm_panel.visible:
				return  # los clics del cartel los manejan los botones
			if highlighted_suspect != null:
				_show_confirm(highlighted_suspect)


func _show_confirm(suspect: Node) -> void:
	selected_suspect = suspect
	confirm_label.text = "¿Seguro que querés culpar a " + suspect.get_suspect_name() + "?"
	confirm_panel.show()


func _hide_confirm() -> void:
	confirm_panel.hide()
	selected_suspect = null


func _on_accept() -> void:
	# Guardamos a quién se acusó para que la escena de veredicto lo sepa
	var id = selected_suspect.get_suspect_id()
	# Usamos un autoload/variable global, o lo pasamos por un singleton simple
	Global.accused_id = id
	Global.accused_name = selected_suspect.get_suspect_name()
	get_tree().change_scene_to_file("res://scenes/veredicto.tscn")


func _exit_scene() -> void:
	get_tree().change_scene_to_file(PREVIOUS_SCENE)


func _build_confirm_ui() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	confirm_panel = Panel.new()
	confirm_panel.anchor_left = 0.5
	confirm_panel.anchor_right = 0.5
	confirm_panel.anchor_top = 0.5
	confirm_panel.anchor_bottom = 0.5
	confirm_panel.offset_left = -250
	confirm_panel.offset_right = 250
	confirm_panel.offset_top = -110
	confirm_panel.offset_bottom = 110
	confirm_panel.visible = false
	canvas.add_child(confirm_panel)
	
	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 20
	content.offset_right = -20
	content.offset_top = 20
	content.offset_bottom = -20
	content.add_theme_constant_override("separation", 24)
	confirm_panel.add_child(content)
	
	confirm_label = Label.new()
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.add_theme_font_size_override("font_size", 20)
	content.add_child(confirm_label)
	
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	content.add_child(buttons)
	
	var btn_yes = Button.new()
	btn_yes.text = "Acusar"
	btn_yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_yes.pressed.connect(_on_accept)
	buttons.add_child(btn_yes)

	var btn_no = Button.new()
	btn_no.text = "Cancelar"
	btn_no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_no.pressed.connect(_hide_confirm)
	buttons.add_child(btn_no)

func _build_exit_ui() -> void:
	exit_canvas = CanvasLayer.new()
	exit_canvas.layer = 5
	add_child(exit_canvas)

	var panel := HBoxContainer.new()
	panel.anchor_left = 1
	panel.anchor_right = 1
	panel.anchor_top = 0
	panel.anchor_bottom = 0
	panel.offset_left = -220
	panel.offset_right = -20
	panel.offset_top = 20
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 12)
	exit_canvas.add_child(panel)

	exit_hint = Label.new()
	exit_hint.add_theme_font_size_override("font_size", 16)
	exit_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	panel.add_child(exit_hint)

	close_button = Button.new()
	close_button.text = "X"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.tooltip_text = "Cerrar pizarrón"
	close_button.pressed.connect(_on_close_pressed)
	panel.add_child(close_button)


func _update_exit_hint() -> void:
	if exit_hint == null:
		return
	exit_hint.text = "%s Salir" % InputManager.action_glyph("ui_quit_dialogue")


func _on_close_pressed() -> void:
	_exit_scene()


func _on_device_changed(_using_controller: bool) -> void:
	_update_exit_hint()
