from pydantic import BaseModel, EmailStr, Field, field_validator

from app.schemas.user import validate_password_byte_length


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class PasswordResetRequest(BaseModel):
    """Step 1: user requests a reset email."""

    email: EmailStr


class PasswordResetConfirm(BaseModel):
    """Step 2: user submits the token from their email with a new password."""

    token: str
    new_password: str = Field(min_length=8, max_length=128)

    _validate_password_bytes = field_validator("new_password")(
        validate_password_byte_length
    )
