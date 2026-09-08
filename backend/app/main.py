from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# (registers every model before any mapper configures - see app/core/celery_app.py's identical import for
# why this can't be left to endpoint modules importing models
# incidentally; today's router.py import chain happens to touch every
# model, but that's fragile, not a guarantee)
from app import models  # noqa: F401

from app.api.v1.router import api_router
from app.core.config import settings

app = FastAPI(
    title=settings.APP_NAME,
    version="0.1.0",
    docs_url="/docs" if settings.ENVIRONMENT != "production" else None,
    redoc_url="/redoc" if settings.ENVIRONMENT != "production" else None,
)

# Chrome exempts host_permissions-covered origins from CORS entirely
# for extension background requests, so it never needed an entry here -
# Firefox doesn't grant that exemption and enforces ordinary CORS
# instead (confirmed against a real "CORS header 'Access-Control-
# Allow-Origin' missing" rejection from the LwkApply browser extension
# running there). A static allow_origins entry can't fix this: Chrome's
# extension origin is stable (derived from the extension's key), but
# Firefox deliberately randomizes moz-extension://<uuid> per
# installation as an anti-fingerprinting measure - every user who
# installs the extension gets a different origin, published or not, so
# there is no fixed value to whitelist. allow_origin_regex matches the
# *shape* of an extension origin instead of one specific value - safe
# to allow broadly here because this API is Bearer-token authenticated,
# not cookie-based, so there's no ambient credential for a stranger's
# extension to ride on the way CORS is usually guarding against.
EXTENSION_ORIGIN_REGEX = r"^(chrome|moz)-extension://.*"

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_origin_regex=EXTENSION_ORIGIN_REGEX,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["Authorization", "Content-Type", "X-CSRF-Token"],
)

app.include_router(api_router, prefix=settings.API_V1_PREFIX)


@app.get("/health", tags=["health"])
def health_check():
    return {"status": "ok", "environment": settings.ENVIRONMENT}
