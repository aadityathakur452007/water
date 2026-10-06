"""Phase 3 Split A (backend reads/contracts): stop field completion (016),
tracking resource, instructions PATCH, vendor quality list, leads capture,
audit export, payments search, trust counts, IST business days.
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
        "007_ops.sql", "015_pod_otp.sql", "016_stop_fields.sql"]
DAY = _dt.datetime.now(_dt.timezone.utc).date().isoformat()


def _conn(with_016=True):
    c = get_connection(":memory:")
    init_schema(c)
    base = API_ROOT / "src" / "app" / "db" / "migrations"
    for name in MIGS:
        if name == "016_stop_fields.sql" and not with_016:
            continue
        c.executescript((base / name).read_text())
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    c.execute(
        "INSERT INTO users(id, phone, name, role, created_at) VALUES "
        "('admin1', '+911111111111', 'Admin', 'admin', ?),"
        " ('v1', '+912222222222', 'Ramu', 'vendor', ?),"
        " ('v2', '+916666666666', 'Kishore', 'vendor', ?),"
        " ('u1', '+913333333333', 'Meena', 'user', ?),"
        " ('u2', '+914444444444', 'Asha', 'user', ?)",
        (now,) * 5,
    )
    c.execute(
        "INSERT INTO addresses(id, user_id, type, lat, lng, pincode, created_at)"
        " VALUES ('a1', 'u1', 'home', 28.6, 77.2, '110001', ?)", (now,))
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
        " total, payment_mode, payment_status, state, window_start, idempotency_key, created_at)"
        " VALUES ('o1', 'u1', 'a1', '[{\"sku\":\"refill\",\"qty\":2}]', 2, 1, 5600, 0,"
        " 5600, 'cod', 'unpaid', 'dispatched', '2026-10-01T08:00:00+00:00', 'k-o1', ?)", (now,))
    c.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status) VALUES ('r1', ?, 'v1', 'z1', 'open')",
        (DAY,),
    )
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status) VALUES ('s1', 'r1', 'o1', 'u1', 0, 2, 1, 1, 'pending')")
    c.commit()
    return c


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


def _orders(c, uid="u1"):
    from app.api.v1 import orders as orders_mod

    return _client(c, orders_mod, _canned(uid, "user"))


def _admin(c):
    from app.api.v1 import admin as admin_mod

    return _client(c, admin_mod, _canned("admin1", "admin"))


def _vendor(c):
    from app.api.v1 import vendor as vendor_mod

    return _client(c, vendor_mod, _canned("v1", "vendor"))


# -- §3.2 stop fields ---------------------------------------------------------------

async def test_stop_carries_window_items_contact_instructions():
    from app.services.vendor_service import VendorService

    c = _conn()
    c.execute("UPDATE orders SET instructions = 'gate band hai, call karna' WHERE id = 'o1'")
    c.commit()
    stop = await VendorService(_w(c)).get_stop("v1", "s1")
    assert stop["window_start"] == "2026-10-01T08:00:00+00:00"
    assert stop["items"] == [{"sku": "refill", "qty": 2}]
    assert stop["customer_name"] == "Meena" and stop["customer_phone"] == "+913333333333"
    assert stop["instructions"] == "gate band hai, call karna"


async def test_pre_016_db_still_serves_stops_with_fallbacks():
    from app.services.vendor_service import VendorService

    stop = await VendorService(_w(_conn(with_016=False))).get_stop("v1", "s1")
    assert stop["items"] == [{"sku": "refill", "qty": 2}]  # frozen order items
    assert stop["instructions"] == "" and stop["window_start"].startswith("2026-10-01")


async def test_dispatch_snapshots_items_json():
    from app.services.dispatch_service import assign_order

    c = _conn()
    c.execute("UPDATE orders SET state = 'packed' WHERE id = 'o1'")
    # init_schema seeds v1/v2 profiles (25/60 caps); zones need seeding.
    c.execute("INSERT INTO zones(id, name, pincodes) VALUES ('z1', 'Z1', '110001')")
    c.execute("INSERT INTO vendor_zones(vendor_id, zone_id) VALUES ('v1', 'z1')")
    c.commit()
    out = await assign_order(_w(c), "o1", "v1", {"id": "admin1", "role": "admin"})
    row = c.execute("SELECT items_json FROM stops WHERE id = ?", (out["stop_id"],)).fetchone()
    assert row["items_json"] == '[{"sku":"refill","qty":2}]'


# -- tracking + instructions ----------------------------------------------------------

def test_tracking_shape_owner_only_no_bill():
    c = _conn()
    r = _orders(c).get("/v1/orders/o1/tracking")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["order_id"] == "o1" and body["state"] == "dispatched"
    assert body["tracker"]["current"] == "dispatched" and isinstance(body["events"], list)
    assert "bill" not in body and "ledger" not in body
    assert _orders(c, "u2").get("/v1/orders/o1/tracking").status_code == 404


def test_instructions_patch_matrix():
    c = _conn()
    c.execute("UPDATE orders SET state = 'placed' WHERE id = 'o1'")
    c.commit()
    client = _orders(c)
    r = client.patch("/v1/orders/o1/instructions", json={"instructions": "  gate band, call  "})
    assert r.status_code == 200 and r.json()["instructions"] == "gate band, call"
    assert client.patch("/v1/orders/o1/instructions", json={"instructions": "x" * 501}).status_code == 400
    assert _orders(c, "u2").patch("/v1/orders/o1/instructions", json={"instructions": "hijack"}).status_code == 404
    c.execute("UPDATE orders SET state = 'dispatched' WHERE id = 'o1'")
    c.commit()
    assert client.patch("/v1/orders/o1/instructions", json={"instructions": "late"}).status_code == 409


# -- §3.3 reads --------------------------------------------------------------------------

def test_vendor_quality_list_owned_only():
    c = _conn()
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    c.execute(
        "INSERT INTO quality_incidents(id, order_id, vendor_id, reason_code, status, created_at)"
        " VALUES ('q1', 'o1', 'v1', 'seal', 'open', ?)", (now,))
    c.commit()
    assert _vendor(c).get("/v1/vendor/quality").json() == {
        "data": [{"id": "q1", "order_id": "o1", "reason_code": "seal", "status": "open",
                  "vendor_agree": None, "created_at": now}], "next_cursor": None}
    from app.api.v1 import vendor as vendor_mod

    other = _client(c, vendor_mod, _canned("v2", "vendor"))
    assert other.get("/v1/vendor/quality").json() == {"data": [], "next_cursor": None}


def test_leads_capture_and_validation():
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.deps import get_db_conn
    from app.api.v1.catalog import router
    from app.core.errors import register_exception_handlers

    c = _conn()
    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: _w(c)
    client = TestClient(app)
    r = client.post("/v1/leads", json={"phone": "+919876543210", "pincode": "999999"})
    assert r.status_code == 201 and r.json()["id"]
    assert c.execute("SELECT COUNT(*) c FROM leads").fetchone()["c"] == 1
    assert client.post("/v1/leads", json={"phone": "x", "pincode": "999999"}).status_code == 400
    assert client.post("/v1/leads", json={"phone": "+919876543210", "pincode": "000"}).status_code == 400


def test_audit_export_csv_with_filters():
    c = _conn()
    c.execute(
        "INSERT INTO audit_log(actor, action, entity, entity_id, created_at)"
        " VALUES ('admin1', 'order.accept', 'orders', 'o1', 't')")
    c.commit()
    admin = _admin(c)
    r = admin.get("/v1/admin/audit/export", params={"action": "order.accept"})
    assert r.status_code == 200 and "text/csv" in r.headers["content-type"]
    assert "order.accept" in r.text and "o1" in r.text
    assert admin.get("/v1/admin/audit/export", params={"action": "nope"}).text.count("order.accept") == 0


def test_payments_server_search():
    c = _conn()
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    c.execute(
        "INSERT INTO payments(id, order_id, user_id, amount, method, provider_ref,"
        " status, created_at, verified_at) VALUES ('p1', 'o1', 'u1', 5600, 'upi', 'order_ABC',"
        " 'link_sent', ?, NULL)", (now,))
    c.commit()
    admin = _admin(c)
    assert len(admin.get("/v1/admin/payments", params={"query": "order_ABC"}).json()["data"]) == 1
    assert admin.get("/v1/admin/payments", params={"query": "zzz-no-match"}).json()["data"] == []


def test_trust_counts_match_db():
    c = _conn()
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    c.execute(
        "INSERT INTO complaints(id, order_id, user_id, reason_code, text, status, created_at)"
        " VALUES ('c1', 'o1', 'u1', 'short', 'x', 'open', ?)", (now,))
    c.execute(
        "INSERT INTO quality_incidents(id, order_id, vendor_id, reason_code, status, created_at)"
        " VALUES ('q1', 'o1', 'v1', 'seal', 'open', ?)", (now,))
    c.execute(
        "INSERT INTO strikes(id, subject_id, kind, severity, ref_type, ref_id, note,"
        " created_by, created_at) VALUES ('s1', 'v1', 'quality', 1, 'quality_incidents', 'q1',"
        " 'n', 'admin1', ?)", (now,))
    c.commit()
    admin = _admin(c)
    assert admin.get("/v1/admin/complaints").json()["counts"] == {"open": 1}
    assert admin.get("/v1/admin/quality").json()["counts"] == {"open": 1}
    assert admin.get("/v1/admin/strikes").json()["counts"] == {"open": 1}


async def test_ist_business_day_grouping():
    from app.repositories.admin_read_repo import AdminReadRepo

    c = _conn()
    # 23:30 UTC = 05:00 IST next day → belongs to the IST date.
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
        " total, payment_mode, payment_status, state, window_start, idempotency_key, created_at)"
        " VALUES ('o9', 'u1', 'a1', '[]', 1, 0, 2800, 0, 2800, 'cod', 'unpaid',"
        " 'placed', '2026-10-01T08:00Z', 'k-o9', '2026-10-03T23:30:00+00:00')")
    c.commit()
    rows = await AdminReadRepo(_w(c)).daily_series("2026-10-01")
    by_day = {r["day"]: r for r in rows}
    assert "2026-10-04" in by_day  # IST date, not the UTC date


def test_recon_rows_match_hand_sums():
    c = _conn()
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
        " total, payment_mode, payment_status, state, window_start, idempotency_key, created_at)"
        " VALUES ('o2', 'u1', 'a1', '[]', 1, 0, 2800, 0, 2800, 'cod', 'unpaid',"
        " 'assigned', '2026-10-01T08:00Z', 'k-o2', ?)", (now,))
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status) VALUES ('s2', 'r1', 'o2', 'u1', 1, 1, 0, 1, 'pending')")
    c.execute("UPDATE stops SET status = 'done' WHERE id = 's1'")
    c.execute(
        "INSERT INTO payments(id, order_id, user_id, amount, method, provider_ref,"
        " status, created_at, verified_at) VALUES ('p1', 'o1', 'u1', 1000, 'cod', 'cash:o1:x',"
        " 'paid', ?, ?)", (now, now))
    c.execute(
        "INSERT INTO payments(id, order_id, user_id, amount, method, provider_ref,"
        " status, created_at, verified_at) VALUES ('p2', 'o1', 'u1', 500, 'cod', 'cash:o1:y',"
        " 'partial', ?, ?)", (now, now))
    c.commit()
    body = _admin(c).get("/v1/admin/reconciliation", params={"date": DAY}).json()
    assert body["date"] == DAY
    assert len(body["routes"]) == 1
    row = body["routes"][0]
    assert row["route_id"] == "r1" and row["vendor_id"] == "v1"
    assert row["stops"] == 2 and row["delivered"] == 1
    assert row["jars_out"] == 3 and row["cash"] == 1500 and row["upi"] == 0
    assert body["dues_receivable"] >= 0 and "orders_by_state" in body


def test_custody_joins_identity_with_zeros():
    c = _conn()
    c.execute("UPDATE users SET name = 'Ramu', phone = '+915555555555' WHERE id = 'v1'")
    c.execute(
        "INSERT INTO vendor_profile(user_id, max_stops_per_shift, max_jars_per_shift,"
        " per_stop_fee, active, on_duty, in_hand) VALUES ('v1', 25, 60, 0, 1, 1, 500)")
    c.commit()
    rows = _admin(c).get("/v1/admin/custody").json()["data"]
    v1 = next(r for r in rows if r["vendor_id"] == "v1")
    assert v1["name"] == "Ramu" and v1["phone"] == "+915555555555"
    assert v1["on_duty"] is True and v1["in_hand"] == 500 and v1["zero"] is False
    # Vendors without custody still show (zero flag), instead of vanishing.
    others = [r for r in rows if r["vendor_id"] != "v1"]
    assert others and all(r["zero"] is True for r in others)
