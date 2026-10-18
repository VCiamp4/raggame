extends RefCounted

# Pruebas necesarias para acusar a cada sospechoso. Se usa con
# preload("res://data/accusations.gd").
#
# Cada prueba se cumple con cualquiera de sus hechos (fact_id del backend), y
# para acusar hacen falta EVIDENCE_NEEDED pruebas distintas: tres hechos sobre
# la misma pelea cuentan como una sola prueba.

const EVIDENCE_NEEDED := 2

const SUSPECTS: Dictionary = {
	"criada": {
		"name": "la criada",
		"evidence": [
			{"label": "La señora Stevens la trataba mal.", "facts": ["CL-CRI-01"]},
			{"label": "Le sirvió el vaso de whisky.", "facts": ["CL-CRI-06"]},
			{"label": "Fue la última en verla con vida.", "facts": ["CL-CRI-02"]},
		],
	},
	"juan": {
		"name": "Juan",
		"evidence": [
			{"label": "Se beneficia económicamente con la muerte.", "facts": ["CL-JUA-04", "CL-POL-03"]},
			{"label": "Cree que la señora Stevens lo delató con la policía por las drogas.", "facts": ["CL-JUA-02"]},
		],
	},
	"esteban": {
		"name": "Esteban",
		"evidence": [
			{"label": "Se peleó feo con la señora Stevens por el cambio de la póliza.", "facts": ["CL-EST-02"]},
			{"label": "Se beneficia económicamente con la muerte.", "facts": ["CL-EST-06", "CL-POL-03"]},
			{"label": "Gestionó el seguro de vida de la señora Stevens.", "facts": ["CL-POL-04"]},
		],
	},
	"pablo": {
		"name": "Pablo",
		"evidence": [
			{"label": "Es el que más se beneficia con la muerte.", "facts": ["CL-PAB-04", "CL-PAB-09", "CL-POL-03"]},
			{"label": "En Erpa, donde trabaja, había cianuro.", "facts": ["CL-ERP-01", "CL-ERP-02"]},
			{"label": "Arregló la heladera días antes del crimen: tuvo acceso al congelador.", "facts": ["CL-FRI-02", "CL-PAB-07"]},
		],
	},
}


# Textos de las pruebas contra el sospechoso que ya se descubrieron.
static func found_evidence(suspect_id: String, discovered: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	for item in SUSPECTS[suspect_id]["evidence"]:
		for fact_id in item["facts"]:
			if discovered.has(fact_id):
				found.append(item["label"])
				break
	return found


static func can_accuse(suspect_id: String, discovered: Dictionary) -> bool:
	return found_evidence(suspect_id, discovered).size() >= EVIDENCE_NEEDED

