"""FastAPI application entry point."""
import logging
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .database import init_db
from .routers import auth, chat, chat_global, lectures, summary, notes, calendar, tasks

# Единая настройка логирования для всего приложения
def _setup_logging() -> None:
    level = getattr(logging, settings.log_level.upper(), logging.INFO)
    fmt = "%(asctime)s | %(levelname)-7s | %(name)s | %(message)s"
    datefmt = "%Y-%m-%d %H:%M:%S"
    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stdout)]
    if settings.log_file:
        try:
            handlers.append(logging.FileHandler(settings.log_file, encoding="utf-8"))
        except OSError as e:
            sys.stderr.write(f"Could not open log file {settings.log_file}: {e}\n")
    for h in handlers:
        h.setFormatter(logging.Formatter(fmt, datefmt=datefmt))
    logging.basicConfig(level=level, handlers=handlers, force=True)
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)  # меньше шума от access-логов
    # Подавляем ошибки телеметрии ChromaDB (не критичные)
    logging.getLogger("chromadb.telemetry.product.posthog").setLevel(logging.CRITICAL)

_setup_logging()
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Create DB tables on startup and recover incomplete lectures."""
    try:
        await init_db()
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.warning(f"Database initialization failed: {e}. App will continue but DB features may not work.")
    
    # Восстановление незавершённых обработок после перезагрузки сервера
    try:
        await _recover_incomplete_lectures()
    except Exception as e:
        logger.error(f"Failed to recover incomplete lectures: {e}")
    
    yield
    # shutdown if needed


async def _recover_incomplete_lectures():
    """Восстановить обработку лекций со статусом pending или processing после перезагрузки."""
    from .database import AsyncSessionLocal
    from .services import storage_service
    from .routers.lectures import process_lecture_transcription
    
    async with AsyncSessionLocal() as db:
        incomplete = await storage_service.get_incomplete_lectures(db)
        
        if not incomplete:
            logger.info("No incomplete lectures to recover")
            return
        
        logger.info(f"Found {len(incomplete)} incomplete lecture(s), recovering...")
        
        for lecture in incomplete:
            lecture_id = lecture["id"]
            audio_path = lecture.get("audio_path")
            language = lecture.get("language")
            
            if not audio_path:
                logger.warning(f"Lecture {lecture_id} has no audio_path, marking as failed")
                await storage_service.update_lecture_status(lecture_id, "failed", db)
                await storage_service.update_lecture_metadata(
                    lecture_id, 
                    {"error": "Audio file path missing"}, 
                    db
                )
                continue
            
            # Проверяем что файл существует
            from pathlib import Path
            if not Path(audio_path).exists():
                logger.warning(f"Audio file not found for lecture {lecture_id}: {audio_path}, marking as failed")
                await storage_service.update_lecture_status(lecture_id, "failed", db)
                await storage_service.update_lecture_metadata(
                    lecture_id, 
                    {"error": f"Audio file not found: {audio_path}"}, 
                    db
                )
                continue
            
            # Перезапускаем обработку
            logger.info(f"Recovering lecture {lecture_id}: {lecture.get('title', 'Unknown')}")
            # Запускаем в фоне (не ждём завершения)
            # process_lecture_transcription - это async функция
            import asyncio
            # В lifespan мы уже в async контексте, можно создать task
            asyncio.create_task(process_lecture_transcription(lecture_id, audio_path, language))
        
        logger.info(f"Recovery initiated for {len(incomplete)} lecture(s)")


app = FastAPI(
    title=settings.app_name,
    description="API для записи лекций, транскрибации и умного конспектирования",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# CORS middleware for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify exact origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    """Health check endpoint."""
    return {
        "status": "ok",
        "app": settings.app_name,
        "version": "0.1.0"
    }


@app.get("/health")
async def health():
    """Detailed health check."""
    from .services.llm_service import llm_service
    
    return {
        "status": "healthy",
        "whisper_model": settings.whisper_model,
        "embedding_model": settings.embedding_model,
        "llm": llm_service.get_provider_info(),
    }


# Include routers
app.include_router(
    auth.router,
    prefix=f"{settings.api_prefix}/auth",
    tags=["auth"],
)
app.include_router(
    lectures.router,
    prefix=f"{settings.api_prefix}/lectures",
    tags=["lectures"],
)
app.include_router(
    notes.router,
    prefix=f"{settings.api_prefix}/notes",
    tags=["notes"],
)
app.include_router(
    calendar.router,
    prefix=f"{settings.api_prefix}/calendar",
    tags=["calendar"],
)
app.include_router(
    chat.router,
    prefix=f"{settings.api_prefix}/lectures",
    tags=["chat"]
)

app.include_router(
    summary.router,
    prefix=f"{settings.api_prefix}/lectures",
    tags=["summary"]
)
app.include_router(
    chat_global.router,
    prefix=f"{settings.api_prefix}/chat",
    tags=["chat"],
)

app.include_router(
    tasks.router,
    prefix=f"{settings.api_prefix}/tasks",
    tags=["tasks"],
)
