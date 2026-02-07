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
    """Create DB tables on startup."""
    try:
        await init_db()
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.warning(f"Database initialization failed: {e}. App will continue but DB features may not work.")
    yield
    # shutdown if needed


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
