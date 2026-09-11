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
		"tagline": "Más margen para experimentar y pistas tempranas",
		"planned_effects": {
			"clue_window": 1.5,
			"npc_patience": 1.3,
			"llm_temperature_bias": -0.1
		}
	},
	{
		"id": "standard",
		"name": "Procedimiento",
		"label": "Medio",
		"tagline": "Equilibrio entre presión y descubrimiento",
		"planned_effects": {
			"clue_window": 1.0,
			"npc_patience": 1.0,
			"llm_temperature_bias": 0.0
		}
	},
	{
		"id": "hardcore",
		"name": "Contra reloj",
		"label": "Difícil",
		"tagline": "Claves estrictas, sospechosos menos tolerantes",
		"planned_effects": {
			"clue_window": 0.6,
			"npc_patience": 0.7,
			"llm_temperature_bias": 0.15
		}
	}
]

var _canvas: CanvasLayer
var _difficulty_overlay: Control
var _difficulty_buttons: Array = []


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
	titulo.text = "EL DEPARTAMENTO"  # provisorio, cambialo cuando tengas nombre
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
	subtitulo.text = "un caso sin resolver"
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
	
	# Botón Salir
	var btn_salir = _crear_boton("Salir", 110)
	btn_salir.pressed.connect(_on_salir)
	_canvas.add_child(btn_salir)
	
		# Audio de ambiente
	var ambiente := AudioStreamPlayer.new()
	var stream = load("res://audio/438135__craigsmith__g16-11-police-teletype-and-ambience.wav")
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ambiente.bus = "Music"
	ambiente.stream = stream
	ambiente.autoplay = true
	ambiente.volume_db = -20
	add_child(ambiente)
	
	# Viñeta (shader encima de todo)
	_crear_difficulty_overlay()
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
	_difficulty_overlay = ColorRect.new()
	_difficulty_overlay.color = Color(0, 0, 0, 0.88)
	_difficulty_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_difficulty_overlay.visible = false
	_difficulty_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.add_child(_difficulty_overlay)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -230
	panel.offset_bottom = 230
	panel.add_theme_constant_override("margin_left", 32)
	panel.add_theme_constant_override("margin_right", 32)
	panel.add_theme_constant_override("margin_top", 28)
	panel.add_theme_constant_override("margin_bottom", 28)
	_difficulty_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Seleccioná la dificultad"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", COLOR_TEXTO)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Los modos ajustarán pistas, paciencia y presión temporal cuando esas mecánicas estén listas."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", COLOR_HOVER)
	vbox.add_child(subtitle)

	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 10)
	vbox.add_child(options)
	_difficulty_buttons.clear()

	for profile in DIFFICULTY_PROFILES:
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var level_label: String = str(profile.get("label", ""))
		var display_name: String = str(profile.get("name", ""))
		var tagline: String = str(profile.get("tagline", ""))
		if level_label != "":
			btn.text = "%s  —  %s\n%s" % [display_name, level_label, tagline]
		else:
			btn.text = "%s\n%s" % [display_name, tagline]
		btn.add_theme_font_size_override("font_size", 20)
		btn.add_theme_color_override("font_color", COLOR_TEXTO)
		btn.add_theme_color_override("font_hover_color", COLOR_HOVER)
		btn.pressed.connect(func(): _on_difficulty_selected(profile))
		options.add_child(btn)
		_difficulty_buttons.append(btn)

	var cancel := Button.new()
	cancel.text = "Volver"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.add_theme_color_override("font_color", COLOR_ACENTO)
	cancel.pressed.connect(_hide_difficulty_menu)
	vbox.add_child(cancel)

	var note := Label.new()
	note.text = "Tip: podés cambiar la dificultad reiniciando la partida desde este menú."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", COLOR_TEXTO.darkened(0.4))
	vbox.add_child(note)


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
	_start_game()


func _start_game() -> void:
	get_tree().change_scene_to_file(ESCENA_INICIAL)
