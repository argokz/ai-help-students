"""Tasks (To-Do List) API router."""
from datetime import datetime
from typing import Annotated, Optional, List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, desc, or_
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..db_models import User, Task
from ..dependencies import get_current_user
from ..models.tasks import TaskCreate, TaskUpdate, TaskResponse

router = APIRouter(prefix="/tasks", tags=["tasks"])

@router.get("", response_model=List[TaskResponse])
async def get_tasks(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    completed: Optional[bool] = None,
    lecture_id: Optional[str] = None,
    priority: Optional[str] = None,
):
    """Get user's tasks with optional filters."""
    query = select(Task).where(Task.user_id == current_user.id)
    
    if completed is not None:
        query = query.where(Task.is_completed == completed)
    if lecture_id:
        query = query.where(Task.lecture_id == lecture_id)
    if priority:
        query = query.where(Task.priority == priority)
        
    # Order: incomplete first, then by due date, then by priority
    query = query.order_by(
        Task.is_completed,
        Task.due_date.asc().nullslast(),
        desc(Task.created_at)
    )
    
    result = await db.execute(query)
    return result.scalars().all()

@router.post("", response_model=TaskResponse)
async def create_task(
    task_in: TaskCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Create a new task."""
    task = Task(
        user_id=current_user.id,
        title=task_in.title,
        description=task_in.description,
        due_date=task_in.due_date,
        priority=task_in.priority,
        lecture_id=task_in.lecture_id,
    )
    db.add(task)
    await db.commit()
    await db.refresh(task)

    # Sync to Google Calendar if linked
    if current_user.google_refresh_token:
        try:
            from ..services.google_calendar import get_google_calendar_service
            gc_service = get_google_calendar_service(current_user.google_refresh_token)
            if gc_service:
                await gc_service.push_task(task)
        except Exception as e:
            print(f"Failed to sync task to Google: {e}")

    return task

@router.get("/{task_id}", response_model=TaskResponse)
async def get_task(
    task_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Get specific task."""
    task = await db.get(Task, task_id)
    if not task or task.user_id != current_user.id:
        raise HTTPException(404, "Task not found")
    return task

@router.patch("/{task_id}", response_model=TaskResponse)
async def update_task(
    task_id: str,
    task_in: TaskUpdate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Update task."""
    task = await db.get(Task, task_id)
    if not task or task.user_id != current_user.id:
        raise HTTPException(404, "Task not found")
        
    update_data = task_in.model_dump(exclude_unset=True)
    
    # Handle completion
    if 'is_completed' in update_data:
        if update_data['is_completed'] and not task.is_completed:
            task.completed_at = datetime.utcnow()
        elif not update_data['is_completed'] and task.is_completed:
            task.completed_at = None
    
    for key, value in update_data.items():
        setattr(task, key, value)
            
    await db.commit()
    await db.refresh(task)
    return task

@router.post("/{task_id}/toggle", response_model=TaskResponse)
async def toggle_task_completion(
    task_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Toggle task completion status."""
    task = await db.get(Task, task_id)
    if not task or task.user_id != current_user.id:
        raise HTTPException(404, "Task not found")
    
    task.is_completed = not task.is_completed
    task.completed_at = datetime.utcnow() if task.is_completed else None
    
    await db.commit()
    await db.refresh(task)
    return task

@router.delete("/{task_id}")
async def delete_task(
    task_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Delete task."""
    task = await db.get(Task, task_id)
    if not task or task.user_id != current_user.id:
        raise HTTPException(404, "Task not found")

    await db.delete(task)
    await db.commit()
    return {"ok": True}

@router.post("/from-extracted", response_model=TaskResponse)
async def create_task_from_extracted(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    task_data: dict,
):
    """Create task from AI-extracted data."""
    from datetime import datetime
    
    # Parse deadline
    deadline_date_str = task_data.get('deadline_date')
    deadline_time_str = task_data.get('deadline_time')
    
    due_date = None
    if deadline_date_str:
        try:
            deadline_date = datetime.strptime(deadline_date_str, '%Y-%m-%d')
            
            if deadline_time_str:
                deadline_time_obj = datetime.strptime(deadline_time_str, '%H:%M').time()
                due_date = datetime.combine(deadline_date.date(), deadline_time_obj)
            else:
                due_date = deadline_date
        except ValueError:
            pass
    
    task = Task(
        user_id=current_user.id,
        title=task_data.get('title', 'Задание'),
        description=task_data.get('description'),
        due_date=due_date,
        priority='high',  # Extracted tasks are usually important
        lecture_id=task_data.get('lecture_id'),
    )
    
    db.add(task)
    await db.commit()
    await db.refresh(task)

    # Sync to Google Calendar if linked
    if current_user.google_refresh_token:
        try:
            from ..services.google_calendar import get_google_calendar_service
            gc_service = get_google_calendar_service(current_user.google_refresh_token)
            if gc_service:
                await gc_service.push_task(task)
        except Exception as e:
            print(f"Failed to sync task to Google: {e}")

    return task
