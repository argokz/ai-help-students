from datetime import datetime
from typing import List, Optional

from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from ..config import settings
from ..db_models import CalendarEvent, Task

class GoogleCalendarService:
    def __init__(self, refresh_token: str):
        self.credentials = Credentials(
            token=None,
            refresh_token=refresh_token,
            token_uri="https://oauth2.googleapis.com/token",
            client_id=settings.google_client_id,
            client_secret=settings.google_client_secret,
            scopes=["https://www.googleapis.com/auth/calendar.events"]
        )
        self.service = build("calendar", "v3", credentials=self.credentials)

    async def push_event(self, event: CalendarEvent):
        """Push a local calendar event to Google Calendar."""
        try:
            google_event = {
                'summary': event.title,
                'location': event.location,
                'description': event.description,
                'start': {
                    'dateTime': event.start_time.isoformat(),
                    'timeZone': 'UTC',
                },
                'end': {
                    'dateTime': event.end_time.isoformat(),
                    'timeZone': 'UTC',
                },
                'reminders': {
                    'useDefault': False,
                    'overrides': [
                        {'method': 'popup', 'minutes': 15},
                    ],
                },
            }
            
            # If color is specified, we could map it to Google Calendar colorId
            # but for now let's keep it simple.
            
            result = self.service.events().insert(calendarId='primary', body=google_event).execute()
            return result.get('id')
        except HttpError as error:
            print(f"An error occurred: {error}")
            return None

    async def push_task(self, task: Task):
        """Push a task as an all-day event (or specific time if due_date has time)."""
        if not task.due_date:
            return None
            
        try:
            google_event = {
                'summary': f"📌 {task.title}",
                'description': task.description or "",
                'start': {
                    'date': task.due_date.date().isoformat(),
                },
                'end': {
                    'date': task.due_date.date().isoformat(),
                },
            }
            
            result = self.service.events().insert(calendarId='primary', body=google_event).execute()
            return result.get('id')
        except HttpError as error:
            print(f"An error occurred: {error}")
            return None

def get_google_calendar_service(refresh_token: Optional[str]):
    if not refresh_token:
        return None
    return GoogleCalendarService(refresh_token)
