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
            # Use chunking for long transcripts
            max_chunk_size = 15000  # Increased from 4000
            
            if len(transcript) > max_chunk_size:
                # Process in chunks and merge results
                from ..services.chunker_service import chunker_service
                
                chunks = chunker_service.chunk_text_by_size(
                    transcript,
                    chunk_size=max_chunk_size,
                    preserve_sentences=True
                )
                
                all_tasks = []
                
                for i, chunk in enumerate(chunks):
                    chunk_tasks = await self._extract_from_chunk(
                        chunk, reference_date, current_date_str, str(i+1)
                    )
                    all_tasks.extend(chunk_tasks)
                
                # Deduplicate tasks
                seen_titles = set()
                unique_tasks = []
                for task in all_tasks:
                    title = task.get('title', '')
                    if title and title not in seen_titles:
                        seen_titles.add(title)
                        unique_tasks.append(task)
                
                processed_tasks = self._post_process_tasks(unique_tasks, reference_date)
                logger.info(f"Extracted {len(processed_tasks)} tasks from {len(chunks)} chunks")
                return processed_tasks
            else:
                # Single chunk processing
                tasks = await self._extract_from_chunk(transcript, reference_date, current_date_str, "1")
                processed_tasks = self._post_process_tasks(tasks, reference_date)
                logger.info(f"Extracted {len(processed_tasks)} tasks from transcript")
                return processed_tasks
            
        except Exception as e:
            logger.error(f"Error extracting tasks: {e}")
            return []
    
    async def _extract_from_chunk(
        self,
        chunk_text: str,
        reference_date: datetime,
        current_date_str: str,
        chunk_id: str,
    ) -> List[Dict]:
        """Extract tasks from a single chunk."""
        prompt = self.EXTRACTION_PROMPT.format(
            current_date=current_date_str,
            transcript=chunk_text
        )
        
        try:
            system_prompt = "Ты анализируешь транскрипцию лекции и извлекаешь задания. Верни ТОЛЬКО валидный JSON."
            provider = await llm_service.get_provider_with_fallback(
                system_prompt=system_prompt,
                user_message=prompt,
                temperature=0.2,
                max_tokens=2000,
                json_mode=True,
            )
            response = await provider.generate(
                system_prompt=system_prompt,
                user_message=prompt,
                temperature=0.2,
                max_tokens=2000,
                json_mode=True,
            )
            
            # Clean response - remove markdown if present
            response_text = response.strip()
            if response_text.startswith('```'):
                # Remove markdown code blocks
                lines = response_text.split('\n')
                response_text = '\n'.join(lines[1:-1]) if len(lines) > 2 else response_text
                response_text = response_text.replace('```json', '').replace('```', '').strip()
            
            import json
            try:
                result = json.loads(response_text)
                tasks = result.get('tasks', [])
                return tasks
            except json.JSONDecodeError as json_err:
                logger.warning(f"JSON parse error in chunk {chunk_id}: {json_err}")
                logger.debug(f"Response text (first 500 chars): {response_text[:500]}")
                
                # Попытка исправить распространённые проблемы с JSON
                try:
                    # 1. Ищем последний валидный JSON объект (до ошибки)
                    error_pos = json_err.pos if hasattr(json_err, 'pos') else len(response_text)
                    # Пробуем найти последнюю закрывающую скобку до ошибки
                    truncated = response_text[:error_pos]
                    last_brace = truncated.rfind('}')
                    if last_brace > 0:
                        # Находим начало объекта
                        first_brace = truncated.rfind('{', 0, last_brace)
                        if first_brace >= 0:
                            json_part = truncated[first_brace:last_brace+1]
                            result = json.loads(json_part)
                            tasks = result.get('tasks', [])
                            logger.info(f"Recovered {len(tasks)} tasks from truncated JSON in chunk {chunk_id}")
                            return tasks
                except Exception as recover_err:
                    logger.debug(f"Could not recover JSON: {recover_err}")
                
                # Если не получилось исправить, возвращаем пустой список
                logger.error(f"Could not parse JSON from chunk {chunk_id}, returning empty tasks")
                return []
            
        except Exception as e:
            logger.warning(f"Error extracting tasks from chunk {chunk_id}: {e}")
            return []
    
    def _post_process_tasks(self, tasks: List[Dict], reference_date: datetime) -> List[Dict]:
        """Post-process extracted tasks."""
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
        
        return processed_tasks


task_extractor = TaskExtractor()
