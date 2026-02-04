"""Auth-related Pydantic models."""
from pydantic import BaseModel, EmailStr, Field


class UserRegister(BaseModel):
    email: EmailStr = Field(..., description="Email")
    password: str = Field(..., min_length=6, description="Пароль (мин. 6 символов)")


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class GoogleAuthRequest(BaseModel):
    id_token: str = Field(..., description="Google ID token from client")


class TokenResponse(BaseModel):
    access_token: str = Field(..., description="JWT токен")
    token_type: str = Field(default="bearer")
    user_id: str = Field(..., description="ID пользователя")
    email: str = Field(..., description="Email пользователя")


class UserResponse(BaseModel):
    id: str
    email: str
    created_at: str
