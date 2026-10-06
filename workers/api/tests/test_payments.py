"""D1 payments slice tests: adapter + repo + service + router (contract §4.6/§10/§11).

Layers (python card: unit -> service -> API):
- adapter unit: live Razorpay protocol — signed payment.captured/failed
  events, bad-HMAC/stale rejection (see test_upi_real.py for the full matrix).
- service/repo: :memory: sqlite + 004_orders.sql + 005_payments.sql applied,
  RealUpiProvider with dummy keys + stubbed Orders API (no network, no secrets).
- router: TestClient with get_db + get_current_user overridden (integrator mounts
  the bare router under /v1; main.py wiring is NOT touched here).
"""
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

from _rzp import signed_event, stub_orders_api, use_dummy_keys  # noqa: E402
from app.adapters.upi import RealUpiProvider, UnauthError  # noqa: E402
from app.core.errors import AppError  # noqa: E402
from app.db import get_connection  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.repositories.ledger_repo import LedgerRepo  # noqa: E402
from app.repositories.order_repo import OrderRepo  # noqa: E402
from app.repositories.payment_repo import (  # noqa: E402
    AmountMismatchError,
    PaymentRepo,
    RefundClaimError,
)
from app.services import pricing  # noqa: E402
from app.services.order_service import OrderService  # noqa: E402
from app.services.payment_service import PaymentService  # noqa: E402

MIG4 = (API_ROOT / "src" / "app" / "db" / "migrations" / "004_orders.sql").read_text()
MIG5 = (API_ROOT / "src" / "app" / "db" / "migrations" / "005_payments.sql").read_text()
WINDOW = "2026-10-01T08:00:00+00:00"


def _rates() -> dict:
    from app.api.deps import get_settings

    s = get_settings()
    return {"refill": s.rate_refill_paise, "container": s.rate_container_paise,
            "deposit": s.deposit_per_jar_paise}


def _conn():
    c = get_connection(":memory:")
    c.executescript(MIG4)
    c.executescript(MIG5)
    return c


@pytest.fixture(autouse=True)
def _rzp(monkeypatch):
    """Every test runs against the live Razorpay protocol: dummy keys plus a
    stubbed Orders API (unique order_TESTn refs, no network)."""
    use_dummy_keys(monkeypatch)
    stub_orders_api(monkeypatch)


def _svc(c, provider=None) -> PaymentService:
    provider = provider if provider is not None else RealUpiProvider()
    ac = AsyncSqliteConn(c)
    return PaymentService(PaymentRepo(ac), OrderRepo(ac), LedgerRepo(ac), provider)


def _osvc(c) -> OrderService:
    ac = AsyncSqliteConn(c)
    return OrderService(OrderRepo(ac), LedgerRepo(ac), pricing, _rates())


def _payload(items=None, e=1, mode="upi", **over) -> dict:
    items = items if items is not None else [{"sku": "refill", "qty": 2}]
    q = pricing.compute_quote(items, e, _rates(), address_id="a1", window_start=WINDOW,
                              rate_version=pricing.RATE_VERSION)
    base = {
        "items": items, "e": e, "address_id": "a1", "window_start": WINDOW,
        "quote_hash": q["quote_hash"], "quote_total": q["total"],
        "quote_rate_version": q["rate_version"],
        "quote_expires_at": (datetime.now(timezone.utc) + timedelta(minutes=15)).isoformat(),
        "payment_mode": mode,
    }
    base.update(over)
    return base


async def _order(c, user="u1", mode="upi", key="k1") -> dict:
    return await _osvc(c).create(user, _payload(mode=mode), key)


# -- captured event → paid_upi + dues zeroed ---------------------------------

async def test_captured_paid_upi_dues_zeroed():
    c = _conn()
    s = _svc(c)
    o = await _order(c, mode="upi")
    out = await s.intent("u1", o["id"], "idem-1")
    assert out["payment"]["status"] == "link_sent" and out["link"].startswith("upi://pay?")
    raw, sig = signed_event(out["provider_ref"], o["total"], order_id=o["id"])
    res = await s.webhook_ingest(raw, sig)
    assert res["ok"] and res["payment"]["status"] == "paid"
    row = c.execute("SELECT payment_status FROM orders WHERE id=?", (o["id"],)).fetchone()
    assert row["payment_status"] == "paid_upi"
    assert (await s.get_dues("u1"))["dues"] == 0
    inv = await s.get_invoice("u1", o["id"])
    assert inv["amount_due"] == 0 and inv["total_due"] == 0


# -- replay same webhook → single credit ------------------------------------

async def test_webhook_replay_single_credit():
    c = _conn()
    s = _svc(c)
    o = await _order(c, mode="upi")
    out = await s.intent("u1", o["id"], "idem-1")
    raw, sig = signed_event(out["provider_ref"], o["total"], order_id=o["id"])
    r1 = await s.webhook_ingest(raw, sig)
    r2 = await s.webhook_ingest(raw, sig)
    assert r1["ok"] and r2.get("duplicate") is True
    assert c.execute("SELECT COUNT(*) c FROM payments").fetchone()["c"] == 1
    assert await PaymentRepo(AsyncSqliteConn(c)).paid_sum_for_order(o["id"]) == o["total"]
    assert (await s.get_dues("u1"))["dues"] == 0


# -- forged signature / wrong amount → rejected ------------------------------

async def test_webhook_bad_signature_rejected():
    c = _conn()
    s = _svc(c)
    o = await _order(c, mode="upi")
    out = await s.intent("u1", o["id"], "idem-1")
    raw, _ = signed_event(out["provider_ref"], o["total"], order_id=o["id"])
    with pytest.raises(UnauthError) as e:
        await s.webhook_ingest(raw, "forged")
    assert e.value.code == "UNAUTH" and e.value.status_code == 401


async def test_webhook_wrong_amount_rejected():
    c = _conn()
    s = _svc(c)
    o = await _order(c, mode="upi")
    out = await s.intent("u1", o["id"], "idem-1")
    raw, sig = signed_event(out["provider_ref"], o["total"] - 100, order_id=o["id"])
    with pytest.raises(AmountMismatchError) as e:
        await s.webhook_ingest(raw, sig)
    assert e.value.code == "AMOUNT_MISMATCH" and e.value.status_code == 422


# -- double-claim refund → one claimant wins ---------------------------------

async def test_double_claim_refund_one_winner():
    c = _conn()
    o = await _order(c, mode="upi")
    c.execute("UPDATE orders SET payment_status='paid_upi' WHERE id=?", (o["id"],))
    c.commit()
    outcome = await _osvc(c).cancel("u1", o["id"], "changed mind", "c1")
    rid = outcome["refund"]["id"]
    s = _svc(c)
    first = await s.claim_refund("admin-1", rid)
    assert first["status"] == "claimed" and first["claimed_by"] == "admin-1"
    with pytest.raises(RefundClaimError) as e:
        await s.claim_refund("admin-2", rid)
    assert e.value.code == "REFUND_CLAIM_CONFLICT" and e.value.status_code == 409
    done = await s.complete_refund("admin-2", rid, "done")
    assert done["status"] == "done"
    with pytest.raises(AppError):  # closed refunds never reopen
        await s.complete_refund("admin-2", rid, "done")


# -- COD confirm → dues until cash posted ------------------------------------

async def test_cod_confirm_dues_until_cash_posted():
    c = _conn()
    s = _svc(c)
    o = await _order(c, mode="cod", key="cod-1")
    bill = await s.cod_confirm("u1", o["id"])
    assert bill["payment_status"] == "unpaid"
    assert bill["dues"] == o["total"]  # dues visible until cash arrives
    inv = await s.get_invoice("u1", o["id"])
    assert inv["amount_due"] == o["total"]
    res = await s.mark_cash(o["id"], o["total"], "vendor-1")
    assert res["order"]["payment_status"] == "paid_cash"
    assert (await s.get_dues("u1"))["dues"] == 0
    assert (await s.get_invoice("u1", o["id"]))["amount_due"] == 0


async def test_cod_partial_cash_carried():
    c = _conn()
    s = _svc(c)
    o = await _order(c, mode="cod", key="cod-1")
    await s.cod_confirm("u1", o["id"])
    half = o["total"] // 2
    res = await s.mark_cash(o["id"], half, "vendor-1")
    assert res["order"]["payment_status"] == "partial_dues"
    assert (await s.get_dues("u1"))["dues"] == o["total"] - half  # partials carried, never zeroed


# -- adapter unit: failed event declines without settling -------------------

async def test_failed_event_declined_no_settlement():
    c = _conn()
    s = _svc(c)
    o = await _order(c, mode="upi")
    out = await s.intent("u1", o["id"], "idem-1")
    raw, sig = signed_event(out["provider_ref"], o["total"], order_id=o["id"],
                            event="payment.failed", status="failed")
    res = await s.webhook_ingest(raw, sig)
    assert res["ok"] and res["declined"] is True
    row = c.execute("SELECT payment_status FROM orders WHERE id=?", (o["id"],)).fetchone()
    assert row["payment_status"] == "link_sent"


# -- router ------------------------------------------------------------------

def _client(c, user="u1", role="user"):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.auth_deps import get_current_user
    from app.api.deps import get_db_conn
    from app.api.v1.payments import router
    from app.core.errors import register_exception_handlers
    from app.db_d1 import AsyncSqliteConn

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: AsyncSqliteConn(c)
    app.dependency_overrides[get_current_user] = lambda: {
        "id": user, "role": role, "phone": "+919000000000", "suspended": False,
        "session_id": "s", "family_id": "f", "device_fp": "d",
    }
    return TestClient(app)


async def test_router_intent_dues_invoice_cod():
    c = _conn()
    await _order(c, mode="upi", key="rk1")
    o2 = await _order(c, user="u1", mode="cod", key="rk2")
    client = _client(c)
    assert client.post("/v1/payments/upi-intent", json={}).status_code in (400, 422)
    r = client.get("/v1/billing/dues")
    assert r.status_code == 200 and "dues" in r.json()
    cod = client.post(f"/v1/orders/{o2['id']}/cod-confirm")
    assert cod.status_code == 200 and cod.json()["dues"] == o2["total"]
    inv = client.get(f"/v1/invoices/{o2['id']}")
    assert inv.status_code == 200 and inv.json()["total"] == o2["total"]


async def test_router_webhook_no_auth_and_admin_claim():
    c = _conn()
    s = _svc(c)
    o = await _order(c, mode="upi", key="wk1")
    out = await s.intent("u1", o["id"], "wk-idem")
    client = _client(c)  # webhook needs no session
    raw, sig = signed_event(out["provider_ref"], o["total"], order_id=o["id"])
    r = client.post("/v1/webhooks/upi", content=raw,
                    headers={"X-Razorpay-Signature": sig})
    assert r.status_code == 200 and r.json()["ok"] is True
    r2 = client.post("/v1/webhooks/upi", content=raw,
                     headers={"X-Razorpay-Signature": sig})  # duplicate → 200 no-op
    assert r2.status_code == 200 and r2.json().get("duplicate") is True
    r3 = client.post("/v1/webhooks/upi", content=raw)  # unsigned → 401
    assert r3.status_code == 401
    # refund claim needs admin: user role → 403, admin → 200
    c.execute("UPDATE orders SET payment_status='paid_upi' WHERE id=?", (o["id"],))
    c.commit()
    rid = (await _osvc(c).cancel("u1", o["id"], "r", "wc1"))["refund"]["id"]
    assert _client(c, role="user").post(f"/v1/refunds/{rid}/claim").status_code == 403
    admin = _client(c, user="admin-1", role="admin")
    assert admin.post(f"/v1/refunds/{rid}/claim").status_code == 200
    assert admin.post(f"/v1/refunds/{rid}/claim").status_code == 409  # second claimant loses
    assert admin.post(f"/v1/refunds/{rid}/done").status_code == 409  # maker-checker: claimer cannot close
    admin2 = _client(c, user="admin-2", role="admin")
    assert admin2.post(f"/v1/refunds/{rid}/done").status_code == 200
