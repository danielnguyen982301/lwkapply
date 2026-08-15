"""
Unit tests for app.services.rate_limit.

Uses the real Redis instance (settings.REDIS_URL) rather than a mock or
a library like fakeredis - same "use the real dependency you already
provision, don't mock infra" philosophy as this suite's real-Postgres DB
tests. Isolation: every test builds its key from a fresh uuid4(), so
tests never share a counter and don't need any cleanup between runs -
unlike the DB tests' SAVEPOINT rollback, these keys genuinely persist in
Redis until their TTL expires, which is harmless (low volume,
self-expiring) and not worth engineering around.
"""

import uuid

import pytest

from app.services.rate_limit import (
    RateLimitExceeded,
    ai_usage_key,
    check_and_increment,
)


def _fresh_key() -> str:
    return f"test:{uuid.uuid4()}"


class TestCheckAndIncrement:
    def test_succeeds_under_the_limit(self):
        key = _fresh_key()
        for _ in range(3):
            check_and_increment(key, limit=3)  # should not raise

    def test_raises_at_limit_plus_one(self):
        key = _fresh_key()
        for _ in range(3):
            check_and_increment(key, limit=3)
        with pytest.raises(RateLimitExceeded):
            check_and_increment(key, limit=3)

    def test_retry_after_is_positive_and_within_ttl_bound(self):
        key = _fresh_key()
        check_and_increment(key, limit=1)
        with pytest.raises(RateLimitExceeded) as exc_info:
            check_and_increment(key, limit=1)
        assert 0 < exc_info.value.retry_after_seconds <= 90_000

    def test_separate_keys_do_not_share_a_counter(self):
        key_a = _fresh_key()
        key_b = _fresh_key()
        check_and_increment(key_a, limit=1)
        check_and_increment(key_b, limit=1)  # should not raise - distinct key


class TestAiUsageKey:
    def test_same_user_same_day_produces_the_same_key(self):
        user_id = uuid.uuid4()
        assert ai_usage_key(user_id) == ai_usage_key(user_id)

    def test_different_users_produce_different_keys(self):
        assert ai_usage_key(uuid.uuid4()) != ai_usage_key(uuid.uuid4())
