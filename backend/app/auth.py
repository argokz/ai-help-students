"""Auth: JWT, password hashing, Google ID token verification."""
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


def verify_google_id_token(id_token_str: str) -> Optional[dict]:
    """
    Verify Google ID token and return payload (email, sub, etc.) or None.
    Requires GOOGLE_CLIENT_ID to be set (Web client ID from Google Cloud Console).
    """
    if not settings.google_client_id:
        return None
    try:
        idinfo = id_token.verify_oauth2_token(
            id_token_str,
            google_requests.Request(),
            settings.google_client_id,
        )
        if idinfo.get("iss") not in ("accounts.google.com", "https://accounts.google.com"):
            return None
        return idinfo
    except (ValueError, Exception):
        return None
