"""LLM service for RAG and summary generation with support for multiple providers."""
import json
import asyncio
import logging
from typing import Optional
from abc import ABC, abstractmethod

from ..config import settings
from ..models.chat import ChatMessage


# System prompts
RAG_SYSTEM_PROMPT = """Ты — умный ассистент для студентов, который отвечает на вопросы ТОЛЬКО на основе предоставленного контекста из лекции.

Правила:
1. Отвечай ТОЛЬКО на основе информации из контекста ниже
2. Если ответа нет в контексте, честно скажи: "В лекции об этом не говорилось"
3. Цитируй таймкоды в формате [MM:SS], когда ссылаешься на конкретные моменты
4. Отвечай на том же языке, на котором задан вопрос
5. Будь кратким, но информативным

Контекст из лекции:
{context}"""

RAG_GLOBAL_SYSTEM_PROMPT = """Ты — умный ассистент для студентов. Отвечаешь на вопросы на основе контекста из НЕСКОЛЬКИХ лекций.

Правила:
1. Отвечай ТОЛЬКО на основе предоставленного контекста из лекций
2. Обязательно указывай, в какой лекции (название) найдена информация: например «В лекции "Математический анализ" сказано...»
3. Если ответа нет в контексте, честно скажи: "В ваших лекциях об этом не говорилось"
4. Отвечай на том же языке, на котором задан вопрос
5. Будь кратким, но информативным

Контекст из лекций (каждый блок помечен названием лекции):
{context}"""

SUMMARY_SYSTEM_PROMPT = """Ты — ассистент для создания структурированных конспектов лекций.

Создай конспект в формате JSON со следующей структурой:
{
    "main_topics": ["тема 1", "тема 2", ...],
    "key_definitions": [{"term": "термин", "definition": "определение"}, ...],
    "important_facts": ["факт 1", "факт 2", ...],
    "assignments": ["задание 1", ...],
    "brief_summary": "Краткое резюме лекции в 2-3 предложениях",
    "detailed_summary": "Детальный конспект с основными идеями и выводами"
}

Правила:
1. Используй ТОЛЬКО информацию из текста лекции
2. Пиши на том же языке, что и лекция
3. Если какой-то раздел пустой (например, нет заданий), оставь пустой массив []
4. Возвращай ТОЛЬКО валидный JSON, без markdown-разметки
5. В detailed_summary включи все важные детали, ничего не теряй"""

SUMMARY_CHUNK_PROMPT = """Ты анализируешь часть большой лекции. Извлеки из этого фрагмента:
- Основные темы
- Ключевые определения
- Важные факты
- Задания (если есть)

Верни результат в формате JSON:
{
    "main_topics": ["тема 1", ...],
    "key_definitions": [{"term": "...", "definition": "..."}, ...],
    "important_facts": ["факт 1", ...],
    "assignments": ["задание 1", ...]
}

Используй ТОЛЬКО информацию из предоставленного текста. Возвращай ТОЛЬКО валидный JSON."""


class BaseLLMProvider(ABC):
    """Base class for LLM providers."""
    
    @abstractmethod
    async def generate(
        self,
        system_prompt: str,
        user_message: str,
        history: Optional[list] = None,
        temperature: float = 0.3,
        max_tokens: int = 1000,
        json_mode: bool = False,
    ) -> str:
        """Generate a response from the LLM."""
        pass


class GeminiProvider(BaseLLMProvider):
    """Google Gemini API provider."""
    
    def __init__(self):
        self._model = None
    
    @property
    def model(self):
        """Lazy load Gemini model."""
        if self._model is None:
            import google.generativeai as genai
            
            genai.configure(api_key=settings.gemini_api_key)
            self._model = genai.GenerativeModel(
                model_name=settings.gemini_model,
                generation_config={
                    "temperature": 0.3,
                    "max_output_tokens": 2000,
                }
            )
        return self._model
    
    async def generate(
        self,
        system_prompt: str,
        user_message: str,
        history: Optional[list] = None,
        temperature: float = 0.3,
        max_tokens: int = 1000,
        json_mode: bool = False,
    ) -> str:
        """Generate response using Gemini."""
        import google.generativeai as genai
        
        # Build the full prompt
        full_prompt = f"{system_prompt}\n\nПользователь: {user_message}"
        
        # Add history if provided
        if history:
            history_text = "\n".join([
                f"{'Пользователь' if msg.role == 'user' else 'Ассистент'}: {msg.content}"
                for msg in history[-6:]  # Last 6 messages
            ])
            full_prompt = f"{system_prompt}\n\nИстория диалога:\n{history_text}\n\nПользователь: {user_message}"
        
        # Configure generation
        generation_config = genai.GenerationConfig(
            temperature=temperature,
            max_output_tokens=max_tokens,
        )
        
        if json_mode:
            generation_config.response_mime_type = "application/json"
        
        # Run in thread pool since the SDK is synchronous
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None,
            lambda: self.model.generate_content(
                full_prompt,
                generation_config=generation_config,
            )
        )
        
        return response.text


class OpenAIProvider(BaseLLMProvider):
    """OpenAI API provider."""
    
    def __init__(self):
        self._client = None
    
    @property
    def client(self):
        """Lazy load OpenAI client."""
        if self._client is None:
            from openai import AsyncOpenAI
            self._client = AsyncOpenAI(api_key=settings.openai_api_key)
        return self._client
    
    async def generate(
        self,
        system_prompt: str,
        user_message: str,
        history: Optional[list] = None,
        temperature: float = 0.3,
        max_tokens: int = 1000,
        json_mode: bool = False,
    ) -> str:
        """Generate response using OpenAI."""
        messages = [{"role": "system", "content": system_prompt}]
        
        if history:
            for msg in history[-6:]:
                messages.append({
                    "role": msg.role,
                    "content": msg.content
                })
        
        messages.append({"role": "user", "content": user_message})
        
        kwargs = {
            "model": settings.openai_model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        
        if json_mode:
            kwargs["response_format"] = {"type": "json_object"}
        
        response = await self.client.chat.completions.create(**kwargs)
        return response.choices[0].message.content


class LLMService:
    """
    LLM service with support for multiple providers.
    
    Supports: Gemini (default), OpenAI
    """
    
    def __init__(self):
        self._provider: Optional[BaseLLMProvider] = None
    
    @property
    def provider(self) -> BaseLLMProvider:
        """Get the configured LLM provider."""
        if self._provider is None:
            if settings.llm_provider == "gemini":
                self._provider = GeminiProvider()
            elif settings.llm_provider == "openai":
                self._provider = OpenAIProvider()
            else:
                raise ValueError(f"Unknown LLM provider: {settings.llm_provider}")
        return self._provider
    
    def get_provider_info(self) -> dict:
        """Get information about the current provider."""
        if settings.llm_provider == "gemini":
            return {
                "provider": "gemini",
                "model": settings.gemini_model,
            }
        else:
            return {
                "provider": "openai",
                "model": settings.openai_model,
            }
    
    async def generate_answer(
        self,
        question: str,
        context: str,
        history: Optional[list[ChatMessage]] = None,
    ) -> tuple[str, Optional[float]]:
        """
        Generate an answer to a question based on lecture context.
        
        Args:
            question: User's question
            context: Relevant context from lecture chunks
            history: Previous conversation history
            
        Returns:
            Tuple of (answer, confidence)
        """
        system_prompt = RAG_SYSTEM_PROMPT.format(context=context)
        
        try:
            answer = await self.provider.generate(
                system_prompt=system_prompt,
                user_message=question,
                history=history,
                temperature=0.3,
                max_tokens=1000,
            )
            
            # Simple confidence heuristic
            confidence = 0.8 if "в лекции" not in answer.lower() else 0.5
            if "не говорилось" in answer.lower() or "нет информации" in answer.lower():
                confidence = None
            
            return answer, confidence
            
        except Exception as e:
            return f"Ошибка при генерации ответа: {str(e)}", None

    async def generate_global_answer(
        self,
        question: str,
        context: str,
        history: Optional[list[ChatMessage]] = None,
    ) -> str:
        """Ответ на вопрос по контексту из нескольких лекций (с указанием источников)."""
        system_prompt = RAG_GLOBAL_SYSTEM_PROMPT.format(context=context)
        try:
            return await self.provider.generate(
                system_prompt=system_prompt,
                user_message=question,
                history=history,
                temperature=0.3,
                max_tokens=1200,
            )
        except Exception as e:
            return f"Ошибка при генерации ответа: {str(e)}"

    async def generate_summary(
        self,
        text: str,
        language: Optional[str] = None,
    ) -> dict:
        """
        Generate a structured summary of lecture text.
        
        Args:
            text: Full lecture text
            language: Language of the lecture
            
        Returns:
            Dict with summary structure
        """
        from ..services.chunker_service import chunker_service
        import logging
        
        # For large texts, use chunking strategy
        max_chars_per_chunk = 25000  # Safe limit for Gemini
        text_length = len(text)
        
        if text_length <= max_chars_per_chunk:
            # Small lecture - process directly
            return await self._generate_summary_single(text, language)
        else:
            # Large lecture - use chunking
            return await self._generate_summary_chunked(text, language, max_chars_per_chunk, chunker_service)
    
    async def _generate_summary_single(
        self,
        text: str,
        language: Optional[str] = None,
    ) -> dict:
        """Generate summary for a single chunk."""
        user_message = f"Создай конспект следующей лекции:\n\n{text}"
        
        try:
            content = await self.provider.generate(
                system_prompt=SUMMARY_SYSTEM_PROMPT,
                user_message=user_message,
                temperature=0.2,
                max_tokens=3000,
                json_mode=True,
            )
            
            summary = self._parse_json_response(content)
            
            # Ensure all required fields exist
            summary.setdefault("main_topics", [])
            summary.setdefault("key_definitions", [])
            summary.setdefault("important_facts", [])
            summary.setdefault("assignments", [])
            summary.setdefault("brief_summary", "")
            summary.setdefault("detailed_summary", "")
            summary["language"] = language
            
            return summary
            
        except Exception as e:
            return self._create_error_summary(f"Ошибка при генерации конспекта: {str(e)}", language)
    
    async def _generate_summary_chunked(
        self,
        text: str,
        language: Optional[str] = None,
        chunk_size: int = 25000,
        chunker_service = None,
    ) -> dict:
        """Generate summary for large lecture using chunking."""
        import logging
        
        # Split text into chunks
        chunks = chunker_service.chunk_text(text, preserve_sentences=True)
        
        # Adjust chunk size to fit within limits
        adjusted_chunks = []
        for chunk in chunks:
            if len(chunk) > chunk_size:
                # Further split if needed
                for i in range(0, len(chunk), chunk_size):
                    adjusted_chunks.append(chunk[i:i+chunk_size])
            else:
                adjusted_chunks.append(chunk)
        
        # Process each chunk
        chunk_summaries = []
        for i, chunk in enumerate(adjusted_chunks):
            try:
                user_message = f"Проанализируй эту часть лекции (часть {i+1} из {len(adjusted_chunks)}):\n\n{chunk}"
                content = await self.provider.generate(
                    system_prompt=SUMMARY_CHUNK_PROMPT,
                    user_message=user_message,
                    temperature=0.2,
                    max_tokens=2000,
                    json_mode=True,
                )
                chunk_data = self._parse_json_response(content)
                chunk_summaries.append(chunk_data)
            except Exception as e:
                logging.warning(f"Error processing chunk {i+1}: {e}")
                continue
        
        # Merge chunk summaries
        merged = {
            "main_topics": [],
            "key_definitions": [],
            "important_facts": [],
            "assignments": [],
            "brief_summary": "",
            "detailed_summary": "",
        }
        
        seen_topics = set()
        seen_definitions = {}
        
        for chunk_summary in chunk_summaries:
            # Merge topics (deduplicate)
            for topic in chunk_summary.get("main_topics", []):
                if topic not in seen_topics:
                    merged["main_topics"].append(topic)
                    seen_topics.add(topic)
            
            # Merge definitions (deduplicate by term)
            for def_item in chunk_summary.get("key_definitions", []):
                term = def_item.get("term", "")
                if term and term not in seen_definitions:
                    merged["key_definitions"].append(def_item)
                    seen_definitions[term] = def_item
            
            # Merge facts
            merged["important_facts"].extend(chunk_summary.get("important_facts", []))
            
            # Merge assignments
            merged["assignments"].extend(chunk_summary.get("assignments", []))
        
        # Generate final brief and detailed summaries
        try:
            # Create summary of all chunks for final summary
            chunks_text = "\n\n".join([f"Часть {i+1}:\n{chunk}" for i, chunk in enumerate(adjusted_chunks[:5])])  # Use first 5 chunks
            final_prompt = f"""На основе анализа всех частей лекции создай:
1. Краткое резюме (2-3 предложения) - brief_summary
2. Детальный конспект с основными идеями и выводами - detailed_summary

Содержание лекции:
{chunks_text[:40000]}

Верни JSON:
{{
    "brief_summary": "...",
    "detailed_summary": "..."
}}"""
            
            final_content = await self.provider.generate(
                system_prompt="Ты создаёшь финальные резюме лекции. Верни ТОЛЬКО валидный JSON.",
                user_message=final_prompt,
                temperature=0.2,
                max_tokens=2000,
                json_mode=True,
            )
            final_data = self._parse_json_response(final_content)
            merged["brief_summary"] = final_data.get("brief_summary", "")
            merged["detailed_summary"] = final_data.get("detailed_summary", "")
        except Exception as e:
            logging.warning(f"Error generating final summaries: {e}")
            merged["brief_summary"] = f"Конспект создан из {len(chunk_summaries)} частей лекции"
            merged["detailed_summary"] = "Детальный конспект объединён из всех частей лекции"
        
        merged["language"] = language
        return merged
    
    def _parse_json_response(self, content: str) -> dict:
        """Parse JSON response, handling markdown formatting."""
        import json
        content = content.strip()
        if content.startswith("```json"):
            content = content[7:]
        if content.startswith("```"):
            content = content[3:]
        if content.endswith("```"):
            content = content[:-3]
        content = content.strip()
        return json.loads(content)
    
    def _create_error_summary(self, error_msg: str, language: Optional[str] = None) -> dict:
        """Create error summary structure."""
        return {
            "main_topics": [],
            "key_definitions": [],
            "important_facts": [],
            "assignments": [],
            "brief_summary": error_msg,
            "detailed_summary": "",
            "language": language,
        }


# Global instance
llm_service = LLMService()
