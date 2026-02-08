"""Storage: PostgreSQL for lecture metadata, files for transcripts/summaries."""
import json
import aiofiles
import os
from pathlib import Path
from typing import Optional

from sqlalchemy import select, distinct
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
            "processing_progress": lecture.processing_progress,
            "subject": lecture.subject,
            "group_name": lecture.group_name,
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
            subject=data.get("subject"),
            group_name=data.get("group_name"),
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

    async def get_incomplete_lectures(self, db: AsyncSession) -> list[dict]:
        """Получить все лекции со статусом pending или processing для восстановления после перезагрузки."""
        result = await db.execute(
            select(Lecture).where(
                Lecture.status.in_(["pending", "processing"])
            )
        )
        lectures = result.scalars().all()
        return [self._lecture_to_dict(l) for l in lectures]

    async def list_lectures(
        self,
        user_id: str,
        db: AsyncSession,
        subject: Optional[str] = None,
        group_name: Optional[str] = None,
    ) -> list[dict]:
        """List lectures for user, optionally filter by subject and/or group."""
        q = select(Lecture).where(Lecture.user_id == user_id)
        if subject is not None and subject != "":
            q = q.where(Lecture.subject == subject)
        if group_name is not None and group_name != "":
            q = q.where(Lecture.group_name == group_name)
        q = q.order_by(Lecture.created_at.desc())
        result = await db.execute(q)
        lectures = result.scalars().all()
        return [self._lecture_to_dict(l) for l in lectures]

    async def list_subjects(self, user_id: str, db: AsyncSession) -> list[str]:
        """Distinct subject values for user's lectures."""
        result = await db.execute(
            select(distinct(Lecture.subject))
            .where(Lecture.user_id == user_id)
            .where(Lecture.subject.isnot(None))
            .where(Lecture.subject != "")
            .order_by(Lecture.subject)
        )
        return [r[0] for r in result.all()]

    async def list_groups(self, user_id: str, db: AsyncSession) -> list[str]:
        """Distinct group_name values for user's lectures."""
        result = await db.execute(
            select(distinct(Lecture.group_name))
            .where(Lecture.user_id == user_id)
            .where(Lecture.group_name.isnot(None))
            .where(Lecture.group_name != "")
            .order_by(Lecture.group_name)
        )
        return [r[0] for r in result.all()]

    async def search_lectures(
        self,
        user_id: str,
        query: str,
        db: AsyncSession,
        subject: Optional[str] = None,
        group_name: Optional[str] = None,
        limit: int = 50,
    ) -> list[dict]:
        """Умный поиск: по названию и по тексту транскрипта. Возвращает лекции с snippet."""
        if not query or not query.strip():
            return []
        q_lower = query.strip().lower()
        lectures = await self.list_lectures(user_id, db, subject=subject, group_name=group_name)
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
            content = (await f.read()).strip()
        if not content:
            return None
        try:
            return json.loads(content)
        except json.JSONDecodeError:
            return None

    async def delete_lecture(self, lecture_id: str, db: AsyncSession) -> None:
        """Delete lecture from DB and remove files. Commit делает get_db."""
        result = await db.execute(select(Lecture).where(Lecture.id == lecture_id))
        lecture = result.scalar_one_or_none()
        if lecture:
            await db.delete(lecture)
        for path in [self._transcript_path(lecture_id), self._summary_path(lecture_id)]:
            if path.exists():
                os.remove(path)
        for ext in [".mp3", ".wav", ".m4a", ".ogg", ".webm", ".flac"]:
            audio_path = settings.audio_dir / f"{lecture_id}{ext}"
            if audio_path.exists():
                os.remove(audio_path)
                break


storage_service = StorageService()
