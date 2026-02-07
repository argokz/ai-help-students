"""Remote ASR client for sending transcription tasks to GPU worker."""
import logging
import aiohttp
from typing import Optional
from pathlib import Path

from ..config import settings

logger = logging.getLogger(__name__)


class RemoteASRClient:
    """Client for remote Whisper worker service."""
    
    def __init__(self, worker_url: str):
        """
        Initialize remote ASR client.
        
        Args:
            worker_url: Base URL of the worker service (e.g., http://100.115.128.128:8004)
        """
        self.worker_url = worker_url.rstrip('/')
        self.timeout = aiohttp.ClientTimeout(total=3600)  # 1 hour timeout for long files
    
    async def check_health(self) -> bool:
        """Check if worker is available."""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    f"{self.worker_url}/health",
                    timeout=aiohttp.ClientTimeout(total=5)
                ) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        return data.get("status") == "healthy"
                    return False
        except Exception as e:
            logger.debug(f"Worker health check failed: {e}")
            return False
    
    async def transcribe(
        self,
        audio_path: str,
        language: Optional[str] = None,
    ) -> dict:
        """
        Transcribe audio file using remote worker.
        
        Args:
            audio_path: Path to audio file
            language: Optional language code (ru, kz, en)
            
        Returns:
            dict with segments, language, duration, language_probability
        """
        import aiofiles
        
        if not Path(audio_path).exists():
            raise FileNotFoundError(f"Audio file not found: {audio_path}")
        
        # Читаем файл
        async with aiofiles.open(audio_path, "rb") as f:
            file_data = await f.read()
        
        # Определяем MIME type
        suffix = Path(audio_path).suffix.lower()
        mime_types = {
            ".mp3": "audio/mpeg",
            ".wav": "audio/wav",
            ".m4a": "audio/mp4",
            ".ogg": "audio/ogg",
            ".flac": "audio/flac",
        }
        content_type = mime_types.get(suffix, "audio/mpeg")
        
        # Подготавливаем данные для multipart/form-data
        data = aiohttp.FormData()
        data.add_field(
            'file',
            file_data,
            filename=Path(audio_path).name,
            content_type=content_type
        )
        
        if language:
            data.add_field('language', language)
        
        logger.info(f"Sending transcription request to {self.worker_url} for {audio_path}")
        
        try:
            async with aiohttp.ClientSession(timeout=self.timeout) as session:
                async with session.post(
                    f"{self.worker_url}/transcribe",
                    data=data,
                ) as resp:
                    if resp.status != 200:
                        error_text = await resp.text()
                        raise Exception(f"Worker returned status {resp.status}: {error_text}")
                    
                    result = await resp.json()
                    
                    if result.get("status") == "error":
                        error = result.get("error", "Unknown error")
                        raise Exception(f"Worker transcription error: {error}")
                    
                    return {
                        "segments": result.get("segments", []),
                        "language": result.get("language", ""),
                        "duration": result.get("duration", 0.0),
                        "language_probability": result.get("language_probability", 0.0),
                    }
        except aiohttp.ClientError as e:
            logger.error(f"Network error communicating with worker: {e}")
            raise Exception(f"Failed to communicate with worker: {e}")
        except Exception as e:
            logger.error(f"Error in remote transcription: {e}")
            raise


# Global instance (will be initialized if worker_url is set)
remote_asr_client: Optional[RemoteASRClient] = None


def get_remote_client() -> Optional[RemoteASRClient]:
    """Get remote ASR client if configured."""
    global remote_asr_client
    
    if not settings.whisper_worker_url:
        return None
    
    if remote_asr_client is None:
        remote_asr_client = RemoteASRClient(settings.whisper_worker_url)
    
    return remote_asr_client

