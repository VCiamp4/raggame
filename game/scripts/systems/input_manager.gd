extends Node


# ============================================================
# INPUT MANAGER
# ============================================================
# Detecta si el jugador está usando TECLADO/MOUSE o MANDO (Xbox).
#
# La idea es simple: cada vez que llega un evento de entrada,
# nos fijamos de qué tipo es:
#
#     - InputEventKey / InputEventMouse(Button|Motion) -> teclado/mouse
#     - InputEventJoypadButton / InputEventJoypadMotion -> mando
#
# El último dispositivo usado gana. Así, si el jugador mueve el
# joystick, la UI muestra "(A)"; si vuelve a tocar una tecla,
# vuelve a mostrar "[E]".
#
# Cualquier otro script puede consultarlo:
#
#     InputManager.using_controller
#     InputManager.action_glyph()   # "(A)" o "[E]"
#
# o escuchar la señal para reaccionar al cambio en vivo:
#
#     InputManager.device_changed.connect(_on_device_changed)
# ============================================================


# ------------------------------------------------------------
# SEÑAL
# ------------------------------------------------------------
# Se emite cuando el jugador cambia de dispositivo
# (teclado <-> mando). Útil para refrescar textos de la UI
# que ya estaban visibles.
# ------------------------------------------------------------

signal device_changed(using_controller: bool)


# ------------------------------------------------------------
# ESTADO
# ------------------------------------------------------------
# true  -> el último input vino del mando (Xbox)
# false -> el último input vino de teclado/mouse
# ------------------------------------------------------------

var using_controller: bool = false


func _input(event: InputEvent) -> void:

	# --------------------------------------------------------
	# Botones y sticks del mando.
	# --------------------------------------------------------

	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_set_device(true)

	# --------------------------------------------------------
	# Teclas y mouse (mover el mouse también cuenta).
	# --------------------------------------------------------

	elif event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventMouseMotion:
		_set_device(false)


func _set_device(controller: bool) -> void:

	# --------------------------------------------------------
	# Si el dispositivo no cambió, no avisamos a nadie.
	# --------------------------------------------------------

	if using_controller == controller:
		return

	using_controller = controller
	device_changed.emit(controller)


# ============================================================
# GLIFOS PARA LA UI
# ============================================================
# Devuelven el texto del botón según el dispositivo activo,
# buscando la vinculación real de la acción en el InputMap.
#
#     InputManager.action_glyph()            -> "[E]"  o  "(A)"
#     InputManager.action_glyph("examine")   -> "[F]"  o  "(X)"
#     InputManager.cancel_glyph()            -> "[Esc]" o "(B)"
#
# ============================================================

const XBOX_BUTTON_NAMES := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_START: "Start",
}


func action_glyph(action_name: String = "interact") -> String:
	var events := InputMap.action_get_events(action_name)

	# --------------------------------------------------------
	# Buscamos primero el evento del dispositivo activo.
	# --------------------------------------------------------

	if using_controller:
		for e in events:
			if e is InputEventJoypadButton:
				return "(%s)" % xbox_button_label(e.button_index)
	else:
		for e in events:
			if e is InputEventKey:
				return "[%s]" % OS.get_keycode_string(e.physical_keycode)

	# Si no hay vínculo para el dispositivo activo, mostramos el otro.

	for e in events:
		if e is InputEventKey:
			return "[%s]" % OS.get_keycode_string(e.physical_keycode)
		if e is InputEventJoypadButton:
			return "(%s)" % xbox_button_label(e.button_index)
	return "?"


func xbox_button_label(button_index: int) -> String:
	return XBOX_BUTTON_NAMES.get(button_index, str(button_index))


func cancel_glyph() -> String:
	return "(B)" if using_controller else "[Esc]"
