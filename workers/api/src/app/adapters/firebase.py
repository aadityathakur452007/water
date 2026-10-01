"""Firebase ID-token verifier (Adapter pattern) — C1 auth slice.

Swaps slice-1's ``FirebaseStub`` for the real verifier: same method name
(``verify_id_token``), same return contract (``{"uid", "phone_number"}``).

Error mapping (contract §6): misconfigured provider / fetch failure -> 502
UPSTREAM_FAIL (retry-safe); bad/expired token -> 401 UNAUTH.
"""

from __future__ import annotations

import logging
import time

from app.core.errors import AppError

log = logging.getLogger(__name__)


class UnauthError(AppError):
    code = "UNAUTH"
    status_code = 401


class UpstreamError(AppError):
    code = "UPSTREAM_FAIL"
    status_code = 502


CERTS_URL = (
    "https://www.googleapis.com/robot/v1/metadata/x509/"
    "securetoken@system.gserviceaccount.com"
)
CERTS_TTL_S = 3600

try:  # cryptography is a C extension: present locally, banned on Workers.
    import cryptography  # noqa: F401, PLC0415

    _HAS_CRYPTO = True
except ImportError:
    _HAS_CRYPTO = False

_certs: dict = {"keys": None, "fetched": 0.0}


class RealVerifier:
    """Verifies Firebase phone-auth ID tokens (SEC-A08: signature + aud + exp)."""

    def __init__(self, project_id: str | None = None):
        if project_id is None:
            from app.core.worker_env import env_get  # noqa: PLC0415 (request env first)

            project_id = env_get("FIREBASE_PROJECT_ID")
        if project_id is None:
            from app.core.config import Settings  # noqa: PLC0415 (lazy: light import)

            try:
                project_id = Settings().firebase_project_id
            except Exception:  # env/.env unreadable -> treated as unconfigured
                project_id = None
        self.project_id = project_id

    def verify_id_token(self, token: str) -> dict:
        """Return ``{"uid", "phone_number"}`` for a valid token.

        Raises:
            UpstreamError: no FIREBASE_PROJECT_ID / cert fetch failed / jwt lib missing.
            UnauthError: bad, expired, or aud-mismatched token.
        """
        if not self.project_id:
            raise UpstreamError(
                "Auth provider not configured.",
                {"retryable": True},
            )
        if not token or not token.strip():
            raise UnauthError("Invalid session.", {})
        try:
            import jwt  # noqa: PLC0415 (optional at import time; tests inject fakes)
        except ImportError as e:
            raise UpstreamError("Token library missing.", {"retryable": False}) from e
        try:
            kid = jwt.get_unverified_header(token).get("kid")
        except Exception as e:
            raise UnauthError("Invalid session.", {}) from e
        cert = self._cert(kid)
        claims = _decode_rs256(
            token,
            cert,
            audience=self.project_id,
            issuer=f"https://securetoken.google.com/{self.project_id}",
        )
        uid = claims.get("sub") or claims.get("user_id")
        if not uid:
            raise UnauthError("Invalid session.", {})
        return {"uid": str(uid), "phone_number": claims.get("phone_number")}

    def _cert(self, kid: str | None) -> str:
        keys = _certs_cached()
        if kid and kid in keys:
            return keys[kid]
        keys = _certs_cached(force=True)  # one refresh for key rotation
        if kid and kid in keys:
            return keys[kid]
        raise UnauthError("Invalid session.", {})


def _certs_cached(force: bool = False) -> dict:
    if not force and _certs["keys"] is not None and time.time() - _certs["fetched"] < CERTS_TTL_S:
        return _certs["keys"]
    try:
        import httpx  # noqa: PLC0415 (network only on this path)

        r = httpx.get(CERTS_URL, timeout=10.0)
        r.raise_for_status()
        keys = r.json()
    except Exception as e:
        if _certs["keys"] is not None:  # stale certs beat no certs
            log.warning("firebase certs refresh failed, using cache: %s", e)
            return _certs["keys"]
        raise UpstreamError("Auth provider unreachable.", {"retryable": True}) from e
    _certs["keys"], _certs["fetched"] = keys, time.time()
    return keys


def get_verifier() -> RealVerifier:
    """FastAPI DI factory — tests override this with a fake (Dependency Injection)."""
    return RealVerifier()


def _decode_rs256(token: str, cert: str, *, audience: str, issuer: str) -> dict:
    """Decode + fully verify an RS256 token (signature, aud, iss, exp, sub).

    Uses PyJWT's ``cryptography`` backend wherever it imports (local dev);
    on Workers (no C extensions) falls back to the pure-stdlib verifier in
    :mod:`app.adapters.rsa_verify` with identical checks. Raises
    :class:`UnauthError` for anything invalid, :class:`UpstreamError` when
    no verifier exists at all.
    """
    require = {"require": ["exp", "aud", "sub"]}
    if _HAS_CRYPTO:
        try:
            import jwt as _jwt_crypto  # noqa: PLC0415 (C backend, local dev)

            return _jwt_crypto.decode(
                token,
                cert,
                algorithms=["RS256"],
                audience=audience,
                issuer=issuer,
                options=require,
            )
        except Exception as e:
            raise UnauthError("Invalid or expired session.", {}) from e
    try:
        from app.adapters.rsa_verify import (  # noqa: PLC0415
            b64url_decode,
            verify_rs256,
        )
    except ImportError as e:
        raise UpstreamError("Token library missing.", {"retryable": False}) from e
    try:
        parts = token.split(".")
        if len(parts) != 3:
            raise ValueError("malformed token")
        header_b64, payload_b64, sig_b64 = parts
        verify_rs256(
            f"{header_b64}.{payload_b64}".encode("ascii"),
            b64url_decode(sig_b64),
            cert,
        )
        # PyJWT skips aud/exp checks when the signature is unverified, so the
        # claims are checked by hand here (stdlib only, no behavior change).
        import json as _json  # noqa: PLC0415
        import time as _time  # noqa: PLC0415

        claims = _json.loads(b64url_decode(payload_b64).decode("utf-8"))
        if not isinstance(claims, dict):
            raise ValueError("bad claims")
        aud = claims.get("aud")
        aud_ok = aud == audience or (
            isinstance(aud, list) and audience in aud
        )
        if not aud_ok or claims.get("iss") != issuer:
            raise ValueError("bad aud/iss")
        exp = claims.get("exp")
        if not isinstance(exp, (int, float)) or exp <= _time.time() - 60:
            raise ValueError("expired")
        if not claims.get("sub") and not claims.get("user_id"):
            raise ValueError("no subject")
        return claims
    except UnauthError:
        raise
    except Exception as e:
        raise UnauthError("Invalid or expired session.", {}) from e
