"""Application configuration."""
from pydantic_settings import BaseSettings
from pathlib import Path


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""
    
    # App settings
    app_name: str = "Lecture Assistant API"
    app_debug: bool = True  # Renamed to avoid conflict with system DEBUG env var
    
    # API settings
    api_prefix: str = "/api"
    
    # Storage paths
    data_dir: Path = Path("data")
    audio_dir: Path = Path("data/audio")
    chroma_dir: Path = Path("data/chroma")
    
    # ASR settings
    whisper_model: str = "medium"  # small, medium, large-v3
    whisper_device: str = "cpu"  # cpu or cuda
    whisper_compute_type: str = "int8"  # float16, int8
    
    # Embedding settings
    embedding_model: str = "sentence-transformers/paraphrase-multilingual-mpnet-base-v2"
    
    # LLM settings
    llm_provider: str = "gemini"  # "gemini" or "openai"
    
    # Gemini settings
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-flash"
    
    # OpenAI settings (optional)
    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"
    
    # Chunking settings
    chunk_size: int = 400  # words
    chunk_overlap: int = 50  # words
    
    # Redis settings (for Celery)
    redis_url: str = "redis://localhost:6379/0"
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"  # Ignore extra env vars like DEBUG


settings = Settings()

# Ensure directories exist
settings.audio_dir.mkdir(parents=True, exist_ok=True)
settings.chroma_dir.mkdir(parents=True, exist_ok=True)
