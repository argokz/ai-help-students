"""Calendar events API router."""
from datetime import datetime, timedelta
from typing import Annotated, Optional, List

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..db_models import User, CalendarEvent
from ..dependencies import get_current_user
from ..models.calendar import CalendarEventCreate, CalendarEventUpdate, CalendarResponse

router = APIRouter(prefix="/calendar", tags=["calendar"])

@router.get("", response_model=List[CalendarResponse])
async def get_events(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
):
    """Get calendar events, optionally filtered by date range."""
    query = select(CalendarEvent).where(CalendarEvent.user_id == current_user.id)
    
    if start_date:
        query = query.where(CalendarEvent.start_time >= start_date)
    if end_date:
        query = query.where(CalendarEvent.start_time <= end_date)
        
    query = query.order_by(CalendarEvent.start_time)
    
    result = await db.execute(query)
    return result.scalars().all()

@router.post("", response_model=CalendarResponse)
async def create_event(
    event_in: CalendarEventCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Create a new calendar event."""
    event = CalendarEvent(
        user_id=current_user.id,
        title=event_in.title,
        description=event_in.description,
        start_time=event_in.start_time,
        end_time=event_in.end_time,
        location=event_in.location,
        remind_at=event_in.remind_at,
        color=event_in.color,
    )
    db.add(event)
    await db.commit()
    await db.refresh(event)

    # Sync to Google Calendar if linked
    if current_user.google_refresh_token:
        try:
            from ..services.google_calendar import get_google_calendar_service
            gc_service = get_google_calendar_service(current_user.google_refresh_token)
            if gc_service:
                await gc_service.push_event(event)
        except Exception as e:
            print(f"Failed to sync to Google: {e}")

    return event

@router.get("/{event_id}", response_model=CalendarResponse)
async def get_event(
    event_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Get specific event."""
    event = await db.get(CalendarEvent, event_id)
    if not event or event.user_id != current_user.id:
        raise HTTPException(404, "Event not found")
    return event

@router.patch("/{event_id}", response_model=CalendarResponse)
async def update_event(
    event_id: str,
    event_in: CalendarEventUpdate,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Update event."""
    event = await db.get(CalendarEvent, event_id)
    if not event or event.user_id != current_user.id:
        raise HTTPException(404, "Event not found")
        
    update_data = event_in.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(event, key, value)
            
    await db.commit()
    await db.refresh(event)
    return event

@router.delete("/{event_id}")
async def delete_event(
    event_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Delete event."""
    event = await db.get(CalendarEvent, event_id)
    if not event or event.user_id != current_user.id:
        raise HTTPException(404, "Event not found")

    await db.delete(event)
    await db.commit()
    return {"ok": True}

@router.post("/create-from-task", response_model=CalendarResponse)
async def create_event_from_task(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    task_data: dict,
):
    """Create calendar event from extracted task data."""
    from datetime import datetime, time
    
    # Parse deadline
    deadline_date_str = task_data.get('deadline_date')
    deadline_time_str = task_data.get('deadline_time')
    
    if not deadline_date_str:
        raise HTTPException(400, "Deadline date is required")
    
    try:
        deadline_date = datetime.strptime(deadline_date_str, '%Y-%m-%d')
        
        if deadline_time_str:
            deadline_time_obj = datetime.strptime(deadline_time_str, '%H:%M').time()
        else:
            deadline_time_obj = time(23, 59)  # End of day by default
        
        start_time = datetime.combine(deadline_date.date(), deadline_time_obj)
        end_time = start_time + timedelta(hours=1)
        
    except ValueError as e:
        raise HTTPException(400, f"Invalid date format: {e}")
    
    event = CalendarEvent(
        user_id=current_user.id,
        title=task_data.get('title', 'Задание'),
        description=task_data.get('description'),
        start_time=start_time,
        end_time=end_time,
        color='red',  # Deadlines are red
    )
    
    db.add(event)
    await db.commit()
    await db.refresh(event)

    # Sync to Google Calendar if linked
    if current_user.google_refresh_token:
        try:
            from ..services.google_calendar import get_google_calendar_service
            gc_service = get_google_calendar_service(current_user.google_refresh_token)
            if gc_service:
                await gc_service.push_event(event)
        except Exception as e:
            print(f"Failed to sync to Google: {e}")

    return event

