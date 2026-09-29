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

MIGRATIONS = ["002_auth.sql", "003_addresses.sql", "004_orders.sql", "007_ops.sql"]


def _conn():
    c = get_connection(":memory:")
    for name in MIGRATIONS:
        c.executescript((API_ROOT / "app" / "db" / "migrations" / name).read_text())
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
    from app.api.deps import get_db
    from app.api.v1.admin import router
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    app.dependency_overrides[get_db] = lambda: c
    app.dependency_overrides[auth_deps.get_current_user] = lambda: user
    return TestClient(app)


ADM = {"id": "admin1", "role": "admin"}

# -- dispatch service ----------------------------------------------------------

def test_assign_least_loaded_and_capacity_refused():
    c = _conn()
    _seed_base(c)
    _order(c, "o0")
    assign_order(c, "o0", "v1", ADM)  # v1 now carries 1 stop
    pick = least_loaded_vendor(c, "z1")
    assert pick and pick["vendor_id"] == "v2"  # least-loaded wins
    _order(c, "o1")
    out = assign_order(c, "o1", pick["vendor_id"], ADM)
    assert out["version"] == 1
    assert c.execute("SELECT state FROM orders WHERE id = 'o1'").fetchone()["state"] == "assigned"
    c.execute("UPDATE vendor_profile SET max_stops_per_shift = 1 WHERE user_id = 'v2'")
    _order(c, "o2")
    with pytest.raises(CapacityExceededError) as e:
        assign_order(c, "o2", "v2", ADM)
    assert e.value.code == "CAPACITY_EXCEEDED" and e.value.status_code == 422
    c.execute("INSERT INTO users(id, phone, role, language, kyc_status, suspended, created_at)"
              " VALUES ('v3', '+915555555555', 'vendor', 'hi', 'verified', 0, 't')")
    c.execute("INSERT INTO zones(id, name, pincodes, active) VALUES ('z2', 'Z2', '999999', 1)")
    c.execute("INSERT INTO vendor_zones(vendor_id, zone_id) VALUES ('v3', 'z2')")
    with pytest.raises(ZoneMismatchError) as e2:
        assign_order(c, "o2", "v3", ADM)
    assert e2.value.code == "ZONE_MISMATCH"


def test_reassign_fences_old_stop():
    c = _conn()
    _seed_base(c)
    _order(c, "o1")
    first = assign_order(c, "o1", "v1", ADM)
    before_total = c.execute("SELECT total FROM orders WHERE id = 'o1'").fetchone()["total"]
    out = reassign_order(c, "o1", "v2", ADM, "rebalance")
    assert out["version"] == first["version"] + 1
    assert out["total_frozen"] == before_total  # price frozen
    old = c.execute("SELECT status FROM stops WHERE id = ?", (first["stop_id"],)).fetchone()
    assert old["status"] != "pending"  # old stop fenced
    with pytest.raises(StaleStopError) as e:
        check_stop_fresh(c, first["stop_id"], first["version"])  # triple on old version
    assert e.value.code == "STALE_STOP" and e.value.status_code == 409
    assert check_stop_fresh(c, out["stop_id"], out["version"])["status"] == "pending"


def test_override_cancel_post_dispatch():
    c = _conn()
    _seed_base(c)
    _order(c, "o1")
    assign_order(c, "o1", "v1", ADM)
    OrderRepo(c).transition("o1", "dispatched", ADM, "ops")
    with pytest.raises(NeedDispatchOverrideError):  # user self-cancel blocked
        OrderRepo(c).cancel_settle("o1", {"id": "u1", "role": "user"})
    out = OrderRepo(c).cancel_settle("o1", ADM)  # dispatcher override settles
    assert out["state"] == "cancelled" and out["bill_total"] == 0
    client = _client(c)  # router-level override path
    _order(c, "o2")
    assign_order(c, "o2", "v2", ADM)
    OrderRepo(c).transition("o2", "dispatched", ADM, "ops")
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
