"""Auth: JWT, password hashing, Google ID token verification."""
import asyncio
from datetime import datetime, timedelta
from typing import Optional

from jose import JWTError, jwt
from passlib.context import CryptContext
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests

from .config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(subject: str) -> str:
    expire = datetime.utcnow() + timedelta(minutes=settings.jwt_expire_minutes)
    to_encode = {"sub": subject, "exp": expire}
    return jwt.encode(to_encode, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> Optional[str]:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        return payload.get("sub")
    except JWTError:
        return None


def _verify_google_id_token_sync(id_token_str: str) -> Optional[dict]:
    """Synchronous Google token verification (run in thread)."""
    if not settings.google_client_id:
        return None
    audiences = [settings.google_client_id]
    if settings.google_android_client_id:
        audiences.append(settings.google_android_client_id)
    idinfo = id_token.verify_oauth2_token(
        id_token_str,
        google_requests.Request(),
        audiences[0] if len(audiences) == 1 else audiences,
    )
    if idinfo.get("iss") not in ("accounts.google.com", "https://accounts.google.com"):
        return None
    return idinfo


async def verify_google_id_token(id_token_str: str) -> Optional[dict]:
    """
    Verify Google ID token and return payload (email, sub, etc.) or None.
    Runs sync verification in thread pool to avoid blocking.
    """
    if not settings.google_client_id:
        return None
    try:
        loop = asyncio.get_event_loop()
        idinfo = await loop.run_in_executor(
            None,
            _verify_google_id_token_sync,
            id_token_str,
        )
        return idinfo
    except Exception:
        return None
