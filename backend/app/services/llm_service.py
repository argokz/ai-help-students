"""LLM service for RAG and summary generation with support for multiple providers."""
import json
import asyncio
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

SUMMARY_SYSTEM_PROMPT = """Ты — ассистент для создания структурированных конспектов лекций.

Создай конспект в формате JSON со следующей структурой:
{
    "main_topics": ["тема 1", "тема 2", ...],
    "key_definitions": [{"term": "термин", "definition": "определение"}, ...],
    "important_facts": ["факт 1", "факт 2", ...],
    "assignments": ["задание 1", ...],
    "brief_summary": "Краткое резюме лекции в 2-3 предложениях"
}

Правила:
1. Используй ТОЛЬКО информацию из текста лекции
2. Пиши на том же языке, что и лекция
3. Если какой-то раздел пустой (например, нет заданий), оставь пустой массив []
4. Возвращай ТОЛЬКО валидный JSON, без markdown-разметки"""


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
        # Truncate very long texts to fit context window
        max_chars = 30000  # Gemini has larger context
        if len(text) > max_chars:
            text = text[:max_chars] + "... [текст сокращён]"
        
        user_message = f"Создай конспект следующей лекции:\n\n{text}"
        
        try:
            content = await self.provider.generate(
                system_prompt=SUMMARY_SYSTEM_PROMPT,
                user_message=user_message,
                temperature=0.2,
                max_tokens=2000,
                json_mode=True,
            )
            
            # Parse JSON response
            # Clean up potential markdown formatting
            content = content.strip()
            if content.startswith("```json"):
                content = content[7:]
            if content.startswith("```"):
                content = content[3:]
            if content.endswith("```"):
                content = content[:-3]
            content = content.strip()
            
            summary = json.loads(content)
            
            # Ensure all required fields exist
            summary.setdefault("main_topics", [])
            summary.setdefault("key_definitions", [])
            summary.setdefault("important_facts", [])
            summary.setdefault("assignments", [])
            summary.setdefault("brief_summary", "")
            summary["language"] = language
            
            return summary
            
        except json.JSONDecodeError as e:
            return {
                "main_topics": ["Ошибка парсинга конспекта"],
                "key_definitions": [],
                "important_facts": [],
                "assignments": [],
                "brief_summary": f"Не удалось создать структурированный конспект: {str(e)}",
                "language": language,
            }
        except Exception as e:
            return {
                "main_topics": ["Ошибка генерации"],
                "key_definitions": [],
                "important_facts": [],
                "assignments": [],
                "brief_summary": f"Ошибка при генерации конспекта: {str(e)}",
                "language": language,
            }


# Global instance
llm_service = LLMService()
