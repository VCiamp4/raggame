extends RefCounted

# Acciones narradas antes de que un NPC responda. Se usa con
# preload("res://data/beats.gd").
#
# Si la respuesta debería revelar uno de estos hechos (header X-Focus-Fact), el
# chat muestra el texto y espera BEAT_SECONDS antes de mostrar lo que dice el NPC.

const BEAT_SECONDS := 4.5

const BEATS: Dictionary = {
	"CL-ICE-03": "(La forense se queda pensando: el hielo nunca se lo entregaron, así que nunca lo analizó. Saca una muestra de las cubeteras y la analiza en silencio...)",
}


# Texto de la primera acción que corresponde a esos hechos, o "" si ninguna.
static func for_facts(facts: PackedStringArray) -> String:
	for fact_id in facts:
		if BEATS.has(fact_id):
			return BEATS[fact_id]
	return ""
