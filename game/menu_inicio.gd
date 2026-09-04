extends Node

# Ajustá a la escena por la que arranca el juego
const ESCENA_INICIAL = "res://scenes/mapa_menu.tscn"

# Paleta horror PSX
const COLOR_FONDO = Color("0a0a0c")
const COLOR_TEXTO = Color("c8c4b8")
const COLOR_ACENTO = Color("8b2b2b")
const COLOR_HOVER = Color("a8823c")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	# Fondo oscuro
	var bg = ColorRect.new()
	bg.color = COLOR_FONDO
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)
	
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
	canvas.add_child(titulo)
	
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
	canvas.add_child(subtitulo)
	
	# Botón Jugar
	var btn_jugar = _crear_boton("Jugar", 40)
	btn_jugar.pressed.connect(_on_jugar)
	canvas.add_child(btn_jugar)
	
	# Botón Salir
	var btn_salir = _crear_boton("Salir", 110)
	btn_salir.pressed.connect(_on_salir)
	canvas.add_child(btn_salir)
	
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
	_crear_vineta(canvas)


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
	get_tree().change_scene_to_file(ESCENA_INICIAL)


func _on_salir() -> void:
	get_tree().quit()
