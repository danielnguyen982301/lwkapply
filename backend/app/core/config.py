"""
Application configuration.

Loads settings from environment variables (via .env in local dev).
Centralizing config here avoids scattering os.getenv() calls
throughout the codebase and gives us type validation for free.
"""

from functools import lru_cache
from typing import List, Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env.local", extra="ignore")

    # --- App ---
    APP_NAME: str = "LwkApply API"
    ENVIRONMENT: str = "development"  # development | staging | production
    DEBUG: bool = True
    API_V1_PREFIX: str = "/api/v1"

    # --- Security ---
    SECRET_KEY: str = "CHANGE_ME_IN_PRODUCTION"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    PASSWORD_RESET_TOKEN_EXPIRE_MINUTES: int = 30
    COOKIE_SECURE: bool = True
    COOKIE_SAMESITE: Literal["lax", "strict", "none"] = "none"
    REFRESH_TOKEN_COOKIE_MAX_AGE: int = 60 * 60 * 24 * 7  # 7 days

    # --- Database ---
    DATABASE_URL: str = (
        "postgresql+psycopg2://postgres:postgres@localhost:5432/lwkapply"
    )
    TEST_DATABASE_URL: str = (
        "postgresql+psycopg2://postgres:postgres@localhost:5432/lwkapply_test"
    )

    # --- Redis / Celery ---
    REDIS_URL: str = "redis://localhost:6379/0"

    # --- CORS ---
    CORS_ORIGINS: List[str] = ["http://localhost:5173", "http://localhost:3000"]

    # --- AWS S3 ---
    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = ""
    AWS_REGION: str = "us-east-1"
    AWS_S3_BUCKET: str = "lwkapply-documents"

    # --- Cloudflare R2 (object storage for documents) ---
    # R2_ACCOUNT_ID determines the S3-compatible endpoint
    # (https://<R2_ACCOUNT_ID>.r2.cloudflarestorage.com) - see
    # app/services/r2.py. No region setting: R2 requires the literal
    # string "auto", which is hardcoded in r2.py rather than exposed here,
    # since it isn't actually configurable.
    R2_ACCOUNT_ID: str = ""
    R2_ACCESS_KEY_ID: str = ""
    R2_SECRET_ACCESS_KEY: str = ""
    R2_BUCKET: str = "lwkapply-documents"

    # --- Rate limiting / misc ---
    MAX_UPLOAD_SIZE_MB: int = 10

    # --- Email (interview reminders, Phase A - see TODO.md) ---
    # "smtp" is for local dev against MailHog (docker-compose's `mailhog`
    # service, SMTP on 1025 / web UI on 8025 - nothing sent there ever
    # leaves the machine). "resend" is the real provider, used in
    # staging/production. Same "isolate the network client behind one
    # module, switch on config" shape as app/services/r2.py.
    EMAIL_PROVIDER: Literal["smtp", "resend"] = "smtp"
    EMAIL_FROM_ADDRESS: str = "notifications@lwkapply.local"
    EMAIL_FROM_NAME: str = "LwkApply"

    RESEND_API_KEY: str = ""

    SMTP_HOST: str = "localhost"
    SMTP_PORT: int = 1025
    SMTP_USE_TLS: bool = False
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""

    # Used to build the "view application" link inside a reminder email.
    FRONTEND_URL: str = "http://localhost:5173"

    # Hardcoded single lead time for Phase A's first pass (see TODO.md -
    # multi-lead-time UI is explicitly out of scope for now). The
    # `interview_reminders` table itself doesn't assume a single lead
    # time - this setting just controls how many rows get created today.
    REMINDER_LEAD_HOURS: int = 24


@lru_cache
def get_settings() -> Settings:
    """Cached settings instance so we don't re-parse env vars on every call."""
    return Settings()


settings = get_settings()
