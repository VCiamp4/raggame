extends Node

const EventCatalogResource = preload("res://data/events/events.gd")


# ============================================================
# EVENT MANAGER
# ============================================================
# Este objeto mantiene el estado global de los eventos/pistas
# descubiertos durante la partida.
#
# Como posteriormente lo vamos a registrar como "Autoload",
# podremos acceder desde cualquier script mediante:
#
#     EventManager.activate_event("seguro_de_vida")
#
# o:
#
#     EventManager.has_event("seguro_de_vida")
#
# De esta manera, no importa quién descubrió la pista:
#
#     - un NPC
#     - un objeto del mapa
#     - una interacción
#     - etc.
#
# Todos terminan activando el mismo evento.
# ============================================================


# ------------------------------------------------------------
# SEÑAL
# ------------------------------------------------------------
# Se emite cada vez que se activa un evento NUEVO.
#
# Otros objetos del juego podrán escuchar esta señal para
# reaccionar cuando el jugador descubre una pista.
#
# Por ejemplo:
#
# EventManager.event_activated.connect(_on_event_activated)
#
# y luego:
#
# func _on_event_activated(event_id):
#     print("Se descubrió: ", event_id)
#
# ------------------------------------------------------------

signal event_activated(event_id)


# ------------------------------------------------------------
# EVENTOS ACTIVADOS
# ------------------------------------------------------------
# Dictionary que contiene todos los eventos que el jugador
# descubrió durante la partida.
#
# Ejemplo:
#
# {
#     "seguro_de_vida": true,
#     "testamento": true
# }
#
# Si un evento NO aparece en el Dictionary, significa que
# todavía no fue descubierto.
# ------------------------------------------------------------

var activated_events: Dictionary = {}
var event_history: Array = []

# Índice fact_id → [clue_id, ...] construido desde los "facts" de cada pista
# en data/events/events.gd. Se usa para activar pistas cuando el RAG recupera
# el chunk/fact correspondiente (en vez de matchear keywords del texto).
var fact_clues: Dictionary = _build_fact_index()


# ============================================================
# ACTIVAR EVENTO
# ============================================================
# Activa un evento/pista.
#
# event_id:
#     Identificador único del evento.
#
# Ejemplo:
#
#     EventManager.activate_event("seguro_de_vida")
#
# ============================================================

func activate_event(event_id: String) -> void:

	# --------------------------------------------------------
	# Primero comprobamos si el evento ya había sido activado.
	#
	# Esto es importante porque una misma pista podría
	# descubrirse varias veces.
	#
	# Por ejemplo:
	#
	# 1. El jugador encuentra los papeles en un cajón.
	# 2. Después le pregunta a un NPC por el seguro de vida.
	#
	# Ambos caminos intentarán activar:
	#
	#     "seguro_de_vida"
	#
	# Pero nosotros queremos registrar el evento una sola vez.
	# --------------------------------------------------------

	if has_event(event_id):
		return


	# --------------------------------------------------------
	# Guardamos el evento como descubierto.
	# --------------------------------------------------------

	activated_events[event_id] = true
	event_history.append(event_id)


	# --------------------------------------------------------
	# Avisamos al resto del juego que se descubrió un evento.
	#
	# Esto permite que otros sistemas reaccionen sin tener que
	# estar preguntando constantemente si ocurrió algo.
	# --------------------------------------------------------

	event_activated.emit(event_id)


# ============================================================
# COMPROBAR SI UN EVENTO FUE ACTIVADO
# ============================================================
# Devuelve:
#
#     true  -> el jugador ya descubrió el evento.
#     false -> todavía no lo descubrió.
#
# Ejemplo:
#
#     if EventManager.has_event("seguro_de_vida"):
#         print("El jugador conoce el seguro de vida")
#
# ============================================================

func has_event(event_id: String) -> bool:

	return activated_events.has(event_id)


# ============================================================
# REINICIAR EVENTOS
# ============================================================
# Borra todos los eventos descubiertos.
#
# Esto nos puede servir cuando:
#
#     - empieza una partida nueva
#     - queremos reiniciar una investigación
#     - estamos haciendo pruebas
#
# Ejemplo:
#
#     EventManager.reset_events()
#
# ============================================================

func reset_events() -> void:

	activated_events.clear()
	event_history.clear()


func clue_info(event_id: String) -> Dictionary:
	return EventCatalogResource.get_clue(event_id)


func get_event_history() -> Array:
	return event_history.duplicate(true)


# ============================================================
# ACTIVAR PISTAS A PARTIR DE UN FACT DESCUBIERTO POR EL RAG
# ============================================================
# El backend devuelve en el header "X-Focus-Fact" el fact_id del chunk foco
# del turno. Acá lo traducimos a las pistas que declaran ese fact en
# data/events/events.gd y las activamos (una sola vez cada una).
#
# Ejemplo:
#
#     EventManager.activate_fact_clues("CL-POL-01")
#     -> activa "PI-EST-01" y muestra la notificación.
#
# ============================================================

func activate_fact_clues(fact_id: String) -> void:
	if fact_id == "":
		return
	var clue_ids: Array = fact_clues.get(fact_id, [])
	for clue_id in clue_ids:
		if not has_event(clue_id):
			activate_event(clue_id)
			NotificationManager.show_clue_notification(clue_id)


static func _build_fact_index() -> Dictionary:
	var map: Dictionary = {}
	var catalog: Dictionary = EventCatalog.get_clue_index()
	for clue_id in catalog.keys():
		var clue_data: Dictionary = catalog[clue_id]
		var facts: Array = clue_data.get("facts", [])
		for raw_fact in facts:
			var fact_id: String = str(raw_fact)
			if not map.has(fact_id):
				map[fact_id] = []
			map[fact_id].append(clue_id)
	return map
