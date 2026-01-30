"""Pydantic models for API."""
from .lecture import (
    Lecture,
    LectureCreate,
    LectureResponse,
    LectureListResponse,
    TranscriptSegment,
    TranscriptResponse,
)
from .chat import (
    ChatMessage,
    ChatRequest,
    ChatResponse,
    SourceChunk,
)
from .summary import SummaryResponse

__all__ = [
    "Lecture",
    "LectureCreate", 
    "LectureResponse",
    "LectureListResponse",
    "TranscriptSegment",
    "TranscriptResponse",
    "ChatMessage",
    "ChatRequest",
    "ChatResponse",
    "SourceChunk",
    "SummaryResponse",
]
