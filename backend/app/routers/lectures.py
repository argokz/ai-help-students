"""Lectures API router."""
import asyncio
import logging
import uuid
import aiofiles
import shutil
from datetime import datetime
from pathlib import Path
from typing import Annotated, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, BackgroundTasks, Body
from fastapi.responses import FileResponse
from pydantic import BaseModel as PydanticBaseModel

from ..config import settings
from ..database import AsyncSessionLocal, get_db
from ..db_models import User, Lecture
from ..dependencies import get_current_user
from ..models import (
    LectureListResponse,
    LectureResponse,
    LectureSearchResponse,
    LectureSearchResult,
    TranscriptResponse,
    TranscriptSegment,
)

class UploadInitRequest(PydanticBaseModel):
    filename: str
    total_chunks: Optional[int] = None
    total_size: Optional[int] = None

class UploadInitResponse(PydanticBaseModel):
    upload_id: str
from ..services.asr_service import asr_service
from ..services.storage_service import storage_service
from ..services.lectures_repo import lectures_repo
from sqlalchemy.ext.asyncio import AsyncSession

router = APIRouter()
logger = logging.getLogger(__name__)


def _get_audio_duration_sec(audio_path: str) -> Optional[float]:
    """Длительность аудио в секундах (для расчёта прогресса)."""
    try:
        from mutagen import File as MutagenFile
        audio = MutagenFile(audio_path)
        if audio is not None and hasattr(audio, "info") and audio.info is not None:
            return getattr(audio.info, "length", None)
    except Exception:
        pass
    return None


@router.post("/upload/init", response_model=UploadInitResponse)
async def init_upload(
    request: UploadInitRequest,
    current_user: Annotated[User, Depends(get_current_user)],
):
    """Start a resumable upload session."""
    upload_id = str(uuid.uuid4())
    upload_path = settings.upload_dir / upload_id
    upload_path.mkdir(parents=True, exist_ok=True)
    return UploadInitResponse(upload_id=upload_id)


@router.post("/upload/chunk/{upload_id}")
async def upload_chunk(
    upload_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    chunk_index: int = Form(...),
    file: UploadFile = File(...),
):
    """Upload a single chunk of the file."""
    upload_path = settings.upload_dir / upload_id
    if not upload_path.exists():
        raise HTTPException(status_code=404, detail="Upload session not found")
    
    chunk_path = upload_path / f"{chunk_index}.part"
    async with aiofiles.open(chunk_path, "wb") as f:
        while True:
            chunk = await file.read(1024 * 1024)
            if not chunk:
                break
            await f.write(chunk)
    return {"status": "ok", "chunk_index": chunk_index}


@router.post("/upload/complete/{upload_id}", response_model=LectureResponse)
async def complete_upload(
    upload_id: str,
    background_tasks: BackgroundTasks,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    title: Optional[str] = Form(None),
    language: Optional[str] = Form(None),
    subject: Optional[str] = Form(None),
    group_name: Optional[str] = Form(None),
    filename: Optional[str] = Form(None),
):
    """Assemble chunks and start processing."""
    upload_path = settings.upload_dir / upload_id
    if not upload_path.exists():
        raise HTTPException(status_code=404, detail="Upload session not found")
    
    # Sort chunks
    chunks = sorted(list(upload_path.glob("*.part")), key=lambda p: int(p.stem))
    if not chunks:
        # Cleanup empty folder
        shutil.rmtree(upload_path)
        raise HTTPException(status_code=400, detail="No chunks found")
        
    if not filename:
        filename = f"upload_{upload_id}.mp3"

    allowed_extensions = {".mp3", ".wav", ".m4a", ".ogg", ".webm", ".flac"}
    file_ext = Path(filename).suffix.lower()
    if file_ext not in allowed_extensions:
         if not file_ext: 
             file_ext = ".mp3" # default
         else:
             raise HTTPException(
                status_code=400, 
                detail=f"Unsupported file format. Allowed: {', '.join(allowed_extensions)}"
            )

    lecture_id = upload_id 
    final_path = settings.audio_dir / f"{lecture_id}{file_ext}"
    
    # Merge chunks
    async with aiofiles.open(final_path, "wb") as outfile:
        for chunk_path in chunks:
            async with aiofiles.open(chunk_path, "rb") as infile:
                while True:
                    chunk = await infile.read(1024 * 1024)
                    if not chunk:
                        break
                    await outfile.write(chunk)
    
    # Clean up
    shutil.rmtree(upload_path)
    
    lecture_title = title or filename or f"Лекция {datetime.now().strftime('%Y-%m-%d %H:%M')}"
    lecture_data = {
        "title": lecture_title,
        "filename": filename,
        "audio_path": str(final_path),
        "language": language,
        "status": "pending",
        "subject": subject,
        "group_name": group_name,
    }

    await lectures_repo.create(lecture_id, current_user.id, lecture_data, db)

    background_tasks.add_task(
        process_lecture_transcription,
        lecture_id,
        str(final_path),
        language,
    )

    return LectureResponse(
        id=lecture_id,
        title=lecture_title,
        filename=filename,
        duration=None,
        language=language,
        status="pending",
        created_at=datetime.utcnow(),
        has_transcript=False,
        has_summary=False,
        processing_progress=None,
        subject=subject,
        group_name=group_name,
    )


@router.post("/upload", response_model=LectureResponse)
async def upload_lecture(
    background_tasks: BackgroundTasks,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    file: UploadFile = File(...),
    title: Optional[str] = Form(None),
    language: Optional[str] = Form(None),
    subject: Optional[str] = Form(None),
    group_name: Optional[str] = Form(None),
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
        "title": lecture_title,
        "filename": file.filename,
        "audio_path": str(audio_path),
        "language": language,
        "status": "pending",
        "subject": subject,
        "group_name": group_name,
    }

    await lectures_repo.create(lecture_id, current_user.id, lecture_data, db)

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
        processing_progress=None,
        subject=None,
        group_name=None,
    )


async def process_lecture_transcription(
    lecture_id: str,
    audio_path: str,
    language: Optional[str],
):
    """Background task: transcribe and index. Обновляет processing_progress при обработке."""
    from ..database import AsyncSessionLocal
    from ..services.vector_store import vector_store

    logger.info("Starting transcription: lecture_id=%s path=%s", lecture_id, audio_path)
    total_duration = _get_audio_duration_sec(audio_path)
    loop = asyncio.get_event_loop()

    async def update_progress(progress: float) -> None:
        async with AsyncSessionLocal() as db:
            await lectures_repo.update(
                lecture_id, {"processing_progress": round(progress, 3)}, db
            )

    def on_progress(p: float) -> None:
        asyncio.run_coroutine_threadsafe(update_progress(p), loop)

    async with AsyncSessionLocal() as db:
        try:
            await lectures_repo.update_status(lecture_id, "processing", db)
        finally:
            pass

    try:
        # Таймаут для транскрибации: 3 часа для очень длинных лекций
        # Для лекции 3 часа аудио на GPU может потребоваться ~1-2 часа обработки
        # Плюс запас на сетевые задержки и fallback на CPU
        result = await asyncio.wait_for(
            asr_service.transcribe(
                audio_path,
                language,
                total_duration=total_duration,
                progress_callback=on_progress if total_duration else None,
            ),
            timeout=10800.0,  # 3 hours - достаточно для лекций до 3-4 часов аудио
        )
    except asyncio.TimeoutError:
        error_msg = "Превышено время ожидания транскрибации (3 часа). Файл слишком большой или сервер перегружен."
        logger.error("Transcription timeout: lecture_id=%s path=%s duration=%s", 
                     lecture_id, audio_path, total_duration)
        async with AsyncSessionLocal() as db:
            await lectures_repo.update_status(lecture_id, "failed", db)
            await lectures_repo.update(lecture_id, {"error": error_msg}, db)
        return
    except Exception as e:
        logger.exception("Lecture transcription failed: lecture_id=%s path=%s", lecture_id, audio_path)
        async with AsyncSessionLocal() as db:
            await lectures_repo.update_status(lecture_id, "failed", db)
            await lectures_repo.update(lecture_id, {"error": str(e)}, db)
        return  # Не поднимаем исключение, чтобы не крашить background task

    async with AsyncSessionLocal() as db:
        await storage_service.save_transcript(lecture_id, result, db)
        await lectures_repo.update(
            lecture_id,
            {
                "status": "completed",
                "language": result.get("language"),
                "duration": result.get("duration"),
                "processing_progress": None,
                "has_transcript": True
            },
            db,
        )
    await vector_store.index_lecture(lecture_id, result["segments"])


def _check_lecture_owner(lecture: dict, user_id: str) -> None:
    if lecture.get("user_id") != user_id:
        raise HTTPException(status_code=403, detail="Доступ запрещён")


def _lecture_to_response(l: dict) -> LectureResponse:
    return LectureResponse(
        id=l["id"],
        title=l["title"],
        filename=l["filename"],
        duration=l.get("duration"),
        language=l.get("language"),
        status=l["status"],
        created_at=datetime.fromisoformat(l["created_at"]),
        has_transcript=l.get("has_transcript", False),
        has_summary=l.get("has_summary", False),
        processing_progress=l.get("processing_progress"),
        subject=l.get("subject"),
        group_name=l.get("group_name"),
    )


@router.get("", response_model=LectureListResponse)
async def list_lectures(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    subject: Optional[str] = None,
    group_name: Optional[str] = None,
):
    """List current user's lectures. Фильтр по предмету и/или группе."""
    lectures = await lectures_repo.list(
        current_user.id, db, subject=subject, group_name=group_name
    )
    subjects = await lectures_repo.list_subjects(current_user.id, db)
    groups = await lectures_repo.list_groups(current_user.id, db)
    return LectureListResponse(
        lectures=[_lecture_to_response(l) for l in lectures],
        total=len(lectures),
        subjects=subjects,
        groups=groups,
    )


@router.get("/search", response_model=LectureSearchResponse)
async def search_lectures(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    q: str = "",
    subject: Optional[str] = None,
    group_name: Optional[str] = None,
    limit: int = 50,
):
    """Умный поиск по названию и тексту транскриптов."""
    results = await storage_service.search_lectures(
        current_user.id, q, db, subject=subject, group_name=group_name, limit=limit
    )
    return LectureSearchResponse(
        results=[
            LectureSearchResult(
                id=r["id"],
                title=r["title"],
                subject=r.get("subject"),
                group_name=r.get("group_name"),
                snippet=r.get("snippet"),
                match_in=r.get("match_in"),
            )
            for r in results
        ],
        total=len(results),
    )


@router.get("/{lecture_id}", response_model=LectureResponse)
async def get_lecture(
    lecture_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Get lecture by ID. Must belong to current user."""
    lecture = await lectures_repo.get(lecture_id, db)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    _check_lecture_owner(lecture, current_user.id)
    return _lecture_to_response(lecture)


class _LectureUpdateBody(PydanticBaseModel):
    subject: Optional[str] = None
    group_name: Optional[str] = None


@router.patch("/{lecture_id}", response_model=LectureResponse)
async def update_lecture(
    lecture_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: Optional[_LectureUpdateBody] = Body(None),
):
    """Обновить предмет и/или группу лекции."""
    if body is None:
        body = _LectureUpdateBody()
    lecture = await lectures_repo.get(lecture_id, db)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    _check_lecture_owner(lecture, current_user.id)
    updates = {}
    if body.subject is not None:
        updates["subject"] = body.subject if body.subject != "" else None
    if body.group_name is not None:
        updates["group_name"] = body.group_name if body.group_name != "" else None
    if updates:
        await lectures_repo.update(lecture_id, updates, db)
        lecture = await lectures_repo.get(lecture_id, db)
    return _lecture_to_response(lecture)


@router.get("/{lecture_id}/transcript", response_model=TranscriptResponse)
async def get_transcript(
    lecture_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Get transcript. Lecture must belong to current user."""
    lecture = await lectures_repo.get(lecture_id, db)
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


@router.get("/{lecture_id}/audio")
async def get_lecture_audio(
    lecture_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    download: bool = False,
):
    """Скачать / прослушать аудио лекции. Только владелец.
    
    Args:
        download: Если True, отдаёт как вложение (для скачивания). 
                  Если False (по умолчанию), отдаёт inline (для воспроизведения).
    """
    lecture = await lectures_repo.get(lecture_id, db)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    _check_lecture_owner(lecture, current_user.id)

    audio_path = lecture.get("audio_path")
    path_obj = None
    if audio_path:
        path_obj = Path(audio_path)
        if not path_obj.exists():
            path_obj = None
    if path_obj is None:
        for ext in [".mp3", ".wav", ".m4a", ".ogg", ".webm", ".flac"]:
            candidate = settings.audio_dir / f"{lecture_id}{ext}"
            if candidate.exists():
                path_obj = candidate
                break
    if path_obj is None or not path_obj.exists():
        raise HTTPException(status_code=404, detail="Audio file not found")

    media_types = {
        ".mp3": "audio/mpeg",
        ".m4a": "audio/mp4",
        ".wav": "audio/wav",
        ".ogg": "audio/ogg",
        ".webm": "audio/webm",
        ".flac": "audio/flac",
    }
    media_type = media_types.get(path_obj.suffix.lower(), "application/octet-stream")
    
    # Если download=True, передаём filename, что заставляет браузер добавить
    # Content-Disposition: attachment. Если False — отдаём без filename (inline).
    return FileResponse(
        str(path_obj),
        media_type=media_type,
        filename=lecture.get("filename") or path_obj.name if download else None,
    )


@router.post("/{lecture_id}/extract-tasks")
async def extract_tasks_from_lecture(
    lecture_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Extract tasks and deadlines from lecture transcript using AI."""
    lecture = await lectures_repo.get(lecture_id, db)
    if not lecture:
        raise HTTPException(404, "Lecture not found")
    _check_lecture_owner(lecture, current_user.id)
    
    # Get transcript from storage service
    transcript = await storage_service.get_transcript(lecture_id)
    if not transcript:
        raise HTTPException(404, "Transcript not found. Please wait for transcription to complete.")
    
    # Extract full text from transcript segments
    full_text = " ".join(seg.get("text", "") for seg in transcript.get("segments", []))
    if not full_text.strip():
        raise HTTPException(400, "Transcript is empty")
    
    # Extract tasks
    from ..services.task_extractor import task_extractor
    created_at_dt = datetime.fromisoformat(lecture["created_at"])
    tasks = await task_extractor.extract_tasks(full_text, created_at_dt)
    
    return {"tasks": tasks, "lecture_id": lecture_id}


@router.delete("/{lecture_id}")
async def delete_lecture(
    lecture_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Delete lecture. Must belong to current user."""
    lecture = await lectures_repo.get(lecture_id, db)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    _check_lecture_owner(lecture, current_user.id)

    from ..services.vector_store import vector_store
    
    await lectures_repo.delete(lecture_id, db)
    await storage_service.delete_lecture_files(lecture_id)
    await vector_store.delete_lecture(lecture_id)
    await db.commit()
    return {"status": "deleted", "id": lecture_id}
