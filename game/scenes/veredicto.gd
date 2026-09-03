extends Node

const CULPABLE_REAL = "mira"

# Velocidad del efecto: segundos por carácter (más bajo = más rápido)
const TYPE_SPEED = 0.03

var finales = {
	"aldric": "Acusaste a Aldric, el herrero del pueblo. Durante días sospechaste de sus manos curtidas y su carácter reservado, pero las pruebas nunca terminaron de encajar. En el juicio, su coartada resulta sólida: tres testigos lo vieron en la fragua la noche del crimen. Aldric es liberado sin cargos. Te mira a los ojos al salir, sin rencor, apenas con lástima. Mientras tanto, en algún lugar de la ciudad, el verdadero asesino respira aliviado y desaparece entre las sombras. El caso se archiva. Nunca sabrás cuán cerca estuviste de la verdad.",
	"mira": "Acusaste a Mira, la posadera. Al principio parecía la más amable de todos, siempre con una sonrisa y una copa servida. Pero las piezas encajan una a una: el veneno hallado en la copa de whisky, el testamento que la beneficiaba en secreto, la coartada que se deshace bajo tu interrogatorio. Cuando le presentás las pruebas, su rostro se quiebra. Confiesa entre lágrimas, contando cómo los años de resentimiento la llevaron al crimen. Los guardias se la llevan mientras el pueblo observa en silencio. Hiciste justicia. El caso se cierra con tu nombre grabado como el investigador que resolvió lo imposible.",
	"herve": "Acusaste a Hervé, el alcalde. Un error de proporciones fatales. Hervé no solo es inocente: es el hombre más poderoso de la región. Con una llamada, mueve sus influencias para destruir tu reputación. Al amanecer, tu placa ya no vale nada. El verdadero crimen queda impune, sepultado bajo la burocracia y el miedo. La ciudad murmura tu nombre con desprecio, y vos cargás con el peso de haber dejado libre a un asesino por perseguir al hombre equivocado."
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
