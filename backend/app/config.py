"""Application configuration."""
import os

# Fix for Windows: Disable symlinks in HuggingFace cache (avoids WinError 1314)
os.environ["HF_HUB_DISABLE_SYMLINKS"] = "1"

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
    upload_dir: Path = Path("data/uploads")
    
    # ASR settings (скорость: small/base + cuda + beam_size=1)
    whisper_model: str = "large-v3"  # base, small, medium, large-v3 — меньше = быстрее
    whisper_device: str = "cpu"  # cuda — сильно быстрее при наличии GPU
    whisper_compute_type: str = "int8"  # float16 на cuda быстрее
    whisper_beam_size: int = 5  # 1 — быстрее, 5 — качество по умолчанию
    whisper_condition_on_previous_text: bool = False  # False — быстрее, меньше петлей
    
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
    
    # Database
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/lecture_assistant"
    
    # JWT
    jwt_secret: str = "change-me-in-production-use-env"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 7  # 7 days
    
    # Google OAuth (Web Client ID для проверки токена; Android Client ID опционально)
    google_client_id: str = ""
    google_android_client_id: str = ""
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"  # Ignore extra env vars like DEBUG


settings = Settings()

# Ensure directories exist
settings.audio_dir.mkdir(parents=True, exist_ok=True)
settings.chroma_dir.mkdir(parents=True, exist_ok=True)
settings.upload_dir.mkdir(parents=True, exist_ok=True)
