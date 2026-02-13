"""Repository for Lecture-related database operations."""
from typing import Optional, List
from datetime import datetime

from sqlalchemy import select, distinct
from sqlalchemy.ext.asyncio import AsyncSession

from ..db_models import Lecture


class LecturesRepository:
    """Repository for Lecture database operations."""

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

    async def create(
        self,
        lecture_id: str,
        user_id: str,
        data: dict,
        db: AsyncSession,
    ) -> Lecture:
        """Create new lecture record."""
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
        return lecture

    async def get(
        self,
        lecture_id: str,
        db: AsyncSession,
    ) -> Optional[dict]:
        """Get lecture by ID."""
        result = await db.execute(select(Lecture).where(Lecture.id == lecture_id))
        lecture = result.scalar_one_or_none()
        if not lecture:
            return None
        return self._lecture_to_dict(lecture)

    async def update(
        self,
        lecture_id: str,
        updates: dict,
        db: AsyncSession,
    ) -> None:
        """Update lecture fields."""
        result = await db.execute(select(Lecture).where(Lecture.id == lecture_id))
        lecture = result.scalar_one_or_none()
        if not lecture:
            return
        for key, value in updates.items():
            if hasattr(lecture, key):
                setattr(lecture, key, value)
        await db.commit()

    async def update_status(
        self,
        lecture_id: str,
        status: str,
        db: AsyncSession,
    ) -> None:
        """Update lecture status."""
        await self.update(lecture_id, {"status": status}, db)

    async def list(
        self,
        user_id: str,
        db: AsyncSession,
        subject: Optional[str] = None,
        group_name: Optional[str] = None,
    ) -> List[dict]:
        """List user's lectures with optional filtering."""
        q = select(Lecture).where(Lecture.user_id == user_id)
        if subject is not None and subject != "":
            q = q.where(Lecture.subject == subject)
        if group_name is not None and group_name != "":
            q = q.where(Lecture.group_name == group_name)
        q = q.order_by(Lecture.created_at.desc())
        
        result = await db.execute(q)
        lectures = result.scalars().all()
        return [self._lecture_to_dict(l) for l in lectures]

    async def delete(self, lecture_id: str, db: AsyncSession) -> Optional[Lecture]:
        """Delete lecture. Returns deleted lecture object if found."""
        result = await db.execute(select(Lecture).where(Lecture.id == lecture_id))
        lecture = result.scalar_one_or_none()
        if lecture:
            await db.delete(lecture)
            return lecture
        return None

    async def get_incomplete(self, db: AsyncSession) -> List[dict]:
        """Get lectures involving active processing (pending/processing)."""
        result = await db.execute(
            select(Lecture).where(
                Lecture.status.in_(["pending", "processing"])
            )
        )
        lectures = result.scalars().all()
        return [self._lecture_to_dict(l) for l in lectures]

    async def list_subjects(self, user_id: str, db: AsyncSession) -> List[str]:
        """Get distinct subjects for user."""
        result = await db.execute(
            select(distinct(Lecture.subject))
            .where(Lecture.user_id == user_id)
            .where(Lecture.subject.isnot(None))
            .where(Lecture.subject != "")
            .order_by(Lecture.subject)
        )
        return [r[0] for r in result.all()]

    async def list_groups(self, user_id: str, db: AsyncSession) -> List[str]:
        """Get distinct groups for user."""
        result = await db.execute(
            select(distinct(Lecture.group_name))
            .where(Lecture.user_id == user_id)
            .where(Lecture.group_name.isnot(None))
            .where(Lecture.group_name != "")
            .order_by(Lecture.group_name)
        )
        return [r[0] for r in result.all()]


lectures_repo = LecturesRepository()
