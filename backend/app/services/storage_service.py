"""Storage: PostgreSQL for lecture metadata, files for transcripts/summaries."""
import json
import aiofiles
import os
from pathlib import Path
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings
from ..db_models import Lecture


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

    @staticmethod
    def _lecture_to_dict(lecture: Lecture) -> dict:
        return {
            "id": lecture.id,
            "user_id": lecture.user_id,
            "title": lecture.title,
            "filename": lecture.filename,
            "audio_path": lecture.audio_path,
            "duration": lecture.duration,
            "language": lecture.language,
            "status": lecture.status,
            "has_transcript": lecture.has_transcript,
            "has_summary": lecture.has_summary,
            "error": lecture.error,
            "created_at": lecture.created_at.isoformat(),
        }

    async def save_lecture_metadata(
        self,
        lecture_id: str,
        user_id: str,
        data: dict,
        db: AsyncSession,
    ) -> None:
        """Create lecture row in DB."""
        lecture = Lecture(
            id=lecture_id,
            user_id=user_id,
            title=data["title"],
            filename=data["filename"],
            audio_path=data.get("audio_path"),
            language=data.get("language"),
            status=data.get("status", "pending"),
        )
        db.add(lecture)
        await db.commit()
        await db.refresh(lecture)

    async def get_lecture_metadata(
        self,
        lecture_id: str,
        db: AsyncSession,
    ) -> Optional[dict]:
        """Load lecture from DB."""
        result = await db.execute(select(Lecture).where(Lecture.id == lecture_id))
        lecture = result.scalar_one_or_none()
        if not lecture:
            return None
        return self._lecture_to_dict(lecture)

    async def update_lecture_metadata(
        self,
        lecture_id: str,
        updates: dict,
        db: AsyncSession,
    ) -> None:
        """Update lecture fields in DB."""
        result = await db.execute(select(Lecture).where(Lecture.id == lecture_id))
        lecture = result.scalar_one_or_none()
        if not lecture:
            return
        for key, value in updates.items():
            if hasattr(lecture, key):
                setattr(lecture, key, value)
        await db.commit()

    async def update_lecture_status(
        self,
        lecture_id: str,
        status: str,
        db: AsyncSession,
    ) -> None:
        await self.update_lecture_metadata(lecture_id, {"status": status}, db)

    async def list_lectures(self, user_id: str, db: AsyncSession) -> list[dict]:
        """List lectures for user."""
        result = await db.execute(
            select(Lecture).where(Lecture.user_id == user_id).order_by(Lecture.created_at.desc())
        )
        lectures = result.scalars().all()
        return [self._lecture_to_dict(l) for l in lectures]

    async def save_transcript(
        self,
        lecture_id: str,
        transcript: dict,
        db: AsyncSession,
    ) -> None:
        path = self._transcript_path(lecture_id)
        async with aiofiles.open(path, "w") as f:
            await f.write(json.dumps(transcript, ensure_ascii=False, indent=2))
        await self.update_lecture_metadata(lecture_id, {"has_transcript": True}, db)

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
            content = await f.read()
            return json.loads(content)

    async def delete_lecture(self, lecture_id: str, db: AsyncSession) -> None:
        """Delete lecture from DB and remove files."""
        result = await db.execute(select(Lecture).where(Lecture.id == lecture_id))
        lecture = result.scalar_one_or_none()
        if lecture:
            db.delete(lecture)
            await db.commit()
        for path in [self._transcript_path(lecture_id), self._summary_path(lecture_id)]:
            if path.exists():
                os.remove(path)
        for ext in [".mp3", ".wav", ".m4a", ".ogg", ".webm", ".flac"]:
            audio_path = settings.audio_dir / f"{lecture_id}{ext}"
            if audio_path.exists():
                os.remove(audio_path)
                break


storage_service = StorageService()
