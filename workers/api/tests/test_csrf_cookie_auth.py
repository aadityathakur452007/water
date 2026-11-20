"""Regression: cookie-authenticated writes must be same-origin (CSRF gate).

Bearer clients are untouched; a ``sh_session`` cookie on a cross-origin unsafe
request is rejected before any service/repo work.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(API_ROOT / "src"))

from app.db import get_connection, init_schema  # noqa: E402

ADMIN_TOKEN = "csrf-admin-token"
ADMIN_COOKIE = {"sh_session": ADMIN_TOKEN}
FOREIGN = {"Origin": "https://evil.example"}


def _iso(**kw) -> str:
    return (dt.datetime.now(dt.timezone.utc) + dt.timedelta(**kw)).isoformat()


def _db():
    c = get_connection(":memory:")
    init_schema(c)
    mig = API_ROOT / "src" / "app" / "db" / "migrations"
    for name in sorted(p.name for p in mig.glob("*.sql")):
        c.executescript((mig / name).read_text())
    c.execute(
        "INSERT INTO users(id, phone, name, role, created_at) VALUES ('adm', '+919000000041', 'A', 'admin', ?)",
        (_iso(),),
    )
    c.execute(
        "INSERT INTO sessions(id, user_id, token_hash, refresh_hash, role, device_fp,"
        " family_id, expires_at, refresh_expires_at, created_at)"
        " VALUES ('s1','adm',?,'r','admin','d','f',?,?,?)",
        (hashlib.sha256(ADMIN_TOKEN.encode()).hexdigest(), _iso(days=1), _iso(days=1), _iso()),
    )
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, total, payment_mode,"
        " payment_status, state, window_start, idempotency_key, created_at)"
        " VALUES ('ord-1','cust','addr','[]',1,2800,'cod','unpaid','placed',?,'k',?)",
        (_iso(days=1), _iso()),
    )
    c.commit()
    return c


def _client(c, monkeypatch):
    monkeypatch.setenv("AUTH_SESSION_CACHE_TTL_S", "0")
    from fastapi.testclient import TestClient

    from app.api.deps import get_db_conn
    from app.db_d1 import AsyncSqliteConn
    from app.factory import create_app

    app = create_app("all")
    conn = AsyncSqliteConn(c)
    app.dependency_overrides[get_db_conn] = lambda: conn
    return TestClient(app, raise_server_exceptions=False)


def _state(c) -> str:
    return str(c.execute("SELECT state FROM orders WHERE id='ord-1'").fetchone()[0])


def test_foreign_origin_cookie_write_is_rejected(monkeypatch):
    c = _db()
    client = _client(c, monkeypatch)
    r = client.post("/v1/admin/orders/ord-1/cancel-override", json={"reason": "csrf"},
                    cookies=ADMIN_COOKIE, headers=FOREIGN)
    assert r.status_code == 403, r.text
    assert _state(c) == "placed"


def test_cookie_write_without_origin_is_rejected(monkeypatch):
    c = _db()
    client = _client(c, monkeypatch)
    r = client.post("/v1/admin/orders/ord-1/cancel-override", json={"reason": "csrf"},
                    cookies=ADMIN_COOKIE)
    assert r.status_code == 403, r.text
    assert _state(c) == "placed"


def test_same_origin_cookie_write_still_works(monkeypatch):
    c = _db()
    client = _client(c, monkeypatch)
    r = client.post("/v1/admin/orders/ord-1/cancel-override", json={"reason": "ok"},
                    cookies=ADMIN_COOKIE, headers={"Origin": "http://testserver"})
    assert r.status_code == 200, r.text
    assert _state(c) == "cancelled"


def test_bearer_write_from_foreign_origin_is_unaffected(monkeypatch):
    c = _db()
    client = _client(c, monkeypatch)
    r = client.post("/v1/admin/orders/ord-1/cancel-override", json={"reason": "api"},
                    headers={**FOREIGN, "Authorization": f"Bearer {ADMIN_TOKEN}"})
    assert r.status_code == 200, r.text
    assert _state(c) == "cancelled"


def test_cookie_read_is_unaffected(monkeypatch):
    c = _db()
    client = _client(c, monkeypatch)
    r = client.get("/v1/auth/me", cookies=ADMIN_COOKIE)
    assert r.status_code == 200, r.text


def test_unsafe_cookie_write_without_session_cookie_still_401(monkeypatch):
    c = _db()
    client = _client(c, monkeypatch)
    r = client.post("/v1/admin/orders/ord-1/cancel-override", json={"reason": "x"})
    assert r.status_code == 401, r.text


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
