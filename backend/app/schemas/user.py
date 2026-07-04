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

    _validate_password_bytes = field_validator("password")(validate_password_byte_length)


class UserRead(UserBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    avatar_url: str | None = None
    is_active: bool


class UserUpdate(BaseModel):
    first_name: str | None = Field(default=None, min_length=1, max_length=100)
    last_name: str | None = Field(default=None, min_length=1, max_length=100)
    avatar_url: str | None = None