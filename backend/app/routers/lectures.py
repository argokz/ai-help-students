"""Lectures API router."""
import uuid
import aiofiles
from datetime import datetime
from pathlib import Path
from typing import Annotated, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, BackgroundTasks

from ..config import settings
from ..database import AsyncSessionLocal, get_db
from ..db_models import User
from ..dependencies import get_current_user
from ..models import (
    LectureListResponse,
    LectureResponse,
    TranscriptResponse,
    TranscriptSegment,
)
from ..services.asr_service import asr_service
from ..services.storage_service import storage_service
from sqlalchemy.ext.asyncio import AsyncSession

router = APIRouter()


@router.post("/upload", response_model=LectureResponse)
async def upload_lecture(
    background_tasks: BackgroundTasks,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    file: UploadFile = File(...),
    title: Optional[str] = Form(None),
    language: Optional[str] = Form(None),
):
    """Upload an audio file for transcription. Requires auth."""
    allowed_extensions = {".mp3", ".wav", ".m4a", ".ogg", ".webm", ".flac"}
    file_ext = Path(file.filename).suffix.lower()
    if file_ext not in allowed_extensions:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file format. Allowed: {', '.join(allowed_extensions)}",
        )

    lecture_id = str(uuid.uuid4())
    audio_path = settings.audio_dir / f"{lecture_id}{file_ext}"

    # Stream to disk by chunks — меньше памяти и быстрее для больших файлов
    chunk_size = 1024 * 1024  # 1 MiB
    async with aiofiles.open(audio_path, "wb") as f:
        while True:
            chunk = await file.read(chunk_size)
            if not chunk:
                break
            await f.write(chunk)

    lecture_title = title or file.filename or f"Лекция {datetime.now().strftime('%Y-%m-%d %H:%M')}"
    lecture_data = {
        "id": lecture_id,
        "title": lecture_title,
        "filename": file.filename,
        "audio_path": str(audio_path),
        "language": language,
        "status": "pending",
    }

    await storage_service.save_lecture_metadata(lecture_id, current_user.id, lecture_data, db)

    background_tasks.add_task(
        process_lecture_transcription,
        lecture_id,
        str(audio_path),
        language,
    )

    return LectureResponse(
        id=lecture_id,
        title=lecture_title,
        filename=file.filename,
        duration=None,
        language=language,
        status="pending",
        created_at=datetime.utcnow(),
        has_transcript=False,
        has_summary=False,
    )


async def process_lecture_transcription(
    lecture_id: str,
    audio_path: str,
    language: Optional[str],
):
    """Background task: transcribe and index."""
    from ..database import AsyncSessionLocal
    from ..services.vector_store import vector_store

    async with AsyncSessionLocal() as db:
        try:
            await storage_service.update_lecture_status(lecture_id, "processing", db)
            result = await asr_service.transcribe(audio_path, language)
            await storage_service.save_transcript(lecture_id, result, db)
            await storage_service.update_lecture_metadata(
                lecture_id,
                {
                    "status": "completed",
                    "language": result.get("language"),
                    "duration": result.get("duration"),
                },
                db,
            )
            await vector_store.index_lecture(lecture_id, result["segments"])
        except Exception as e:
            await storage_service.update_lecture_status(lecture_id, "failed", db)
            await storage_service.update_lecture_metadata(lecture_id, {"error": str(e)}, db)
            raise


def _check_lecture_owner(lecture: dict, user_id: str) -> None:
    if lecture.get("user_id") != user_id:
        raise HTTPException(status_code=403, detail="Доступ запрещён")


@router.get("", response_model=LectureListResponse)
async def list_lectures(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """List current user's lectures."""
    lectures = await storage_service.list_lectures(current_user.id, db)
    return LectureListResponse(
        lectures=[
            LectureResponse(
                id=l["id"],
                title=l["title"],
                filename=l["filename"],
                duration=l.get("duration"),
                language=l.get("language"),
                status=l["status"],
                created_at=datetime.fromisoformat(l["created_at"]),
                has_transcript=l.get("has_transcript", False),
                has_summary=l.get("has_summary", False),
            )
            for l in lectures
        ],
        total=len(lectures),
    )


@router.get("/{lecture_id}", response_model=LectureResponse)
async def get_lecture(
    lecture_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Get lecture by ID. Must belong to current user."""
    lecture = await storage_service.get_lecture_metadata(lecture_id, db)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    _check_lecture_owner(lecture, current_user.id)
    return LectureResponse(
        id=lecture["id"],
        title=lecture["title"],
        filename=lecture["filename"],
        duration=lecture.get("duration"),
        language=lecture.get("language"),
        status=lecture["status"],
        created_at=datetime.fromisoformat(lecture["created_at"]),
        has_transcript=lecture.get("has_transcript", False),
        has_summary=lecture.get("has_summary", False),
    )


@router.get("/{lecture_id}/transcript", response_model=TranscriptResponse)
async def get_transcript(
    lecture_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Get transcript. Lecture must belong to current user."""
    lecture = await storage_service.get_lecture_metadata(lecture_id, db)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    _check_lecture_owner(lecture, current_user.id)
    if lecture["status"] != "completed":
        raise HTTPException(status_code=400, detail=f"Transcript not ready. Status: {lecture['status']}")

    transcript = await storage_service.get_transcript(lecture_id)
    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")

    segments = [
        TranscriptSegment(start=seg["start"], end=seg["end"], text=seg["text"])
        for seg in transcript["segments"]
    ]
    full_text = " ".join(seg["text"] for seg in transcript["segments"])
    return TranscriptResponse(
        lecture_id=lecture_id,
        segments=segments,
        full_text=full_text,
        language=transcript.get("language"),
    )


@router.delete("/{lecture_id}")
async def delete_lecture(
    lecture_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Delete lecture. Must belong to current user."""
    lecture = await storage_service.get_lecture_metadata(lecture_id, db)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    _check_lecture_owner(lecture, current_user.id)

    from ..services.vector_store import vector_store
    await storage_service.delete_lecture(lecture_id, db)
    await vector_store.delete_lecture(lecture_id)
    return {"status": "deleted", "id": lecture_id}
