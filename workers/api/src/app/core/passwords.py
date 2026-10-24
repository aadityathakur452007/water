"""Password hashing for customer auth (034).

PBKDF2-HMAC-SHA256 at 100,000 iterations, 16-byte salt, 32-byte key. Local
Python/tests use ``hashlib``; Cloudflare Python Workers use WebCrypto because
the Workers runtime does not expose OpenSSL's PBKDF2 implementation. The
parameters are server-side constants — never client-selected. Cloudflare's
WebCrypto implementation rejects iteration counts above 100,000, so this is the
runtime maximum, documented explicitly rather than silently downgraded.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import sys

ALGORITHM = "pbkdf2_sha256"
ITERATIONS = 100_000
SALT_BYTES = 16
KEY_BYTES = 32
MAX_PASSWORD_CHARS = 128
MIN_PASSWORD_CHARS = 8

# Precomputed with the same parameters. Used only to equalize login timing for
# an unknown phone / empty hash; it is not a real account credential.
DUMMY_HASH = (
    "pbkdf2_sha256$100000$c2hvZGFzaGEtZHVtbXkhIQ$"
    "gF45v-hUQdcfMOSG1Pl_Wn31M0n9tetNGpji2_fXJSg"
)


def _b64e(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _b64d(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def _workers_runtime() -> bool:
    return sys.platform in ("emscripten", "wasi")


async def _derive(password: str, salt: bytes, iterations: int, key_bytes: int) -> bytes:
    if not _workers_runtime():
        return hashlib.pbkdf2_hmac(
            "sha256", password.encode("utf-8"), salt, iterations, key_bytes
        )

    # Cloudflare Python Workers (Pyodide): WebCrypto is the only PBKDF2 path.
    from js import Object, crypto  # type: ignore[import-not-found]  # noqa: PLC0415
    from pyodide.ffi import to_js  # type: ignore[import-not-found]  # noqa: PLC0415

    key = await crypto.subtle.importKey(
        "raw", to_js(password.encode("utf-8"), create_pyproxies=False),
        "PBKDF2", False, to_js(["deriveBits"], create_pyproxies=False),
    )
    bits = await crypto.subtle.deriveBits(
        to_js(
            {
                "name": "PBKDF2",
                "salt": to_js(salt, create_pyproxies=False),
                "iterations": iterations,
                "hash": "SHA-256",
            },
            dict_converter=Object.fromEntries,
            create_pyproxies=False,
        ),
        key,
        key_bytes * 8,
    )
    return bytes(bits.to_py())


async def hash_password(password: str) -> str:
    salt = secrets.token_bytes(SALT_BYTES)
    derived = await _derive(password, salt, ITERATIONS, KEY_BYTES)
    return f"{ALGORITHM}${ITERATIONS}${_b64e(salt)}${_b64e(derived)}"


async def verify_password(password: str, encoded: str | None) -> bool:
    if not encoded:
        return False
    try:
        algorithm, iterations_s, salt_s, key_s = encoded.split("$", 3)
        iterations = int(iterations_s)
        salt = _b64d(salt_s)
        expected = _b64d(key_s)
    except (ValueError, TypeError):
        return False
    if algorithm != ALGORITHM or iterations <= 0 or not salt or not expected:
        return False
    derived = await _derive(password, salt, iterations, len(expected))
    return hmac.compare_digest(derived, expected)
