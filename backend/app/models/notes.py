from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel

class NoteAttachmentBase(BaseModel):
    id: str
    file_type: str
    filename: str
    created_at: datetime
    
    class Config:
        from_attributes = True

class NoteBase(BaseModel):
    id: str
    title: Optional[str] = None
    content: Optional[str] = None
    lecture_id: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    
    # Audio
    has_audio: bool = False
    duration: Optional[float] = None
    status: str = "simple" # simple, processing, ready, error
    transcription: Optional[str] = None
    
    attachments: List[NoteAttachmentBase] = []

    class Config:
        from_attributes = True

class NoteCreate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None
    lecture_id: Optional[str] = None

class NoteUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None
    lecture_id: Optional[str] = None

class NoteResponse(NoteBase):
    pass
