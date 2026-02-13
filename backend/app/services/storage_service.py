"""Storage: PostgreSQL for lecture metadata, files for transcripts/summaries."""
import json
import aiofiles
import os
from pathlib import Path
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings


class StorageService:
    """Lecture metadata in DB, transcript/summary in files."""

    def __init__(self):
        self.data_dir = settings.data_dir
        self.transcripts_dir = self.data_dir / "transcripts"
        self.summaries_dir = self.data_dir / "summaries"
        for dir_path in [self.transcripts_dir, self.summaries_dir]:
            dir_path.mkdir(parents=True, exist_ok=True)

    def _transcript_path(self, lecture_id: str) -> Path:
        return self.transcripts_dir / f"{lecture_id}.json"

    def _summary_path(self, lecture_id: str) -> Path:
        return self.summaries_dir / f"{lecture_id}.json"

    async def search_lectures(
        self,
        user_id: str,
        query: str,
        db: AsyncSession,
        subject: Optional[str] = None,
        group_name: Optional[str] = None,
        limit: int = 50,
    ) -> list[dict]:
        """
        Smart search: title and transcript text.
        
        Note: This method combines DB search (titles) and File search (transcripts).
        It might be better moved to a "SearchService" or kept here if we consider unique hybrid logic.
        For now, we import repository here to avoid circular imports in main routers.
        """
        from .lectures_repo import lectures_repo
        
        if not query or not query.strip():
            return []
            
        q_lower = query.strip().lower()
        lectures = await lectures_repo.list(user_id, db, subject=subject, group_name=group_name)
        out = []
        
        for l in lectures:
            if l.get("status") != "completed":
                if q_lower in (l.get("title") or "").lower():
                    out.append({
                        **l,
                        "snippet": None,
                        "match_in": "title",
                    })
                continue
                
            title_match = q_lower in (l.get("title") or "").lower()
            full_text = ""
            transcript = await self.get_transcript(l["id"])
            if transcript and transcript.get("segments"):
                full_text = " ".join(s.get("text", "") for s in transcript["segments"])
                
            text_match = q_lower in full_text.lower() if full_text else False
            
            if not title_match and not text_match:
                continue
                
            snippet = None
            match_in = "title" if title_match else "transcript"
            
            if text_match and full_text:
                pos = full_text.lower().find(q_lower)
                start = max(0, pos - 80)
                end = min(len(full_text), pos + len(query) + 120)
                snippet = (full_text[start:end] + "…") if end < len(full_text) else full_text[start:end]
                snippet = snippet.strip()
                
            out.append({
                **l,
                "snippet": snippet,
                "match_in": match_in,
            })
            
            if len(out) >= limit:
                break
                
        return out

    async def save_transcript(
        self,
        lecture_id: str,
        transcript: dict,
    ) -> None:
        path = self._transcript_path(lecture_id)
        async with aiofiles.open(path, "w") as f:
            await f.write(json.dumps(transcript, ensure_ascii=False, indent=2))

    async def get_transcript(self, lecture_id: str) -> Optional[dict]:
        path = self._transcript_path(lecture_id)
        if not path.exists():
            return None
        async with aiofiles.open(path, "r") as f:
            content = await f.read()
            return json.loads(content)

    async def save_summary(self, lecture_id: str, summary: dict) -> None:
        path = self._summary_path(lecture_id)
        async with aiofiles.open(path, "w") as f:
            await f.write(json.dumps(summary, ensure_ascii=False, indent=2))

    async def get_summary(self, lecture_id: str) -> Optional[dict]:
        path = self._summary_path(lecture_id)
        if not path.exists():
            return None
        async with aiofiles.open(path, "r") as f:
            content = (await f.read()).strip()
        if not content:
            return None
        try:
            return json.loads(content)
        except json.JSONDecodeError:
            return None

    async def delete_lecture_files(self, lecture_id: str) -> None:
        """Remove files associated with lecture."""
        for path in [self._transcript_path(lecture_id), self._summary_path(lecture_id)]:
            if path.exists():
                try:
                    os.remove(path)
                except OSError:
                    pass
                    
        for ext in [".mp3", ".wav", ".m4a", ".ogg", ".webm", ".flac"]:
            audio_path = settings.audio_dir / f"{lecture_id}{ext}"
            if audio_path.exists():
                try:
                    os.remove(audio_path)
                except OSError:
                    pass
                break


storage_service = StorageService()
