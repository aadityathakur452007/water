"""Phase 1 Split 1 (§1.1 + §1.2) authz matrix: suspended-write bypass + role gates.

Suspended principals get 403 + zero rows on every write (orders create/cancel/
reschedule, addresses create/update/delete, devices delete) while reads stay
200. Non-user roles (vendor) get 403 + zero rows on user-surface writes
(orders/returns/subscriptions create, upi-intent, cod-confirm).

Guards run before any service/repo touch, so fake ids are enough to prove the
gate — row counts prove nothing was written. Happy paths for legit users are
covered by the existing router suites (role=user passes the gates); one
address-create happy path is pinned here against regressions.
"""

import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(API_ROOT / "src"))

from app.db import get_connection, init_schema  # noqa: E402


def _conn():
    c = get_connection(":memory:")
    init_schema(c)
    mig = API_ROOT / "src" / "app" / "db" / "migrations"
    for name in sorted(p.name for p in mig.glob("*.sql")):
        c.executescript((mig / name).read_text())
    c.commit()
    return c


def _user_dict(uid, role, suspended=False):
    return {
        "id": uid, "role": role, "phone": "+919000000000",
        "name": "T", "suspended": suspended, "suspended_reason": None,
        "session_id": "s", "family_id": "f", "device_fp": "d",
    }


def _client(c, canned):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api import auth_deps
    from app.api.deps import get_db_conn
    from app.api.v1 import addresses, devices, orders, payments, returns, subscriptions
    from app.core.errors import register_exception_handlers
    from app.db_d1 import AsyncSqliteConn

    app = FastAPI()
    register_exception_handlers(app)
    for mod in (orders, addresses, subscriptions, returns, payments, devices):
        app.include_router(mod.router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: AsyncSqliteConn(c)
    # Every guard (require_active_user, require_role closures) chains through
    # auth_deps.get_current_user, so one override drives the whole matrix.
    app.dependency_overrides[auth_deps.get_current_user] = lambda: canned
    return TestClient(app)


def _order_payload():
    from app.api.deps import get_settings
    from app.services import pricing

    s = get_settings()
    rates = {"refill": s.rate_refill_paise, "container": s.rate_container_paise,
             "deposit": s.deposit_per_jar_paise}
    items = [{"sku": "refill", "qty": 2}]
    window = "2026-10-01T08:00:00+00:00"
    q = pricing.compute_quote(items, 1, rates, address_id="a1",
                              window_start=window, rate_version=pricing.RATE_VERSION)
    return {
        "items": items, "e": 1, "address_id": "a1", "window_start": window,
        "quote_hash": q["quote_hash"], "quote_total": q["total"],
        "quote_rate_version": q["rate_version"],
        "quote_expires_at": (datetime.now(timezone.utc) + timedelta(minutes=15)).isoformat(),
        "payment_mode": "cod",
    }


def _address_payload():
    return {
        "type": "home", "lat": 12.9716, "lng": 77.5946, "accuracy_m": 10,
        "place_id": "stub-place", "formatted": "1 Main St", "landmark": "near park",
        "label": "Home", "pincode": "560001", "lift_flag": False,
    }


def _count(c, table):
    return c.execute(f"SELECT COUNT(*) c FROM {table}").fetchone()["c"]


IDEM = {"Idempotency-Key": "k-phase01"}


# -- §1.1 suspended-write bypass --------------------------------------------

def test_suspended_order_writes_403_zero_rows():
    c = _conn()
    client = _client(c, _user_dict("u9", "user", suspended=True))
    assert client.post("/v1/orders", json=_order_payload(), headers=IDEM).status_code == 403
    assert client.post("/v1/orders/nope/cancel", json={"reason": "x"},
                       headers=IDEM).status_code == 403
    assert client.post("/v1/orders/nope/reschedule",
                       json={"window_start": "2026-10-01T09:00:00+00:00"}).status_code == 403
    assert _count(c, "orders") == 0


def test_suspended_address_device_writes_403_zero_rows():
    c = _conn()
    client = _client(c, _user_dict("u9", "user", suspended=True))
    assert client.post("/v1/addresses", json=_address_payload()).status_code == 403
    assert client.patch("/v1/addresses/nope", json={"landmark": "x"}).status_code == 403
    assert client.delete("/v1/addresses/nope").status_code == 403
    assert client.request("DELETE", "/v1/devices", json={"device_id": "d1"}).status_code == 403
    assert _count(c, "addresses") == 0


def test_suspended_reads_still_200():
    c = _conn()
    client = _client(c, _user_dict("u9", "user", suspended=True))
    assert client.get("/v1/orders").status_code == 200
    assert client.get("/v1/addresses").status_code == 200


# -- §1.2 any-role write surface ---------------------------------------------

def test_vendor_user_surface_writes_403_zero_rows():
    c = _conn()
    client = _client(c, _user_dict("v1", "vendor"))
    assert client.post("/v1/orders", json=_order_payload(), headers=IDEM).status_code == 403
    assert client.post("/v1/returns", json={"qty": 1, "address_id": "a1"}).status_code == 403
    assert client.post("/v1/subscriptions",
                       json={"address_id": "a1", "qty": 1}).status_code == 403
    assert client.post("/v1/payments/upi-intent", json={"order_id": "x"},
                       headers=IDEM).status_code == 403
    assert client.post("/v1/orders/x/cod-confirm").status_code == 403
    assert _count(c, "orders") == 0
    assert _count(c, "returns") == 0
    assert _count(c, "subscriptions") == 0


def test_active_user_write_still_green():
    c = _conn()
    client = _client(c, _user_dict("u1", "user"))
    r = client.post("/v1/addresses", json=_address_payload())
    assert r.status_code == 201, r.text
    assert _count(c, "addresses") == 1
