import uuid

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

# bcrypt only uses the first 72 bytes of a password - anything past that
# is silently ignored by the algorithm. We reject rather than truncate,
# so no one thinks a 100-character password is stronger than a 72-byte one.
BCRYPT_MAX_PASSWORD_BYTES = 72


def validate_password_byte_length(password: str) -> str:
    if len(password.encode("utf-8")) > BCRYPT_MAX_PASSWORD_BYTES:
        raise ValueError(
            f"Password must not exceed {BCRYPT_MAX_PASSWORD_BYTES} bytes when UTF-8 encoded "
            "(most passwords: 72 characters; fewer if using emoji/non-Latin scripts)."
        )
    return password


class UserBase(BaseModel):
    email: EmailStr
    first_name: str = Field(min_length=1, max_length=100)
    last_name: str = Field(min_length=1, max_length=100)


class UserCreate(UserBase):
    password: str = Field(min_length=8, max_length=128)
    # Client-reported IANA tz name (web: Intl.DateTimeFormat().resolvedOptions()
    # .timeZone; mobile: flutter_timezone) - optional and unvalidated at the
    # schema level on purpose. Validation (is it actually a real IANA name)
    # happens once, in app/utils/timezone.py, shared with the same
    # re-report-on-login/refresh path in api/v1/endpoints/auth.py, rather
    # than duplicating a zoneinfo check across every schema that carries
    # this field. An invalid/missing value here should never fail
    # registration - it just leaves User.timezone NULL, same as any
    # pre-this-feature account, and the UTC fallback everywhere else
    # already handles that.
    timezone: str | None = None

    _validate_password_bytes = field_validator("password")(
        validate_password_byte_length
    )


class UserRead(UserBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    avatar_url: str | None = None
    is_active: bool
    # NULL until the first register/login/refresh auto-detects one (see
    # app/utils/timezone.py / _maybe_update_timezone in
    # app/api/v1/endpoints/auth.py). timezone_is_manual distinguishes
    # "auto-detected" from "the user explicitly picked this in Account
    # Settings" - PATCH /users/me sets it True on an explicit non-null
    # timezone, and back to False on an explicit null (see
    # UserProfileUpdate.timezone / the endpoint) - so a client can tell
    # whether re-detecting will silently overwrite this value.
    timezone: str | None = None
    timezone_is_manual: bool


class UserUpdate(BaseModel):
    first_name: str | None = Field(default=None, min_length=1, max_length=100)
    last_name: str | None = Field(default=None, min_length=1, max_length=100)
    avatar_url: str | None = None


class UserProfileUpdate(BaseModel):
    """Body for PATCH /users/me. A separate schema from UserUpdate, not a
    reuse of it - UserUpdate.avatar_url must never be settable by a client
    directly (only POST/DELETE /users/me/avatar may write it, since those
    are what control the R2 object key behind it); a schema that can't
    even express avatar_url closes that off structurally rather than
    relying on the endpoint to remember to ignore it."""

    first_name: str | None = Field(default=None, min_length=1, max_length=100)
    last_name: str | None = Field(default=None, min_length=1, max_length=100)
    # Re-validated against app/utils/timezone.py::is_valid_timezone in the
    # endpoint, same as everywhere else this shape of field appears
    # (UserCreate.timezone, LoginRequest.timezone) - unvalidated here on
    # purpose, so an invalid value is ignored rather than rejecting the
    # whole request over just this one field.
    timezone: str | None = None


class PasswordChangeRequest(BaseModel):
    """Body for POST /users/me/password - requires proving the current
    password even though the request is already bearer-authenticated,
    since a change like this shouldn't be possible from just a leaked
    access token alone."""

    current_password: str
    new_password: str = Field(min_length=8, max_length=128)

    _validate_password_bytes = field_validator("new_password")(
        validate_password_byte_length
    )


class AccountDeleteRequest(BaseModel):
    """Body for DELETE /users/me - same reasoning as
    PasswordChangeRequest: an irreversible action shouldn't be possible
    from just a leaked access token, so it requires re-proving the
    password."""

    password: str
