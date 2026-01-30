"""Storage service for lecture data persistence."""
import json
import aiofiles
import os
from pathlib import Path
from typing import Optional

from ..config import settings


class StorageService:
    """Handles file-based storage for lectures, transcripts, and summaries."""
    
    def __init__(self):
        self.data_dir = settings.data_dir
        self.metadata_dir = self.data_dir / "metadata"
        self.transcripts_dir = self.data_dir / "transcripts"
        self.summaries_dir = self.data_dir / "summaries"
        
        # Ensure directories exist
        for dir_path in [self.metadata_dir, self.transcripts_dir, self.summaries_dir]:
            dir_path.mkdir(parents=True, exist_ok=True)
    
    def _metadata_path(self, lecture_id: str) -> Path:
        return self.metadata_dir / f"{lecture_id}.json"
    
    def _transcript_path(self, lecture_id: str) -> Path:
        return self.transcripts_dir / f"{lecture_id}.json"
    
    def _summary_path(self, lecture_id: str) -> Path:
        return self.summaries_dir / f"{lecture_id}.json"
    
    async def save_lecture_metadata(self, lecture_id: str, data: dict) -> None:
        """Save lecture metadata to file."""
        async with aiofiles.open(self._metadata_path(lecture_id), "w") as f:
            await f.write(json.dumps(data, ensure_ascii=False, indent=2))
    
    async def get_lecture_metadata(self, lecture_id: str) -> Optional[dict]:
        """Load lecture metadata from file."""
        path = self._metadata_path(lecture_id)
        if not path.exists():
            return None
        
        async with aiofiles.open(path, "r") as f:
            content = await f.read()
            return json.loads(content)
    
    async def update_lecture_metadata(self, lecture_id: str, updates: dict) -> None:
        """Update specific fields in lecture metadata."""
        data = await self.get_lecture_metadata(lecture_id)
        if data:
            data.update(updates)
            await self.save_lecture_metadata(lecture_id, data)
    
    async def update_lecture_status(self, lecture_id: str, status: str) -> None:
        """Update lecture processing status."""
        await self.update_lecture_metadata(lecture_id, {"status": status})
    
    async def list_lectures(self) -> list[dict]:
        """List all lectures."""
        lectures = []
        for path in self.metadata_dir.glob("*.json"):
            async with aiofiles.open(path, "r") as f:
                content = await f.read()
                lectures.append(json.loads(content))
        
        # Sort by created_at descending
        lectures.sort(key=lambda x: x.get("created_at", ""), reverse=True)
        return lectures
    
    async def save_transcript(self, lecture_id: str, transcript: dict) -> None:
        """Save transcript data."""
        async with aiofiles.open(self._transcript_path(lecture_id), "w") as f:
            await f.write(json.dumps(transcript, ensure_ascii=False, indent=2))
        
        # Update metadata to indicate transcript is available
        await self.update_lecture_metadata(lecture_id, {"has_transcript": True})
    
    async def get_transcript(self, lecture_id: str) -> Optional[dict]:
        """Load transcript data."""
        path = self._transcript_path(lecture_id)
        if not path.exists():
            return None
        
        async with aiofiles.open(path, "r") as f:
            content = await f.read()
            return json.loads(content)
    
    async def save_summary(self, lecture_id: str, summary: dict) -> None:
        """Save summary data."""
        async with aiofiles.open(self._summary_path(lecture_id), "w") as f:
            await f.write(json.dumps(summary, ensure_ascii=False, indent=2))
    
    async def get_summary(self, lecture_id: str) -> Optional[dict]:
        """Load summary data."""
        path = self._summary_path(lecture_id)
        if not path.exists():
            return None
        
        async with aiofiles.open(path, "r") as f:
            content = await f.read()
            return json.loads(content)
    
    async def delete_lecture(self, lecture_id: str) -> None:
        """Delete all data associated with a lecture."""
        # Delete metadata
        metadata_path = self._metadata_path(lecture_id)
        if metadata_path.exists():
            os.remove(metadata_path)
        
        # Delete transcript
        transcript_path = self._transcript_path(lecture_id)
        if transcript_path.exists():
            os.remove(transcript_path)
        
        # Delete summary
        summary_path = self._summary_path(lecture_id)
        if summary_path.exists():
            os.remove(summary_path)
        
        # Delete audio file
        for ext in [".mp3", ".wav", ".m4a", ".ogg", ".webm", ".flac"]:
            audio_path = settings.audio_dir / f"{lecture_id}{ext}"
            if audio_path.exists():
                os.remove(audio_path)
                break


# Global instance
storage_service = StorageService()
