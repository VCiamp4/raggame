extends Node


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