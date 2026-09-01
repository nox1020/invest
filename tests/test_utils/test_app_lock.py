"""Tests for local app-lock password hashing."""

from app.utils.app_lock import hash_password, is_lock_enabled, verify_password


def test_hash_and_verify_password() -> None:
    stored = hash_password("secret123")
    assert verify_password("secret123", stored)
    assert not verify_password("wrong", stored)


def test_is_lock_enabled() -> None:
    assert not is_lock_enabled("")
    assert not is_lock_enabled(None)
    assert is_lock_enabled(hash_password("x"))
