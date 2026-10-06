"""Phase 2 Split A (§2.1 dispatch pipeline + §2.6 duty repool + §2.7 PoD offline).

- §2.1: full placed→delivered walk (accept→pack→assign→dispatch→triple→
  cash→PoD) with audit rows per transition; 409s on illegal jumps; zone +
  capacity rejections on vendor pull; replay on double pull.
- §2.6: duty-off repools pending stops (failed + events + audit); duty-on
  unaffected.
- §2.7: pod replay returns the stored outcome (no write, no attempt burn);
  sync_batch accepts pod items (applied → replayed).
"""

import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(API_ROOT / "src"))

import datetime as _dt  # noqa: E402

from app.db import get_connection, init_schema  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402

MIGS = ["002_auth.sql", "003_addresses.sql", "004_orders.sql", "005_payments.sql",
        "007_ops.sql", "015_pod_otp.sql"]
DAY = _dt.datetime.now(_dt.timezone.utc).date().isoformat()


def _conn():
    c = get_connection(":memory:")
    init_schema(c)
    base = API_ROOT / "src" / "app" / "db" / "migrations"
    for name in MIGS:
        c.executescript((base / name).read_text())
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    c.execute(
        "INSERT INTO users(id, phone, role, created_at) VALUES "
        "('admin1', '+911111111111', 'admin', ?),"
        " ('v1', '+912222222222', 'vendor', ?),"
        " ('v2', '+913333333333', 'vendor', ?),"
        " ('u1', '+914444444444', 'user', ?)",
        (now,) * 4,
    )
    c.execute("INSERT INTO zones(id, name, pincodes) VALUES ('z1', 'Z1', '110001'), ('z2', 'Z2', '999999')")
    c.execute("INSERT INTO vendor_zones(vendor_id, zone_id) VALUES ('v1', 'z1'), ('v2', 'z2')")
    c.execute(
        "INSERT INTO vendor_profile(user_id, max_stops_per_shift, max_jars_per_shift,"
        " per_stop_fee, active, on_duty, in_hand) VALUES ('v1', 25, 60, 0, 1, 1, 0),"
        " ('v2', 25, 60, 0, 1, 1, 0)")
    c.execute(
        "INSERT INTO addresses(id, user_id, type, lat, lng, pincode, created_at)"
        " VALUES ('a1', 'u1', 'home', 28.6, 77.2, '110001', ?)", (now,))
    c.commit()
    return c


def _order(c, oid="o1", state="placed", total=20600):
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
        " total, payment_mode, payment_status, state, window_start, idempotency_key, created_at)"
        " VALUES (?, 'u1', 'a1', '[{\"sku\":\"refill\",\"qty\":2}]', 2, 1, 5600, 15000,"
        " ?, 'cod', 'unpaid', ?, '2026-10-01T08:00Z', ?, ?)",
        (oid, total, state, f"k-{oid}", now))
    c.commit()


def _w(c):
    return c if isinstance(c, AsyncSqliteConn) else AsyncSqliteConn(c)


def _canned(uid, role):
    return {"id": uid, "role": role, "phone": "+910000000000",
            "suspended": False, "session_id": "s", "family_id": "f", "device_fp": "d"}


def _client(c, router_mod, canned):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api import auth_deps
    from app.api.deps import get_db_conn
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router_mod.router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: _w(c)
    app.dependency_overrides[auth_deps.get_current_user] = lambda: canned
    return TestClient(app)


def _admin(c):
    from app.api.v1 import admin as admin_mod

    return _client(c, admin_mod, _canned("admin1", "admin"))


def _vendor(c, uid="v1"):
    from app.api.v1 import vendor as vendor_mod

    return _client(c, vendor_mod, _canned(uid, "vendor"))


# -- §2.1 dispatch pipeline ----------------------------------------------------

def test_full_walk_placed_to_delivered():
    c = _conn()
    _order(c)
    admin, vendor = _admin(c), _vendor(c)
    assert admin.post("/v1/admin/orders/o1/accept").status_code == 200
    assert admin.post("/v1/admin/orders/o1/pack").status_code == 200
    assign = admin.post("/v1/admin/orders/o1/assign", json={"vendor_id": "v1"})
    assert assign.status_code == 200, assign.text
    route_id, stop_id = assign.json()["route_id"], assign.json()["stop_id"]
    d = admin.post(f"/v1/admin/routes/{route_id}/dispatch")
    assert d.status_code == 200 and d.json()["dispatched"] == [stop_id]
    t = vendor.post(f"/v1/vendor/stops/{stop_id}/triple",
                    json={"fulls_given": 2, "empties_back": 1, "version": 1},
                    headers={"Idempotency-Key": "tw1"})
    assert t.status_code == 200, t.text
    assert vendor.post(f"/v1/vendor/stops/{stop_id}/cash", json={"amount": 5600}).status_code == 200
    otp = c.execute("SELECT pod_otp FROM stops WHERE id = ?", (stop_id,)).fetchone()["pod_otp"]
    assert otp and len(otp) == 6
    p = vendor.post(f"/v1/vendor/stops/{stop_id}/pod", json={"delivery_otp": otp})
    assert p.status_code == 200, p.text
    assert c.execute("SELECT state FROM orders WHERE id = 'o1'").fetchone()["state"] == "delivered"
    events = c.execute("SELECT to_state FROM order_events WHERE order_id = 'o1' ORDER BY created_at").fetchall()
    assert [r["to_state"] for r in events] == ["accepted", "picked", "packed", "assigned", "dispatched", "delivered"]
    # Per-transition trail lives in order_events (above); the dispatcher
    # actions additionally land in audit_log (accept + pack).
    assert c.execute("SELECT COUNT(*) c FROM audit_log WHERE entity_id = 'o1'").fetchone()["c"] >= 2


def test_illegal_jumps_409_and_dispatch_skips():
    c = _conn()
    _order(c)
    admin = _admin(c)
    assert admin.post("/v1/admin/orders/o1/pack").status_code == 409  # placed→picked illegal
    assert admin.post("/v1/admin/orders/o1/accept").status_code == 200
    assert admin.post("/v1/admin/orders/o1/accept").status_code == 409  # no longer placed
    assert admin.post("/v1/admin/orders/o1/reject", json={"reason": "no stock"}).status_code == 409
    d = admin.post("/v1/admin/routes/nonexistent/dispatch")
    assert d.status_code == 200 and d.json() == {"route_id": "nonexistent", "dispatched": [], "skipped": []}


def test_reject_terminal():
    c = _conn()
    _order(c)
    admin = _admin(c)
    r = admin.post("/v1/admin/orders/o1/reject", json={"reason": "area unserviceable"})
    assert r.status_code == 200
    assert c.execute("SELECT state FROM orders WHERE id = 'o1'").fetchone()["state"] == "rejected"


def test_vendor_pull_zone_capacity_replay():
    c = _conn()
    _order(c)
    vendor = _vendor(c)
    # v2 serves z2 only — the order's address is in z1.
    other = _vendor(c, "v2")
    assert other.post("/v1/vendor/placed/o1/accept").status_code == 422
    assert c.execute("SELECT state FROM orders WHERE id = 'o1'").fetchone()["state"] == "placed"
    assert c.execute("SELECT COUNT(*) c FROM stops").fetchone()["c"] == 0
    # Capacity: v1 capped at 0 stops also fails cheap (zero writes).
    # (init_schema seeds v1/v2 profiles with 25/60 caps.)
    c.execute("UPDATE vendor_profile SET max_stops_per_shift = 0 WHERE user_id = 'v1'")
    assert vendor.post("/v1/vendor/placed/o1/accept").status_code == 422
    assert c.execute("SELECT state FROM orders WHERE id = 'o1'").fetchone()["state"] == "placed"
    assert c.execute("SELECT COUNT(*) c FROM stops").fetchone()["c"] == 0
    assert c.execute("SELECT COUNT(*) c FROM order_events WHERE order_id = 'o1'").fetchone()["c"] == 0
    c.execute("UPDATE vendor_profile SET max_stops_per_shift = 25 WHERE user_id = 'v1'")
    first = vendor.post("/v1/vendor/placed/o1/accept")
    assert first.status_code == 200, first.text
    assert first.json()["stop_id"]
    assert c.execute("SELECT state FROM orders WHERE id = 'o1'").fetchone()["state"] == "assigned"
    again = vendor.post("/v1/vendor/placed/o1/accept")
    assert again.status_code == 200 and again.json().get("replay") is True
    assert again.json()["stop_id"] == first.json()["stop_id"]
    assert c.execute("SELECT COUNT(*) c FROM audit_log WHERE action = 'vendor.accept'").fetchone()["c"] == 1


# -- §2.6 duty repool ------------------------------------------------------------

async def test_duty_off_repools_on_stays_clean():
    from app.services.vendor_service import VendorService

    c = _conn()
    _order(c, state="packed")
    from app.services.dispatch_service import assign_order

    await assign_order(_w(c), "o1", "v1", {"id": "admin1", "role": "admin"})
    svc = VendorService(_w(c))
    off = await svc.duty("v1", False)
    assert off["duty_on"] is False and off["repooled"] == 1
    assert c.execute("SELECT status FROM stops").fetchone()["status"] == "failed"
    assert c.execute("SELECT COUNT(*) c FROM audit_log WHERE action = 'vendor.duty_off'").fetchone()["c"] == 1
    on = await svc.duty("v1", True)
    assert on == {"vendor_id": "v1", "duty_on": True, "since": on["since"], "repooled": 0}


# -- §2.7 pod offline replay + sync ----------------------------------------------

async def test_pod_replay_no_write_no_burn():
    from app.services.vendor_service import VendorService

    c = _conn()
    _order(c, state="dispatched")
    c.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status) VALUES ('r1', '2026-10-01', 'v1', 'z1', 'open')")
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status, pod_otp) VALUES ('s1', 'r1', 'o1', 'u1', 0, 2, 1, 1, 'pending', '482910')")
    c.commit()
    svc = VendorService(_w(c))
    first = await svc.pod_complete("v1", "s1", {"delivery_otp": "482910"})
    assert first["status"] == "done" and not first.get("replay")
    second = await svc.pod_complete("v1", "s1", {"delivery_otp": "482910"})
    assert second.get("replay") is True
    assert c.execute("SELECT pod_attempts FROM stops WHERE id = 's1'").fetchone()["pod_attempts"] == 0


async def test_sync_batch_pod_item_applied_then_replayed():
    from app.services.vendor_service import VendorService

    c = _conn()
    _order(c, state="dispatched")
    c.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status) VALUES ('r1', '2026-10-01', 'v1', 'z1', 'open')")
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status, pod_otp) VALUES ('s1', 'r1', 'o1', 'u1', 0, 2, 1, 1, 'pending', '482910')")
    c.commit()
    svc = VendorService(_w(c))
    item = {"stop_id": "s1", "pod": True, "delivery_otp": "482910", "empties_count": 1}
    once = await svc.sync_batch("v1", [item])
    assert once["applied"] == ["s1"] and once["rejected"] == []
    twice = await svc.sync_batch("v1", [item])
    assert twice["replayed"] == ["s1"] and twice["applied"] == []
