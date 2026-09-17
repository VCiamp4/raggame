from dataclasses import dataclass


@dataclass
class Settings:
    chat_model: str = "gemma4:e4b"
    embedding_model: str = "hf.co/unsloth/embeddinggemma-300m-GGUF:Q4_0"
    ollama_url: str = "http://localhost:11434"
    max_chunks: int = 3
    min_similarity: float = 0.5
    max_history: int = 20
    num_predict: int = 160
    temperature: float = 0.8


settings = Settings()
