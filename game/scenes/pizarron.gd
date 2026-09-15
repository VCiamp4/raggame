extends StaticBody3D

@export var object_name: String = "Pizarrón"

var is_highlighted: bool = false
var mesh_instance: MeshInstance3D
var exit_canvas: CanvasLayer
var exit_hint: Label
var close_button: Button


func _ready() -> void:
	add_to_group("pizarron")
	mesh_instance = _find_mesh(self)
	_build_exit_ui()
	_update_exit_hint()
	if not InputManager.device_changed.is_connected(_on_device_changed):
		InputManager.device_changed.connect(_on_device_changed)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result = _find_mesh(child)
		if result:
			return result
	return null


func highlight() -> void:
	if is_highlighted or mesh_instance == null:
		return
	is_highlighted = true
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.9, 0.3)
	mat.emission_energy_multiplier = 0.4
	mesh_instance.material_overlay = mat
	_show_exit_ui()


func unhighlight() -> void:
	if not is_highlighted or mesh_instance == null:
		return
	is_highlighted = false
	mesh_instance.material_overlay = null
	_hide_exit_ui()


func interact() -> void:
	get_tree().change_scene_to_file("res://scenes/reconocimiento.tscn")


func _build_exit_ui() -> void:
	exit_canvas = CanvasLayer.new()
	exit_canvas.layer = 90
	add_child(exit_canvas)
	exit_canvas.visible = false

	var panel := HBoxContainer.new()
	panel.anchor_left = 1
	panel.anchor_right = 1
	panel.anchor_top = 0
	panel.anchor_bottom = 0
	panel.offset_left = -220
	panel.offset_right = -20
	panel.offset_top = 20
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


func _show_exit_ui() -> void:
	if exit_canvas:
		exit_canvas.visible = true
	_update_exit_hint()


func _hide_exit_ui() -> void:
	if exit_canvas:
		exit_canvas.visible = false


func _update_exit_hint() -> void:
	if exit_hint == null:
		return
	exit_hint.text = "%s Salir" % InputManager.action_glyph("ui_quit_dialogue")


func _on_close_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hall.tscn")


func _on_device_changed(_using_controller: bool) -> void:
	_update_exit_hint()
