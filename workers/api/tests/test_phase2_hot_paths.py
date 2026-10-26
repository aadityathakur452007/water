"""Phase 2 P1 hot paths: query budgets, schema caches, headers, and limits.

These tests pin the steady-state costs the audit asked for. The per-isolate
schema probes are paid once, so each measurement warms the cache first.
"""

import datetime as dt
import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db import get_connection  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.db_schema import reset_schema_cache, stop_columns  # noqa: E402
from app.migrate import pending  # noqa: E402
from app.repositories.ledger_repo import LedgerRepo  # noqa: E402
from app.repositories.order_repo import OrderRepo  # noqa: E402
from app.services import pricing  # noqa: E402
from app.services.order_service import OrderService  # noqa: E402
from app.services.subscription_service import (  # noqa: E402
    _ensure_billing_mode,
    reset_billing_mode_cache,
)

NOW = dt.datetime.now(dt.timezone.utc).isoformat()
DAY = dt.datetime.now(dt.timezone.utc).date().isoformat()


def _conn():
    c = get_connection(":memory:")
    for path in pending(c):
        c.executescript(path.read_text(encoding="utf-8"))
        c.execute(
            "INSERT INTO schema_migrations(filename, applied_at) VALUES (?, datetime('now'))",
            (path.name,),
        )
    c.commit()
    return c


class CountingConn(AsyncSqliteConn):
    """Counts statements without changing the connection contract."""

    def __init__(self, conn):
        super().__init__(conn)
        self.sql: list[str] = []

    async def execute(self, sql, params=()):
        self.sql.append(sql)
        return await super().execute(sql, params)

    async def batch(self, statements):
        self.sql.extend(s for s, _ in statements)
        return await super().batch(statements)

    def pragmas(self) -> list[str]:
        return [s for s in self.sql if "pragma" in s.lower()]


def _seed_order(c, *, oid="o1", events=1):
    c.execute(
        "INSERT INTO users(id, phone, role, name, created_at) VALUES"
        " ('u1','+912222222222','user','Asha',?),"
        " ('v1','+911111111111','vendor','Ravi',?)",
        (NOW, NOW),
    )
    c.execute(
        "INSERT INTO vendor_profile(user_id, name, phone) VALUES ('v1','Ravi Kumar','+919900001111')"
    )
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill,"
        " deposit_due, total, payment_mode, state, window_start, idempotency_key, created_at)"
        " VALUES (?, 'u1', 'a1', '[]', 2, 1, 5600, 15000, 20600, 'cod', 'assigned', ?, 'seed:o1', ?)",
        (oid, NOW, NOW),
    )
    c.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status)"
        " VALUES ('r1', ?, 'v1', 'z1', 'open')",
        (DAY,),
    )
    # An earlier pending stop on the same route -> stops_ahead == 1.
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status)"
        " VALUES ('s0', 'r1', NULL, 'u0', 0, 1, 0, 1, 'pending')"
    )
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status)"
        " VALUES ('s1', 'r1', ?, 'u1', 1, 2, 1, 1, 'pending')",
        (oid,),
    )
    for i in range(events):
        c.execute(
            "INSERT INTO order_events(id, order_id, from_state, to_state, actor_id,"
            " actor_role, reason, created_at)"
            " VALUES (?, ?, 'placed', 'assigned', 'admin', 'admin', '', ?)",
            (f"e{i}", oid, NOW),
        )
    c.commit()


def _order_service(conn) -> OrderService:
    return OrderService(OrderRepo(conn), LedgerRepo(conn), pricing, {})


# -- 2A: order detail + schema caches ----------------------------------------


async def test_order_detail_statements_flat_with_event_count():
    async def count(events: int) -> list[str]:
        c = _conn()
        _seed_order(c, events=events)
        conn = CountingConn(c)
        svc = _order_service(conn)
        await svc.detail("u1", "o1")  # warm the schema probe
        conn.sql.clear()
        await svc.detail("u1", "o1")
        return list(conn.sql)

    one = await count(1)
    many = await count(5)
    assert len(one) == len(many)
    # find_owned + events + stop state + one rider join.
    assert len(one) == 4


async def test_order_detail_rider_join_parity():
    c = _conn()
    _seed_order(c)
    detail = await _order_service(AsyncSqliteConn(c)).detail("u1", "o1")
    assert detail["stops_ahead"] == 1
    assert detail["rider"] == {
        "name": "Ravi Kumar",
        "phone": "+919900001111",
        "stops_ahead": 1,
    }
    assert detail["tracker"]["current"] == "assigned"
    assert len(detail["events"]) == 1


async def test_stop_columns_probe_once_per_isolate():
    conn = CountingConn(_conn())
    first = await stop_columns(conn)
    second = await stop_columns(conn)
    assert "pod_otp" in first
    assert first == second
    assert len(conn.pragmas()) == 1
    reset_schema_cache()
    await stop_columns(conn)
    assert len(conn.pragmas()) == 2


async def test_billing_mode_probe_once_per_isolate():
    conn = CountingConn(_conn())
    await _ensure_billing_mode(conn)
    await _ensure_billing_mode(conn)
    assert len(conn.pragmas()) == 1
    reset_billing_mode_cache()
    await _ensure_billing_mode(conn)
    assert len(conn.pragmas()) == 2


async def test_billing_mode_still_alters_legacy_schema():
    c = get_connection(":memory:")
    c.executescript(
        (API_ROOT / "src" / "app" / "db" / "migrations" / "004_orders.sql").read_text()
    )
    conn = CountingConn(c)
    await _ensure_billing_mode(conn)
    cols = {r["name"] for r in (
        await conn.execute("PRAGMA table_info(subscriptions)")).fetchall()}
    assert {"billing_mode", "billing_status", "credit_balance_paise", "refund_upi"} <= cols


# -- 2B: admin cache headers, metrics cache, windows horizon ------------------

ADMIN = {"id": "admin1", "role": "admin", "phone": "+911111111111",
         "suspended": False, "session_id": "s", "family_id": "f", "device_fp": "d"}


def _admin_client(c):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api import auth_deps
    from app.api.deps import get_db_conn
    from app.api.v1.admin import reset_metrics_cache, router
    from app.core.errors import register_exception_handlers

    reset_metrics_cache()
    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: AsyncSqliteConn(c)
    app.dependency_overrides[auth_deps.get_current_user] = lambda: ADMIN
    return TestClient(app)


def _catalog_client():
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.v1.catalog import router
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    return TestClient(app)


def test_admin_reads_are_private_no_store():
    client = _admin_client(_conn())
    for path in ("/v1/admin/config", "/v1/admin/zones",
                 "/v1/admin/metrics", "/v1/admin/metrics/overview"):
        resp = client.get(path)
        assert resp.status_code == 200, (path, resp.text)
        assert resp.headers["cache-control"] == "private, no-store"
        assert "cdn-cache-control" not in resp.headers
        assert "etag" not in resp.headers


def test_public_catalog_stays_public():
    resp = _catalog_client().get("/v1/windows")
    assert resp.status_code == 200
    assert resp.headers["cache-control"].startswith("public")


def test_admin_overview_cached_within_ttl():
    from app.api.v1 import admin as admin_mod

    client = _admin_client(_conn())
    calls = {"n": 0}
    real = admin_mod.AdminReadRepo.money_totals

    async def counting(self):
        calls["n"] += 1
        return await real(self)

    admin_mod.AdminReadRepo.money_totals = counting
    try:
        client.get("/v1/admin/metrics/overview")
        client.get("/v1/admin/metrics/overview")
        assert calls["n"] == 1
        client.get("/v1/admin/metrics/overview", params={"days": 7})
        assert calls["n"] == 2
    finally:
        admin_mod.AdminReadRepo.money_totals = real


async def test_metrics_cache_expires():
    from app.api.v1 import admin as admin_mod

    admin_mod.reset_metrics_cache()
    calls = {"n": 0}

    async def build():
        calls["n"] += 1
        return {"n": calls["n"]}

    old = admin_mod._METRICS_TTL_S
    admin_mod._METRICS_TTL_S = 0
    try:
        await admin_mod._metrics_cached("k", build)
        await admin_mod._metrics_cached("k", build)
    finally:
        admin_mod._METRICS_TTL_S = old
    assert calls["n"] == 2


def test_windows_horizon_bounds():
    client = _catalog_client()
    today = dt.date.today()
    past = client.get("/v1/windows", params={
        "date": (today - dt.timedelta(days=5)).isoformat()})
    assert past.status_code == 200
    assert past.json()["date"] >= today.isoformat()
    edge = client.get("/v1/windows", params={
        "date": (today + dt.timedelta(days=30)).isoformat()})
    assert edge.status_code == 200
    far = client.get("/v1/windows", params={
        "date": (today + dt.timedelta(days=31)).isoformat()})
    assert far.status_code == 400
    assert far.json()["error"]["code"] == "VALIDATION"


# -- 2C: edge IP, combined login checks, bounded throttle --------------------


def test_client_ip_prefers_cf_header():
    from types import SimpleNamespace

    from app.api.middleware import client_ip

    req = SimpleNamespace(
        headers={"cf-connecting-ip": "203.0.113.9"},
        client=SimpleNamespace(host="10.0.0.1"),
    )
    assert client_ip(req) == "203.0.113.9"
    assert client_ip(SimpleNamespace(headers={}, client=SimpleNamespace(host="10.0.0.1"))) == "10.0.0.1"
    assert client_ip(SimpleNamespace(headers={}, client=None)) == "unknown"


def test_login_route_uses_cf_connecting_ip():
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.v1.auth import _service, router
    from app.core.errors import register_exception_handlers

    seen: dict[str, str] = {}

    class Stub:
        async def user_login(self, phone, password, device_id, device=None, ip="unknown"):
            seen["ip"] = ip
            return {"ok": True}

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    app.dependency_overrides[_service] = lambda: Stub()
    resp = TestClient(app).post(
        "/v1/auth/user/login",
        json={"phone": "+919999999999", "password": "secret123",
              "device": {"id": "d1"}},
        headers={"CF-Connecting-IP": "203.0.113.9"},
    )
    assert resp.status_code == 200, resp.text
    assert seen["ip"] == "203.0.113.9"


async def test_login_checks_are_one_batch():
    from app.services.auth_service import AuthService, reset_rate_limits

    reset_rate_limits()
    conn = CountingConn(_conn())
    svc = AuthService(conn)
    conn.sql.clear()
    await svc._limit_checks([
        ("login:phone:+919999999999", 5, 900),
        ("login:ip:203.0.113.9", 100, 3600),
    ])
    assert len(conn.sql) == 2
    assert "INSERT INTO rate_counters" in conn.sql[0]
    assert "SELECT key, count FROM rate_counters" in conn.sql[1]


async def test_login_phone_limit_still_enforced():
    from app.core.errors import RateLimitedError
    from app.services.auth_service import AuthService, reset_rate_limits

    reset_rate_limits()
    svc = AuthService(AsyncSqliteConn(_conn()))
    key = "login:phone:+919999999999"
    for _ in range(5):
        await svc._limit_checks([(key, 5, 900)])
    with pytest.raises(RateLimitedError):
        await svc._limit_checks([(key, 5, 900)])


def test_login_limits_match_approved_values():
    from app.services.auth_service import LOGIN_IP_LIMIT, LOGIN_PHONE_LIMIT

    assert LOGIN_PHONE_LIMIT == (5, 900)
    assert LOGIN_IP_LIMIT == (100, 3600)


def test_throttle_map_bounded_and_prunes_expired():
    import time as _time

    from app.api import middleware as mw

    mw.reset_throttle()
    now = _time.monotonic()
    mw._throttle_hits["expired"] = [now - 120]
    mw._throttle_hits["fresh"] = [now]
    mw._prune_throttle(now)
    assert "expired" not in mw._throttle_hits
    assert "fresh" in mw._throttle_hits
    for i in range(mw._THROTTLE_MAX_KEYS + 10):
        mw._throttle_hits[f"k{i}"] = [now]
    mw._prune_throttle(now)
    assert len(mw._throttle_hits) == mw._THROTTLE_MAX_KEYS
    mw.reset_throttle()
