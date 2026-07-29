from typing import Optional

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.schemas.user import validate_password_byte_length


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    # Only ever populated for mobile-client requests (see
    # app/api/deps.py::is_mobile_client). Web must keep getting its
    # refresh token exclusively via the httpOnly cookie - populating this
    # unconditionally would let any XSS payload on the web app read the
    # refresh token straight out of the fetch response, defeating the
    # entire reason that cookie is httpOnly.
    refresh_token: Optional[str] = None


class RefreshRequest(BaseModel):
    """Body for POST /auth/refresh. Only used by the mobile client, which
    has no cookie to read the refresh token from and must send it
    explicitly. Web's refresh flow doesn't send a body at all - it relies
    entirely on the httpOnly cookie - so every field here is optional."""

    refresh_token: Optional[str] = None


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
