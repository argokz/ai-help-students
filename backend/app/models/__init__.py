"""Pydantic models for API."""
from .lecture import (
    Lecture,
    LectureCreate,
    LectureResponse,
    LectureListResponse,
    LectureSearchResult,
    LectureSearchResponse,
    TranscriptSegment,
    TranscriptResponse,
)
from .chat import (
    ChatMessage,
    ChatRequest,
    ChatResponse,
    SourceChunk,
    GlobalChatRequest,
    GlobalChatResponse,
    GlobalChatSource,
)
from .summary import SummaryResponse
from .auth import UserRegister, UserLogin, GoogleAuthRequest, TokenResponse, UserResponse

__all__ = [
    "Lecture",
    "LectureCreate",
    "LectureResponse",
    "LectureListResponse",
    "LectureSearchResult",
    "LectureSearchResponse",
    "TranscriptSegment",
    "TranscriptResponse",
    "ChatMessage",
    "ChatRequest",
    "ChatResponse",
    "SourceChunk",
    "GlobalChatRequest",
    "GlobalChatResponse",
    "GlobalChatSource",
    "SummaryResponse",
    "UserRegister",
    "UserLogin",
    "GoogleAuthRequest",
    "TokenResponse",
    "UserResponse",
]
