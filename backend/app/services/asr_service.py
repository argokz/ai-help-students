"""ASR service using faster-whisper for speech-to-text."""
import asyncio
from typing import Optional
from functools import lru_cache

from ..config import settings


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
            
            self._model = WhisperModel(
                settings.whisper_model,
                device=settings.whisper_device,
                compute_type=settings.whisper_compute_type,
            )
        return self._model
    
    async def transcribe(
        self,
        audio_path: str,
        language: Optional[str] = None,
    ) -> dict:
        """
        Transcribe audio file to text with timestamps.
        
        Args:
            audio_path: Path to the audio file
            language: Optional language code (ru, kz, en) or None for auto-detect
            
        Returns:
            dict with:
                - segments: list of {start, end, text}
                - language: detected language
                - duration: total audio duration
        """
        async with self._model_lock:
            # Run in thread pool since faster-whisper is synchronous
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(
                None,
                self._transcribe_sync,
                audio_path,
                language
            )
            return result
    
    def _transcribe_sync(
        self,
        audio_path: str,
        language: Optional[str] = None,
    ) -> dict:
        """Synchronous transcription (runs in thread pool)."""
        # Map language codes
        lang_map = {
            "kz": "kk",  # Kazakh uses 'kk' in Whisper
            "kazakh": "kk",
        }
        
        whisper_lang = lang_map.get(language, language) if language else None
        
        # Transcribe
        segments_generator, info = self.model.transcribe(
            audio_path,
            language=whisper_lang,
            task="transcribe",
            vad_filter=True,  # Voice activity detection for better accuracy
            vad_parameters=dict(
                min_silence_duration_ms=500,
            ),
            word_timestamps=False,  # Segment-level is enough for MVP
        )
        
        # Collect segments
        segments = []
        for segment in segments_generator:
            segments.append({
                "start": round(segment.start, 2),
                "end": round(segment.end, 2),
                "text": segment.text.strip(),
            })
        
        # Calculate duration from last segment or info
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
