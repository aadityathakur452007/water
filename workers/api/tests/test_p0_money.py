"""P0 money regressions: FK-on dues, one-provider-call replay, canceled-order
capture, honest cancel accounting, real monthly prepaid billing, cron tick."""
import hashlib
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
from app.adapters.upi import RealUpiProvider  # noqa: E402
from app.core.errors import ConflictError  # noqa: E402
from app.db import get_connection  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.jobs.scheduler import cron_tick, run_due_subscriptions  # noqa: E402
from app.repositories.ledger_repo import LedgerRepo  # noqa: E402
from app.repositories.order_repo import OrderRepo  # noqa: E402
from app.repositories.payment_repo import PaymentRepo  # noqa: E402
from app.services import pricing  # noqa: E402
from app.services.order_service import OrderService  # noqa: E402
from app.services.payment_service import PaymentService  # noqa: E402
from app.services.subscription_service import SubscriptionService  # noqa: E402

MIGS = [
    "002_auth.sql", "003_addresses.sql", "004_orders.sql", "005_payments.sql",
    "006_aftermath.sql", "007_ops.sql", "010_config_audit.sql",
    "012_monthly.sql", "015_pod_otp.sql", "019_rate_counters.sql",
    "021_return_upi.sql", "022_vendor_leaves_and_sub_cancel.sql",
    "027_pod_otp_lifecycle.sql", "028_p0_money_monthly.sql",
    "029_p0_correctness.sql",
]
WINDOW = "2026-09-01T08:00:00+00:00"
DAY = "2026-09-29"


@pytest.fixture()
def rzp(monkeypatch):
    use_dummy_keys(monkeypatch)
    return stub_orders_api(monkeypatch)


def _conn():
    raw = get_connection(":memory:")
    raw.execute("PRAGMA foreign_keys=ON")
    base = API_ROOT / "src" / "app" / "db" / "migrations"
    for name in MIGS:
        raw.executescript((base / name).read_text())
    now = datetime.now(timezone.utc).isoformat()
    raw.execute("INSERT INTO users(id, phone, role, created_at)"
                " VALUES ('u1', '+919000000001', 'user', ?)", (now,))
    raw.execute("INSERT INTO addresses(id, user_id) VALUES ('a1', 'u1')")
    raw.commit()
    assert raw.execute("PRAGMA foreign_keys").fetchone()[0] == 1
    return raw


def _rates() -> dict:
    from app.api.deps import get_settings

    s = get_settings()
    return {"refill": s.rate_refill_paise, "container": s.rate_container_paise,
            "deposit": s.deposit_per_jar_paise}


def _payload(mode="upi") -> dict:
    items = [{"sku": "refill", "qty": 1}]
    q = pricing.compute_quote(items, 0, _rates(), address_id="a1",
                              window_start=WINDOW, rate_version=pricing.RATE_VERSION)
    return {
        "items": items, "e": 0, "address_id": "a1", "window_start": WINDOW,
        "quote_hash": q["quote_hash"], "quote_total": q["total"],
        "quote_rate_version": q["rate_version"],
        "quote_expires_at": (datetime.now(timezone.utc) + timedelta(minutes=15)).isoformat(),
        "payment_mode": mode,
    }


def _order(raw, mode="upi", key="k1"):
    return OrderService(OrderRepo(AsyncSqliteConn(raw)), LedgerRepo(AsyncSqliteConn(raw)),
                        pricing, _rates()).create("u1", _payload(mode), key)


def _osvc(raw):
    conn = AsyncSqliteConn(raw)
    return OrderService(OrderRepo(conn), LedgerRepo(conn), pricing, _rates())


def _svc(raw):
    conn = AsyncSqliteConn(raw)
    return PaymentService(PaymentRepo(conn), OrderRepo(conn), LedgerRepo(conn),
                          RealUpiProvider())


async def test_dues_intent_fk_on_has_no_synthetic_order(rzp):
    raw = _conn()
    s = _svc(raw)
    o = await _order(raw, mode="cod")
    await s.cod_confirm("u1", o["id"])
    assert (await s.get_dues("u1"))["dues"] == o["total"]

    out = await s.dues_intent("u1", "dk1")  # FK-on: must not insert dues:<user>
    assert out["provider_ref"] and out["link"].startswith("upi://pay?")
    assert raw.execute("SELECT COUNT(*) c FROM payments").fetchone()["c"] == 0
    assert raw.execute("SELECT status FROM dues_intents").fetchone()["status"] == "link_sent"

    body, sig = signed_event(out["provider_ref"], o["total"], order_id=None)
    res = await s.webhook_ingest(body, sig)
    assert res["ok"] and res["dues_intent"]["status"] == "paid"
    assert (await s.get_dues("u1"))["dues"] == 0
    # The order that posted those dues is settled too, so the door cannot
    # collect the same rupees a second time.
    row = raw.execute("SELECT payment_status FROM orders WHERE id=?", (o["id"],)).fetchone()
    assert row["payment_status"] == "paid_upi"
    paid = raw.execute("SELECT COUNT(*) c, COALESCE(SUM(amount),0) a FROM payments"
                       " WHERE order_id=?", (o["id"],)).fetchone()
    assert paid["c"] == 1 and paid["a"] == o["total"]


async def test_same_key_and_new_key_replay_never_mint_two_provider_orders(rzp):
    raw = _conn()
    s = _svc(raw)
    o = await _order(raw, mode="upi")

    first = await s.intent("u1", o["id"], "same-key")
    second = await s.intent("u1", o["id"], "same-key")
    third = await s.intent("u1", o["id"], "different-key")
    assert rzp["n"] == 1  # exactly one Razorpay Orders call
    assert first["payment"]["id"] == second["payment"]["id"] == third["payment"]["id"]
    assert raw.execute("SELECT COUNT(*) c FROM payments").fetchone()["c"] == 1


async def test_canceled_order_intent_blocked_and_capture_refunds(rzp):
    raw = _conn()
    s = _svc(raw)
    o = await _order(raw, mode="upi")
    intent = await s.intent("u1", o["id"], "cap-1")
    await _osvc(raw).cancel("u1", o["id"], "changed mind", "c1")

    with pytest.raises(ConflictError):
        await s.intent("u1", o["id"], "cap-2")  # canceled orders are unpayable

    body, sig = signed_event(intent["provider_ref"], o["total"], order_id=o["id"])
    res = await s.webhook_ingest(body, sig)
    assert res["payment"]["status"] == "paid"
    assert res["payment"].get("_refund_queued") is True

    order = raw.execute("SELECT state, payment_status FROM orders WHERE id=?",
                        (o["id"],)).fetchone()
    assert order["state"] == "cancelled" and order["payment_status"] == "unpaid"
    refund = raw.execute("SELECT * FROM refunds WHERE order_id=?", (o["id"],)).fetchone()
    assert refund["amount"] == o["total"] and refund["status"] == "pending"


async def test_cancel_with_zero_payments_has_no_refund_and_keeps_dues():
    raw = _conn()
    s = _svc(raw)
    o = await _order(raw, mode="cod")
    await s.cod_confirm("u1", o["id"])

    outcome = await _osvc(raw).cancel("u1", o["id"], "changed mind", "c2")
    assert outcome["refund"] is None
    assert raw.execute("SELECT COUNT(*) c FROM refunds").fetchone()["c"] == 0
    assert (await LedgerRepo(AsyncSqliteConn(raw)).get("u1"))["dues"] == o["total"]


async def test_monthly_prepaid_charge_credit_consume_and_refund(rzp):
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    s = _svc(raw)
    subs = SubscriptionService(conn)
    sub = await subs.create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily", "next_run": DAY,
        "payment_method": "upi", "billing_mode": "monthly_prepaid",
    })
    assert sub["billing_status"] == "pending_payment"

    topup = await s.subscription_intent("u1", sub["id"], "topup-1")
    amount = int(topup["charge"]["amount"])
    assert amount == int(sub["due_today_paise"]) * 30
    body, sig = signed_event(topup["provider_ref"], amount,
                             order_id=f"sub:{sub['id']}")
    paid = await s.webhook_ingest(body, sig)
    assert paid["ok"] and paid["charge"]["credited_paise"] == amount
    row = raw.execute("SELECT billing_status, credit_balance_paise FROM subscriptions"
                      " WHERE id=?", (sub["id"],)).fetchone()
    assert row["billing_status"] == "active" and row["credit_balance_paise"] == amount

    run1 = await run_due_subscriptions(conn, DAY)
    assert len(run1["created"]) == 1 and not run1["failed"]
    order = raw.execute("SELECT * FROM orders WHERE id=?", (run1["created"][0]["order_id"],)).fetchone()
    assert order["payment_status"] == "paid_upi"
    after = raw.execute("SELECT credit_balance_paise FROM subscriptions WHERE id=?",
                        (sub["id"],)).fetchone()["credit_balance_paise"]
    assert after == amount - 2800

    # Replayed webhook and same-day replay never double-credit/debit.
    await s.webhook_ingest(body, sig)
    assert raw.execute("SELECT credit_balance_paise FROM subscriptions WHERE id=?",
                       (sub["id"],)).fetchone()["credit_balance_paise"] == after
    run2 = await run_due_subscriptions(conn, DAY)
    assert run2["created"] == []

    cancel = await subs.cancel("u1", sub["id"], "stop", "u1@upi")
    assert cancel["unused_water_refund_paise"] == after
    refund = raw.execute("SELECT * FROM refunds WHERE subscription_id=?",
                         (sub["id"],)).fetchone()
    assert refund["amount"] == after and refund["order_id"] is None
    assert refund["upi_id"] == "u1@upi"
    assert raw.execute("SELECT refund_upi FROM subscriptions WHERE id=?",
                       (sub["id"],)).fetchone()["refund_upi"] == "u1@upi"


async def test_prepaid_low_balance_pauses_until_top_up(rzp):
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    s = _svc(raw)
    subs = SubscriptionService(conn)
    sub = await subs.create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily", "next_run": DAY,
        "payment_method": "upi", "billing_mode": "monthly_prepaid",
    })
    now = datetime.now(timezone.utc).isoformat()
    raw.execute(
        "INSERT INTO subscription_credit_entries(id, subscription_id, user_id, delta, kind,"
        " ref, created_at) VALUES ('small', ?, 'u1', 2799, 'adjust', 'seed', ?)",
        (sub["id"], now))
    raw.execute("UPDATE subscriptions SET credit_balance_paise=2799, billing_status='active'"
                " WHERE id=?", (sub["id"],))
    raw.commit()

    blocked = await run_due_subscriptions(conn, DAY)
    assert blocked["created"] == []
    assert blocked["low_balance"][0]["reason"] == "low_balance"
    assert raw.execute("SELECT COUNT(*) c FROM orders").fetchone()["c"] == 0

    topup = await s.subscription_intent("u1", sub["id"], "topup-2")
    body, sig = signed_event(topup["provider_ref"], int(topup["charge"]["amount"]),
                             order_id=f"sub:{sub['id']}")
    await s.webhook_ingest(body, sig)
    unblocked = await run_due_subscriptions(conn, DAY)
    assert len(unblocked["created"]) == 1


async def test_cron_tick_creates_one_order_then_noop(rzp):
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    await SubscriptionService(conn).create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily", "next_run": DAY,
        "payment_method": "cod", "billing_mode": "per_delivery",
    })
    first = await cron_tick(conn, DAY)
    assert len(first["due"]["created"]) == 1
    second = await cron_tick(conn, DAY)
    assert second["due"]["created"] == []
    assert raw.execute("SELECT COUNT(*) c FROM orders").fetchone()["c"] == 1


async def _walk_to_delivered(raw, order_id: str) -> None:
    repo = OrderRepo(AsyncSqliteConn(raw))
    for state in ("accepted", "picked", "packed", "assigned", "dispatched", "delivered"):
        await repo.transition(order_id, state, {"id": "sys", "role": "system"}, "test walk")


async def test_postpaid_delivery_posts_real_dues_once(rzp):
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    subs = SubscriptionService(conn)
    sub = await subs.create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily", "next_run": DAY,
        "payment_method": "upi", "billing_mode": "monthly_postpaid",
    })
    assert sub["billing_status"] == "active"
    run = await run_due_subscriptions(conn, DAY)
    assert len(run["created"]) == 1 and not run["failed"]
    order_id = run["created"][0]["order_id"]
    total = int(raw.execute("SELECT total FROM orders WHERE id=?", (order_id,)).fetchone()["total"])
    led = LedgerRepo(AsyncSqliteConn(raw))
    assert (await led.get("u1"))["dues"] == 0  # nothing owed before delivery

    await _walk_to_delivered(raw, order_id)
    assert (await led.get("u1"))["dues"] == total
    # A retried close (or a second caller) cannot double-post.
    repo = OrderRepo(AsyncSqliteConn(raw))
    order_row = raw.execute("SELECT * FROM orders WHERE id=?", (order_id,)).fetchone()
    await repo._post_postpaid_dues(dict(order_row))
    assert (await led.get("u1"))["dues"] == total

    # Month-end dues payment clears it through the real intent path and also
    # closes the delivered order (no door-side double collection).
    out = await _svc(raw).dues_intent("u1", "postpaid-pay")
    assert int(out["payment"]["amount"]) == total
    assert out["link"]
    body, sig = signed_event(out["provider_ref"], total, order_id=None)
    res = await _svc(raw).webhook_ingest(body, sig)
    assert res["dues_intent"]["status"] == "paid"
    assert (await led.get("u1"))["dues"] == 0
    row = raw.execute("SELECT payment_status FROM orders WHERE id=?", (order_id,)).fetchone()
    assert row["payment_status"] == "paid_upi"


async def test_postpaid_cancel_before_delivery_owes_nothing(rzp):
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    await SubscriptionService(conn).create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily", "next_run": DAY,
        "payment_method": "upi", "billing_mode": "monthly_postpaid",
    })
    run = await run_due_subscriptions(conn, DAY)
    order_id = run["created"][0]["order_id"]
    await _osvc(raw).cancel("u1", order_id, "test cancel", "cancel-1")
    assert (await LedgerRepo(AsyncSqliteConn(raw)).get("u1"))["dues"] == 0


def _session(raw, uid: str, role: str, token: str) -> None:
    now = datetime.now(timezone.utc).isoformat()
    future = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    raw.execute(
        "INSERT INTO sessions(id, user_id, token_hash, refresh_hash, role, device_fp,"
        " family_id, expires_at, created_at) VALUES (?, ?, ?, ?, ?, 'd', 'f', ?, ?)",
        (f"ses-{uid}", uid, hashlib.sha256(token.encode()).hexdigest(),
         hashlib.sha256(f"r:{token}".encode()).hexdigest(), role, future, now))
    raw.commit()


def _client(raw):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.deps import get_db_conn
    from app.api.v1.vendor import router
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    conn = raw if isinstance(raw, AsyncSqliteConn) else AsyncSqliteConn(raw)
    app.dependency_overrides[get_db_conn] = lambda: conn
    return TestClient(app)


async def test_real_pod_route_posts_postpaid_dues_once(rzp):
    """The HTTP door a rider actually calls posts dues on delivery, once."""
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    now = datetime.now(timezone.utc).isoformat()
    raw.execute("INSERT INTO users(id, phone, role, created_at)"
                " VALUES ('v1', '+919000000002', 'vendor', ?)", (now,))
    raw.commit()

    await SubscriptionService(conn).create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily", "next_run": DAY,
        "payment_method": "upi", "billing_mode": "monthly_postpaid",
    })
    run = await run_due_subscriptions(conn, DAY)
    order_id = run["created"][0]["order_id"]
    total = int(raw.execute("SELECT total FROM orders WHERE id=?", (order_id,)).fetchone()["total"])
    for state in ("accepted", "picked", "packed", "assigned", "dispatched"):
        await OrderRepo(conn).transition(order_id, state, {"id": "sys", "role": "system"},
                                         "pod route test")
    raw.execute("INSERT INTO routes(id, date, vendor_id, zone, status)"
                " VALUES ('r1', ?, 'v1', '', 'open')", (DAY,))
    raw.execute("INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
                " empties_exp, version, status, pod_otp, pod_otp_expires_at)"
                " VALUES ('s1', 'r1', ?, 'u1', 1, 1, 0, 1, 'pending', '482910', ?)",
                (order_id, (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()))
    raw.commit()
    _session(raw, "v1", "vendor", "tok-vendor")

    client = _client(raw)
    h = {"Authorization": "Bearer tok-vendor"}
    ok = client.post("/v1/vendor/stops/s1/pod",
                     json={"delivery_otp": "482910", "seal_ok": True}, headers=h)
    assert ok.status_code == 200, ok.text
    assert ok.json()["status"] == "done"
    led = LedgerRepo(conn)
    assert (await led.get("u1"))["dues"] == total

    replay = client.post("/v1/vendor/stops/s1/pod",
                         json={"delivery_otp": "000000"}, headers=h)
    assert replay.status_code == 200 and replay.json().get("replay") is True
    assert (await led.get("u1"))["dues"] == total
