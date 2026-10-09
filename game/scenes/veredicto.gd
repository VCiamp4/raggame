extends Node

const CULPABLE_REAL = "pablo"

# Velocidad del efecto: segundos por carácter (más bajo = más rápido)
const TYPE_SPEED = 0.03

var finales = {
	"pablo": "Acusaste a Pablo, el hermano menor. Su coartada en Erpa parecía perfecta, pero el crimen había empezado días antes. Las pruebas encajan: el cianuro en el hielo, los reactivos del laboratorio, la heladera que él reparó y la póliza que le reservaba la mitad del beneficio. Había cambiado un fusible y contaminado el agua del congelador. Después sólo necesitaba esperar a que su hermana pidiera whisky con hielo. La discusión con Esteban adelantó sus planes. Cuando le presentás las pruebas, Pablo conserva la frialdad y vuelve a señalar a Juan. No confiesa. Los agentes se lo llevan igual. Hiciste justicia. Una pequeña mancha de humedad te condujo hasta el hombre que había convertido una costumbre en una trampa mortal.",
	"esteban": "Acusaste a Esteban, el corredor de seguros. Había gestionado la póliza y salido furioso al descubrir que Pablo recibiría el doble que él. El dinero parecía explicar todo. Pero su estancia en Lister, desde las seis de la tarde hasta las nueve de la mañana siguiente, estaba comprobada, y no aparece ninguna prueba que lo vincule con el veneno. Esteban sale en libertad, todavía indignado. Su discusión había llevado a Stevens a pedir el whisky antes de lo habitual; vos confundiste ese último empujón con la preparación del crimen. El verdadero asesino sigue libre. El caso queda sin resolver y la póliza permanece sobre tu escritorio, como el recuerdo de una sospecha que nunca supiste convertir en prueba.",
	"juan": "Acusaste a Juan, el hermano mayor. Sus antecedentes, sus negocios turbios y la sonrisa con la que recibió la muerte de su hermana parecían una confesión. Pero odiar a Stevens no demostraba haberla matado. Los registros de la comisaría confirman que estuvo demorado desde las cinco de la tarde hasta la medianoche por un accidente de tránsito. No encontrás una sola prueba que lo relacione con el hielo envenenado. Juan recupera la libertad y te dedica otra sonrisa, tan desagradable como la primera. Mientras vos perseguías su pasado, el verdadero asesino quedaba fuera de tu alcance. El expediente se cierra sin justicia. Elegiste al hombre que más fácil resultaba odiar, y dejaste escapar al que había preparado el crimen.",
	"criada": "Acusaste a la criada. Había soportado años de insultos y humillaciones, preparado el whisky y sido la última persona que vio viva a Stevens. Parecía imposible que alguien más hubiera puesto el veneno. Pero la botella estaba limpia: el cianuro esperaba en el hielo antes de que ella sirviera la bebida. No aparece ninguna prueba de que hubiera contaminado las cubeteras. La acusación se derrumba y la mujer sale en libertad, retorciendo el mismo pañuelo que apretaba durante el interrogatorio. Ya temía que la culparan; vos convertiste ese miedo en otra humillación. El asesino sigue libre, protegido por tu error. Confundiste las manos que sirvieron el vaso con las que habían preparado la muerte."
}

var label: Label
var full_text: String = ""
var char_index: int = 0
var type_timer: float = 0.0
var typing: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	# Fondo negro a pantalla completa
	var bg = ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)
	
	# Texto
	label = Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.offset_left = 120
	label.offset_right = -120
	label.offset_top = 100
	label.offset_bottom = -100
	canvas.add_child(label)
	
	# Armar el texto completo según la acusación
	var id = Global.accused_id
	if finales.has(id):
		var veredicto = ""
		if id == CULPABLE_REAL:
			veredicto = "[ ACERTASTE ]\n\n"
		else:
			veredicto = "[ TE EQUIVOCASTE ]\n\n"
		full_text = veredicto + finales[id]
	else:
		full_text = "No se registró ninguna acusación."
	
	# Arrancar el efecto typewriter
	label.text = ""
	char_index = 0
	typing = true


func _process(delta: float) -> void:
	if not typing:
		return
	
	type_timer += delta
	if type_timer >= TYPE_SPEED:
		type_timer = 0.0
		char_index += 1
		label.text = full_text.substr(0, char_index)
		if char_index >= full_text.length():
			typing = false


func _unhandled_input(event: InputEvent) -> void:
	# Si presionás algo mientras escribe, se completa de golpe (skip)
	if typing and (event is InputEventMouseButton or event is InputEventKey):
		if event.is_pressed():
			label.text = full_text
			char_index = full_text.length()
			typing = false
