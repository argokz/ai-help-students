from datetime import datetime
from typing import Optional
from pydantic import BaseModel

class TaskBase(BaseModel):
    id: str
    title: str
    description: Optional[str] = None
    is_completed: bool = False
    completed_at: Optional[datetime] = None
    due_date: Optional[datetime] = None
    priority: str = "medium"
    lecture_id: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True

class TaskCreate(BaseModel):
    title: str
    description: Optional[str] = None
    due_date: Optional[datetime] = None
    priority: str = "medium"
    lecture_id: Optional[str] = None

class TaskUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    is_completed: Optional[bool] = None
    due_date: Optional[datetime] = None
    priority: Optional[str] = None
    lecture_id: Optional[str] = None

class TaskResponse(TaskBase):
    pass
