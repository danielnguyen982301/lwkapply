"""
Redis-backed rate limiting - currently used only for the AI features'
free-tier daily usage cap (app/api/v1/endpoints/ai.py). Same "isolate
the client, lazy-init on first use" shape as r2.py/push.py: importing
this module must not crash startup just because Redis isn't reachable
yet. First direct `redis` client usage in this codebase - REDIS_URL
already exists and Redis already runs in docker-compose.yml, but only
as Celery's broker/backend until now.

This module is deliberately generic (a bare atomic counter keyed by a
caller-supplied string), not "AI-aware" - app/api/v1/endpoints/ai.py
owns the AI-specific key format (ai_usage_key()) and limit value
(settings.AI_FREE_TIER_DAILY_LIMIT), so any future Redis-backed limit
elsewhere can reuse check_and_increment() directly.
"""

import uuid
from datetime import datetime, timezone
from typing import cast

import redis

from app.core.config import settings

_redis_client: redis.Redis | None = None

# Longer than 24h on purpose - the key's embedded date is what actually
# enforces a UTC-calendar-day window; this TTL just makes sure the key
# eventually cleans itself out of Redis rather than relying on exact-
# midnight expiry. Re-set on every INCR rather than conditionally (e.g.
# Redis 7's EXPIRE ... NX) - simpler, and harmless since correctness
# never depends on the exact TTL value, only on the key changing at UTC
# midnight.
_KEY_TTL_SECONDS = 90_000  # ~25 hours


def _get_redis() -> redis.Redis:
    """Lazily initializes the Redis client on first use - mirrors
    push.py's _get_app()/r2.py's _r2_client()."""
    global _redis_client
    if _redis_client is None:
        _redis_client = redis.Redis.from_url(settings.REDIS_URL, decode_responses=True)
    return _redis_client


class RateLimitExceeded(Exception):
    def __init__(self, retry_after_seconds: int):
        self.retry_after_seconds = retry_after_seconds
        super().__init__(f"Rate limit exceeded, retry after {retry_after_seconds}s")


def check_and_increment(key: str, limit: int) -> None:
    """Atomically increments `key`'s counter and raises
    RateLimitExceeded if that puts it over `limit`. INCR is a single
    atomic Redis command, so two concurrent requests incrementing the
    same key land on distinct values - no read-then-write race on the
    counter itself.
    """
    client = _get_redis()
    # redis-py's stubs type these as ResponseT (a union that also covers
    # the async client's Awaitable return) even on the synchronous
    # `redis.Redis` client used here, which always returns the plain
    # value directly at runtime - cast() reflects that actual behavior
    # rather than the overly-broad stub type.
    count = cast(int, client.incr(key))
    if count == 1:
        client.expire(key, _KEY_TTL_SECONDS)

    if count > limit:
        retry_after = cast(int, client.ttl(key))
        # ttl() returns -1 (no expiry set) or -2 (key doesn't exist) in
        # edge cases that shouldn't happen here given the incr()/expire()
        # above, but fall back to the full window rather than a
        # nonsensical negative Retry-After header if it ever does.
        if retry_after < 0:
            retry_after = _KEY_TTL_SECONDS
        raise RateLimitExceeded(retry_after_seconds=retry_after)


def ai_usage_key(user_id: uuid.UUID) -> str:
    """Shared budget across every AI feature endpoint (resume-analyses,
    ats-scores) - one counter per user per UTC calendar day, not one per
    endpoint, since both draw on the same underlying Gemini cost."""
    today = datetime.now(timezone.utc).date().isoformat()
    return f"ai_rate_limit:{user_id}:{today}"
