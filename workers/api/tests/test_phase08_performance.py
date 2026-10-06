"""Phase 8 performance tests (ADR-090): index migrations, bounds, atomicity,
D1 rate counters + Retry-After, cache headers. Backend-only; suites stay green.
"""
import asyncio
import datetime as _dt
import hashlib
import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db import get_connection  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.services.vendor_service import VendorService  # noqa: E402

M002 = (API_ROOT / "src" / "app" / "db" / "migrations" / "002_auth.sql").read_text()
M003 = (API_ROOT / "src" / "app" / "db" / "migrations" / "003_addresses.sql").read_text()
M004 = (API_ROOT / "src" / "app" / "db" / "migrations" / "004_orders.sql").read_text()
M005 = (API_ROOT / "src" / "app" / "db" / "migrations" / "005_payments.sql").read_text()
M006 = (API_ROOT / "src" / "app" / "db" / "migrations" / "006_aftermath.sql").read_text()
M007 = (API_ROOT / "src" / "app" / "db" / "migrations" / "007_ops.sql").read_text()
M010 = (API_ROOT / "src" / "app" / "db" / "migrations" / "010_config_audit.sql").read_text()
M017 = (API_ROOT / "src" / "app" / "db" / "migrations" / "017_perf_indexes_core.sql").read_text()
M018 = (API_ROOT / "src" / "app" / "db" / "migrations" / "018_perf_indexes_rest.sql").read_text()
M019 = (API_ROOT / "src" / "app" / "db" / "migrations" / "019_rate_counters.sql").read_text()

NOW = _dt.datetime.now(_dt.timezone.utc).isoformat()
DAY = _dt.datetime.now(_dt.timezone.utc).date().isoformat()
FUTURE = (_dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(hours=1)).isoformat()

CORE_INDEXES = ["idx_stops_route_seq", "idx_stops_order", "idx_stops_customer",
                "idx_stops_return", "idx_routes_vendor_date",
                "idx_audit_actor_created", "idx_audit_action_entity"]
REST_INDEXES = ["idx_orders_state_created", "idx_payments_status", "idx_ledger_dues",
                "idx_complaints_status_created", "idx_quality_status", "idx_payouts_status",
                "idx_payouts_vendor_period", "idx_vendor_zones_zone",
                "idx_sessions_device_created"]


def _conn():
    c = get_connection(":memory:")
    c.executescript(M002 + M003 + M004 + M005 + M006 + M007 + M010)
    c.execute(
        "INSERT INTO users(id, phone, role, created_at) VALUES "
        "('v1', '+911111111111', 'vendor', ?), ('u1', '+912222222222', 'user', ?)",
        (NOW, NOW),
    )
    c.execute(
        "INSERT INTO addresses(id, user_id, type, lat, lng, pincode, created_at)"
        " VALUES ('a1', 'u1', 'home', 12.9716, 77.5946, '560001', ?)", (NOW,),
    )
    for oid in ("o1", "o2"):
        c.execute(
            "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
            " total, payment_mode, state, window_start, idempotency_key, created_at)"
            " VALUES (?, 'u1', 'a1', '[]', 2, 1, 5600, 15000, 20600, 'cod',"
            " 'dispatched', '2026-10-01T08:00Z', ?, ?)",
            (oid, f"seed:{oid}", NOW),
        )
    c.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status) VALUES ('r1', ?, 'v1', 'z1', 'open')",
        (DAY,),
    )
    for sid, oid in (("s1", "o1"), ("s2", "o2")):
        c.execute(
            "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
            " empties_exp, version, status) VALUES (?, 'r1', ?, 'u1', 0, 2, 1, 1, 'pending')",
            (sid, oid),
        )
    c.commit()
    return c


def _svc(c) -> VendorService:
    return VendorService(AsyncSqliteConn(c))


# -- §8.1 migrations --------------------------------------------------------

def test_migrations_idempotent_and_indexed():
    c = get_connection(":memory:")
    c.executescript(M002 + M003 + M004 + M005 + M006 + M007 + M010)
    c.executescript(M017 + M018 + M019)  # first apply
    c.executescript(M017 + M018 + M019)  # re-apply: must be a silent no-op
    names = {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='index'")}
    for idx in CORE_INDEXES + REST_INDEXES:
        assert idx in names, idx
    assert c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='rate_counters'").fetchone()


# -- §8.2 bounds --------------------------------------------------------------

def test_syncin_cap_200():
    from pydantic import ValidationError as PydanticValidationError

    from app.api.v1.vendor import SyncIn

    assert len(SyncIn(items=[{"stop_id": "s"}] * 200).items) == 200
    with pytest.raises(PydanticValidationError):
        SyncIn(items=[{"stop_id": "s"}] * 201)


def test_placed_limit_validated_at_router():
    pytest.importorskip("httpx")
    import hashlib as _hl

    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.deps import get_db_conn
    from app.api.v1.vendor import router
    from app.core.errors import register_exception_handlers

    c = _conn()
    c.execute(
        "INSERT INTO sessions(id, user_id, token_hash, refresh_hash, role, device_fp,"
        " family_id, expires_at, created_at) VALUES ('ses-v1', 'v1', ?, ?, 'vendor', 'd', 'f', ?, ?)",
        (_hl.sha256(b"tok").hexdigest(), _hl.sha256(b"r:tok").hexdigest(), FUTURE, FUTURE),
    )
    c.commit()
    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: AsyncSqliteConn(c)
    client = TestClient(app)
    h = {"Authorization": "Bearer tok"}
    assert client.get("/v1/vendor/placed?limit=999", headers=h).status_code == 400
    assert client.get("/v1/vendor/placed?limit=0", headers=h).status_code == 400
    assert client.get("/v1/vendor/placed?limit=50", headers=h).status_code == 200


async def test_vendor_complaints_cursor_pages():
    c = _conn()
    for i in range(5):
        c.execute(
            "INSERT INTO complaints(id, order_id, user_id, reason_code, text, status, created_at)"
            " VALUES (?, 'o1', 'u1', 'late_delivery', 't', 'open', ?)",
            (f"c{i}", f"2026-10-0{1 + i}T00:00:00+00:00"),
        )
    c.commit()
    first = await _svc(c).vendor_complaints("v1", limit=2)
    assert [r["id"] for r in first["data"]] == ["c4", "c3"] and first["next_cursor"]
    second = await _svc(c).vendor_complaints("v1", limit=2, cursor=first["next_cursor"])
    assert [r["id"] for r in second["data"]] == ["c2", "c1"] and second["next_cursor"]
    third = await _svc(c).vendor_complaints("v1", limit=2, cursor=second["next_cursor"])
    assert [r["id"] for r in third["data"]] == ["c0"] and third["next_cursor"] is None


async def test_vendor_bad_cursor_400():
    from app.core.errors import ValidationError

    with pytest.raises(ValidationError):
        await _svc(_conn()).vendor_quality("v1", cursor="!!!not-base64!!!")


async def test_payouts_cap_and_cursor():
    c = _conn()
    for i in range(3):
        c.execute(
            "INSERT INTO payouts(id, vendor_id, period, stops_done, gross_fee, net, status, created_at)"
            " VALUES (?, 'v1', ?, 1, 100, 100, 'pending', ?)",
            (f"p{i}", f"2026-0{i + 1}", f"2026-0{i + 1}-01T00:00:00+00:00"),
        )
    c.commit()
    first = await _svc(c).payouts_for_vendor("v1", limit=2)
    assert len(first["payouts"]) == 2 and first["next_cursor"]
    rest = await _svc(c).payouts_for_vendor("v1", limit=2, cursor=first["next_cursor"])
    assert len(rest["payouts"]) == 1 and rest["next_cursor"] is None


async def test_purge_chunked_beyond_500():
    from app.jobs.scheduler import purge_expired

    c = _conn()
    old = "2020-01-01T00:00:00+00:00"
    c.executemany(
        "INSERT INTO audit_log(actor, action, entity, entity_id, trace_id, created_at)"
        " VALUES ('a', 'ops.read', 'orders', 'o1', 't', ?)",
        [(old,)] * 1200,
    )
    c.commit()
    out = await purge_expired(AsyncSqliteConn(c))
    assert out["audit_ops_deleted"] == 1200
    assert c.execute("SELECT COUNT(*) FROM audit_log").fetchone()[0] == 0


async def test_collect_reminders_paged_beyond_500():
    from app.jobs.scheduler import collect_reminders

    c = _conn()
    c.executemany(
        "INSERT INTO ledger(customer_id, held, deposit_paid, deposit_refunded, dues)"
        " VALUES (?, 0, 0, 0, 100)",
        [(f"cust-{i:04d}",) for i in range(600)],
    )
    c.commit()
    out = await collect_reminders(AsyncSqliteConn(c))
    assert len(out["dues"]) == 600


# -- §8.3 atomicity --------------------------------------------------------------

async def test_cash_torn_write_rolls_back_payment_too(monkeypatch):
    """Kill-mid-op harness: crash between the payment writes and the in_hand
    bump must leave ZERO payment trace (single txn) — on the old two-txn
    code the payment row survived."""
    import app.services.dispatch_service as dispatch

    c = _conn()

    async def _boom(conn, vendor_id):
        raise RuntimeError("killed mid-op")

    monkeypatch.setattr(dispatch, "ensure_profile", _boom)
    with pytest.raises(RuntimeError):
        await _svc(c).cash_post("v1", "s1", 20600)
    assert c.execute("SELECT COUNT(*) FROM payments").fetchone()[0] == 0
    assert c.execute("SELECT payment_status FROM orders WHERE id = 'o1'").fetchone()[0] == "unpaid"
    # Harness intact after the kill: the real op still closes the loop.
    monkeypatch.undo()
    out = await _svc(c).cash_post("v1", "s1", 20600)
    assert out["order"]["payment_status"] == "paid_cash"
    assert c.execute("SELECT in_hand FROM vendor_profile WHERE user_id = 'v1'").fetchone()[0] == 20600


async def test_cash_concurrent_same_key_single_effect():
    """Concurrent duplicate cash posts: exactly one payment row survives
    (single effect — 409 or replay for the loser, never a double-post)."""
    from app.core.errors import ConflictError

    c = _conn()
    svc = _svc(c)
    results = await asyncio.gather(
        svc.cash_post("v1", "s1", 20600), svc.cash_post("v1", "s1", 20600),
        return_exceptions=True,
    )
    ok = [r for r in results if not isinstance(r, Exception)]
    losers = [r for r in results if isinstance(r, Exception)]
    # Sequential event-loop run: the second call replays the stored outcome
    # (replay:True); under a real multi-isolate race the already-paid guard
    # 409s instead. Either way: exactly one payment row, never a double-post.
    assert c.execute("SELECT COUNT(*) FROM payments").fetchone()[0] == 1
    assert c.execute("SELECT in_hand FROM vendor_profile WHERE user_id = 'v1'").fetchone()[0] == 20600
    assert len(ok) + len(losers) == 2
    if losers:
        assert len(ok) == 1 and isinstance(losers[0], ConflictError)
    else:
        assert sorted([bool(r.get("replay")) for r in ok]) == [False, True]


# -- §8.4 rate counters + Retry-After ---------------------------------------------

async def test_auth_rate_limit_d1_backed_and_retry_after():
    """5 otp-starts pass and persist D1 counts; the 6th 429s with details
    that the error handler maps to a Retry-After header."""
    from starlette.requests import Request

    from app.core.errors import RateLimitedError, app_error_handler
    from app.services.auth_service import AuthService, reset_rate_limits

    reset_rate_limits()
    c = _conn()
    c.executescript(M019)
    c.commit()
    svc = AuthService(AsyncSqliteConn(c))
    for _ in range(5):
        out = await svc.otp_start("+919876543210", "9.9.9.9")
        assert out["channel"] in ("firebase", "sms")
    assert c.execute(
        "SELECT SUM(count) FROM rate_counters WHERE key LIKE 'otp-start:phone:%'").fetchone()[0] == 5
    assert c.execute(
        "SELECT SUM(count) FROM rate_counters WHERE key LIKE 'otp-start:ip:%'").fetchone()[0] == 5
    with pytest.raises(RateLimitedError) as exc:
        await svc.otp_start("+919876543210", "9.9.9.9")
    assert exc.value.details["retry_after_s"] >= 1
    scope = {"type": "http", "method": "POST", "path": "/", "headers": []}
    resp = await app_error_handler(Request(scope), exc.value)
    assert resp.status_code == 429
    assert resp.headers["Retry-After"] == str(exc.value.details["retry_after_s"])


async def test_rate_counter_purge():
    from app.jobs.scheduler import purge_expired

    c = _conn()
    c.executescript(M019)
    old = (_dt.datetime.now(_dt.timezone.utc) - _dt.timedelta(hours=3)).isoformat()
    c.execute("INSERT INTO rate_counters(key, window_start, count) VALUES ('k:1', ?, 9)", (old,))
    c.execute(
        "INSERT INTO rate_counters(key, window_start, count) VALUES ('k:2', ?, 1)",
        (_dt.datetime.now(_dt.timezone.utc).isoformat(),),
    )
    c.commit()
    await purge_expired(AsyncSqliteConn(c))
    left = {r[0] for r in c.execute("SELECT key FROM rate_counters")}
    assert left == {"k:2"}


# -- §8.5 cache headers --------------------------------------------------------------

def test_catalog_cache_headers_and_304():
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.v1.catalog import router

    app = FastAPI()
    app.include_router(router, prefix="/v1")
    client = TestClient(app)
    r = client.get("/v1/catalog")
    assert r.status_code == 200
    assert r.headers["Cache-Control"] == "public, max-age=300"
    assert r.headers["ETag"]
    assert client.get("/v1/windows").headers["Cache-Control"] == "public, max-age=300"
    assert client.get("/v1/serviceability?pincode=560001").headers["ETag"]
    again = client.get("/v1/catalog", headers={"If-None-Match": r.headers["ETag"]})
    assert again.status_code == 304
