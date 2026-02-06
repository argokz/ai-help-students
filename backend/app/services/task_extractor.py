"""Service for extracting tasks and deadlines from lecture transcripts using LLM."""
import logging
from datetime import datetime, timedelta
from typing import List, Dict, Optional
import re

from .llm_service import llm_service

logger = logging.getLogger(__name__)


class TaskExtractor:
    """Extract tasks, deadlines, and assignments from lecture transcripts."""
    
    EXTRACTION_PROMPT = """Проанализируй транскрипцию лекции и найди все упоминания заданий, дедлайнов, экзаменов и важных дат.

Для каждого найденного задания извлеки:
1. Название задания (что нужно сделать)
2. Срок выполнения (когда сдавать)
3. Дополнительные детали (если есть)

Текущая дата: {current_date}

Транскрипция лекции:
{transcript}

Верни результат СТРОГО в формате JSON (без markdown, без ```json):
{{
  "tasks": [
    {{
      "title": "Название задания",
      "description": "Детали задания",
      "deadline_text": "текст из лекции о сроке",
      "deadline_date": "YYYY-MM-DD или null если дата неясна",
      "deadline_time": "HH:MM или null",
      "confidence": 0.0-1.0
    }}
  ]
}}

Если заданий не найдено, верни: {{"tasks": []}}
"""

    @staticmethod
    def _parse_relative_date(text: str, reference_date: datetime) -> Optional[datetime]:
        """Parse relative dates like 'следующий четверг', 'через неделю'."""
        text_lower = text.lower()
        
        # Дни недели
        weekdays = {
            'понедельник': 0, 'вторник': 1, 'среда': 2, 'четверг': 3,
            'пятница': 4, 'суббота': 5, 'воскресенье': 6
        }
        
        # "следующий четверг"
        for day_name, day_num in weekdays.items():
            if day_name in text_lower:
                days_ahead = day_num - reference_date.weekday()
                if days_ahead <= 0 or 'следующ' in text_lower:
                    days_ahead += 7
                return reference_date + timedelta(days=days_ahead)
        
        # "через N дней/недель"
        if 'через' in text_lower:
            if 'неделю' in text_lower or 'недели' in text_lower:
                match = re.search(r'(\d+)', text)
                weeks = int(match.group(1)) if match else 1
                return reference_date + timedelta(weeks=weeks)
            elif 'день' in text_lower or 'дня' in text_lower or 'дней' in text_lower:
                match = re.search(r'(\d+)', text)
                days = int(match.group(1)) if match else 1
                return reference_date + timedelta(days=days)
        
        # "завтра"
        if 'завтра' in text_lower:
            return reference_date + timedelta(days=1)
        
        # "послезавтра"
        if 'послезавтра' in text_lower:
            return reference_date + timedelta(days=2)
        
        return None

    async def extract_tasks(self, transcript: str, lecture_date: Optional[datetime] = None) -> List[Dict]:
        """
        Extract tasks from lecture transcript.
        
        Args:
            transcript: Full lecture transcript text
            lecture_date: Date when lecture was recorded (for relative date parsing)
            
        Returns:
            List of extracted tasks with metadata
        """
        if not transcript or len(transcript.strip()) < 50:
            return []
        
        reference_date = lecture_date or datetime.now()
        current_date_str = reference_date.strftime("%d.%m.%Y (%A)")
        
        try:
            prompt = self.EXTRACTION_PROMPT.format(
                current_date=current_date_str,
                transcript=transcript[:4000]  # Limit to avoid token limits
            )
            
            response = await llm_service.generate(prompt)
            
            # Clean response - remove markdown if present
            response_text = response.strip()
            if response_text.startswith('```'):
                # Remove markdown code blocks
                lines = response_text.split('\n')
                response_text = '\n'.join(lines[1:-1]) if len(lines) > 2 else response_text
                response_text = response_text.replace('```json', '').replace('```', '').strip()
            
            import json
            result = json.loads(response_text)
            tasks = result.get('tasks', [])
            
            # Post-process tasks
            processed_tasks = []
            for task in tasks:
                # Try to parse deadline if LLM didn't provide exact date
                if not task.get('deadline_date') and task.get('deadline_text'):
                    parsed_date = self._parse_relative_date(task['deadline_text'], reference_date)
                    if parsed_date:
                        task['deadline_date'] = parsed_date.strftime('%Y-%m-%d')
                
                # Only include tasks with reasonable confidence
                if task.get('confidence', 0) >= 0.5:
                    processed_tasks.append(task)
            
            logger.info(f"Extracted {len(processed_tasks)} tasks from transcript")
            return processed_tasks
            
        except Exception as e:
            logger.error(f"Error extracting tasks: {e}")
            return []


task_extractor = TaskExtractor()
