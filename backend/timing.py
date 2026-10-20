import logging
import time


# Logs de tiempos del pipeline (recuperación, embeddings, chat). Pensados para
# ver qué cuesta más en cada turno. Formato fácil de grepear:
#   14:32:05 [timing] embedding: 812 ms | modelo=qwen3-embedding:4b | load_s=0.71
logger = logging.getLogger("raggame.timing")
if not logger.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(
        logging.Formatter("%(asctime)s [timing] %(message)s", "%H:%M:%S")
    )
    logger.addHandler(_handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False

NS_PER_SECOND = 1_000_000_000
# Ollama reporta un load_duration chico (unos pocos ms) aunque el modelo ya
# esté en memoria. Por debajo de este umbral lo contamos como 0 ("ya cargado").
LOADED_THRESHOLD_SECONDS = 0.05


def log_timing(label: str, seconds: float, **fields) -> None:
    """
    Escribe una línea de tiempo en milisegundos, con campos extra opcionales.
    """
    message = f"{label}: {seconds * 1000:.0f} ms"
    for key, value in fields.items():
        message += f" | {key}={value}"
    logger.info(message)


def log_milestone(label: str, seconds: float, **fields) -> None:
    """
    Como log_timing, pero con un formato que resalta en el archivo de logs.
    """
    message = f"==== {label}: {seconds * 1000:.0f} ms"
    for key, value in fields.items():
        message += f" | {key}={value}"
    logger.info(message + " ====")


def ollama_load_seconds(data: dict) -> float:
    """
    Tiempo que Ollama tardó en cargar el modelo en memoria (segundos). Devuelve
    0 si el modelo ya estaba cargado cuando llegó el pedido.
    """
    load = data.get("load_duration", 0) / NS_PER_SECOND
    return 0.0 if load < LOADED_THRESHOLD_SECONDS else load


def now() -> float:
    return time.perf_counter()
