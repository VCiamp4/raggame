extends CanvasLayer

const BackendError = preload("res://ui/backend_error.gd")

const DISPLAY_TIME := 3.0
const ERROR_DISPLAY_TIME := 9.0
const FADE_TIME := 0.4
const ERROR_COLOR := Color("ff8a80")

var notification_stack: VBoxContainer


func _ready() -> void:
	layer = 100
	_notification_ui()
	if Engine.is_editor_hint():
		return


func _notification_ui() -> void:
	notification_stack = VBoxContainer.new()
	notification_stack.anchor_left = 1
	notification_stack.anchor_right = 1
	notification_stack.anchor_top = 0
	notification_stack.anchor_bottom = 0
	notification_stack.offset_left = -360
	notification_stack.offset_right = -20
	notification_stack.offset_top = 20
	notification_stack.alignment = BoxContainer.ALIGNMENT_END
	add_child(notification_stack)


# Error para el jugador: más tiempo en pantalla, en rojo y con a quién avisar.
func show_error(message: String) -> void:
	show_message(BackendError.with_contact(message), ERROR_DISPLAY_TIME, ERROR_COLOR)


func show_message(text: String, display_time: float = DISPLAY_TIME, color: Color = Color.TRANSPARENT) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 0)
	panel.modulate.a = 0.0

	var padding := MarginContainer.new()
	padding.add_theme_constant_override("margin_left", 12)
	padding.add_theme_constant_override("margin_right", 12)
	padding.add_theme_constant_override("margin_top", 8)
	padding.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(padding)

	var label := Label.new()
	label.text = text
	if color.a > 0.0:  # sin color explícito queda el del tema
		label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.add_child(label)

	notification_stack.add_child(panel)

	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_interval(display_time)
	tween.tween_property(panel, "modulate:a", 0.0, FADE_TIME)
	tween.finished.connect(func():
		if is_instance_valid(panel):
			panel.queue_free()
	)
