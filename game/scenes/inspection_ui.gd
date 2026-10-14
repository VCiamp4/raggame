extends CanvasLayer

# Popup de inspección de local-work, separado del historial y los retratos del chat.
const PAPEL = Color("d2cbbb")
const AMBAR = Color("c39a56")

var inspection_overlay: Control
var inspection_popup: PanelContainer
var inspection_title: Label
var inspection_description: Label
var inspection_close_button: Button

signal inspection_closed


func _ready() -> void:
	_build_inspection_popup()


func _build_inspection_popup() -> void:
	inspection_overlay = Control.new()
	inspection_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspection_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	inspection_overlay.hide()
	add_child(inspection_overlay)

	inspection_popup = PanelContainer.new()
	inspection_popup.name = "InspectionPopup"
	inspection_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	inspection_popup.offset_left = -250
	inspection_popup.offset_right = 250
	inspection_popup.offset_top = -115
	inspection_popup.offset_bottom = 115
	var style := StyleBoxFlat.new()
	style.bg_color = Color("141418")
	style.border_color = Color(AMBAR, 0.7)
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 14
	inspection_popup.add_theme_stylebox_override("panel", style)
	inspection_overlay.add_child(inspection_popup)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	inspection_popup.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	inspection_title = Label.new()
	inspection_title.uppercase = true
	inspection_title.add_theme_font_size_override("font_size", 20)
	inspection_title.add_theme_color_override("font_color", AMBAR)
	content.add_child(inspection_title)
	inspection_description = Label.new()
	inspection_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspection_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspection_description.add_theme_font_size_override("font_size", 17)
	inspection_description.add_theme_color_override("font_color", PAPEL)
	content.add_child(inspection_description)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(actions)
	inspection_close_button = Button.new()
	inspection_close_button.text = "Cerrar [Esc]"
	inspection_close_button.add_theme_font_size_override("font_size", 16)
	inspection_close_button.pressed.connect(hide_inspection)
	actions.add_child(inspection_close_button)


func show_inspection(title: String, description: String) -> void:
	inspection_title.text = title
	inspection_description.text = description
	inspection_overlay.show()
	inspection_close_button.grab_focus()


func hide_inspection() -> void:
	if not inspection_overlay.visible:
		return
	inspection_overlay.hide()
	inspection_close_button.release_focus()
	inspection_closed.emit()
