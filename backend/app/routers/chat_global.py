"""Global chat API — ответы на вопросы по всем лекциям пользователя."""
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..db_models import User
from ..dependencies import get_current_user
from ..models import GlobalChatRequest, GlobalChatResponse, GlobalChatSource
from ..services.llm_service import llm_service
from ..services.storage_service import storage_service
from ..services.vector_store import vector_store

router = APIRouter()


@router.post("/global", response_model=GlobalChatResponse)
async def global_chat(
    request: GlobalChatRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """
    Общий ИИ-чат по всем вашим лекциям.
    Ищет по всем лекциям и отвечает с указанием источника (в какой лекции найдено).
    """
    lectures = await storage_service.list_lectures(current_user.id, db)
    completed = [l for l in lectures if l.get("status") == "completed"]
    if not completed:
        return GlobalChatResponse(
            answer="У вас пока нет обработанных лекций. Загрузите и дождитесь обработки — тогда можно будет задавать вопросы.",
            sources=[],
        )
    lecture_ids = [l["id"] for l in completed]
    lecture_titles = {l["id"]: l.get("title") or "Без названия" for l in completed}

    search_results = await vector_store.search_all_lectures(
        lecture_ids=lecture_ids,
        query=request.question,
        top_k_per_lecture=3,
        min_score=0.25,
    )
    if not search_results:
        return GlobalChatResponse(
            answer="К сожалению, по вашим лекциям не нашлось релевантной информации для ответа на этот вопрос.",
            sources=[],
        )

    context_parts = []
    sources_out = []
    for item in search_results:
        lid = item["lecture_id"]
        title = lecture_titles.get(lid, lid)
        for chunk in item["chunks"]:
            context_parts.append(
                f'[Лекция «{title}»]:\n{chunk["text"]}'
            )
            sources_out.append(
                GlobalChatSource(
                    lecture_id=lid,
                    lecture_title=title,
                    snippet=chunk["text"][:300] + ("…" if len(chunk["text"]) > 300 else ""),
                )
            )
    context = "\n\n".join(context_parts)
    answer = await llm_service.generate_global_answer(
        question=request.question,
        context=context,
        history=request.history,
    )
    return GlobalChatResponse(answer=answer, sources=sources_out)
