"""Lecture-related Pydantic models."""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class TranscriptSegment(BaseModel):
    """Single segment of transcribed text with timestamps."""
    start: float = Field(..., description="Start time in seconds")
    end: float = Field(..., description="End time in seconds")
    text: str = Field(..., description="Transcribed text")


class LectureCreate(BaseModel):
    """Request model for creating a lecture."""
    title: Optional[str] = Field(None, description="Optional lecture title")
    language: Optional[str] = Field(None, description="Language code (ru, kz, en) or auto")


class Lecture(BaseModel):
    """Lecture model with all fields."""
    id: str = Field(..., description="Unique lecture ID")
    title: str = Field(..., description="Lecture title")
    filename: str = Field(..., description="Original audio filename")
    duration: Optional[float] = Field(None, description="Audio duration in seconds")
    language: Optional[str] = Field(None, description="Detected or specified language")
    status: str = Field("pending", description="Processing status: pending, processing, completed, failed")
    created_at: datetime = Field(default_factory=datetime.utcnow)
    transcript: Optional[list[TranscriptSegment]] = Field(None, description="Full transcript with timestamps")
    
    class Config:
        from_attributes = True


class LectureResponse(BaseModel):
    """Response model for single lecture."""
    id: str
    title: str
    filename: str
    duration: Optional[float]
    language: Optional[str]
    status: str
    created_at: datetime
    has_transcript: bool = Field(..., description="Whether transcript is available")
    has_summary: bool = Field(..., description="Whether summary is available")
    processing_progress: Optional[float] = Field(None, description="0.0–1.0 when status=processing")
    subject: Optional[str] = Field(None, description="Предмет")
    group_name: Optional[str] = Field(None, description="Группа")


class LectureListResponse(BaseModel):
    """Response model for list of lectures."""
    lectures: list[LectureResponse]
    total: int
    subjects: list[str] = Field(default_factory=list, description="Список предметов для фильтра")
    groups: list[str] = Field(default_factory=list, description="Список групп для фильтра")


class LectureSearchResult(BaseModel):
    """Один результат умного поиска."""
    id: str
    title: str
    subject: Optional[str] = None
    group_name: Optional[str] = None
    snippet: Optional[str] = None
    match_in: Optional[str] = None  # title | transcript


class LectureSearchResponse(BaseModel):
    """Ответ поиска по лекциям."""
    results: list[LectureSearchResult]
    total: int


class TranscriptResponse(BaseModel):
    """Response model for transcript."""
    lecture_id: str
    segments: list[TranscriptSegment]
    full_text: str = Field(..., description="Complete text without timestamps")
    language: Optional[str]
