"""Chat API router for RAG Q&A."""
from fastapi import APIRouter, HTTPException

from ..models import ChatRequest, ChatResponse, SourceChunk
from ..services.storage_service import storage_service
from ..services.vector_store import vector_store
from ..services.llm_service import llm_service

router = APIRouter()


@router.post("/{lecture_id}/chat", response_model=ChatResponse)
async def chat_with_lecture(lecture_id: str, request: ChatRequest):
    """
    Ask a question about the lecture content.
    
    Uses RAG to find relevant chunks and generates an answer
    based only on the lecture content.
    """
    # Verify lecture exists and is processed
    lecture = await storage_service.get_lecture_metadata(lecture_id)
    
    if not lecture:
        raise HTTPException(status_code=404, detail="Lecture not found")
    
    if lecture["status"] != "completed":
        raise HTTPException(
            status_code=400,
            detail=f"Lecture not ready for chat. Status: {lecture['status']}"
        )
    
    # Search for relevant chunks
    relevant_chunks = await vector_store.search(
        lecture_id=lecture_id,
        query=request.question,
        top_k=5
    )
    
    if not relevant_chunks:
        return ChatResponse(
            answer="К сожалению, я не нашёл релевантной информации в этой лекции для ответа на ваш вопрос.",
            sources=[],
            confidence=None
        )
    
    # Build context from chunks
    context_parts = []
    source_chunks = []
    
    for chunk in relevant_chunks:
        context_parts.append(f"[{chunk['start_time']:.1f}s - {chunk['end_time']:.1f}s]: {chunk['text']}")
        source_chunks.append(SourceChunk(
            text=chunk["text"],
            start_time=chunk["start_time"],
            end_time=chunk["end_time"],
            relevance_score=chunk["score"]
        ))
    
    context = "\n\n".join(context_parts)
    
    # Generate answer using LLM
    answer, confidence = await llm_service.generate_answer(
        question=request.question,
        context=context,
        history=request.history
    )
    
    return ChatResponse(
        answer=answer,
        sources=source_chunks,
        confidence=confidence
    )
