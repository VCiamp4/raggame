extends CanvasLayer

const NOTEBOOK_URL = "http://127.0.0.1:8000/notebook/"
const TYPEWRITER = preload("res://assets/ui/fonts/SpecialElite.ttf")
const HANDWRITING = preload("res://assets/ui/fonts/Zeyada.ttf")
const HAND_SIZE = 22
const LINE = 30  # alto del renglón de la ficha
const RED = Color("b8433c")
const INK = Color("222222")

# Una hoja por personaje. Cada pista va a la hoja de quien trata, según el
# prefijo de su fact_id (CL-PAB-02 -> "PAB").
const PAGES = [
	{"id": "caso", "name": "Sra. Stevens", "role": "La víctima", "prefixes": ["CASE", "POL", "FRI", "ERP", "RES"]},
	{"id": "criada", "name": "La criada", "role": "Empleada de la víctima", "prefixes": ["CRI"]},
	{"id": "portero", "name": "El portero", "role": "Portero del edificio", "prefixes": ["POR"]},
	{"id": "juan", "name": "Juan", "role": "Hermano mayor", "prefixes": ["JUA"]},
	{"id": "esteban", "name": "Esteban", "role": "Hermano de la víctima", "prefixes": ["EST"]},
	{"id": "pablo", "name": "Pablo", "role": "Hermano menor", "prefixes": ["PAB"]},
	{"id": "quimico", "name": "El químico", "role": "Perito forense", "prefixes": ["FOR", "ICE"]},
	{"id": "tecnico", "name": "El técnico", "role": "Técnico de heladeras", "prefixes": ["TEC"]},
]

var folder: Control
var photo: TextureRect
var caption: Label
var name_label: Label
var role_label: Label
var clues_label: Label
var page_label: Label
var prev_button: Button
var next_button: Button
var http: HTTPRequest

var pages: Array = []  # [{page, clues}] solo las hojas con alguna pista
var current := 0


func _ready() -> void:
	# Ícono de la libreta (render del libro del pack PSX)
	var icon := TextureButton.new()
	icon.texture_normal = preload("res://assets/ui/libreta.png")
	icon.ignore_texture_size = true
	icon.stretch_mode = TextureButton.STRETCH_SCALE
	icon.tooltip_text = "Libreta"
	icon.offset_left = 12
	icon.offset_right = 108
	icon.offset_top = 12
	icon.offset_bottom = 108
	icon.pressed.connect(_toggle)
	add_child(icon)

	# Carpeta manila con la solapa del expediente
	folder = Control.new()
	folder.offset_left = 20
	folder.offset_right = 440
	folder.anchor_bottom = 1
	folder.offset_top = 112
	folder.offset_bottom = -20
	add_child(folder)
	folder.hide()
	folder.add_child(_panel(Color("c9a263"), true))

	var tab := _panel(Color("c9a263"), false)
	tab.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tab.position = Vector2(230, -22)
	tab.size = Vector2(170, 24)
	(tab.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_left = 6
	(tab.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_right = 6
	folder.add_child(tab)
	folder.add_child(_label("EXP. N.° 1147", TYPEWRITER, 14, Color("3b2a14"), Vector2(248, -20), Vector2(150, 22)))

	# Ficha rayada, apenas torcida sobre la carpeta
	var card := Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.offset_left = 18
	card.offset_top = 22
	card.offset_right = -18
	card.offset_bottom = -22
	card.rotation_degrees = -1.2
	card.resized.connect(func(): card.pivot_offset = card.size / 2)
	folder.add_child(card)
	card.add_child(_panel(Color("f7f4ea"), true))

	var rule := Control.new()
	rule.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rule.draw.connect(func(): rule.draw_line(Vector2(0, 160), Vector2(rule.size.x, 160), RED, 2))
	card.add_child(rule)

	# Encabezado tipeado
	card.add_child(_label("CASO STEVENS", TYPEWRITER, 13, Color("6b6b6b"), Vector2(150, 18), Vector2(220, 20)))
	name_label = _label("", TYPEWRITER, 20, INK, Vector2(150, 38), Vector2(220, 28))
	card.add_child(name_label)
	role_label = _label("", TYPEWRITER, 13, INK, Vector2(150, 68), Vector2(220, 20))
	card.add_child(role_label)
	var stamp := _label("CONFIDENCIAL", TYPEWRITER, 15, Color(RED, 0.8), Vector2(170, 112), Vector2(140, 24))
	stamp.rotation_degrees = -8
	card.add_child(stamp)

	# Polaroid pegada con cinta
	var polaroid := Control.new()
	polaroid.position = Vector2(14, 12)
	polaroid.size = Vector2(118, 138)
	polaroid.pivot_offset = polaroid.size / 2
	polaroid.rotation_degrees = -3
	card.add_child(polaroid)
	polaroid.add_child(_panel(Color("fbfaf5"), true))
	photo = TextureRect.new()
	photo.position = Vector2(8, 8)
	photo.size = Vector2(102, 102)
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	polaroid.add_child(photo)
	caption = _label("", HANDWRITING, 20, Color("1c2640"), Vector2(8, 108), Vector2(102, 28))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	polaroid.add_child(caption)
	var tape := ColorRect.new()
	tape.color = Color(0.93, 0.9, 0.78, 0.75)
	tape.position = Vector2(38, -8)
	tape.size = Vector2(42, 16)
	tape.rotation_degrees = 4
	polaroid.add_child(tape)

	# Renglones con las pistas (los renglones se desplazan junto con el texto)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 166
	scroll.offset_bottom = -44
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)

	var ruled := PanelContainer.new()
	ruled.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	ruled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ruled.size_flags_vertical = Control.SIZE_EXPAND_FILL  # renglones hasta el pie de la ficha
	var first_line := HANDWRITING.get_ascent(HAND_SIZE) + 6
	ruled.draw.connect(func():
		var y := first_line
		while y < ruled.size.y:
			ruled.draw_line(Vector2(0, y), Vector2(ruled.size.x, y), Color("a9c1dd"), 1)
			y += LINE)
	scroll.add_child(ruled)

	clues_label = _label("", HANDWRITING, HAND_SIZE, Color("151515"), Vector2.ZERO, Vector2.ZERO)
	clues_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clues_label.add_theme_constant_override("line_spacing", LINE - int(HANDWRITING.get_height(HAND_SIZE)))
	clues_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_child(clues_label)
	ruled.add_child(margin)

	# Pie: cambiar de hoja
	var nav := HBoxContainer.new()
	nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_top = -40
	nav.offset_bottom = -6
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 18)
	card.add_child(nav)
	prev_button = _nav_button("<", -1)
	nav.add_child(prev_button)
	page_label = _label("", TYPEWRITER, 15, INK, Vector2.ZERO, Vector2.ZERO)
	nav.add_child(page_label)
	next_button = _nav_button(">", 1)
	nav.add_child(next_button)

	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_clues_received)


func _panel(color: Color, shadow: bool) -> Panel:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	if shadow:
		style.shadow_color = Color(0, 0, 0, 0.45)
		style.shadow_size = 8
		style.shadow_offset = Vector2(4, 5)
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(text: String, font: Font, font_size: int, color: Color, pos: Vector2, label_size: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = label_size
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _nav_button(text: String, step: int) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.add_theme_font_override("font", TYPEWRITER)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", RED)
	button.pressed.connect(func(): _show_page(current + step))
	return button


func _toggle() -> void:
	if folder.visible:
		folder.hide()
		return
	folder.show()
	_show_message("Revisando el expediente...")
	http.request(NOTEBOOK_URL + Global.session_id)


func _on_clues_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_show_message("No se pudo abrir el expediente: el servidor no responde.")
		return
	var clues: Array = JSON.parse_string(body.get_string_from_utf8())["clues"]
	pages = []
	for page in PAGES:
		var texts := PackedStringArray()
		for clue in clues:
			if clue["fact_id"].split("-")[1] in page["prefixes"]:
				texts.append("- " + clue["text"])
		if not texts.is_empty():
			pages.append({"page": page, "clues": "\n".join(texts)})
	if pages.is_empty():
		_show_message("Todavía no anotaste ninguna pista.")
		return
	_show_page(0)


func _show_message(text: String) -> void:
	pages = [{"page": PAGES[0], "clues": text}]
	_show_page(0)


func _show_page(index: int) -> void:
	current = index
	var page: Dictionary = pages[index]["page"]
	photo.texture = load("res://assets/ui/retratos/%s.png" % page["id"])
	caption.text = page["name"]
	name_label.text = page["name"].to_upper()
	role_label.text = page["role"]
	clues_label.text = pages[index]["clues"]
	page_label.text = "%d / %d" % [index + 1, pages.size()]
	prev_button.disabled = index == 0
	next_button.disabled = index == pages.size() - 1
