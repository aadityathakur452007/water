"""D4 dispatch + admin tests (contract §9/§11/§14 + api-contract §4.11).

Service + router levels. Router tests mount the bare admin router standalone
with get_db + session auth overridden (main.py wiring is the integrator's job).
"""
import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db import get_connection, init_schema  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.repositories.order_repo import NeedDispatchOverrideError, OrderRepo  # noqa: E402
from app.services.dispatch_service import (  # noqa: E402
    CapacityExceededError,
    StaleStopError,
    ZoneMismatchError,
    assign_order,
    check_stop_fresh,
    least_loaded_vendor,
    reassign_order,
)

MIGRATIONS = ["002_auth.sql", "003_addresses.sql", "004_orders.sql", "005_payments.sql", "007_ops.sql"]


def _conn():
    c = get_connection(":memory:")
    for name in MIGRATIONS:
        c.executescript((API_ROOT / "src" / "app" / "db" / "migrations" / name).read_text())
    init_schema(c)  # landed slice-1 config/audit_log shape
    return c


ADMIN = {"id": "admin1", "role": "admin", "phone": "+911111111111",
         "suspended": False, "session_id": "s", "family_id": "f", "device_fp": "d"}


def _seed_base(c):
    c.execute(
        "INSERT INTO users(id, phone, name, role, language, kyc_status, suspended, created_at)"
        " VALUES ('admin1', '+911111111111', 'Admin', 'admin', 'hi', 'none', 0, 't'),"
        " ('v1', '+912222222222', 'V One', 'vendor', 'hi', 'verified', 0, 't'),"
        " ('v2', '+913333333333', 'V Two', 'vendor', 'hi', 'verified', 0, 't'),"
        " ('u1', '+914444444444', 'User', 'user', 'hi', 'none', 0, 't')")
    c.execute("INSERT INTO zones(id, name, pincodes, active) VALUES ('z1', 'Z1', '110001,110002', 1)")
    c.execute("INSERT INTO vendor_zones(vendor_id, zone_id, priority) VALUES ('v1', 'z1', 0), ('v2', 'z1', 1)")
    c.execute(
        "INSERT INTO vendor_profile(user_id, max_stops_per_shift, max_jars_per_shift,"
        " per_stop_fee, active, on_duty, in_hand) VALUES ('v1', 25, 60, 0, 1, 1, 0),"
        " ('v2', 25, 60, 0, 1, 1, 0)")
    c.execute(
        "INSERT INTO addresses(id, user_id, type, lat, lng, pincode, serviceable, created_at)"
        " VALUES ('a1', 'u1', 'home', 28.6, 77.2, '110001', 1, 't')")
    c.commit()


def _order(c, oid="o1", state="packed", n=2, e=1, total=20600):
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, m, water_bill, deposit_due,"
        " cap_charge, total, payment_mode, payment_status, state, window_start, window_end,"
        " idempotency_key, payload_hash, quote_hash, quote_rate_version, created_at)"
        " VALUES (?, 'u1', 'a1', '[{\"sku\":\"refill\",\"qty\":2}]', ?, 1, 0, 5600, 15000, 0,"
        " ?, 'cod', 'unpaid', ?, '2026-10-01T08:00:00+00:00', '', ?, '', '', 'v1', 't')",
        (oid, n, total, state, f"k-{oid}"))
    c.commit()
    return oid


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


ADM = {"id": "admin1", "role": "admin"}

# -- dispatch service ----------------------------------------------------------

async def test_assign_least_loaded_and_capacity_refused():
    c = _conn()
    _seed_base(c)
    _order(c, "o0")
    ac = AsyncSqliteConn(c)
    await assign_order(ac, "o0", "v1", ADM)  # v1 now carries 1 stop
    pick = await least_loaded_vendor(ac, "z1")
    assert pick and pick["vendor_id"] == "v2"  # least-loaded wins
    _order(c, "o1")
    out = await assign_order(ac, "o1", pick["vendor_id"], ADM)
    assert out["version"] == 1
    assert c.execute("SELECT state FROM orders WHERE id = 'o1'").fetchone()["state"] == "assigned"
    c.execute("UPDATE vendor_profile SET max_stops_per_shift = 1 WHERE user_id = 'v2'")
    _order(c, "o2")
    with pytest.raises(CapacityExceededError) as e:
        await assign_order(ac, "o2", "v2", ADM)
    assert e.value.code == "CAPACITY_EXCEEDED" and e.value.status_code == 422
    c.execute("INSERT INTO users(id, phone, role, language, kyc_status, suspended, created_at)"
              " VALUES ('v3', '+915555555555', 'vendor', 'hi', 'verified', 0, 't')")
    c.execute("INSERT INTO zones(id, name, pincodes, active) VALUES ('z2', 'Z2', '999999', 1)")
    c.execute("INSERT INTO vendor_zones(vendor_id, zone_id) VALUES ('v3', 'z2')")
    with pytest.raises(ZoneMismatchError) as e2:
        await assign_order(ac, "o2", "v3", ADM)
    assert e2.value.code == "ZONE_MISMATCH"


async def test_reassign_fences_old_stop():
    c = _conn()
    _seed_base(c)
    _order(c, "o1")
    ac = AsyncSqliteConn(c)
    first = await assign_order(ac, "o1", "v1", ADM)
    before_total = c.execute("SELECT total FROM orders WHERE id = 'o1'").fetchone()["total"]
    out = await reassign_order(ac, "o1", "v2", ADM, "rebalance")
    assert out["version"] == first["version"] + 1
    assert out["total_frozen"] == before_total  # price frozen
    old = c.execute("SELECT status FROM stops WHERE id = ?", (first["stop_id"],)).fetchone()
    assert old["status"] != "pending"  # old stop fenced
    with pytest.raises(StaleStopError) as e:
        await check_stop_fresh(ac, first["stop_id"], first["version"])  # triple on old version
    assert e.value.code == "STALE_STOP" and e.value.status_code == 409
    assert (await check_stop_fresh(ac, out["stop_id"], out["version"]))["status"] == "pending"


async def test_override_cancel_post_dispatch():
    c = _conn()
    _seed_base(c)
    _order(c, "o1")
    ac = AsyncSqliteConn(c)
    await assign_order(ac, "o1", "v1", ADM)
    await OrderRepo(ac).transition("o1", "dispatched", ADM, "ops")
    with pytest.raises(NeedDispatchOverrideError):  # user self-cancel blocked
        await OrderRepo(ac).cancel_settle("o1", {"id": "u1", "role": "user"})
    out = await OrderRepo(ac).cancel_settle("o1", ADM)  # dispatcher override settles
    assert out["state"] == "cancelled" and out["bill_total"] == 0
    client = _client(c)  # router-level override path
    _order(c, "o2")
    await assign_order(ac, "o2", "v2", ADM)
    await OrderRepo(ac).transition("o2", "dispatched", ADM, "ops")
    r = client.post("/v1/admin/orders/o2/cancel-override", json={"reason": "admin call"})
    assert r.status_code == 200, r.text
    assert r.json()["state"] == "cancelled"


# -- admin router ---------------------------------------------------------------

def test_detach_refused_with_open_custody():
    c = _conn()
    _seed_base(c)
    client = _client(c)
    c.execute("UPDATE vendor_profile SET in_hand = 5000 WHERE user_id = 'v1'")
    c.commit()
    r = client.post("/v1/admin/zones/z1/vendors/v1/detach", json={"reason": "swap"})
    assert r.status_code == 409 and r.json()["error"]["code"] == "CUSTODY_BLOCKED"
    c.execute("UPDATE vendor_profile SET in_hand = 0 WHERE user_id = 'v1'")
    c.commit()
    r2 = client.post("/v1/admin/zones/z1/vendors/v1/detach", json={"reason": "swap"})
    assert r2.status_code == 200, r2.text
    assert r2.json()["detached"] is True


def test_ledger_adjust_writes_audit_row():
    c = _conn()
    _seed_base(c)
    client = _client(c)
    r = client.post("/v1/admin/ledger/u1/adjust",
                    json={"d_held": 0, "d_deposit": 0, "d_dues": 500, "reason": "short cash"})
    assert r.status_code == 200, r.text
    assert r.json()["after"]["dues"] == 500
    audit = client.get("/v1/admin/audit", params={"entity": "ledger"}).json()["data"]
    assert any(a["action"] == "ledger.adjust" and a["entity_id"] == "u1" for a in audit)


def test_quality_confirm_creates_strike():
    c = _conn()
    _seed_base(c)
    _order(c, "o1", state="delivered")
    c.execute(
        "INSERT INTO quality_incidents(id, order_id, vendor_id, reason_code, description,"
        " status, created_at) VALUES ('q1', 'o1', 'v1', 'water_quality', 'smells off', 'open', 't')")
    c.commit()
    client = _client(c)
    r = client.post("/v1/admin/quality/q1/confirm", json={"resolution": "free redelivery"})
    assert r.status_code == 200, r.text
    strike_id = r.json()["strike_id"]
    row = c.execute("SELECT subject_id, kind FROM strikes WHERE id = ?", (strike_id,)).fetchone()
    assert row is not None and row["subject_id"] == "v1" and row["kind"] == "quality"
    assert c.execute("SELECT status FROM quality_incidents WHERE id = 'q1'").fetchone()["status"] \
        == "confirmed"


def test_config_effective_from_stored():
    c = _conn()
    _seed_base(c)
    client = _client(c)
    r = client.patch("/v1/admin/config", json={"key": "cod_cap", "value": "200000"})
    assert r.status_code == 200, r.text
    assert r.json()["effective_from"]  # effective_from returned + stored (Finder-C10)
    row = c.execute("SELECT value, effective_from FROM config WHERE key = 'cod_cap'").fetchone()
    assert row["value"] == "200000" and row["effective_from"]


def _seed_done_stop(c, day="2026-10-03"):
    c.execute("INSERT INTO routes(id, date, vendor_id, zone, status)"
              " VALUES ('r1', ?, 'v1', 'z1', 'open')", (day,))
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, triple, status, synced_at)"
        " VALUES ('s1', 'r1', 'o1', 'u1', 0, 2, 1, 2,"
        " '{\"fulls_given\": 2, \"empties_back\": 1, \"cash\": 20600, \"upi\": 0}',"
        " 'done', 't')")
    c.commit()


def test_payout_generate_approve_and_double_guards():
    c = _conn()
    _seed_base(c)
    _order(c, "o1", state="delivered")
    _seed_done_stop(c)
    c.execute("UPDATE vendor_profile SET per_stop_fee = 500 WHERE user_id = 'v1'")
    c.commit()
    client = _client(c)
    g = client.post("/v1/admin/payouts/generate",
                    json={"vendor_id": "v1", "period": "2026-10"})
    assert g.status_code == 200, g.text
    assert g.json()["stops_done"] == 1 and g.json()["gross_fee"] == 500
    assert g.json()["status"] == "pending"
    dup = client.post("/v1/admin/payouts/generate",
                      json={"vendor_id": "v1", "period": "2026-10"})
    assert dup.status_code == 409  # one payout per vendor+period
    pid = g.json()["id"]
    ok = client.post(f"/v1/admin/payouts/{pid}/approve")
    assert ok.status_code == 200, ok.text
    assert ok.json()["status"] == "approved" and ok.json()["approved_by"] == "admin1"
    again = client.post(f"/v1/admin/payouts/{pid}/approve")
    assert again.status_code == 409  # pending-only
    listed = client.get("/v1/admin/payouts", params={"vendor_id": "v1"}).json()["data"]
    assert any(p["id"] == pid and p["status"] == "approved" for p in listed)


def test_custody_confirm_decrements_and_guards():
    c = _conn()
    _seed_base(c)
    client = _client(c)
    c.execute("UPDATE vendor_profile SET in_hand = 5000 WHERE user_id = 'v1'")
    c.commit()
    r = client.post("/v1/admin/custody/confirm",
                    json={"vendor_id": "v1", "amount": 2000})
    assert r.status_code == 200, r.text
    assert r.json() == {"vendor_id": "v1", "confirmed": 2000, "in_hand": 3000}
    over = client.post("/v1/admin/custody/confirm",
                       json={"vendor_id": "v1", "amount": 99999})
    assert over.status_code == 400  # cannot confirm more than held


def test_reconciliation_close_snapshots_and_audits():
    c = _conn()
    _seed_base(c)
    _order(c, "o1", state="delivered")
    _seed_done_stop(c)
    client = _client(c)
    r = client.post("/v1/admin/reconciliation/close", json={"date": "2026-10-03"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["closed"] is True and body["collected_cash"] == 20600
    assert body["collected_upi"] == 0
    audit = client.get("/v1/admin/audit", params={"entity": "reconciliation"}).json()["data"]
    assert any(a["action"] == "reco.close" for a in audit)


def test_returns_assign_pickup_shape_refund_flow():
    c = _conn()
    _seed_base(c)
    client = _client(c)
    c.execute(
        "INSERT INTO returns(id, user_id, qty, address_id, status, sla_due, created_at)"
        " VALUES ('ret1', 'u1', 2, 'a1', 'requested', '2026-10-15', 't')")
    c.commit()
    a = client.post("/v1/admin/returns/ret1/assign",
                    json={"vendor_id": "v1", "date": "2026-10-03"})
    assert a.status_code == 200, a.text
    stop = c.execute("SELECT route_id, empties_exp, status FROM stops WHERE return_id = 'ret1'").fetchone()
    assert stop is not None and stop["empties_exp"] == 2 and stop["status"] == "pending"
    again = client.post("/v1/admin/returns/ret1/assign",
                        json={"vendor_id": "v1", "date": "2026-10-03"})
    assert again.status_code == 409  # already on a route — no duplicate stop
    # Refund before pickup → 409; pickup happens vendor-side (tested in test_vendor).
    early = client.post("/v1/admin/returns/ret1/refund",
                        json={"method": "upi", "qty": 2})
    assert early.status_code == 409
    c.execute("UPDATE returns SET status = 'picked' WHERE id = 'ret1'")
    c.execute("INSERT INTO ledger(customer_id, held, deposit_paid) VALUES ('u1', 2, 30000)")
    c.commit()
    f = client.post("/v1/admin/returns/ret1/refund",
                    json={"method": "upi", "qty": 2})
    assert f.status_code == 200, f.text
    assert f.json()["status"] == "refunded" and f.json()["refunded"] == 30000
    led = c.execute("SELECT deposit_refunded FROM ledger WHERE customer_id = 'u1'").fetchone()
    assert led["deposit_refunded"] == 30000


def test_admin_authz_and_vendor_lifecycle_and_metrics():
    c = _conn()
    _seed_base(c)
    _order(c, "o1")
    user_client = _client(c, user={"id": "u1", "role": "user", "suspended": False})
    assert user_client.get("/v1/admin/orders").status_code == 403  # ssdlc: admin-only
    client = _client(c)
    assert client.get("/v1/admin/orders", params={"state": "packed"}).status_code == 200
    v = client.post("/v1/admin/vendors",
                    json={"phone": "+916666666666", "name": "V New",
                          "zone_id": "z1", "kyc_note": "aadhaar seen"}).json()
    assert v["kyc_status"] == "pending"  # role granted only on verify
    assert c.execute("SELECT role FROM users WHERE id = ?", (v["id"],)).fetchone()["role"] == "user"
    ok = client.post(f"/v1/admin/vendors/{v['id']}/verify")
    assert ok.status_code == 200
    assert c.execute("SELECT role FROM users WHERE id = ?", (v["id"],)).fetchone()["role"] == "vendor"
    m = client.get("/v1/admin/metrics").json()
    assert m["orders_by_state"].get("packed", 0) >= 1
