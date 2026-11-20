"""Regression: vendor rider onboarding cannot rewrite an existing account.

A vendor may only (re)onboard a phone that is already *their own* rider. Any
other existing account (customer, admin, another vendor's rider) is a 409 and
keeps its role and vendor binding untouched.
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

VENDOR_A = "vend-a"
VENDOR_B = "vend-b"


def _iso(**kw) -> str:
    return (dt.datetime.now(dt.timezone.utc) + dt.timedelta(**kw)).isoformat()


def _db():
    c = get_connection(":memory:")
    init_schema(c)
    mig = API_ROOT / "src" / "app" / "db" / "migrations"
    for name in sorted(p.name for p in mig.glob("*.sql")):
        c.executescript((mig / name).read_text())
    users = [
        ("vend-a", "+919000000021", "Vendor A", "vendor", None),
        ("vend-b", "+919000000022", "Vendor B", "vendor", None),
        ("cust-1", "+919000000012", "Customer", "user", None),
        ("admin-1", "+919000000041", "Admin", "admin", None),
        ("rider-b", "+919000000032", "Rider B", "rider", VENDOR_B),
        ("rider-a", "+919000000031", "Rider A", "rider", VENDOR_A),
    ]
    for uid, phone, name, role, vendor in users:
        c.execute(
            "INSERT INTO users(id, phone, name, role, assigned_vendor_id, created_at)"
            " VALUES (?,?,?,?,?,?)",
            (uid, phone, name, role, vendor, _iso()),
        )
    token = "vend-a-token"
    c.execute(
        "INSERT INTO sessions(id, user_id, token_hash, refresh_hash, role, device_fp,"
        " family_id, expires_at, refresh_expires_at, created_at)"
        " VALUES ('s1','vend-a',?,'r','vendor','d','f',?,?,?)",
        (hashlib.sha256(token.encode()).hexdigest(), _iso(days=1), _iso(days=1), _iso()),
    )
    c.commit()
    return c, token


def _client(c, token, monkeypatch):
    monkeypatch.setenv("AUTH_SESSION_CACHE_TTL_S", "0")
    from fastapi.testclient import TestClient

    from app.api.deps import get_db_conn
    from app.db_d1 import AsyncSqliteConn
    from app.factory import create_app

    app = create_app("all")
    conn = AsyncSqliteConn(c)
    app.dependency_overrides[get_db_conn] = lambda: conn
    return TestClient(app, raise_server_exceptions=False), {
        "Authorization": f"Bearer {token}"}


def _row(c, uid):
    return dict(c.execute(
        "SELECT role, assigned_vendor_id FROM users WHERE id=?", (uid,)).fetchone())


@pytest.mark.parametrize("uid,phone", [
    ("cust-1", "+919000000012"),   # customer account
    ("admin-1", "+919000000041"),  # platform admin
    ("rider-b", "+919000000032"),  # another vendor's rider
])
def test_existing_foreign_account_is_rejected(uid, phone, monkeypatch):
    c, token = _db()
    client, headers = _client(c, token, monkeypatch)
    before = _row(c, uid)
    r = client.post("/v1/vendor/riders", headers=headers,
                    json={"name": "Hijack", "phone": phone})
    assert r.status_code == 409, r.text
    assert _row(c, uid) == before


def test_own_rider_can_be_re_onboarded(monkeypatch):
    c, token = _db()
    client, headers = _client(c, token, monkeypatch)
    r = client.post("/v1/vendor/riders", headers=headers,
                    json={"name": "Rider A Renamed", "phone": "+919000000031"})
    assert r.status_code == 201, r.text
    row = _row(c, "rider-a")
    assert row == {"role": "rider", "assigned_vendor_id": VENDOR_A}
    name = c.execute("SELECT name FROM users WHERE id='rider-a'").fetchone()[0]
    assert name == "Rider A Renamed"


def test_new_phone_creates_a_rider(monkeypatch):
    c, token = _db()
    client, headers = _client(c, token, monkeypatch)
    r = client.post("/v1/vendor/riders", headers=headers,
                    json={"name": "Fresh", "phone": "+919000000099"})
    assert r.status_code == 201, r.text
    row = dict(c.execute(
        "SELECT role, assigned_vendor_id FROM users WHERE phone='+919000000099'").fetchone())
    assert row == {"role": "rider", "assigned_vendor_id": VENDOR_A}


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
