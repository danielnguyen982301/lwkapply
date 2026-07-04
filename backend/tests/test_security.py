"""
Unit tests for app.core.security.

These deliberately avoid any DB or FastAPI dependency injection — they
exercise the hashing and token functions as pure logic, since that's
the highest-value, easiest-to-break code in the auth flow.
"""

from datetime import timedelta

import pytest

from app.core import security


class TestPasswordHashing:
    def test_hash_is_not_the_plaintext_password(self):
        hashed = security.hash_password("correct-horse-battery-staple")
        assert hashed != "correct-horse-battery-staple"

    def test_correct_password_verifies(self):
        hashed = security.hash_password("s3cur3-p@ssword")
        assert security.verify_password("s3cur3-p@ssword", hashed) is True

    def test_incorrect_password_fails_verification(self):
        hashed = security.hash_password("s3cur3-p@ssword")
        assert security.verify_password("wrong-password", hashed) is False

    def test_same_password_produces_different_hashes(self):
        # bcrypt salts each hash, so two hashes of the same password
        # must differ. This guards against someone swapping bcrypt
        # for an unsalted scheme by accident.
        first = security.hash_password("repeat-password")
        second = security.hash_password("repeat-password")
        assert first != second

    def test_password_at_72_byte_limit_hashes_successfully(self):
        # Regression test: bcrypt>=4.1 raises instead of silently
        # truncating at 72 bytes. A password of exactly 72 bytes is
        # the boundary case that must still succeed.
        password = "a" * 72
        hashed = security.hash_password(password)
        assert security.verify_password(password, hashed)

    def test_password_over_72_bytes_raises_clear_error(self):
        # Regression test for the passlib/bcrypt incompatibility bug:
        # previously this surfaced as an opaque ValueError from deep
        # inside bcrypt's C extension. Now it's an explicit, early
        # ValueError from our own code.
        password = "a" * 73
        with pytest.raises(ValueError, match="72 bytes"):
            security.hash_password(password)


class TestAccessToken:
    def test_access_token_round_trips_subject(self):
        token = security.create_access_token(subject="user-123")
        payload = security.decode_token(token)

        assert payload is not None
        assert payload["sub"] == "user-123"
        assert payload["type"] == "access"

    def test_expired_access_token_fails_to_decode(self):
        token = security.create_access_token(
            subject="user-123", expires_delta=timedelta(seconds=-1)
        )
        assert security.decode_token(token) is None

    def test_garbage_token_fails_to_decode(self):
        assert security.decode_token("not.a.valid.jwt") is None


class TestRefreshToken:
    def test_refresh_token_has_refresh_type(self):
        token = security.create_refresh_token(subject="user-123")
        payload = security.decode_token(token)

        assert payload is not None
        assert payload["type"] == "refresh"

    def test_refresh_and_access_tokens_are_typed_differently(self):
        # This is the property that lets the API reject a refresh
        # token if someone tries to use it as an access token, and
        # vice versa.
        access = security.decode_token(security.create_access_token("user-123"))
        refresh = security.decode_token(security.create_refresh_token("user-123"))

        assert access is not None
        assert refresh is not None
        assert access["type"] != refresh["type"]


class TestPasswordResetToken:
    def test_password_reset_token_has_correct_type(self):
        token = security.create_password_reset_token(subject="user-123")
        payload = security.decode_token(token)

        assert payload is not None
        assert payload["type"] == "password_reset"

    def test_password_reset_token_cannot_be_used_as_access_token(self):
        # Defense in depth: even though decode succeeds, the `type`
        # check in get_current_user() is what actually blocks reuse.
        # This test documents/pins that the type tag is present.
        token = security.create_password_reset_token(subject="user-123")
        payload = security.decode_token(token)
        assert payload is not None
        assert payload["type"] != "access"


@pytest.mark.parametrize("bad_token", ["", "abc", "a.b.c.d", None])
def test_decode_token_handles_malformed_input_gracefully(bad_token):
    # decode_token() now explicitly guards against falsy input (including
    # None) with an early return, rather than relying on callers to never
    # pass it - a missing Authorization header is a real-world source of
    # None reaching this function, so it needs to be a genuine runtime
    # guarantee, not just a type hint.
    assert security.decode_token(bad_token) is None