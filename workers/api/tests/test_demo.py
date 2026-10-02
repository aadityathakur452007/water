"""Demo login tests: config-gated OTP bypass for QA accounts."""

import hashlib

import pytest

from app.core.errors import AppError
from app.db import get_connection, init_schema
from app.db_d1 import AsyncSqliteConn
from app.services.auth_service import AuthService

from pathlib import Path

API_ROOT = Path(__file__).resolve().parent.parent
M002 = (API_ROOT / "src" / "app" / "db" / "migrations" / "002_auth.sql").read_text()
M009 = (API_ROOT / "src" / "app" / "db" / "migrations" / "009_demo.sql").read_text()
M010 = (API_ROOT / "src" / "app" / "db" / "migrations" / "010_config_audit.sql").read_text()


def _conn(demo_on=True):
    raw = get_connection(":memory:")
    init_schema(raw)
    raw.executescript(M002 + M009)
    raw.execute(
        "INSERT INTO users(id, phone, role, created_at) VALUES "
        "('du1', '+919000000001', 'user', '2026-10-02T00:00:00Z'),"
        " ('dv1', '+919000000002', 'vendor', '2026-10-02T00:00:00Z')"
    )
    raw.execute(
        "INSERT INTO config(key, value) VALUES ('demo_login_enabled', ?)",
        ("1" if demo_on else "0",),
    )
    raw.execute(
        "INSERT INTO demo_codes(phone, code_hash, created_at) VALUES (?, ?, ?), (?, ?, ?)",
        (
            "+919000000001", hashlib.sha256(b"111111").hexdigest(), "2026-10-02T00:00:00Z",
            "+919000000002", hashlib.sha256(b"222222").hexdigest(), "2026-10-02T00:00:00Z",
        ),
    )
    raw.commit()
    return AsyncSqliteConn(raw)


def _conn_pre010(users=True):
    """Prod D1 before ADR-054: migrations 002+009 applied, 010 missing —
    no ``config`` table at all (what actually 500'd /v1/auth/demo)."""
    raw = get_connection(":memory:")
    raw.executescript(M002 + M009)
    if users:
        raw.execute(
            "INSERT INTO users(id, phone, role, created_at) VALUES "
            "('du1', '+919000000001', 'user', '2026-10-02T00:00:00Z'),"
            " ('dv1', '+919000000002', 'vendor', '2026-10-02T00:00:00Z')"
        )
        raw.execute(
            "INSERT INTO demo_codes(phone, code_hash, created_at) VALUES (?, ?, ?)",
            ("+919000000001", hashlib.sha256(b"111111").hexdigest(), "2026-10-02T00:00:00Z"),
        )
    raw.commit()
    return AsyncSqliteConn(raw)


async def test_demo_customer_ok():
    out = await AuthService(_conn()).demo_login("+919000000001", "111111", "dev-1")
    assert out["role"] == "user" and out["access_token"]


async def test_demo_vendor_ok():
    out = await AuthService(_conn()).demo_login("+919000000002", "222222", "dev-1")
    assert out["role"] == "vendor"


async def test_demo_wrong_code_401():
    with pytest.raises(AppError) as e:
        await AuthService(_conn()).demo_login("+919000000001", "999999", "dev-1")
    assert e.value.status_code == 401


async def test_demo_flag_off_closed():
    with pytest.raises(AppError) as e:
        await AuthService(_conn(demo_on=False)).demo_login("+919000000001", "111111", "dev-1")
    assert e.value.status_code == 401


async def test_demo_missing_device_400():
    with pytest.raises(AppError) as e:
        await AuthService(_conn()).demo_login("+919000000001", "111111", "")
    assert e.value.status_code == 400


async def test_demo_pre010_fail_closed_not_500():
    """ADR-054: missing config table (D1 pre-010) -> clean 401, never a 500."""
    with pytest.raises(AppError) as e:
        await AuthService(_conn_pre010()).demo_login("+919000000001", "111111", "dev-1")
    assert e.value.status_code == 401


async def test_migration_010_fixes_pre010_db():
    """D1 recovery path: applying every migration file (what the documented
    wrangler loop does — all IF NOT EXISTS) + seed makes demo login work."""
    raw = get_connection(":memory:")
    for path in sorted((API_ROOT / "src" / "app" / "db" / "migrations").glob("*.sql")):
        raw.executescript(path.read_text())  # 002..010, no init_schema
    raw.executescript(
        (API_ROOT / "demo_seed.sql").read_text()  # same statements as prod seed
    )
    conn = AsyncSqliteConn(raw)
    out = await AuthService(conn).demo_login("+919000000001", "111111", "dev-1")
    assert out["role"] == "user" and out["access_token"]


def test_demo_router_end_to_end():
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.deps import get_db_conn
    from app.api.v1.auth import router
    from app.core.errors import register_exception_handlers

    c = _conn()
    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: c
    client = TestClient(app)
    r = client.post(
        "/v1/auth/demo",
        json={"phone": "+919000000002", "demo_code": "222222", "device": {"id": "dev-9"}},
    )
    assert r.status_code == 200, r.text
    assert r.json()["role"] == "vendor"
    bad = client.post(
        "/v1/auth/demo",
        json={"phone": "+919000000002", "demo_code": "nope", "device": {"id": "dev-9"}},
    )
    assert bad.status_code == 401
