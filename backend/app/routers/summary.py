"""Summary API router."""
from fastapi import APIRouter, HTTPException

from ..models import SummaryResponse
from ..services.storage_service import storage_service
from ..services.llm_service import llm_service

router = APIRouter()


@router.get("/{lecture_id}/summary", response_model=SummaryResponse)
async def get_summary(lecture_id: str, regenerate: bool = False):
    """
    Get structured summary of the lecture.
    
    Returns cached summary if available, or generates a new one.
    Set regenerate=true to force regeneration.
    """
    # Verify lecture exists
    lecture = await storage_service.get_lecture_metadata(lecture_id)
    
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    
    if lecture["status"] != "completed":
        raise HTTPException(
            status_code=400,
            detail=f"Lecture not ready for summarization. Status: {lecture['status']}"
        )
    
    # Check for cached summary
    if not regenerate:
        cached_summary = await storage_service.get_summary(lecture_id)
        if cached_summary:
            return SummaryResponse(
                lecture_id=lecture_id,
                **cached_summary
            )
    
    # Get transcript
    transcript = await storage_service.get_transcript(lecture_id)
    
    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")
    
    # Combine all segments into full text
    full_text = " ".join(seg["text"] for seg in transcript["segments"])
    
    # Generate summary using LLM
    summary = await llm_service.generate_summary(
        text=full_text,
        language=transcript.get("language")
    )
    
    # Cache the summary
    await storage_service.save_summary(lecture_id, summary)
    
    # Update lecture metadata
    await storage_service.update_lecture_metadata(lecture_id, {"has_summary": True})
    
    return SummaryResponse(
        lecture_id=lecture_id,
        **summary
    )
