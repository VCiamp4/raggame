extends Resource
class_name InspectableCatalog

# Catálogo central de elementos inspeccionables.
#
# Cada entrada se identifica por una clave (inspectable_id) y define:
#   display_name : título que aparece en el diálogo de inspección.
#   description  : texto que se muestra al inspeccionar.
#   clue_id      : (opcional) pista del EventCatalog que se activa al
#                  inspeccionar por primera vez. Debe coincidir con un id
#                  de data/events/events.gd. Usar "" si no dispara pista.
#
# Para agregar un elemento a una escena, se le asigna el script
# res://scenes/inspectable.gd y se escribe su inspectable_id en el export.

const INSPECTABLES: Dictionary = {
	"heladera": {
		"display_name": "Heladera",
		"description": "Una heladera común, pero en el freezer hay un olor raro, algo parece haberse podrido.",
		"clue_id": "",
	},
	"vaso_whisky": {
		"display_name": "Vaso de whisky",
		"description": "Sí, este es un vaso de whisky, pero el olor claramente indica que tiene algo malo.",
		"clue_id": "",
	},
	"archivero_grande": {
		"display_name": "Archivero grande",
		"description": "Solo papeles de cosas raras.",
		"clue_id": "",
	},
	"archivero_mediano": {
		"display_name": "Archivero",
		"description": "Entre los legajos aparece la póliza de vida original. Pablo, Esteban y Juan figuraban como beneficiarios en partes iguales.",
		"clue_id": "PI-GLO-05",
	},
	"pila_papeles": {
		"display_name": "Pila de papeles",
		"description": "No hay nada acá, solo hablan de nuevas políticas de seguros.",
		"clue_id": "",
	},
}


static func get_entry(inspectable_id: String) -> Dictionary:
	return INSPECTABLES.get(inspectable_id, {}).duplicate(true)


static func display_name(inspectable_id: String) -> String:
	var entry: Dictionary = INSPECTABLES.get(inspectable_id, {})
	return str(entry.get("display_name", inspectable_id))


static func description(inspectable_id: String) -> String:
	var entry: Dictionary = INSPECTABLES.get(inspectable_id, {})
	return str(entry.get("description", ""))


static func clue_id(inspectable_id: String) -> String:
	var entry: Dictionary = INSPECTABLES.get(inspectable_id, {})
	var clue = entry.get("clue_id", "")
	if clue == null:
		return ""
	return str(clue)
