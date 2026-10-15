extends Node3D

# Herramienta de desarrollo: renderiza un modelo .fbx a un PNG de retrato
# (fondo transparente) usando el mismo encuadre que los retratos de diálogo.
#
# Uso:
#   godot --path game res://tools/render_portrait.tscn -- \
#     res://assets/Characters_psx/Models/Female/Character_Female_06.fbx \
#     /ruta/absoluta/retratos/criada.png

const OUT_SIZE := 128
const YAW_DEG := 0.0
const HEAD_Y := 0.90
const FRAME_H := 0.26


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var model_path := args[0] if args.size() > 0 else "res://assets/Characters_psx/Models/Female/Character_Female_06.fbx"
	var out_path := args[1] if args.size() > 1 else "user://retrato.png"

	var vp := SubViewport.new()
	vp.size = Vector2i(OUT_SIZE, OUT_SIZE)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	add_child(vp)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.66, 0.72)
	env.ambient_light_energy = 0.7
	world_env.environment = env
	vp.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.1
	vp.add_child(key)
	key.look_at_from_position(Vector3(2.5, 6.0, 5.0), Vector3(0, 3.0, 0), Vector3.UP)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.5
	fill.light_color = Color(0.7, 0.8, 1.0)
	vp.add_child(fill)
	fill.look_at_from_position(Vector3(-3.0, 2.5, 3.5), Vector3(0, 3.0, 0), Vector3.UP)

	var packed: PackedScene = load(model_path)
	if packed == null:
		push_error("No se pudo cargar el modelo: " + model_path)
		get_tree().quit(1)
		return
	var model: Node = packed.instantiate()
	vp.add_child(model)

	var aabb := _model_aabb(model)
	if aabb.size == Vector3.ZERO:
		push_error("El modelo no tiene malla visible.")
		get_tree().quit(1)
		return
	var center := aabb.get_center()
	model.position -= Vector3(center.x, aabb.position.y, center.z)
	var height := aabb.size.y
	var target_y := height * HEAD_Y
	var frame_height := height * FRAME_H

	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	var yaw := deg_to_rad(YAW_DEG)
	var dist := frame_height / (2.0 * tan(deg_to_rad(cam.fov * 0.5)))
	cam.position = Vector3(sin(yaw) * dist, target_y, cos(yaw) * dist)
	cam.look_at(Vector3(0, target_y, 0), Vector3.UP)
	cam.current = true

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var err := img.save_png(out_path)
	if err != OK:
		push_error("No se pudo guardar el PNG: " + out_path)
		get_tree().quit(1)
		return
	print(">> Retrato guardado: ", out_path)
	get_tree().quit(0)


func _model_aabb(node: Node) -> AABB:
	var acc: Array = []
	_collect_aabb(node, Transform3D(), acc)
	if acc.is_empty():
		return AABB()
	return acc[0]


func _collect_aabb(node: Node, xform: Transform3D, acc: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var box: AABB = (xform * mi.transform) * mi.mesh.get_aabb()
			if acc.is_empty():
				acc.append(box)
			else:
				acc[0] = (acc[0] as AABB).merge(box)
	for child in node.get_children():
		if child is Node3D:
			_collect_aabb(child, xform * (child as Node3D).transform, acc)
