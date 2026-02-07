"""ASR service using faster-whisper for speech-to-text."""
import asyncio
import logging
from typing import Callable, Optional
from ..config import settings
from .remote_asr_client import get_remote_client

logger = logging.getLogger(__name__)

class ASRService:
    """
    Speech-to-text service using faster-whisper.
    
    Supports Russian, Kazakh, and English languages.
    Returns segments with timestamps for each transcribed portion.
    """
    
    def __init__(self):
        self._model = None
        self._model_lock = asyncio.Lock()
    
    @property
    def model(self):
        """Lazy load the Whisper model."""
        if self._model is None:
            from faster_whisper import WhisperModel
            
            logger.info(f"Loading Whisper model: {settings.whisper_model} on {settings.whisper_device}")
            self._model = WhisperModel(
                settings.whisper_model,
                device=settings.whisper_device,
                compute_type=settings.whisper_compute_type,
            )
            logger.info("Whisper model loaded successfully")
        return self._model
    
    async def transcribe(
        self,
        audio_path: str,
        language: Optional[str] = None,
        total_duration: Optional[float] = None,
        progress_callback: Optional[object] = None,  # Callable[[float], None]
    ) -> dict:
        """
        Transcribe audio file to text with timestamps.
        
        Tries to use remote worker (GPU) if available, falls back to local processing.
        
        Args:
            audio_path: Path to the audio file
            language: Optional language code (ru, kz, en) or None for auto-detect
            total_duration: Total audio duration in seconds (for progress, from mutagen)
            progress_callback: Optional callable(progress 0.0–1.0), called from sync code
            
        Returns:
            dict with segments, language, duration
        """
        # Try remote worker first if enabled
        if settings.whisper_use_remote:
            remote_client = get_remote_client()
            if remote_client:
                try:
                    # Check if worker is available (responds to requests)
                    is_available = await remote_client.check_health()
                    if is_available:
                        logger.info(f"Using remote worker for transcription: {audio_path}")
                        try:
                            result = await remote_client.transcribe(audio_path, language)
                            
                            # Simulate progress if callback provided (remote doesn't support real-time progress)
                            if progress_callback and total_duration:
                                try:
                                    progress_callback(1.0)  # Mark as complete
                                except Exception:
                                    pass
                            
                            return result
                        except Exception as transcribe_error:
                            logger.error(f"Remote transcription failed: {transcribe_error}, falling back to local")
                            # Fall through to local transcription
                    else:
                        logger.warning("Remote worker is not available, falling back to local")
                except Exception as e:
                    logger.warning(f"Remote worker check failed: {e}, falling back to local")
        
        # Fallback to local transcription
        logger.info(f"Using local transcription: {audio_path}")
        async with self._model_lock:
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(
                None,
                self._transcribe_sync,
                audio_path,
                language,
                total_duration,
                progress_callback,
            )
            return result
    
    def _transcribe_sync(
        self,
        audio_path: str,
        language: Optional[str] = None,
        total_duration: Optional[float] = None,
        progress_callback: Optional[Callable[[float], None]] = None,
    ) -> dict:
        """Synchronous transcription (runs in thread pool)."""
        lang_map = {
            "kz": "kk",
            "kazakh": "kk",
        }
        whisper_lang = lang_map.get(language, language) if language else None

        segments_generator, info = self.model.transcribe(
            audio_path,
            language=whisper_lang,
            task="transcribe",
            beam_size=settings.whisper_beam_size,
            condition_on_previous_text=settings.whisper_condition_on_previous_text,
            vad_filter=True,
            vad_parameters=dict(min_silence_duration_ms=2000),
            word_timestamps=False,
        )

        segments = []
        for segment in segments_generator:
            segments.append({
                "start": round(segment.start, 2),
                "end": round(segment.end, 2),
                "text": segment.text.strip(),
            })
            if progress_callback and total_duration and total_duration > 0:
                progress = min(1.0, segment.end / total_duration)
                try:
                    progress_callback(progress)
                except Exception:
                    pass

        duration = segments[-1]["end"] if segments else 0
        return {
            "segments": segments,
            "language": info.language,
            "duration": duration,
            "language_probability": round(info.language_probability, 2),
        }
    
    async def get_supported_languages(self) -> list[dict]:
        """Get list of supported languages."""
        return [
            {"code": "ru", "name": "Русский"},
            {"code": "kz", "name": "Қазақша"},
            {"code": "en", "name": "English"},
        ]


# Global instance
asr_service = ASRService()
