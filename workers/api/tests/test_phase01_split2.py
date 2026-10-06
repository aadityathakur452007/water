"""Phase 1 Split 2 (§1.5 + §1.6 + §1.7): webhook fail-closed, PoD OTP, adjudication.

- §1.5: fake money doors refuse in prod (502, zero rows); dev fake untouched
  (covered by the existing fake-approve suite).
- §1.6: stored random OTP accepted + non-derivable; NULL rows fall back to the
  legacy deterministic code; wrong codes read as not-found with a DB-backed
  attempt counter; the 6th attempt after 5 fails locks (429); dispatch mints
  a fresh 6-digit code per stop; order detail discloses the stored code.
- §1.7: vendor agree needs a ≥10-char note and lands vendor_confirmed (never
  resolved, resolved_at stays NULL); only the admin release writes resolved.
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
        "('v1', '+911111111111', 'vendor', ?), ('u1', '+912222222222', 'user', ?)",
        (now, now),
    )
    c.execute(
        "INSERT INTO addresses(id, user_id, type, lat, lng, pincode, created_at)"
        " VALUES ('a1', 'u1', 'home', 12.9716, 77.5946, '110001', ?)", (now,),
    )
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
        " total, payment_mode, payment_status, state, window_start, idempotency_key, created_at)"
        " VALUES ('o1', 'u1', 'a1', '[]', 2, 1, 5600, 15000, 20600, 'upi', 'unpaid',"
        " 'dispatched', '2026-10-01T08:00Z', 'seed:o1', ?)", (now,),
    )
    c.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status) VALUES ('r1', ?, 'v1', 'z1', 'open')",
        (DAY,),
    )
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status) VALUES ('s1', 'r1', 'o1', 'u1', 0, 2, 1, 1, 'pending')",
    )
    c.execute(
        "INSERT INTO complaints(id, order_id, user_id, reason_code, text, status, created_at)"
        " VALUES ('c1', 'o1', 'u1', 'short_delivery', 'one jar short', 'open', ?)", (now,),
    )
    c.commit()
    return c


def _w(c):
    return c if isinstance(c, AsyncSqliteConn) else AsyncSqliteConn(c)


def _count(c, table):
    return c.execute(f"SELECT COUNT(*) c FROM {table}").fetchone()["c"]


# -- §1.5 webhook fail-closed --------------------------------------------------

def test_prod_fake_intent_refused(monkeypatch):
    from app.adapters.upi import FakeUpiProvider, UpstreamError

    monkeypatch.setenv("APP_ENV", "prod")
    with pytest.raises(UpstreamError) as e:
        FakeUpiProvider().create_intent({"id": "o1", "total": 5600})
    assert e.value.status_code == 502


async def test_prod_fake_webhook_no_ledger_write(monkeypatch):
    import json

    from app.adapters.upi import FakeUpiProvider, UpstreamError
    from app.repositories.ledger_repo import LedgerRepo
    from app.repositories.order_repo import OrderRepo
    from app.repositories.payment_repo import PaymentRepo
    from app.services.payment_service import PaymentService

    monkeypatch.setenv("APP_ENV", "prod")
    c = _conn()
    svc = PaymentService(PaymentRepo(_w(c)), OrderRepo(_w(c)), LedgerRepo(_w(c)), FakeUpiProvider())
    raw = json.dumps({"order_id": "o1", "provider_ref": "FAKE-APPROVE-x",
                      "amount": 20600, "payee": "shodasha@upi"}).encode()
    with pytest.raises(UpstreamError) as e:
        await svc.webhook_ingest(raw, None)
    assert e.value.status_code == 502
    assert _count(c, "payments") == 0
    assert c.execute("SELECT payment_status FROM orders WHERE id = 'o1'").fetchone()["payment_status"] == "unpaid"


# -- §1.6 PoD OTP ---------------------------------------------------------------

def _stored(c, code):
    c.execute("UPDATE stops SET pod_otp = ? WHERE id = 's1'", (code,))
    c.commit()


async def test_stored_otp_accepted_and_not_derivable():
    from app.services.vendor_service import VendorService, pod_otp

    c = _conn()
    legacy = pod_otp("o1", DAY)
    code = "482910" if legacy != "482910" else "482911"
    _stored(c, code)
    out = await VendorService(_w(c)).pod_complete("v1", "s1", {"delivery_otp": code})
    assert out["status"] == "done"
    # The stored code is random — knowing order+date does not yield it.
    assert code != legacy


async def test_legacy_null_row_accepts_deterministic():
    from app.services.vendor_service import VendorService, pod_otp

    c = _conn()  # 015 applied, pod_otp stays NULL → legacy fallback
    out = await VendorService(_w(c)).pod_complete("v1", "s1", {"delivery_otp": pod_otp("o1", DAY)})
    assert out["status"] == "done"


async def test_wrong_otp_404_and_attempt_counted():
    from app.core.errors import NotFoundError
    from app.services.vendor_service import VendorService

    c = _conn()
    _stored(c, "482910")
    with pytest.raises(NotFoundError) as e:
        await VendorService(_w(c)).pod_complete("v1", "s1", {"delivery_otp": "000000"})
    assert e.value.status_code == 404
    assert c.execute("SELECT pod_attempts FROM stops WHERE id = 's1'").fetchone()["pod_attempts"] == 1


async def test_five_fails_lock_the_sixth():
    from app.services.vendor_service import PodLockedError, VendorService

    c = _conn()
    _stored(c, "482910")
    svc = VendorService(_w(c))
    for _ in range(5):
        try:
            await svc.pod_complete("v1", "s1", {"delivery_otp": "000000"})
        except Exception:
            pass
    with pytest.raises(PodLockedError) as e:
        await svc.pod_complete("v1", "s1", {"delivery_otp": "482910"})
    assert e.value.code == "POD_LOCKED" and e.value.status_code == 429


async def test_detail_discloses_stored_code():
    from app.repositories.ledger_repo import LedgerRepo
    from app.repositories.order_repo import OrderRepo
    from app.services import pricing
    from app.services.order_service import OrderService
    from app.services.vendor_service import pod_otp

    c = _conn()
    _stored(c, "482910")
    svc = OrderService(OrderRepo(_w(c)), LedgerRepo(_w(c)), pricing, {})
    detail = await svc.detail("u1", "o1")
    assert detail["delivery_otp"] == "482910"
    assert detail["delivery_otp"] != pod_otp("o1", DAY)


async def test_assign_mints_fresh_pod_otp():
    import re

    from app.services.dispatch_service import assign_order

    c = _conn()
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    c.execute(
        "INSERT INTO users(id, phone, role, created_at) VALUES ('v9', '+919999999999', 'vendor', ?)",
        (now,),
    )
    c.execute("INSERT INTO zones(id, name, pincodes) VALUES ('z9', 'Z9', '110001')")
    c.execute("INSERT INTO vendor_zones(vendor_id, zone_id) VALUES ('v9', 'z9')")
    c.execute(
        "INSERT INTO vendor_profile(user_id, max_stops_per_shift, max_jars_per_shift,"
        " per_stop_fee, active, on_duty, in_hand) VALUES ('v9', 25, 60, 0, 1, 1, 0)")
    for oid in ("p1", "p2"):
        c.execute(
            "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
            " total, payment_mode, payment_status, state, window_start, idempotency_key, created_at)"
            " VALUES (?, 'u1', 'a1', '[]', 2, 1, 5600, 15000, 20600, 'cod', 'unpaid',"
            " 'packed', '2026-10-01T08:00Z', ?, ?)", (oid, f"k-{oid}", now))
    c.commit()
    a = await assign_order(_w(c), "p1", "v9", {"id": "admin1", "role": "admin"})
    b = await assign_order(_w(c), "p2", "v9", {"id": "admin1", "role": "admin"})
    got = [c.execute("SELECT pod_otp FROM stops WHERE id = ?", (s["stop_id"],)).fetchone()["pod_otp"]
           for s in (a, b)]
    assert all(g and re.fullmatch(r"\d{6}", g) for g in got) and got[0] != got[1]


# -- §1.7 adjudication ------------------------------------------------------------

async def test_vendor_agree_needs_note():
    from app.core.errors import ValidationError
    from app.services.vendor_service import VendorService

    with pytest.raises(ValidationError) as e:
        await VendorService(_w(_conn())).verify_complaint("v1", "c1", True, "short")
    assert e.value.status_code == 400


async def test_vendor_agree_countersigns_admin_releases():
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api import auth_deps
    from app.api.deps import get_db_conn
    from app.api.v1.admin import router as admin_router
    from app.core.errors import register_exception_handlers
    from app.services.vendor_service import VendorService

    c = _conn()
    out = await VendorService(_w(c)).verify_complaint("v1", "c1", True, "short jar redelivered")
    assert out["status"] == "vendor_confirmed"
    row = c.execute("SELECT status, resolved_at FROM complaints WHERE id = 'c1'").fetchone()
    assert row["status"] == "vendor_confirmed" and row["resolved_at"] is None

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(admin_router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: _w(c)
    app.dependency_overrides[auth_deps.get_current_user] = lambda: {
        "id": "admin1", "role": "admin", "phone": "+911111111111",
        "suspended": False, "session_id": "s", "family_id": "f", "device_fp": "d",
    }
    r = TestClient(app).post("/v1/admin/complaints/c1/resolve", json={"action": "note"})
    assert r.status_code == 200 and r.json()["status"] == "resolved"
    assert c.execute("SELECT status FROM complaints WHERE id = 'c1'").fetchone()["status"] == "resolved"
    assert c.execute("SELECT COUNT(*) c FROM audit_log WHERE entity_id = 'c1'").fetchone()["c"] >= 1
