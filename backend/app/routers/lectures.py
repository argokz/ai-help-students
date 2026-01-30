"""Lectures API router."""
import uuid
import aiofiles
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, UploadFile, File, Form, HTTPException, BackgroundTasks

from ..config import settings
from ..models import (
    LectureResponse,
    LectureListResponse,
    TranscriptResponse,
    TranscriptSegment,
)
from ..services.storage_service import storage_service
from ..services.asr_service import asr_service

router = APIRouter()


@router.post("/upload", response_model=LectureResponse)
async def upload_lecture(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    title: Optional[str] = Form(None),
    language: Optional[str] = Form(None),
):
    """
    Upload an audio file for transcription.
    
    Supported formats: mp3, wav, m4a, ogg, webm
    """
    # Validate file type
    allowed_extensions = {".mp3", ".wav", ".m4a", ".ogg", ".webm", ".flac"}
    file_ext = Path(file.filename).suffix.lower()
    
    if file_ext not in allowed_extensions:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file format. Allowed: {', '.join(allowed_extensions)}"
        )
    
    # Generate unique ID
    lecture_id = str(uuid.uuid4())
    
    # Save audio file
    audio_path = settings.audio_dir / f"{lecture_id}{file_ext}"
    
    async with aiofiles.open(audio_path, "wb") as f:
        content = await file.read()
        await f.write(content)
    
    # Create lecture record
    lecture_title = title or file.filename or f"Лекция {datetime.now().strftime('%Y-%m-%d %H:%M')}"
    
    lecture_data = {
        "id": lecture_id,
        "title": lecture_title,
        "filename": file.filename,
        "audio_path": str(audio_path),
        "language": language,
        "status": "pending",
        "created_at": datetime.utcnow().isoformat(),
    }
    
    # Save metadata
    await storage_service.save_lecture_metadata(lecture_id, lecture_data)
    
    # Start background transcription
    background_tasks.add_task(
        process_lecture_transcription,
        lecture_id,
        str(audio_path),
        language
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
    language: Optional[str]
):
    """Background task to transcribe audio."""
    try:
        # Update status
        await storage_service.update_lecture_status(lecture_id, "processing")
        
        # Transcribe
        result = await asr_service.transcribe(audio_path, language)
        
        # Save transcript
        await storage_service.save_transcript(lecture_id, result)
        
        # Update lecture with results
        await storage_service.update_lecture_metadata(lecture_id, {
            "status": "completed",
            "language": result.get("language"),
            "duration": result.get("duration"),
        })
        
        # Index chunks for RAG
        from ..services.vector_store import vector_store
        await vector_store.index_lecture(lecture_id, result["segments"])
        
    except Exception as e:
        await storage_service.update_lecture_status(lecture_id, "failed")
        await storage_service.update_lecture_metadata(lecture_id, {"error": str(e)})
        raise


@router.get("", response_model=LectureListResponse)
async def list_lectures():
    """Get list of all lectures."""
    lectures = await storage_service.list_lectures()
    
    lecture_responses = []
    for lecture in lectures:
        lecture_responses.append(LectureResponse(
            id=lecture["id"],
            title=lecture["title"],
            filename=lecture["filename"],
            duration=lecture.get("duration"),
            language=lecture.get("language"),
            status=lecture["status"],
            created_at=datetime.fromisoformat(lecture["created_at"]),
            has_transcript=lecture.get("has_transcript", False),
            has_summary=lecture.get("has_summary", False),
        ))
    
    return LectureListResponse(
        lectures=lecture_responses,
        total=len(lecture_responses)
    )


@router.get("/{lecture_id}", response_model=LectureResponse)
async def get_lecture(lecture_id: str):
    """Get lecture details by ID."""
    lecture = await storage_service.get_lecture_metadata(lecture_id)
    
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    
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
async def get_transcript(lecture_id: str):
    """Get full transcript with timestamps."""
    lecture = await storage_service.get_lecture_metadata(lecture_id)
    
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    
    if lecture["status"] != "completed":
        raise HTTPException(
            status_code=400, 
            detail=f"Transcript not ready. Status: {lecture['status']}"
        )
    
    transcript = await storage_service.get_transcript(lecture_id)
    
    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")
    
    segments = [
        TranscriptSegment(
            start=seg["start"],
            end=seg["end"],
            text=seg["text"]
        )
        for seg in transcript["segments"]
    ]
    
    full_text = " ".join(seg["text"] for seg in transcript["segments"])
    
    return TranscriptResponse(
        lecture_id=lecture_id,
        segments=segments,
        full_text=full_text,
        language=transcript.get("language")
    )


@router.delete("/{lecture_id}")
async def delete_lecture(lecture_id: str):
    """Delete a lecture and all associated data."""
    lecture = await storage_service.get_lecture_metadata(lecture_id)
    
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    
    await storage_service.delete_lecture(lecture_id)
    
    # Remove from vector store
    from ..services.vector_store import vector_store
    await vector_store.delete_lecture(lecture_id)
    
    return {"status": "deleted", "id": lecture_id}
