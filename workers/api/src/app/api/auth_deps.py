"""Session auth dependencies (C1 owns this file).

``get_current_user`` is the seam every other slice imports: orders/addresses
routers do ``from app.api.auth_deps import get_current_user`` with an
ImportError fallback that retires once this file lands.

Suspend rule (contract §0 C2 + §14.1): ``users.suspended`` is re-read on EVERY
request — the 30-min Bearer never outlives a block. Suspended users still GET
their profile (200 + restrictions); writes die in ``require_active_user``
(user) or ``require_role`` (vendor reads notice-only).
"""

from __future__ import annotations

import hashlib
import time

from fastapi import Depends, HTTPException, Request

from app.api.deps import get_db_conn
from app.core.time_utils import is_expired as _expired
from app.repositories.session_repo import SessionRepo

# 045: per-isolate session memo. One `sessions JOIN users` read currently runs
# on EVERY authenticated request; at 10 ms CPU that lookup is a large share of
# the budget. 10 s TTL means a suspend/logout can take up to 10 s to reach a
# different isolate. Admin sessions are never cached (low volume, high risk).
_SESSION_TTL_DEFAULT_S = 10.0
_SESSION_CACHE_MAX = 4096
_session_cache: dict[str, tuple[float, dict]] = {}


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _session_ttl_s() -> float:
    from app.core.worker_env import env_get  # noqa: PLC0415

    raw = env_get("AUTH_SESSION_CACHE_TTL_S")
    if raw is None:
        return _SESSION_TTL_DEFAULT_S
    try:
        return max(0.0, float(raw))
    except (TypeError, ValueError):
        return _SESSION_TTL_DEFAULT_S


def reset_session_cache() -> None:
    """Test hook / manual reset."""
    _session_cache.clear()


def invalidate_request_session(request: Request) -> None:
    """Drop this request's Bearer token from the memo (logout path)."""
    token = _bearer(request)
    if token:
        _session_cache.pop(_hash(token), None)


def _bearer(request: Request) -> str | None:
    """Bearer token from the Authorization header, or the admin-web session
    cookie ``sh_session`` (contract §0: Flutter uses Bearer, admin web uses an
    HttpOnly cookie against the same API). Cookie tokens are hashed the same way.
    """
    auth = request.headers.get("Authorization", "")
    scheme, _, token = auth.partition(" ")
    if scheme.lower() == "bearer" and token.strip():
        return token.strip()
    return request.cookies.get("sh_session") or None


_SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})


def _same_origin(request: Request) -> bool:
    """True when the request proves it came from this API's own origin.

    Browsers attach ``Origin`` to every cross-origin unsafe request (and to
    same-origin POSTs in current engines), so one comparison is enough to tell
    a first-party form/fetch from a CSRF attempt. A cookie write with no
    Origin/Referer at all is not a browser same-origin form: deny it.
    """
    candidate = (request.headers.get("origin") or "").strip()
    if not candidate:
        referer = (request.headers.get("referer") or "").strip()
        if referer:
            parts = referer.split("/")
            candidate = "/".join(parts[:3]) if len(parts) >= 3 else ""
    if not candidate or candidate == "null":
        return False
    host = (request.headers.get("host") or "").strip().lower()
    if not host:
        return False
    scheme, _, netloc = candidate.partition("://")
    netloc = netloc.split("/", 1)[0].lower()
    return bool(netloc) and netloc == host and scheme in ("http", "https")


def _reject_cross_site_cookie_write(request: Request) -> None:
    """CSRF gate for cookie-authenticated unsafe methods.

    Bearer tokens are immune (a browser never attaches them automatically).
    Requests carrying an Authorization header skip this gate entirely, so
    every app using Bearer is unaffected.
    """
    auth = (request.headers.get("Authorization") or "").strip()
    if auth:
        return
    if not request.cookies.get("sh_session"):
        return
    if request.method.upper() in _SAFE_METHODS:
        return
    if _same_origin(request):
        return
    raise HTTPException(status_code=403, detail="Cross-origin request rejected.")


# _expired imported from app.core.time_utils above


async def get_current_user(request: Request, conn=Depends(get_db_conn)) -> dict:
    """Bearer session -> user dict. Missing/bad/expired/revoked -> 401 UNAUTH."""
    _reject_cross_site_cookie_write(request)
    token = _bearer(request)
    if token is None:
        raise HTTPException(status_code=401, detail="Unauthorized")
    token_hash = _hash(token)
    ttl_s = _session_ttl_s()
    if ttl_s > 0:
        hit = _session_cache.get(token_hash)
        if hit is not None and time.monotonic() - hit[0] < ttl_s:
            return dict(hit[1])
    su = await SessionRepo(conn).find_session_user_by_access_hash(token_hash)
    if su is None or su.get("revoked_at") is not None or _expired(su.get("expires_at", "")):
        raise HTTPException(status_code=401, detail="Unauthorized")
    user = {
        "id": su["user_id"],
        "role": su["role"],
        "phone": su["phone"],
        "name": su.get("name"),
        "suspended": bool(su.get("suspended")),
        "suspended_reason": su.get("suspended_reason"),
        "session_id": su["session_id"],
        "family_id": su["family_id"],
        "device_fp": su["device_fp"],
    }
    if ttl_s > 0 and user["role"] != "admin":
        if len(_session_cache) >= _SESSION_CACHE_MAX:
            _session_cache.clear()
        _session_cache[token_hash] = (time.monotonic(), user)
    return user


def require_active_user(user: dict = Depends(get_current_user)) -> dict:
    """Write gate for users: suspended -> 403 FORBIDDEN (pay-dues/appeal only)."""
    if user.get("suspended"):
        raise HTTPException(status_code=403, detail="Account suspended.")
    return user


def require_role(*roles: str):
    """Write gate for vendors/admins: wrong role OR suspended -> 403 FORBIDDEN."""

    def _dep(user: dict = Depends(get_current_user)) -> dict:
        if user.get("role") not in roles or user.get("suspended"):
            raise HTTPException(status_code=403, detail="Forbidden.")
        return user

    return _dep
