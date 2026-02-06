"""Notes API router."""
import uuid
import shutil
import asyncio
from datetime import datetime
from pathlib import Path
from typing import Annotated, Optional, List

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, BackgroundTasks
from fastapi.responses import FileResponse
from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings
from ..database import get_db
from ..db_models import User, Note, NoteAttachment, Lecture
from ..dependencies import get_current_user
from ..models.notes import NoteCreate, NoteUpdate, NoteResponse
from ..services.asr_service import asr_service

router = APIRouter(prefix="/notes", tags=["notes"])

# Ensure notes directories exist
NOTES_DIR = settings.data_dir / "notes"
NOTES_AUDIO_DIR = NOTES_DIR / "audio"
NOTES_ATTACHMENTS_DIR = NOTES_DIR / "attachments"

NOTES_AUDIO_DIR.mkdir(parents=True, exist_ok=True)
NOTES_ATTACHMENTS_DIR.mkdir(parents=True, exist_ok=True)


async def process_note_audio(note_id: str, audio_path: str):
    """Background task to transcribe note audio."""
    # We create a new DB session for background task
    from ..database import AsyncSessionLocal
    async with AsyncSessionLocal() as db:
        note = await db.get(Note, note_id)
        if not note:
            return

        try:
            # 1. Update status
            note.status = "processing"
            await db.commit()
            
            # 2. Transcribe
            # Notes are usually short, so we can use the same model but maybe simpler parameters?
            # actually asr_service.transcribe is fine.
            # We need to run sync transcribe in executor because it's CPU intensive
            
            start_time = datetime.now()
            result = await asr_service.transcribe(audio_path)
            
            # 3. Save result
            segments = result.get("segments", [])
            full_text = " ".join([s["text"] for s in segments])
            
            note.transcription = full_text
            note.duration = result.get("duration", 0.0)
            note.status = "ready"
            
            # Append transcription to content if content is empty or append to it?
            # Let's keep them separate but maybe the UI wants to see it in content.
            # User requirement: "audio notes and also transcribe them".
            
            await db.commit()
            
        except Exception as e:
            note.status = "error"
            note.content = (note.content or "") + f"\n\n[Error processing audio: {str(e)}]"
            await db.commit()


@router.get("", response_model=List[NoteResponse])
async def get_notes(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    lecture_id: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
):
    """Get list of notes, optionally filtered by lecture."""
    query = select(Note).where(Note.user_id == current_user.id)
    
    if lecture_id:
        query = query.where(Note.lecture_id == lecture_id)
        
    query = query.order_by(desc(Note.created_at)).offset(offset).limit(limit)
    
    result = await db.execute(query)
    notes = result.scalars().all()
    
    # Map to response to handle virtual fields
    responses = []
    for n in notes:
        resp = NoteResponse.model_validate(n)
        resp.has_audio = bool(n.audio_path)
        responses.append(resp)
        
    return responses


@router.post("", response_model=NoteResponse)
async def create_note(
    note_in: NoteCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Create a new text note."""
    note = Note(
        user_id=current_user.id,
        title=note_in.title,
        content=note_in.content,
        lecture_id=note_in.lecture_id,
        status="simple"
    )
    db.add(note)
    await db.commit()
    await db.refresh(note)
    
    resp = NoteResponse.model_validate(note)
    resp.has_audio = False
    return resp


@router.get("/{note_id}", response_model=NoteResponse)
async def get_note(
    note_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Get specific note."""
    note = await db.get(Note, note_id)
    if not note or note.user_id != current_user.id:
        raise HTTPException(404, "Note not found")
        
    resp = NoteResponse.model_validate(note)
    resp.has_audio = bool(note.audio_path)
    return resp


@router.patch("/{note_id}", response_model=NoteResponse)
async def update_note(
    note_id: str,
    note_in: NoteUpdate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Update note text or link."""
    note = await db.get(Note, note_id)
    if not note or note.user_id != current_user.id:
        raise HTTPException(404, "Note not found")
        
    if note_in.title is not None:
        note.title = note_in.title
    if note_in.content is not None:
        note.content = note_in.content
    if note_in.lecture_id is not None:
        # Verify lecture exists
        if note_in.lecture_id: # if not empty string/null
            lecture = await db.get(Lecture, note_in.lecture_id)
            if lecture: # only if exists
                note.lecture_id = note_in.lecture_id
        else:
            note.lecture_id = None
            
    await db.commit()
    await db.refresh(note)
    
    resp = NoteResponse.model_validate(note)
    resp.has_audio = bool(note.audio_path)
    return resp


@router.delete("/{note_id}")
async def delete_note(
    note_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Delete note and its files."""
    note = await db.get(Note, note_id)
    if not note or note.user_id != current_user.id:
        raise HTTPException(404, "Note not found")
        
    # Delete files
    if note.audio_path:
        p = Path(note.audio_path)
        if p.exists():
            try:
                p.unlink()
            except:
                pass
                
    # Delete attachments files
    # NoteAttachment cascade delete handles DB, but we need to delete files from disk
    # Ideally we select attachments first
    # For MVP we might leave orphan files or do it properly:
    result = await db.execute(select(NoteAttachment).where(NoteAttachment.note_id == note_id))
    attachments = result.scalars().all()
    for att in attachments:
        p = Path(att.file_path)
        if p.exists():
            try:
                p.unlink()
            except:
                pass

    await db.delete(note)
    await db.commit()
    return {"ok": True}


@router.post("/{note_id}/audio", response_model=NoteResponse)
async def upload_note_audio(
    note_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
):
    """Upload audio for an existing note and start transcription."""
    note = await db.get(Note, note_id)
    if not note or note.user_id != current_user.id:
        raise HTTPException(404, "Note not found")
        
    # Save file
    file_ext = Path(file.filename).suffix or ".m4a"
    filename = f"{note_id}{file_ext}"
    path = NOTES_AUDIO_DIR / filename
    
    async with aiofiles.open(path, "wb") as out_file:
        while content := await file.read(1024 * 1024):
            await out_file.write(content)
            
    note.audio_path = str(path)
    note.status = "processing"
    await db.commit()
    
    # Start BG task
    background_tasks.add_task(process_note_audio, note_id, str(path))
    
    resp = NoteResponse.model_validate(note)
    resp.has_audio = True
    return resp

@router.get("/{note_id}/audio")
async def get_note_audio(
    note_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Stream note audio."""
    note = await db.get(Note, note_id)
    if not note or note.user_id != current_user.id:
        raise HTTPException(404, "Note not found")
        
    if not note.audio_path or not Path(note.audio_path).exists():
        raise HTTPException(404, "Audio not found")
        
    return FileResponse(note.audio_path, media_type="audio/mp4")


@router.post("/{note_id}/attachments", response_model=NoteResponse)
async def upload_attachment(
    note_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    file: UploadFile = File(...),
):
    """Upload an image or document attachment."""
    note = await db.get(Note, note_id)
    if not note or note.user_id != current_user.id:
        raise HTTPException(404, "Note not found")
        
    # Determine type
    content_type = file.content_type or ""
    file_type = "document"
    if content_type.startswith("image/"):
        file_type = "image"
        
    safe_filename = Path(file.filename).name
    # Unique filename
    att_id = str(uuid.uuid4())
    save_filename = f"{att_id}_{safe_filename}"
    path = NOTES_ATTACHMENTS_DIR / save_filename
    
    async with aiofiles.open(path, "wb") as out_file:
        while content := await file.read(1024 * 1024):
            await out_file.write(content)
            
    attachment = NoteAttachment(
        id=att_id,
        note_id=note_id,
        file_path=str(path),
        file_type=file_type,
        filename=safe_filename
    )
    db.add(attachment)
    await db.commit()
    await db.refresh(note) # Refresh note to get updated attachments list
    
    resp = NoteResponse.model_validate(note)
    resp.has_audio = bool(note.audio_path)
    return resp

@router.get("/{note_id}/attachments/{attachment_id}")
async def get_attachment(
    note_id: str,
    attachment_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Get attachment file."""
    # We verify ownership via note
    att = await db.get(NoteAttachment, attachment_id)
    if not att or att.note_id != note_id:
         raise HTTPException(404, "Attachment not found")
         
    note = await db.get(Note, note_id)
    if not note or note.user_id != current_user.id:
        raise HTTPException(404, "Note not found")
        
    if not Path(att.file_path).exists():
        raise HTTPException(404, "File not found")
        
    return FileResponse(att.file_path, filename=att.filename)

