"""PostgreSQL database connection and session."""
from collections.abc import AsyncGenerator

import asyncpg
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from .config import settings


async def _ensure_database_exists() -> None:
    """Create the database if it does not exist (connect to postgres, then CREATE DATABASE)."""
    url = make_url(settings.database_url)
    # url is postgresql+asyncpg://... so .rendered replaces the scheme
    dbname = url.database or "postgres"
    if dbname == "postgres":
        return
    host = url.host or "localhost"
    port = url.port or 5432
    user = url.username or "postgres"
    password = url.password or ""

    conn = await asyncpg.connect(
        host=host,
        port=port,
        user=user,
        password=password,
        database="postgres",
    )
    try:
        row = await conn.fetchval(
            "SELECT 1 FROM pg_database WHERE datname = $1", dbname
        )
        if row is None:
            await conn.execute(f'CREATE DATABASE "{dbname}"')
    finally:
        await conn.close()


# Async engine: postgresql+asyncpg://user:pass@host:port/dbname
engine = create_async_engine(
    settings.database_url,
    echo=settings.app_debug,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
)

AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


class Base(DeclarativeBase):
    """Base class for SQLAlchemy models."""
    pass


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependency: yield async DB session."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def init_db() -> None:
    """Create database if missing, then create all tables. Call on app startup."""
    await _ensure_database_exists()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
