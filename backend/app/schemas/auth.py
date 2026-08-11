from typing import Optional

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.schemas.user import validate_password_byte_length


class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    # Re-reported on every login, same reasoning as UserCreate.timezone
    # (see schemas/user.py) - covers travel/relocation without the user
    # doing anything. Validated (and silently ignored if invalid/absent)
    # in the endpoint via app/utils/timezone.py, not here.
    timezone: Optional[str] = None


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
    """Body for POST /auth/refresh. `refresh_token` is only ever used by
    the mobile client, which has no cookie to read the refresh token
    from and must send it explicitly - web's refresh flow doesn't
    strictly need a body for that. `timezone` is different: both clients
    may now send a body just to carry this, re-reporting it on every
    refresh the same way login does (see LoginRequest.timezone) - so
    web's refresh request goes from "no body" to "an optional body with
    just timezone" as of this change. Every field here stays optional so
    a client that sends nothing at all still works exactly as before."""

    refresh_token: Optional[str] = None
    timezone: Optional[str] = None


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
