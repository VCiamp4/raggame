extends Node

const CULPABLE_REAL = "mira"

# Velocidad del efecto: segundos por carácter (más bajo = más rápido)
const TYPE_SPEED = 0.03

var finales = {
	"aldric": "Acusaste a Aldric, el herrero del pueblo. Durante días sospechaste de sus manos curtidas y su carácter reservado, pero las pruebas nunca terminaron de encajar. En el juicio, su coartada resulta sólida: tres testigos lo vieron en la fragua la noche del crimen. Aldric es liberado sin cargos. Te mira a los ojos al salir, sin rencor, apenas con lástima. Mientras tanto, en algún lugar de la ciudad, el verdadero asesino respira aliviado y desaparece entre las sombras. El caso se archiva. Nunca sabrás cuán cerca estuviste de la verdad.",
	"esteban": "Acusaste a Esteban, el hermano mayor. Jurabas que el seguro de vida era motivo suficiente, pero la investigación fiscal demuestra que nunca llegó a cobrar un peso: la póliza seguía congelada por trámites bancarios. El juez ordena su liberación inmediata y te recuerda que la sospecha no reemplaza a la evidencia. Esteban abandona la sala con el rostro desencajado, jurando que jamás volverá a confiar en la policía. Vos quedás frente a un expediente vacío y al eco de una inocencia rota por tu apuro.",
	"juan": "Acusaste a Juan, el impulsivo de la familia. Te apoyaste en sus antecedentes y en su mala fama, pero las cámaras del edificio muestran que nunca entró ni salió aquella noche. La fiscalía te exige explicar por qué ignoraste la prueba más clara. Juan ríe con rabia, se proclama inocente y exige que limpien su nombre públicamente. En lugar de aplausos, recibís un expediente disciplinario. El verdadero culpable sigue suelto y Juan, aunque inocente, queda marcado por tu error.",
	"pablo": "Acusaste a Pablo, el ingeniero que arreglaba la heladera. Pensaste que su acceso al laboratorio lo convertía en el asesino perfecto, pero los peritajes de toxicología prueban que el cianuro encontrado en Erpa nunca salió de las vitrinas bajo llave. Pablo demuestra que estuvo en su turno nocturno todo el tiempo, con firmas y controles cruzados. El tribunal te escucha en silencio y luego archiva la causa. Pablo te dedica una última mirada cansada antes de desaparecer entre periodistas. Te quedás sin pistas y con la certeza amarga de haber culpado a un inocente.",
	"criada": "Acusaste a la criada, convencido de que ser la última en servir el whisky la hacía culpable. Sin embargo, su abogado presenta el diario de trabajo: ella se retiró veinte minutos antes de la muerte y fue registrada por el portero del edificio. El jurado tarda apenas unos minutos en absolverla. La mujer rompe en llanto, no por alivio, sino por el daño que le causaste al arrastrarla a un juicio público. Te quedás solo, mirando el pizarrón lleno de flechas que ya no conducen a nadie. El veneno sigue sin dueño.",
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
