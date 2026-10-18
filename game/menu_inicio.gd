extends Node

# Ajustá a la escena por la que arranca el juego
const ESCENA_INICIAL = "res://scenes/mapa_menu.tscn"

# Paleta horror PSX
const COLOR_FONDO = Color("0a0a0c")
const COLOR_TEXTO = Color("c8c4b8")
const COLOR_ACENTO = Color("8b2b2b")
const COLOR_HOVER = Color("a8823c")

const DIFFICULTY_PROFILES = [
	{
		"id": "story",
		"name": "Informe guiado",
		"label": "Fácil",
		"tagline": "Las pistas te dicen a quién preguntar",
		"hint_limit": -1,
		"hint_names_npc": true
	},
	{
		"id": "standard",
		"name": "Procedimiento",
		"label": "Medio",
		"tagline": "Las pistas no te dicen a quién preguntar",
		"hint_limit": -1
	},
	{
		"id": "hardcore",
		"name": "Contra reloj",
		"label": "Difícil",
		"tagline": "Sin pistas: estás solo",
		"hint_limit": 0
	}
]

var _canvas: CanvasLayer
var _difficulty_overlay: Control
var _difficulty_buttons: Array = []
var _about_overlay: Control
var _briefing_overlay: Control
var _briefing_button: Button


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_canvas = CanvasLayer.new()
	add_child(_canvas)

	# Fondo oscuro
	var bg = ColorRect.new()
	bg.color = COLOR_FONDO
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(bg)

	# Título del juego
	var titulo = Label.new()
	titulo.text = "EL CRIMEN CASI PERFECTO"  # provisorio, cambialo cuando tengas nombre
	titulo.set_anchors_preset(Control.PRESET_FULL_RECT)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	titulo.offset_top = -160
	titulo.offset_bottom = -160
	titulo.add_theme_font_size_override("font_size", 52)
	titulo.add_theme_color_override("font_color", COLOR_TEXTO)
	_canvas.add_child(titulo)

	# Subtítulo tenue
	var subtitulo = Label.new()
	subtitulo.text = "Inspirado en el cuento homónimo de Roberto Arlt"
	subtitulo.set_anchors_preset(Control.PRESET_FULL_RECT)
	subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitulo.offset_top = -100
	subtitulo.offset_bottom = -100
	subtitulo.add_theme_font_size_override("font_size", 18)
	subtitulo.add_theme_color_override("font_color", COLOR_ACENTO)
	_canvas.add_child(subtitulo)

	# Botón Jugar
	var btn_jugar = _crear_boton("Jugar", 40)
	btn_jugar.pressed.connect(_on_jugar)
	_canvas.add_child(btn_jugar)

	# Botón Sobre nosotros
	var btn_about = _crear_boton("Sobre nosotros", 110)
	btn_about.pressed.connect(_on_about)
	_canvas.add_child(btn_about)

	# Botón Salir
	var btn_salir = _crear_boton("Salir", 180)
	btn_salir.pressed.connect(_on_salir)
	_canvas.add_child(btn_salir)

	# Audio de ambiente (desactivado)
	#var ambiente = AudioStreamPlayer.new()
	#var stream = load("res://audio/438135__craigsmith__g16-11-police-teletype-and-ambience.wav")
	#if stream is AudioStreamWAV:
	#	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	#ambiente.stream = stream
	#ambiente.autoplay = true
	#ambiente.volume_db = -8
	#add_child(ambiente)

	# Overlay de dificultad (oculto hasta pulsar "Jugar") + viñeta encima
	_crear_difficulty_overlay()
	_crear_about_overlay()
	_crear_briefing_overlay()
	_crear_vineta(_canvas)


func _crear_boton(texto: String, offset_y: float) -> Button:
	var btn = Button.new()
	btn.text = texto
	btn.anchor_left = 0.5
	btn.anchor_right = 0.5
	btn.anchor_top = 0.5
	btn.anchor_bottom = 0.5
	btn.offset_left = -120
	btn.offset_right = 120
	btn.offset_top = offset_y
	btn.offset_bottom = offset_y + 50
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", COLOR_TEXTO)
	btn.add_theme_color_override("font_hover_color", COLOR_HOVER)
	# Estilo plano, sin fondo de botón (para el look minimalista oscuro)
	var estilo_normal = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", estilo_normal)
	btn.add_theme_stylebox_override("hover", estilo_normal)
	btn.add_theme_stylebox_override("pressed", estilo_normal)
	btn.add_theme_stylebox_override("focus", estilo_normal)
	return btn


func _crear_difficulty_overlay() -> void:
	_difficulty_overlay = _crear_overlay()
	var vbox := _crear_panel(_difficulty_overlay, 560)

	var title := Label.new()
	title.text = "Seleccioná la dificultad"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", COLOR_TEXTO)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Define cuánta ayuda te dan las pistas."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", COLOR_HOVER)
	vbox.add_child(subtitle)

	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 8)
	vbox.add_child(_espaciador(6))
	vbox.add_child(options)
	_difficulty_buttons.clear()

	for profile in DIFFICULTY_PROFILES:
		var btn := _crear_opcion_dificultad(profile)
		btn.pressed.connect(func(): _on_difficulty_selected(profile))
		options.add_child(btn)
		_difficulty_buttons.append(btn)

	var note := Label.new()
	note.text = "Para cambiarla, empezá una partida nueva."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", COLOR_TEXTO.darkened(0.4))
	vbox.add_child(note)

	var cancel := Button.new()
	cancel.text = "Volver"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.add_theme_color_override("font_color", COLOR_ACENTO)
	cancel.mouse_entered.connect(cancel.grab_focus)
	cancel.pressed.connect(_hide_difficulty_menu)
	vbox.add_child(_espaciador(4))
	vbox.add_child(cancel)


# Botón de dos líneas: nombre del modo destacado y descripción más chica y tenue
func _crear_opcion_dificultad(profile: Dictionary) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 66)

	var lineas := VBoxContainer.new()
	lineas.set_anchors_preset(Control.PRESET_FULL_RECT)
	lineas.alignment = BoxContainer.ALIGNMENT_CENTER
	lineas.add_theme_constant_override("separation", 2)
	lineas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lineas)

	var level_label: String = str(profile.get("label", ""))
	var display_name: String = str(profile.get("name", ""))
	var nombre := Label.new()
	nombre.text = "%s  —  %s" % [display_name, level_label] if level_label != "" else display_name
	nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nombre.add_theme_font_size_override("font_size", 22)
	nombre.add_theme_color_override("font_color", COLOR_TEXTO)
	nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lineas.add_child(nombre)

	var tagline := Label.new()
	tagline.text = str(profile.get("tagline", ""))
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 16)
	tagline.add_theme_color_override("font_color", COLOR_TEXTO.darkened(0.35))
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lineas.add_child(tagline)

	# El mouse mueve el foco, así nunca quedan dos opciones resaltadas a la vez
	btn.mouse_entered.connect(btn.grab_focus)
	btn.focus_entered.connect(func(): nombre.add_theme_color_override("font_color", COLOR_HOVER))
	btn.focus_exited.connect(func(): nombre.add_theme_color_override("font_color", COLOR_TEXTO))
	return btn


# Fondo casi negro que tapa el menú y bloquea sus clics
func _crear_overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.96)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.add_child(overlay)
	return overlay


# Panel centrado que se ajusta a su contenido, con fondo opaco para que no se
# transparente el menú de atrás. Devuelve la columna donde va el contenido.
func _crear_panel(overlay: Control, ancho: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var estilo_panel := StyleBoxFlat.new()
	estilo_panel.bg_color = COLOR_FONDO.lightened(0.06)
	estilo_panel.set_content_margin_all(32)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ancho, 0)
	panel.add_theme_stylebox_override("panel", estilo_panel)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	return vbox


func _espaciador(alto: float) -> Control:
	var espacio := Control.new()
	espacio.custom_minimum_size = Vector2(0, alto)
	return espacio


func _crear_about_overlay() -> void:
	_about_overlay = _crear_overlay()
	var vbox := _crear_panel(_about_overlay, 640)

	var title := Label.new()
	title.text = "Sobre nosotros"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", COLOR_TEXTO)
	vbox.add_child(title)

	var description := Label.new()
	description.text = "EL CRIMEN CASI PERFECTO es un juego de detectives en primera persona con NPCs potenciados por un backend RAG + LLM.\n\nProyecto IDI — Construcción de Sistemas RAG."
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", COLOR_HOVER)
	vbox.add_child(description)

	var authors := Label.new()
	authors.text = "Autores:\nDamián Bicocchi, Valentin Ciamparella,\nLucas Corbalan Saez, Juan Tarrio"
	authors.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	authors.autowrap_mode = TextServer.AUTOWRAP_WORD
	authors.add_theme_font_size_override("font_size", 18)
	authors.add_theme_color_override("font_color", COLOR_TEXTO)
	vbox.add_child(authors)

	var back := Button.new()
	back.text = "Volver"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.add_theme_font_size_override("font_size", 18)
	back.add_theme_color_override("font_color", COLOR_ACENTO)
	back.mouse_entered.connect(back.grab_focus)
	back.pressed.connect(_hide_about_menu)
	vbox.add_child(_espaciador(4))
	vbox.add_child(back)


func _crear_briefing_overlay() -> void:
	_briefing_overlay = _crear_overlay()
	var vbox := _crear_panel(_briefing_overlay, 720)

	var title := Label.new()
	title.text = "El caso"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", COLOR_TEXTO)
	vbox.add_child(title)

	var description := Label.new()
	description.text = "La policía fue alertada por la muerte de la señora Stevens, una viuda adinerada de sesenta y ocho años, hallada sin vida en el comedor de su departamento. La puerta estaba asegurada por dentro y no había signos de violencia. La forense confirmó que se trató de una intoxicación, aunque todavía no sabe con qué sustancia.\n\nEse mismo día sus tres hermanos habían almorzado con ella. La policía citó a declarar a los principales sospechosos:\n\n- Juan, el mayor, en la comisaría.\n- Esteban, el del medio, en su oficina.\n- Pablo, el menor, en el laboratorio Erpa, donde trabaja.\n- La criada, que encontró el cuerpo, en el hall del edificio.\n\nTambién podés consultar a la forense, en el departamento; ella solo colabora con la investigación.\n\nVas a empezar en el mapa: elegí dónde investigar. Podés visitar el departamento (la escena del crimen), la comisaría, la oficina o el laboratorio, y volver al mapa desde la salida de cada lugar."
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	description.autowrap_mode = TextServer.AUTOWRAP_WORD
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", COLOR_HOVER)
	vbox.add_child(description)

	_briefing_button = Button.new()
	_briefing_button.text = "Continuar"
	_briefing_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_briefing_button.add_theme_font_size_override("font_size", 22)
	_briefing_button.add_theme_color_override("font_color", COLOR_TEXTO)
	_briefing_button.add_theme_color_override("font_hover_color", COLOR_HOVER)
	_briefing_button.pressed.connect(_on_briefing_continue)
	vbox.add_child(_espaciador(4))
	vbox.add_child(_briefing_button)


func _crear_vineta(canvas: CanvasLayer) -> void:
	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float vignette_intensity = 0.5;
uniform float vignette_radius = 0.75;
uniform float grain_amount = 0.08;
uniform float flicker_amount = 0.06;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float dist = distance(uv, vec2(0.5));
	float vignette = smoothstep(vignette_radius, vignette_radius - 0.4, dist);
	float vig_alpha = (1.0 - vignette) * vignette_intensity;
	float grain = rand(uv + fract(TIME)) * grain_amount;
	float flicker = (rand(vec2(TIME, TIME)) - 0.5) * flicker_amount;
	float darkness = vig_alpha + flicker;
	COLOR = vec4(vec3(grain), grain + darkness);
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	overlay.material = mat
	canvas.add_child(overlay)


func _on_jugar() -> void:
	_show_difficulty_menu()


func _on_salir() -> void:
	get_tree().quit()


func _on_about() -> void:
	if _about_overlay == null:
		return
	_about_overlay.visible = true


func _hide_about_menu() -> void:
	if _about_overlay == null:
		return
	_about_overlay.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_difficulty_menu() -> void:
	if _difficulty_overlay == null:
		return
	Global.reset_difficulty()
	_difficulty_overlay.visible = true
	if _difficulty_buttons.size() > 0:
		var first_button: Button = _difficulty_buttons[0]
		if is_instance_valid(first_button):
			first_button.grab_focus()


func _hide_difficulty_menu() -> void:
	if _difficulty_overlay == null:
		return
	_difficulty_overlay.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_difficulty_selected(profile: Dictionary) -> void:
	Global.set_difficulty(profile)
	_hide_difficulty_menu()
	_show_briefing()


func _show_briefing() -> void:
	if _briefing_overlay == null:
		return
	_briefing_overlay.visible = true
	if _briefing_button != null and is_instance_valid(_briefing_button):
		_briefing_button.grab_focus()


func _on_briefing_continue() -> void:
	if _briefing_overlay != null:
		_briefing_overlay.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_start_game()


func _start_game() -> void:
	get_tree().change_scene_to_file(ESCENA_INICIAL)
