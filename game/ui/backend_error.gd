extends RefCounted

# Se usa con preload("res://ui/backend_error.gd"). Mensajes de error que ve el jugador.
# Si el turno falla, el backend manda su propio texto después de STREAM_MARKER;
# estos cubren lo que el juego detecta solo.

const CONTACT := "Si el problema sigue, avisale a Damián, Lucas, Valentín o Juan."
const OFFLINE := "No se pudo conectar con el servidor del juego. Puede que no se haya iniciado o que se haya cerrado."
const INTERRUPTED := "Se cortó la conexión con el servidor del juego mientras respondía."
const UNEXPECTED := "El servidor del juego respondió con un error inesperado (código %d)."

# Byte que separa el texto del NPC del mensaje de error del backend.
const STREAM_MARKER := 0x1e


# Parsea sin que el motor imprima un error si el cuerpo no es JSON (p. ej. una
# página HTML de otro servidor escuchando en el puerto del backend).
static func parse(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


# Mensaje para una respuesta con código de error ({"detail"} de FastAPI).
static func from_body(code: int, body: String) -> String:
	var data = parse(body)
	if data is Dictionary and data.get("detail") is String:
		return data["detail"]
	return UNEXPECTED % code


# Mensaje para un HTTPRequest fallido: sin conexión o con código de error.
static func from_request(result: int, code: int, body: PackedByteArray) -> String:
	if result != HTTPRequest.RESULT_SUCCESS:
		return OFFLINE
	return from_body(code, body.get_string_from_utf8())


static func with_contact(message: String) -> String:
	return message + "\n" + CONTACT
