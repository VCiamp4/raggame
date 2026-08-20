extends CanvasLayer

const PLAYABLE_SCENES := [
	{"name": "Campo · NPC sin ubicación propia", "path": "res://scenes/campo.tscn"},
	{"name": "Departamento · escena del crimen", "path": "res://scenes/dpto.tscn"},
	{"name": "Comisaría", "path": "res://scenes/comisaria.tscn"},
	{"name": "Hall", "path": "res://scenes/Hall.tscn"},
	{"name": "Mapa de ubicaciones", "path": "res://scenes/mapa_menu.tscn"},
]

var panel: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build_menu()
	hide_menu()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		toggle_menu()
		get_viewport().set_input_as_handled()


func _build_menu() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position -= panel.custom_minimum_size / 2.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)

	var title := Label.new()
	title.text = "Escenas de prueba"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	content.add_child(title)

	var hint := Label.new()
	hint.text = "Elegí una escena · Escape cierra este menú"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	content.add_child(hint)

	for scene in PLAYABLE_SCENES:
		var button := Button.new()
		button.text = scene["name"]
		button.custom_minimum_size = Vector2(0, 42)
		button.pressed.connect(_open_scene.bind(scene["path"]))
		content.add_child(button)

	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.pressed.connect(hide_menu)
	content.add_child(close_button)


func toggle_menu() -> void:
	if panel.visible:
		hide_menu()
	else:
		show_menu()


func show_menu() -> void:
	visible = true
	panel.visible = true
	get_tree().paused = true


func hide_menu() -> void:
	if panel == null:
		return
	panel.visible = false
	visible = false
	get_tree().paused = false


func _open_scene(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
