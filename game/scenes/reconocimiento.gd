extends Node3D

@onready var camera: Camera3D = $Camera3D  # ajustá el path a tu cámara

var highlighted_suspect: Node = null
var selected_suspect: Node = null

# UI de confirmación (la creamos por código)
var confirm_panel: Panel
var confirm_label: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_confirm_ui()


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
	if event.is_action_pressed("ui_cancel"):
		if confirm_panel.visible:
			_hide_confirm()  # cerrar cartel
		else:
			get_tree().change_scene_to_file("res://scenes/hall.tscn")  # salir
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
	confirm_panel.offset_top = -100
	confirm_panel.offset_bottom = 100
	confirm_panel.visible = false
	canvas.add_child(confirm_panel)
	
	confirm_label = Label.new()
	confirm_label.anchor_left = 0
	confirm_label.anchor_right = 1
	confirm_label.offset_top = 20
	confirm_label.offset_left = 20
	confirm_label.offset_right = -20
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.add_theme_font_size_override("font_size", 20)
	confirm_panel.add_child(confirm_label)
	
	# Botón Aceptar
	var btn_yes = Button.new()
	btn_yes.text = "Sí, acusar"
	btn_yes.anchor_left = 0
	btn_yes.anchor_top = 1
	btn_yes.offset_left = 40
	btn_yes.offset_top = -60
	btn_yes.offset_right = 180
	btn_yes.offset_bottom = -20
	btn_yes.pressed.connect(_on_accept)
	confirm_panel.add_child(btn_yes)
	
	# Botón Cancelar
	var btn_no = Button.new()
	btn_no.text = "No"
	btn_no.anchor_left = 1
	btn_no.anchor_top = 1
	btn_no.offset_left = -180
	btn_no.offset_top = -60
	btn_no.offset_right = -40
	btn_no.offset_bottom = -20
	btn_no.pressed.connect(_hide_confirm)
	confirm_panel.add_child(btn_no)
