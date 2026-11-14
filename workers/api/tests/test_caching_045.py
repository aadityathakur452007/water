"""045: per-isolate memos — session lookup + public reads."""

import datetime as _dt

import pytest
from starlette.requests import Request

_FUTURE = (_dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(hours=1)).isoformat()


def _request(token: str | None = None) -> Request:
    headers = []
    if token is not None:
        headers.append((b"authorization", f"Bearer {token}".encode()))
    return Request({"type": "http", "method": "GET", "path": "/", "headers": headers})


def _session_row(role: str = "user") -> dict:
    return {
        "session_id": "s1",
        "user_id": "u1",
        "family_id": "f1",
        "device_fp": "d1",
        "revoked_at": None,
        "expires_at": _FUTURE,
        "role": role,
        "phone": "+919000000000",
        "name": "User",
        "suspended": 0,
        "suspended_reason": None,
    }


def _stub_session_repo(monkeypatch, calls: dict, role: str = "user"):
    from app.api import auth_deps

    async def fake(self, token_hash):
        calls["n"] += 1
        return _session_row(role)

    monkeypatch.setattr(auth_deps.SessionRepo, "find_session_user_by_access_hash", fake)
    return auth_deps


@pytest.mark.asyncio
async def test_session_memo_skips_repeat_lookup(monkeypatch):
    monkeypatch.setenv("AUTH_SESSION_CACHE_TTL_S", "10")
    calls = {"n": 0}
    auth_deps = _stub_session_repo(monkeypatch, calls)
    req = _request("tok")

    first = await auth_deps.get_current_user(req, object())
    second = await auth_deps.get_current_user(req, object())

    assert calls["n"] == 1
    assert second == first


@pytest.mark.asyncio
async def test_admin_sessions_are_never_memoized(monkeypatch):
    monkeypatch.setenv("AUTH_SESSION_CACHE_TTL_S", "10")
    calls = {"n": 0}
    auth_deps = _stub_session_repo(monkeypatch, calls, role="admin")
    req = _request("admin-tok")

    await auth_deps.get_current_user(req, object())
    await auth_deps.get_current_user(req, object())

    assert calls["n"] == 2


@pytest.mark.asyncio
async def test_logout_invalidates_memo(monkeypatch):
    monkeypatch.setenv("AUTH_SESSION_CACHE_TTL_S", "10")
    calls = {"n": 0}
    auth_deps = _stub_session_repo(monkeypatch, calls)
    req = _request("tok")

    await auth_deps.get_current_user(req, object())
    auth_deps.invalidate_request_session(req)
    await auth_deps.get_current_user(req, object())

    assert calls["n"] == 2


@pytest.mark.asyncio
async def test_memo_expires(monkeypatch):
    monkeypatch.setenv("AUTH_SESSION_CACHE_TTL_S", "10")
    calls = {"n": 0}
    auth_deps = _stub_session_repo(monkeypatch, calls)
    now = [1000.0]
    monkeypatch.setattr(auth_deps.time, "monotonic", lambda: now[0])
    req = _request("tok")

    await auth_deps.get_current_user(req, object())
    now[0] += 11
    await auth_deps.get_current_user(req, object())

    assert calls["n"] == 2


@pytest.mark.asyncio
async def test_catalog_memo_skips_rebuild(monkeypatch):
    from app.api.v1 import catalog

    calls = {"n": 0}
    real_settings = catalog.get_settings

    def counting_settings():
        calls["n"] += 1
        return real_settings()

    monkeypatch.setattr(catalog, "get_settings", counting_settings)
    req = _request()

    first = await catalog.get_catalog(req)
    second = await catalog.get_catalog(req)

    assert calls["n"] == 1
    assert first.status_code == 200
    assert second.status_code == 200
