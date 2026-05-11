extends Area3D

var jugador_cerca = false
@onready var ui_dialogo = $CanvasLayer

func _process(delta):
	# "ui_accept" suele ser la tecla Espacio o Enter
	if jugador_cerca and Input.is_action_just_pressed("ui_accept"):
		# Si está visible, lo ocultamos. Si está oculto, lo mostramos.
		if ui_dialogo.visible:
			ui_dialogo.hide()
		else:
			ui_dialogo.show()

# Esta función se activa sola cuando alguien entra en la colisión grande
func _on_body_entered(body):
	# ¡Importante! Revisa que el nombre coincida exactamente con el de tu personaje
	if body.name == "jugador": 
		jugador_cerca = true

# Esta función se activa cuando el jugador se aleja
func _on_body_exited(body):
	if body.name == "jugador":
		jugador_cerca = false
		ui_dialogo.hide() # Ocultamos el diálogo automáticamente si se va
