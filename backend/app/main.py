"""FastAPI application entry point."""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .database import init_db
from .routers import auth, chat, lectures, summary


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Create DB tables on startup."""
    await init_db()
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
    chat.router,
    prefix=f"{settings.api_prefix}/lectures",
    tags=["chat"]
)

app.include_router(
    summary.router,
    prefix=f"{settings.api_prefix}/lectures",
    tags=["summary"]
)
