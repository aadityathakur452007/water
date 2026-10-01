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

import datetime as _dt
import hashlib

from fastapi import Depends, HTTPException, Request

from app.api.deps import get_db
from app.repositories.session_repo import SessionRepo
from app.repositories.user_repo import UserRepo


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _bearer(request: Request) -> str | None:
    """Bearer token from the Authorization header, or the admin-web session
    cookie ``sh_session`` (contract §0: Flutter uses Bearer, admin web uses an
    HttpOnly cookie against the same API). Cookie tokens are hashed the same way."""
    auth = request.headers.get("Authorization", "")
    scheme, _, token = auth.partition(" ")
    if scheme.lower() == "bearer" and token.strip():
        return token.strip()
    return request.cookies.get("sh_session") or None


def _expired(iso_ts: str) -> bool:
    try:
        dt = _dt.datetime.fromisoformat(iso_ts)
    except ValueError:
        return True
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=_dt.timezone.utc)
    return dt <= _dt.datetime.now(_dt.timezone.utc)


def get_current_user(request: Request, conn=Depends(get_db)) -> dict:
    """Bearer session -> user dict. Missing/bad/expired/revoked -> 401 UNAUTH."""
    token = _bearer(request)
    if token is None:
        raise HTTPException(status_code=401, detail="Unauthorized")
    session = SessionRepo(conn).find_by_access_hash(_hash(token))
    if (
        session is None
        or session["revoked_at"] is not None
        or _expired(session["expires_at"])
    ):
        raise HTTPException(status_code=401, detail="Unauthorized")
    user = UserRepo(conn).find_by_id(session["user_id"])
    if user is None:  # user deleted but token lives -> treat as unauth (no oracle)
        raise HTTPException(status_code=401, detail="Unauthorized")
    return {
        "id": user["id"],
        "role": user["role"],
        "phone": user["phone"],
        "name": user.get("name"),
        "suspended": bool(user.get("suspended")),
        "suspended_reason": user.get("suspended_reason"),
        "session_id": session["id"],
        "family_id": session["family_id"],
        "device_fp": session["device_fp"],
    }


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
