extends CanvasLayer

const DISPLAY_TIME := 3.0
const FADE_TIME := 0.4

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


func show_message(text: String) -> void:
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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.add_child(label)

	notification_stack.add_child(panel)

	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_interval(DISPLAY_TIME)
	tween.tween_property(panel, "modulate:a", 0.0, FADE_TIME)
	tween.finished.connect(func():
		if is_instance_valid(panel):
			panel.queue_free()
	)


func show_clue_notification(event_id: String) -> void:
	var clue_info: Dictionary = EventManager.clue_info(event_id)
	if clue_info.is_empty():
		return
	var summary: String = clue_info.get("summary", event_id)
	var character: String = clue_info.get("character", "")
	var text: String = summary
	if character != null and str(character) != "":
		text = "%s (%s)" % [summary, character]
	show_message("Pista encontrada: %s" % text)
