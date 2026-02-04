"""Chat API router for RAG Q&A."""
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..db_models import User
from ..dependencies import get_current_user
from ..models import ChatRequest, ChatResponse, SourceChunk
from ..services.llm_service import llm_service
from ..services.storage_service import storage_service
from ..services.vector_store import vector_store

router = APIRouter()


def _check_lecture_owner(lecture: dict, user_id: str) -> None:
    if lecture.get("user_id") != user_id:
        raise HTTPException(status_code=403, detail="Доступ запрещён")


@router.post("/{lecture_id}/chat", response_model=ChatResponse)
async def chat_with_lecture(
    lecture_id: str,
    request: ChatRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Ask a question about the lecture. Lecture must belong to current user."""
    lecture = await storage_service.get_lecture_metadata(lecture_id, db)
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    _check_lecture_owner(lecture, current_user.id)
    if lecture["status"] != "completed":
        raise HTTPException(
            status_code=400,
            detail=f"Lecture not ready for chat. Status: {lecture['status']}",
        )

    relevant_chunks = await vector_store.search(
        lecture_id=lecture_id,
        query=request.question,
        top_k=5,
    )
    if not relevant_chunks:
        return ChatResponse(
            answer="К сожалению, я не нашёл релевантной информации в этой лекции для ответа на ваш вопрос.",
            sources=[],
            confidence=None,
        )

    context_parts = []
    source_chunks = []
    for chunk in relevant_chunks:
        context_parts.append(f"[{chunk['start_time']:.1f}s - {chunk['end_time']:.1f}s]: {chunk['text']}")
        source_chunks.append(
            SourceChunk(
                text=chunk["text"],
                start_time=chunk["start_time"],
                end_time=chunk["end_time"],
                relevance_score=chunk["score"],
            )
        )
    context = "\n\n".join(context_parts)
    answer, confidence = await llm_service.generate_answer(
        question=request.question,
        context=context,
        history=request.history,
    )
    return ChatResponse(answer=answer, sources=source_chunks, confidence=confidence)
