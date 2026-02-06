from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel

class CalendarEventBase(BaseModel):
    id: str
    title: str
    description: Optional[str] = None
    start_time: datetime
    end_time: datetime
    location: Optional[str] = None
    remind_at: Optional[datetime] = None
    color: Optional[str] = "blue"
    created_at: datetime
    
    class Config:
        from_attributes = True

class CalendarEventCreate(BaseModel):
    title: str
    description: Optional[str] = None
    start_time: datetime
    end_time: datetime
    location: Optional[str] = None
    remind_at: Optional[datetime] = None
    color: Optional[str] = "blue"

class CalendarEventUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    location: Optional[str] = None
    remind_at: Optional[datetime] = None
    color: Optional[str] = None

class CalendarResponse(CalendarEventBase):
    pass
