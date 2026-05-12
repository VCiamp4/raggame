# dialogue_ui.gd
extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var name_label: Label = $Panel/MarginContainer/VBoxContainer/NameLabel
@onready var text_label: Label = $Panel/MarginContainer/VBoxContainer/TextLabel

func _ready() -> void:
	hide_dialogue()

func show_dialogue(npc_name: String, text: String) -> void:
	name_label.text = npc_name
	text_label.text = text
	panel.show()

func hide_dialogue() -> void:
	panel.hide()

func is_open() -> bool:
	return panel.visible
