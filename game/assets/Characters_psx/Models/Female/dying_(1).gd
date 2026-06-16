extends Node3D

func _ready() -> void:
	var anim = _find_animation_player(self)
	if anim:
		var anim_name = anim.get_animation_list()[0]
		anim.play(anim_name)
		# Saltar al último frame y congelar
		anim.seek(anim.get_animation(anim_name).length, true)
		anim.pause()
	else:
		print(">> No se encontró AnimationPlayer en la víctima")


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null
