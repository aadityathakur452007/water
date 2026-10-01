"""F-SA super-admin panel tests (contract §3/§4.11/§14.5).

Covers the additive panel surface: overview metrics, user/vendor directories,
user detail, suspend ladder (restrict vs suspend + session revocation + audit +
admin-protection), unsuspend, payments/refunds/ledger pages with cursor paging.
Router-level, standalone-mount admin router (same pattern as test_dispatch_admin).
"""
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db import get_connection, init_schema  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402

MIGRATIONS = ["002_auth.sql", "003_addresses.sql", "004_orders.sql",
              "005_payments.sql", "007_ops.sql"]


def _conn():
    c = get_connection(":memory:")
    for name in MIGRATIONS:
        c.executescript((API_ROOT / "src" / "app" / "db" / "migrations" / name).read_text())
    init_schema(c)
    return c


ADMIN = {"id": "admin1", "role": "admin", "phone": "+911111111111",
         "suspended": False, "session_id": "s", "family_id": "f", "device_fp": "d"}
USER = {"id": "u1", "role": "user", "phone": "+914444444444",
        "suspended": False, "session_id": "s", "family_id": "f", "device_fp": "d"}


def _seed_base(c):
    c.execute(
        "INSERT INTO users(id, phone, name, role, language, kyc_status, suspended, created_at)"
        " VALUES ('admin1', '+911111111111', 'Admin', 'admin', 'hi', 'none', 0, '2026-09-28T10:00:00+00:00'),"
        " ('v1', '+912222222222', 'V One', 'vendor', 'hi', 'verified', 0, '2026-09-28T10:00:00+00:00'),"
        " ('u1', '+914444444444', 'User One', 'user', 'hi', 'none', 0, '2026-09-28T10:00:00+00:00')")
    c.execute(
        "INSERT INTO vendor_profile(user_id, max_stops_per_shift, max_jars_per_shift,"
        " per_stop_fee, active, on_duty, in_hand) VALUES ('v1', 25, 60, 1500, 1, 1, 5000)")
    c.execute(
        "INSERT INTO addresses(id, user_id, type, lat, lng, pincode, serviceable, created_at)"
        " VALUES ('a1', 'u1', 'home', 28.6, 77.2, '110001', 1, 't')")
    c.commit()


def _order(c, oid="o1", user_id="u1", state="delivered", total=5600,
           mode="upi", created="2026-09-29T10:00:00+00:00", window_day="2026-10-01"):
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, m, water_bill, deposit_due,"
        " cap_charge, total, payment_mode, payment_status, state, window_start, window_end,"
        " idempotency_key, payload_hash, quote_hash, quote_rate_version, created_at)"
        " VALUES (?, ?, 'a1', '[{\"sku\":\"refill\",\"qty\":2}]', 2, 1, 0, 5600, 15000, 0,"
        " ?, ?, 'paid_upi', ?, ?, ?,"
        " ?, '', '', 'v1', ?)",
        (oid, user_id, total, mode, state,
         f"{window_day}T08:00:00+00:00", f"{window_day}T08:30:00+00:00",
         f"k-{oid}", created))
    c.commit()


def _client(c, user=ADMIN):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api import auth_deps
    from app.api.deps import get_db_conn
    from app.api.v1.admin import router
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: AsyncSqliteConn(c)
    app.dependency_overrides[auth_deps.get_current_user] = lambda: user
    return TestClient(app)


# -- authz gate -----------------------------------------------------------------

def test_panel_requires_admin():
    c = _conn()
    _seed_base(c)
    resp = _client(c, USER).get("/v1/admin/users")
    assert resp.status_code == 403


# -- overview --------------------------------------------------------------------

def test_overview_kpis_and_series():
    c = _conn()
    _seed_base(c)
    # Relative dates: the endpoint buckets by the real UTC clock (admin.py today =
    # utcnow[:10]), so fixed-date seeds rot when the day rolls over.
    now = datetime.now(timezone.utc).replace(microsecond=0)
    yday = now - timedelta(days=1)
    today = now.strftime("%Y-%m-%d")
    _order(c, "o1", created=yday.replace(hour=10).isoformat(), window_day=today)
    _order(c, "o2", state="cancelled", created=yday.replace(hour=11).isoformat(),
           window_day=today)
    _order(c, "o3", mode="cod", state="dispatched", created=now.isoformat())
    c.execute(
        "INSERT INTO order_events(id, order_id, from_state, to_state, actor_id, actor_role,"
        " reason, created_at) VALUES ('e1', 'o1', 'dispatched', 'delivered', 'v1', 'vendor',"
        " '', ?)", (yday.replace(hour=10, minute=20).isoformat(),))
    c.execute(
        "INSERT INTO ledger(customer_id, held, deposit_paid, dues) VALUES ('u1', 1, 15000, 0)")
    c.commit()
    body = _client(c).get("/v1/admin/metrics/overview?days=14").json()
    assert body["today"]["orders"] >= 1
    days = {r["day"]: r for r in body["series"]}
    assert days[yday.strftime("%Y-%m-%d")]["orders"] == 2
    assert days[yday.strftime("%Y-%m-%d")]["delivered"] == 1
    assert days[yday.strftime("%Y-%m-%d")]["gmv_paise"] == 5600 + 5600
    assert days[yday.strftime("%Y-%m-%d")]["on_time_pct"] == 100.0  # delivered yday 10:20 <= window_end today 08:30
    money = body["money"]
    assert money["jars_held"] == 1
    assert money["deposit_liability_paise"] == 15000


# -- directories + detail ----------------------------------------------------------

def test_users_page_search_and_role_filter():
    c = _conn()
    _seed_base(c)
    client = _client(c)
    body = client.get("/v1/admin/users?role=user").json()
    assert [r["id"] for r in body["data"]] == ["u1"]
    body = client.get("/v1/admin/users?query=9122").json()
    assert [r["id"] for r in body["data"]] == ["v1"]
    body = client.get("/v1/admin/users?query=no-match-zz").json()
    assert body["data"] == []


def test_user_detail_aggregates():
    c = _conn()
    _seed_base(c)
    _order(c, "o1")
    c.execute("INSERT INTO ledger(customer_id, held, dues) VALUES ('u1', 2, 5600)")
    c.commit()
    body = _client(c).get("/v1/admin/users/u1/detail").json()
    assert body["user"]["phone"] == "+914444444444"
    assert body["orders_count"] == 1
    assert body["spend_paise"] == 5600
    assert body["ledger"]["held"] == 2
    assert body["ledger"]["dues"] == 5600
    assert body["recent_orders"][0]["id"] == "o1"
    assert _client(c).get("/v1/admin/users/ghost/detail").status_code == 404


def test_vendor_detail_profile_and_stops():
    c = _conn()
    _seed_base(c)
    c.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status) VALUES ('r1', '2026-10-01', 'v1', 'z1', 'open')")
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp, empties_exp,"
        " status) VALUES ('st1', 'r1', 'o1', 'u1', 1, 2, 1, 'done')")
    _order(c, "o1")
    c.commit()
    body = _client(c).get("/v1/admin/vendors/v1/detail").json()
    assert body["vendor"]["role"] == "vendor"
    assert body["profile"]["per_stop_fee"] == 1500
    assert body["stops_done"] == 1
    assert body["jars_delivered"] == 2


# -- suspend ladder (headline power) ---------------------------------------------

def test_suspend_restrict_and_suspend_revokes_sessions():
    c = _conn()
    _seed_base(c)
    c.execute(
        "INSERT INTO sessions(id, user_id, token_hash, refresh_hash, role, device_fp,"
        " family_id, expires_at, refresh_expires_at, created_at)"
        " VALUES ('s1', 'u1', 'h1', 'r1', 'user', 'd', 'fam', '2099-01-01', '2099-01-01', 't')")
    c.commit()
    client = _client(c)
    out = client.post("/v1/admin/users/u1/suspend",
                      json={"reason": "fake collector report", "level": "suspend"}).json()
    assert out["suspended"] is True and out["revoked_sessions"] == 1
    row = c.execute("SELECT * FROM users WHERE id = 'u1'").fetchone()
    assert row["suspended"] == 1 and "suspend" in row["suspended_reason"]
    sess = c.execute("SELECT revoked_at FROM sessions WHERE id = 's1'").fetchone()
    assert sess["revoked_at"] is not None
    audit = c.execute(
        "SELECT action FROM audit_log WHERE entity_id = 'u1' ORDER BY rowid DESC").fetchone()
    assert audit["action"] == "user.suspend"
    # restrict path: flag only, sessions untouched
    c.execute("UPDATE sessions SET revoked_at = NULL WHERE id = 's1'")
    c.commit()
    out = client.post("/v1/admin/users/u1/suspend",
                      json={"reason": "COD only", "level": "restrict"}).json()
    assert out["revoked_sessions"] == 0


def test_suspend_admin_protection_and_unsuspend():
    c = _conn()
    _seed_base(c)
    client = _client(c)
    assert client.post("/v1/admin/users/admin1/suspend",
                       json={"reason": "self lockout", "level": "suspend"}).status_code == 400
    assert client.post("/v1/admin/users/u1/suspend",
                       json={"reason": "x", "level": "suspend"}).status_code == 400
    client.post("/v1/admin/users/u1/suspend",
                json={"reason": "repeat offender", "level": "suspend"})
    out = client.post("/v1/admin/users/u1/unsuspend").json()
    assert out["suspended"] is False
    row = c.execute("SELECT suspended FROM users WHERE id = 'u1'").fetchone()
    assert row["suspended"] == 0
    audit = c.execute(
        "SELECT action FROM audit_log WHERE entity_id = 'u1' ORDER BY rowid DESC").fetchone()
    assert audit["action"] == "user.unsuspend"
    assert client.post("/v1/admin/users/ghost/unsuspend").status_code == 404


# -- money surfaces ------------------------------------------------------------------

def test_payments_refunds_ledger_pages_and_cursor():
    c = _conn()
    _seed_base(c)
    _order(c, "o1")
    _order(c, "o2")
    c.execute(
        "INSERT INTO payments(id, order_id, user_id, amount, method, provider_ref, status,"
        " created_at, verified_at) VALUES"
        " ('p1', 'o1', 'u1', 5600, 'upi', 'upi_ref_1', 'paid', '2026-09-29T10:05:00+00:00', '2026-09-29T10:06:00+00:00'),"
        " ('p2', 'o2', 'u1', 5600, 'cod', NULL, 'link_sent', '2026-09-29T11:05:00+00:00', NULL)")
    c.execute(
        "INSERT INTO refunds(id, order_id, payment_id, amount, method, status, created_at)"
        " VALUES ('rf1', 'o1', 'p1', 5600, 'upi', 'pending', '2026-09-29T12:00:00+00:00')")
    c.execute("INSERT INTO ledger(customer_id, held, deposit_paid, dues) VALUES ('u1', 1, 15000, 0)")
    c.commit()
    client = _client(c)
    body = client.get("/v1/admin/payments?status=paid").json()
    assert [r["id"] for r in body["data"]] == ["p1"]
    assert body["data"][0]["user_phone"] == "+914444444444"
    body = client.get("/v1/admin/payments?method=cod").json()
    assert [r["id"] for r in body["data"]] == ["p2"]
    # cursor paging: page of 1, then follow next_cursor
    page1 = client.get("/v1/admin/payments?limit=1").json()
    assert len(page1["data"]) == 1 and page1["next_cursor"]
    page2 = client.get(f"/v1/admin/payments?limit=1&cursor={page1['next_cursor']}").json()
    assert {page1["data"][0]["id"], page2["data"][0]["id"]} == {"p1", "p2"}
    body = client.get("/v1/admin/refunds").json()
    assert body["data"][0]["id"] == "rf1" and body["data"][0]["amount"] == 5600
    body = client.get("/v1/admin/ledger").json()
    assert body["data"][0]["customer_id"] == "u1"
    assert body["data"][0]["held"] == 1
