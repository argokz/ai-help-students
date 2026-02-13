"""LLM service for RAG and summary generation with support for multiple providers."""
import json
import asyncio
import logging
from typing import Optional
from abc import ABC, abstractmethod

from ..config import settings
from ..models.chat import ChatMessage

logger = logging.getLogger(__name__)


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
    
    def __init__(self, model_name: str):
        self.model_name = model_name
        self._model = None
        self._genai_configured = False
    
    def _ensure_configured(self):
        """Ensure Gemini API is configured."""
        if not self._genai_configured:
            import google.generativeai as genai
            genai.configure(api_key=settings.gemini_api_key)
            self._genai_configured = True
    
    @property
    def model(self):
        """Lazy load Gemini model."""
        if self._model is None:
            import google.generativeai as genai
            self._ensure_configured()
            self._model = genai.GenerativeModel(
                model_name=self.model_name,
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
        
        self._ensure_configured()
        
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
    
    def __init__(self, model_name: str):
        self.model_name = model_name
        self._client = None
    
    @property
    def client(self):
        """Lazy load OpenAI client."""
        if self._client is None:
            from openai import AsyncOpenAI
            import os
            
            # В версии openai 1.86.0 может быть проблема с автоматической передачей proxies
            # из переменных окружения. Временно убираем их при создании клиента
            old_http_proxy = os.environ.pop('HTTP_PROXY', None)
            old_https_proxy = os.environ.pop('HTTPS_PROXY', None)
            old_http_proxy_lower = os.environ.pop('http_proxy', None)
            old_https_proxy_lower = os.environ.pop('https_proxy', None)
            
            try:
                # Создаём клиент только с api_key
                self._client = AsyncOpenAI(api_key=settings.openai_api_key)
                logger.debug(f"OpenAI client created successfully for model: {self.model_name}")
            except TypeError as e:
                logger.error(f"Error creating OpenAI client: {e}")
                raise
            finally:
                # Восстанавливаем переменные окружения
                if old_http_proxy:
                    os.environ['HTTP_PROXY'] = old_http_proxy
                if old_https_proxy:
                    os.environ['HTTPS_PROXY'] = old_https_proxy
                if old_http_proxy_lower:
                    os.environ['http_proxy'] = old_http_proxy_lower
                if old_https_proxy_lower:
                    os.environ['https_proxy'] = old_https_proxy_lower
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
            "model": self.model_name,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        
        if json_mode:
            kwargs["response_format"] = {"type": "json_object"}
        
        try:
            response = await self.client.chat.completions.create(**kwargs)
            return response.choices[0].message.content
        except Exception as e:
            # Пробрасываем исключение с информацией о модели для лучшей диагностики
            error_msg = f"OpenAI API error for model '{self.model_name}': {str(e)}"
            logger.error(error_msg)
            raise Exception(error_msg) from e


class LLMService:
    """
    LLM service with support for multiple providers and automatic fallback.
    
    Supports: Gemini, OpenAI with model fallback and provider fallback.
    """
    
    def __init__(self):
        self._provider: Optional[BaseLLMProvider] = None
        self._cached_provider: Optional[BaseLLMProvider] = None
        self._cached_model_name: Optional[str] = None
        self._cached_provider_type: Optional[str] = None  # "gemini" or "openai"
        
        # Parse model lists
        gemini_models_str = settings.gemini_models or ""
        openai_models_str = settings.openai_models or ""
        
        self.gemini_models = [m.strip() for m in gemini_models_str.split(",") if m.strip()]
        self.openai_models = [m.strip() for m in openai_models_str.split(",") if m.strip()]
        
        # Fallback to single model if lists are empty
        if not self.gemini_models:
            if settings.gemini_model:
                self.gemini_models = [settings.gemini_model]
            else:
                self.gemini_models = ["gemini-2.5-flash"]  # Ultimate fallback
                logger.warning("No Gemini models configured, using default: gemini-2.5-flash")
        
        if not self.openai_models:
            if settings.openai_model:
                self.openai_models = [settings.openai_model]
            else:
                self.openai_models = ["gpt-4o-mini"]  # Ultimate fallback
                logger.warning("No OpenAI models configured, using default: gpt-4o-mini")
        
        # Проверяем наличие API ключей
        if not settings.openai_api_key:
            logger.warning("OPENAI_API_KEY not set, OpenAI models will not work")
        if not settings.gemini_api_key:
            logger.warning("GEMINI_API_KEY not set, Gemini models will not work")
        
        logger.info(f"Initialized LLM service: priority={settings.ai_priority}, gemini_models={self.gemini_models}, openai_models={self.openai_models}")
    
    async def _try_provider(self, provider_type: str, model_name: str, system_prompt: str, user_message: str, **kwargs) -> tuple[bool, Optional[str]]:
        """Try to generate with specific provider and model. Returns (success, response)."""
        try:
            if provider_type == "gemini":
                provider = GeminiProvider(model_name)
            elif provider_type == "openai":
                provider = OpenAIProvider(model_name)
            else:
                return False, None
            
            response = await provider.generate(
                system_prompt=system_prompt,
                user_message=user_message,
                **kwargs
            )
            return True, response
        except Exception as e:
            # Логируем ошибку с полными деталями для диагностики
            error_msg = str(e)
            error_type = type(e).__name__
            import traceback
            error_trace = traceback.format_exc()
            
            logger.warning(f"Model {model_name} ({provider_type}) failed: {error_type}: {error_msg}")
            logger.debug(f"Full traceback for {model_name} ({provider_type}):\n{error_trace}")
            
            # Для критичных ошибок (API key, model not found, etc) логируем как error
            error_lower = error_msg.lower()
            if any(keyword in error_lower for keyword in ["api", "key", "auth", "unauthorized", "invalid", "not found", "does not exist"]):
                logger.error(f"API error for {provider_type}/{model_name}: {error_msg}")
            
            return False, None
    
    async def _find_working_provider(
        self,
        system_prompt: str,
        user_message: str,
        **kwargs
    ) -> tuple[BaseLLMProvider, str, str]:
        """
        Find working provider and model with fallback logic.
        Returns: (provider, model_name, provider_type)
        """
        # If we have cached working provider, try it first
        if self._cached_provider and self._cached_model_name and self._cached_provider_type:
            try:
                # Test cached provider
                test_response = await self._cached_provider.generate(
                    system_prompt=system_prompt,
                    user_message=user_message,
                    **kwargs
                )
                logger.debug(f"Using cached provider: {self._cached_provider_type}/{self._cached_model_name}")
                return self._cached_provider, self._cached_model_name, self._cached_provider_type
            except Exception as e:
                logger.warning(f"Cached provider {self._cached_provider_type}/{self._cached_model_name} failed: {e}, searching for new one")
                self._cached_provider = None
                self._cached_model_name = None
                self._cached_provider_type = None
        
        # Determine priority order
        priority = settings.ai_priority.lower()
        if priority not in ["gemini", "gpt"]:
            priority = "gemini"  # Default to gemini
        
        # Try priority provider first
        if priority == "gpt":
            # Try OpenAI models first
            for model in self.openai_models:
                success, response = await self._try_provider("openai", model, system_prompt, user_message, **kwargs)
                if success:
                    provider = OpenAIProvider(model)
                    self._cached_provider = provider
                    self._cached_model_name = model
                    self._cached_provider_type = "openai"
                    logger.info(f"Selected working model: openai/{model}")
                    return provider, model, "openai"
            
            # If all OpenAI models failed, try Gemini
            logger.info("All OpenAI models failed, trying Gemini...")
            for model in self.gemini_models:
                success, response = await self._try_provider("gemini", model, system_prompt, user_message, **kwargs)
                if success:
                    provider = GeminiProvider(model)
                    self._cached_provider = provider
                    self._cached_model_name = model
                    self._cached_provider_type = "gemini"
                    logger.info(f"Selected working model: gemini/{model}")
                    return provider, model, "gemini"
        else:
            # Try Gemini models first
            for model in self.gemini_models:
                success, response = await self._try_provider("gemini", model, system_prompt, user_message, **kwargs)
                if success:
                    provider = GeminiProvider(model)
                    self._cached_provider = provider
                    self._cached_model_name = model
                    self._cached_provider_type = "gemini"
                    logger.info(f"Selected working model: gemini/{model}")
                    return provider, model, "gemini"
            
            # If all Gemini models failed, try OpenAI
            logger.info("All Gemini models failed, trying OpenAI...")
            for model in self.openai_models:
                success, response = await self._try_provider("openai", model, system_prompt, user_message, **kwargs)
                if success:
                    provider = OpenAIProvider(model)
                    self._cached_provider = provider
                    self._cached_model_name = model
                    self._cached_provider_type = "openai"
                    logger.info(f"Selected working model: openai/{model}")
                    return provider, model, "openai"
        
        # If all models failed, raise error
        raise RuntimeError("All LLM models are unavailable. Check API keys and model availability.")
    
    @property
    async def provider(self) -> BaseLLMProvider:
        """Get the configured LLM provider (async to support fallback)."""
        # For backward compatibility, return cached or create default
        if self._provider is None:
            if settings.llm_provider == "gemini":
                if self.gemini_models:
                    self._provider = GeminiProvider(self.gemini_models[0])
                else:
                    self._provider = GeminiProvider(settings.gemini_model)
            elif settings.llm_provider == "openai":
                if self.openai_models:
                    self._provider = OpenAIProvider(self.openai_models[0])
                else:
                    self._provider = OpenAIProvider(settings.openai_model)
            else:
                raise ValueError(f"Unknown LLM provider: {settings.llm_provider}")
        return self._provider
    
    async def get_provider_with_fallback(
        self,
        system_prompt: str,
        user_message: str,
        **kwargs
    ) -> BaseLLMProvider:
        """Get provider with automatic fallback."""
        provider, model_name, provider_type = await self._find_working_provider(
            system_prompt, user_message, **kwargs
        )
        return provider
    
    def get_provider_info(self) -> dict:
        """Get information about the current/cached provider."""
        if self._cached_provider_type and self._cached_model_name:
            return {
                "provider": self._cached_provider_type,
                "model": self._cached_model_name,
            }
        # Fallback to settings
        if settings.llm_provider == "gemini":
            return {
                "provider": "gemini",
                "model": self.gemini_models[0] if self.gemini_models else settings.gemini_model,
            }
        else:
            return {
                "provider": "openai",
                "model": self.openai_models[0] if self.openai_models else settings.openai_model,
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
            provider = await self.get_provider_with_fallback(
                system_prompt=system_prompt,
                user_message=question,
                history=history,
                temperature=0.3,
                max_tokens=1000,
            )
            answer = await provider.generate(
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
            provider = await self.get_provider_with_fallback(
                system_prompt=system_prompt,
                user_message=question,
                history=history,
                temperature=0.3,
                max_tokens=1200,
            )
            return await provider.generate(
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
            provider = await self.get_provider_with_fallback(
                system_prompt=SUMMARY_SYSTEM_PROMPT,
                user_message=user_message,
                temperature=0.2,
                max_tokens=3000,
                json_mode=True,
            )
            content = await provider.generate(
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
        
        # Split text into chunks using unified service
        # Note: chunker_service is passed as arg or we can import global
        if chunker_service is None:
            from .chunker_service import chunker_service as global_chunker
            chunker_service = global_chunker

        # Use soft limit with sentence preservation
        adjusted_chunks = chunker_service.chunk_text_by_size(
            text, 
            chunk_size=chunk_size, 
            preserve_sentences=True
        )
        
        # Process each chunk
        chunk_summaries = []
        for i, chunk in enumerate(adjusted_chunks):
            try:
                user_message = f"Проанализируй эту часть лекции (часть {i+1} из {len(adjusted_chunks)}):\n\n{chunk}"
                provider = await self.get_provider_with_fallback(
                    system_prompt=SUMMARY_CHUNK_PROMPT,
                    user_message=user_message,
                    temperature=0.2,
                    max_tokens=2000,
                    json_mode=True,
                )
                content = await provider.generate(
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
            
            provider = await self.get_provider_with_fallback(
                system_prompt="Ты создаёшь финальные резюме лекции. Верни ТОЛЬКО валидный JSON.",
                user_message=final_prompt,
                temperature=0.2,
                max_tokens=2000,
                json_mode=True,
            )
            final_content = await provider.generate(
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
