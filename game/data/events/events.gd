extends Resource
class_name EventCatalog

const CHARACTER_CLUES := {
	"Criada": [
		{
			"id": "PI-CRI-01",
			"summary": "La señora Stevens maltrataba y humillaba a la criada de forma constante.",
			"keywords": ["maltrato", "abusaba", "humillaba", "patrona", "criada"],
			"facts": ["CL-CRI-01"],
		},
		{
			"id": "PI-CRI-02",
			"summary": "La criada sirvió el whisky y fue la última persona que vio viva a Stevens.",
			"keywords": ["sirvió el whisky", "última en verla", "vaso", "pedido", "diario"],
			"facts": ["CL-CRI-02"],
		},
	],
	"Juan": [
		{
			"id": "PI-JUA-01",
			"summary": "Juan guardaba un rencor profundo porque atribuye a Stevens su condena por drogas.",
			"keywords": ["rencor", "condena", "drogas", "odio", "delató"],
			"facts": ["CL-JUA-01", "CL-JUA-02"],
		},
		{
			"id": "PI-JUA-02",
			"summary": "Juan esperaba cobrar parte de la póliza de vida tras la muerte de su hermana.",
			"keywords": ["beneficio", "póliza", "herencia", "25%", "cobrar"],
			"facts": ["CL-JUA-04"],
		},
	],
	"Esteban": [
		{
			"id": "PI-EST-01",
			"summary": "Esteban gestionó el seguro de vida de Stevens y conocía cada cláusula.",
			"keywords": ["gestioné", "seguro de vida", "póliza", "corredor", "documento"],
			"facts": ["CL-POL-01"],
		},
		{
			"id": "PI-EST-02",
			"summary": "Esteban salió furioso del almuerzo al descubrir el favoritismo hacia Pablo.",
			"keywords": ["salí furioso", "discusión", "favoritismo", "pelea", "almuerzo"],
			"facts": ["CL-EST-01"],
		},
		{
			"id": "PI-EST-03",
			"summary": "Esteban también se beneficiaba económicamente de la póliza.",
			"keywords": ["beneficio", "25%", "cobrar", "participación", "seguro"],
			"facts": ["CL-EST-04"],
		},
	],
	"Pablo": [
		{
			"id": "PI-PAB-01",
			"summary": "Pablo trabajaba con químicos en Erpa y tenía acceso habitual a reactivos.",
			"keywords": ["Erpa", "laboratorio", "químicos", "reactivos", "trabajo"],
			"facts": ["CL-PAB-03", "CL-PAB-08"],
		},
		{
			"id": "PI-PAB-02",
			"summary": "Pablo consiguió que Stevens le dejara la mitad de la herencia.",
			"keywords": ["mitad", "favoritismo", "manipuló", "herencia", "póliza"],
			"facts": ["CL-PAB-04"],
		},
		{
			"id": "PI-PAB-03",
			"summary": "Pablo reparó la heladera días antes del crimen, con acceso al congelador.",
			"keywords": ["reparé la heladera", "fusible", "congelador", "arreglo", "cubeteras"],
			"facts": ["CL-FRI-02"],
		},
		{
			"id": "PI-PAB-04",
			"summary": "En Erpa se encontró cianuro entre los reactivos que Pablo podía manipular.",
			"keywords": ["cianuro", "Erpa", "reactivos controlados", "laboratorio", "veneno"],
			"facts": ["CL-ERP-01"],
		},
	],
}

const GLOBAL_CLUES := {
	"PI-GLO-01": {
		"summary": "Los líquidos de la casa estaban limpios.",
		"keywords": ["botellas limpias", "sin veneno", "whisky limpio"],
		"facts": ["CL-FOR-02"],
	},
	"PI-GLO-02": {
		"summary": "El veneno estaba en el hielo.",
		"keywords": ["hielo", "cianuro", "cubitos"],
		"facts": ["CL-ICE-03"],
	},
	"PI-GLO-03": {
		"summary": "La avería de la heladera era solamente un fusible.",
		"keywords": ["fusible", "avería", "técnico", "heladera"],
		"facts": ["CL-TEC-01", "CL-TEC-02"],
	},
	"PI-GLO-04": {
		"summary": "Nadie visitó a Stevens después de las 19:10.",
		"keywords": ["portero", "diario", "nadie subió"],
		"facts": ["CL-POR-01", "CL-POR-02"],
	},
}

static var CLUE_INDEX: Dictionary = _build_index()

static func _build_index() -> Dictionary:
	var dict: Dictionary = {}
	for character in CHARACTER_CLUES.keys():
		for clue in CHARACTER_CLUES[character]:
			var data: Dictionary = clue.duplicate(true)
			data["character"] = character
			dict[data["id"]] = data
	for clue_id in GLOBAL_CLUES.keys():
		var global_data: Dictionary = GLOBAL_CLUES[clue_id].duplicate(true)
		global_data["character"] = null
		global_data["id"] = clue_id
		dict[clue_id] = global_data
	return dict

static func get_clue(clue_id: String) -> Dictionary:
	return CLUE_INDEX.get(clue_id, {}).duplicate(true)

static func clues_for_character(character_name: String) -> Array:
	return CHARACTER_CLUES.get(character_name, []).duplicate(true)

static func character_for_clue(clue_id: String) -> String:
	var data: Dictionary = CLUE_INDEX.get(clue_id, {})
	return data.get("character", "")

static func get_clue_index() -> Dictionary:
	return CLUE_INDEX
