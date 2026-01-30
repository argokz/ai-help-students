"""Summary-related Pydantic models."""
from typing import Optional
from pydantic import BaseModel, Field


class SummaryResponse(BaseModel):
    """Response model for lecture summary."""
    lecture_id: str
    main_topics: list[str] = Field(..., description="Main topics covered (3-5 items)")
    key_definitions: list[dict[str, str]] = Field(
        default_factory=list,
        description="Key terms and their definitions"
    )
    important_facts: list[str] = Field(
        default_factory=list,
        description="Important facts, dates, numbers"
    )
    assignments: list[str] = Field(
        default_factory=list,
        description="Mentioned assignments or action items"
    )
    brief_summary: str = Field(..., description="Brief 2-3 sentence summary")
    language: Optional[str] = Field(None, description="Language of the summary")
