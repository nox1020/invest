"""Local app-lock password hashing (not related to remote OTP auth)."""

from __future__ import annotations

import base64
import hashlib
import secrets

PBKDF2_ITERATIONS = 120_000
MIN_PASSWORD_LEN = 4


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        PBKDF2_ITERATIONS,
    )
    return (
        f"pbkdf2_sha256${PBKDF2_ITERATIONS}$"
        f"{base64.b64encode(salt).decode('ascii')}$"
        f"{base64.b64encode(digest).decode('ascii')}"
    )


def verify_password(password: str, stored: str) -> bool:
    if not stored or not password:
        return False
    try:
        algo, iters_raw, salt_b64, hash_b64 = stored.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        iterations = int(iters_raw)
        salt = base64.b64decode(salt_b64.encode("ascii"))
        expected = base64.b64decode(hash_b64.encode("ascii"))
        actual = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            salt,
            iterations,
        )
        return secrets.compare_digest(actual, expected)
    except (TypeError, ValueError):
        return False


def is_lock_enabled(stored_hash: str | None) -> bool:
    return bool(stored_hash and stored_hash.strip())
