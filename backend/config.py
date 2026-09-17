from dataclasses import dataclass


@dataclass
class Settings:
    chat_model: str = "gemma4:e4b"
    embedding_model: str = "qwen3-embedding:4b"
    ollama_url: str = "http://localhost:11434"
    max_chunks: int = 3
    min_similarity: float = 0.43
    max_history: int = 20
    num_predict: int = 160
    temperature: float = 0.8


settings = Settings()
