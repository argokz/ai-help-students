"""Chat-related Pydantic models."""
from typing import Optional
from pydantic import BaseModel, Field


class SourceChunk(BaseModel):
    """Source chunk used to generate answer."""
    text: str = Field(..., description="Chunk text")
    start_time: float = Field(..., description="Start timestamp in seconds")
    end_time: float = Field(..., description="End timestamp in seconds")
    relevance_score: float = Field(..., description="Similarity score 0-1")


class ChatMessage(BaseModel):
    """Single chat message."""
    role: str = Field(..., description="Role: user or assistant")
    content: str = Field(..., description="Message content")


class ChatRequest(BaseModel):
    """Request model for chat."""
    question: str = Field(..., description="User's question about the lecture")
    history: Optional[list[ChatMessage]] = Field(
        default=None, 
        description="Previous conversation history"
    )


class ChatResponse(BaseModel):
    """Response model for chat."""
    answer: str = Field(..., description="Generated answer based on lecture content")
    sources: list[SourceChunk] = Field(
        default_factory=list,
        description="Source chunks used to generate the answer"
    )
    confidence: Optional[float] = Field(
        None, 
        description="Confidence score 0-1, None if answer not found in content"
    )
