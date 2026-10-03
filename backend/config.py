import os
from dataclasses import dataclass
from dotenv import load_dotenv

load_dotenv()

@dataclass
class Settings:
    chat_provider: str = os.getenv("CHAT_PROVIDER", "ollama")
    chat_model: str = os.getenv("CHAT_MODEL", "gemma4:e4b")
    openai_api_key: str = os.getenv("OPENAI_API_KEY", "")
    embedding_model: str = "qwen3-embedding:4b"
    ollama_url: str = "http://localhost:11434"
    max_chunks: int = 3
    min_similarity: float = 0.43
    max_history: int = 20
    num_predict: int = 160
    temperature: float = 0.8


settings = Settings()
