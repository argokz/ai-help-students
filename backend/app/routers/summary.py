"""Summary API router."""
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..db_models import User
from ..dependencies import get_current_user
from ..models import SummaryResponse
from ..services.llm_service import llm_service
from ..services.storage_service import storage_service

router = APIRouter()


def _check_lecture_owner(lecture: dict, user_id: str) -> None:
    if lecture.get("user_id") != user_id:
        raise HTTPException(status_code=403, detail="Доступ запрещён")


@router.get("/{lecture_id}/summary", response_model=SummaryResponse)
async def get_summary(
    lecture_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    regenerate: bool = False,
):
    """Get structured summary. Lecture must belong to current user."""
    lecture = await storage_service.get_lecture_metadata(lecture_id, db)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    _check_lecture_owner(lecture, current_user.id)
    if lecture["status"] != "completed":
        raise HTTPException(
            status_code=400,
            detail=f"Lecture not ready for summarization. Status: {lecture['status']}",
        )

    if not regenerate:
        cached_summary = await storage_service.get_summary(lecture_id)
        if cached_summary:
            return SummaryResponse(lecture_id=lecture_id, **cached_summary)

    transcript = await storage_service.get_transcript(lecture_id)
    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")
    full_text = " ".join(seg["text"] for seg in transcript["segments"])
    summary = await llm_service.generate_summary(
        text=full_text,
        language=transcript.get("language"),
    )
    await storage_service.save_summary(lecture_id, summary)
    await storage_service.update_lecture_metadata(lecture_id, {"has_summary": True}, db)
    return SummaryResponse(lecture_id=lecture_id, **summary)
