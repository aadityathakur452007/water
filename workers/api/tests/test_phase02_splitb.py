"""Phase 2 Split B (§2.2 dues intent + §2.3 refunds/maker-checker + §2.4 day-close
+ §2.5 idempotency): dues link → intent → signed webhook → cleared; unknown
refs still 404; overpay 422 + zero rows; partial-cancel refunds paid_sum;
maker-checker (claimer cannot close) + claim/complete audits; day-close reads
payments with triple cross-check; reschedule retry + sub double-tap collapse.
"""

import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(API_ROOT / "src"))
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

import datetime as _dt  # noqa: E402

from _rzp import signed_event, stub_orders_api, use_dummy_keys  # noqa: E402
from app.db import get_connection, init_schema  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402


@pytest.fixture(autouse=True)
def _rzp(monkeypatch):
    use_dummy_keys(monkeypatch)
    stub_orders_api(monkeypatch)

MIGS = ["002_auth.sql", "003_addresses.sql", "004_orders.sql", "005_payments.sql", "007_ops.sql"]


def _conn():
    c = get_connection(":memory:")
    init_schema(c)
    base = API_ROOT / "src" / "app" / "db" / "migrations"
    for name in MIGS:
        c.executescript((base / name).read_text())
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    c.execute(
        "INSERT INTO users(id, phone, role, created_at) VALUES "
        "('admin1', '+911111111111', 'admin', ?), ('u1', '+912222222222', 'user', ?)",
        (now, now),
    )
    c.execute(
        "INSERT INTO addresses(id, user_id, type, lat, lng, pincode, created_at)"
        " VALUES ('a1', 'u1', 'home', 28.6, 77.2, '110001', ?)", (now,))
    c.commit()
    return c


def _w(c):
    return c if isinstance(c, AsyncSqliteConn) else AsyncSqliteConn(c)


def _order(c, oid="o1", mode="cod", total=5600, state="placed", status="unpaid"):
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
        " total, payment_mode, payment_status, state, window_start, idempotency_key, created_at)"
        " VALUES (?, 'u1', 'a1', '[]', 2, 1, 5600, 0, ?, ?, ?, ?, '2026-10-01T08:00Z', ?, ?)",
        (oid, total, mode, status, state, f"k-{oid}", now))
    c.commit()


def _svc(c, provider=None):
    from app.adapters.upi import RealUpiProvider
    from app.repositories.ledger_repo import LedgerRepo
    from app.repositories.order_repo import OrderRepo
    from app.repositories.payment_repo import PaymentRepo
    from app.services.payment_service import PaymentService

    return PaymentService(PaymentRepo(_w(c)), OrderRepo(_w(c)), LedgerRepo(_w(c)),
                          provider or RealUpiProvider())


def _count(c, table):
    return c.execute(f"SELECT COUNT(*) c FROM {table}").fetchone()["c"]


# -- §2.2 dues intent ------------------------------------------------------------

async def test_dues_link_intent_webhook_clears():
    c = _conn()
    _order(c)
    s = _svc(c)
    await s.cod_confirm("u1", "o1")
    assert (await s.get_dues("u1"))["dues"] == 5600
    out = await s.dues_intent("u1", "dk1")
    assert out["link"].startswith("upi://pay?") and out["payment"]["status"] == "link_sent"
    again = await s.dues_intent("u1", "dk1")  # same key replays the row
    assert again["payment"]["id"] == out["payment"]["id"]
    raw, sig = signed_event(out["provider_ref"], 5600, order_id=None)
    res = await s.webhook_ingest(raw, sig)
    assert res["ok"] and res["payment"]["status"] == "paid"
    assert (await s.get_dues("u1"))["dues"] == 0


async def test_dues_intent_no_dues_422():
    from app.core.errors import ValidationError

    with pytest.raises(ValidationError):
        await _svc(_conn()).dues_intent("u1", "dk9")


async def test_unknown_ref_webhook_404():
    from app.core.errors import NotFoundError

    c = _conn()
    raw, sig = signed_event("order_NOPE", 100, order_id="o1")
    with pytest.raises(NotFoundError):
        await _svc(c).webhook_ingest(raw, sig)


# -- §2.3 overpay / partial refunds / maker-checker --------------------------------

async def test_overpay_422_zero_rows():
    from app.repositories.payment_repo import OverpayError

    c = _conn()
    _order(c)
    s = _svc(c)
    with pytest.raises(OverpayError) as e:
        await s.mark_cash("o1", 5700, "vendor-1")
    assert e.value.code == "OVERPAY" and e.value.status_code == 422
    assert e.value.details["remaining"] == 5600
    assert _count(c, "payments") == 0
    assert c.execute("SELECT payment_status FROM orders WHERE id = 'o1'").fetchone()["payment_status"] == "unpaid"


async def test_partial_cancel_refunds_paid_sum():
    from app.repositories.order_repo import OrderRepo
    from app.repositories.ledger_repo import LedgerRepo

    c = _conn()
    _order(c)
    s = _svc(c)
    await s.mark_cash("o1", 2000, "vendor-1")  # partial: 2000 of 5600
    out = await OrderRepo(_w(c)).cancel_settle("o1", {"id": "u1", "role": "user"})
    assert out["refund"]["amount"] == 2000  # collected, never the full bill


async def test_maker_checker_and_refund_audits():
    from app.repositories.order_repo import OrderRepo
    from app.repositories.payment_repo import RefundClaimError

    c = _conn()
    _order(c)
    s = _svc(c)
    await s.mark_cash("o1", 5600, "vendor-1")
    rid = (await OrderRepo(_w(c)).cancel_settle("o1", {"id": "u1", "role": "user"}))["refund"]["id"]
    await s.claim_refund("admin-1", rid)
    with pytest.raises(RefundClaimError):  # claimer cannot close their own claim
        await s.complete_refund("admin-1", rid, "done")
    done = await s.complete_refund("admin-2", rid, "done")
    assert done["status"] == "done"
    rows = c.execute("SELECT action FROM audit_log WHERE entity_id = ?", (rid,)).fetchall()
    assert {r["action"] for r in rows} >= {"refund.claim", "refund.done"}


# -- §2.4 day-close -----------------------------------------------------------------

def test_day_close_payments_truth_with_triple_crosscheck():
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api import auth_deps
    from app.api.deps import get_db_conn
    from app.api.v1.admin import router as admin_router
    from app.core.errors import register_exception_handlers

    c = _conn()
    day = _dt.datetime.now(_dt.timezone.utc).date().isoformat()
    c.execute("INSERT INTO routes(id, date, vendor_id, zone, status) VALUES ('r1', ?, 'v1', 'z1', 'open')", (day,))
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, status, triple)"
        " VALUES ('s1', 'r1', NULL, 'u1', 0, 'done', '{\"cash\": 99999, \"upi\": 0}')")
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    c.execute(
        "INSERT INTO payments(id, order_id, user_id, amount, method, provider_ref,"
        " status, created_at, verified_at) VALUES ('p1', 'o9', 'u1', 1000, 'cod', 'cash:o9:x',"
        " 'paid', ?, ?)", (now, now))
    c.commit()
    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(admin_router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: _w(c)
    app.dependency_overrides[auth_deps.get_current_user] = lambda: {
        "id": "admin1", "role": "admin", "phone": "+911111111111",
        "suspended": False, "session_id": "s", "family_id": "f", "device_fp": "d",
    }
    r = TestClient(app).post("/v1/admin/reconciliation/close", json={"date": day})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["payments_cash"] == 1000 and body["collected_cash"] == 99999
    assert body["cash_mismatch"] is True and body["upi_mismatch"] is False


# -- §2.5 idempotency ----------------------------------------------------------------

async def test_reschedule_retry_same_key_single_apply():
    from app.repositories.order_repo import OrderRepo
    from app.repositories.ledger_repo import LedgerRepo
    from app.services import pricing
    from app.services.order_service import OrderService

    c = _conn()
    _order(c)
    svc = OrderService(OrderRepo(_w(c)), LedgerRepo(_w(c)), pricing, {})
    w1 = "2026-10-01T09:00:00+00:00"
    first = await svc.reschedule("u1", "o1", w1, "rk1")
    second = await svc.reschedule("u1", "o1", w1, "rk1")
    assert first["window_start"] == second["window_start"] == w1
    n = c.execute("SELECT COUNT(*) c FROM order_events WHERE order_id = 'o1'").fetchone()["c"]
    assert n == 1
    from app.services.order_service import PayloadMismatchError

    with pytest.raises(PayloadMismatchError):
        await svc.reschedule("u1", "o1", "2026-10-01T10:00:00+00:00", "rk1")


async def test_double_tap_subscription_single_row():
    from app.services.subscription_service import SubscriptionService

    c = _conn()
    svc = SubscriptionService(_w(c))
    payload = {"address_id": "a1", "qty": 1}
    first = await svc.create("u1", payload, "sk1")
    second = await svc.create("u1", payload, "sk1")
    assert first["id"] == second["id"]
    assert _count(c, "subscriptions") == 1
