"""Phase 1A deterministic atomicity tests (spec §9.1).

Local SQLite serialises writers through ``WRITE_LOCK``, so races are
reproduced without timing: the loser has already done its reads when a
wrapped ``batch`` runs the winner to completion, then the loser's guarded
batch executes against the committed state. The deterministic test is the
release gate; the file-backed race is best-effort.
"""
import datetime as dt
import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

from _rzp import signed_event, stub_orders_api, use_dummy_keys  # noqa: E402
from app.adapters.upi import RealUpiProvider  # noqa: E402
from app.core.errors import ConflictError, RateLimitedError  # noqa: E402
from app.db import get_connection  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.repositories.ledger_repo import LedgerRepo  # noqa: E402
from app.repositories.order_repo import AlreadyCancelledError, OrderRepo  # noqa: E402
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
CONTAINER = [{"sku": "container", "qty": 1}]


@pytest.fixture()
def rzp(monkeypatch):
    use_dummy_keys(monkeypatch)
    return stub_orders_api(monkeypatch)


def _conn():
    raw = get_connection(":memory:")
    base = API_ROOT / "src" / "app" / "db" / "migrations"
    for name in MIGS:
        raw.executescript((base / name).read_text())
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    raw.execute(
        "INSERT INTO users(id, phone, role, created_at) VALUES"
        " ('u1', '+919000000001', 'user', ?), ('v1', '+919000000002', 'vendor', ?)",
        (now, now),
    )
    raw.execute("INSERT INTO addresses(id, user_id) VALUES ('a1', 'u1')")
    raw.commit()
    return raw


def _rates() -> dict:
    from app.api.deps import get_settings

    s = get_settings()
    return {"refill": s.rate_refill_paise, "container": s.rate_container_paise,
            "deposit": s.deposit_per_jar_paise}


def _payload(mode="upi", items=None) -> dict:
    items = items or [{"sku": "refill", "qty": 1}]
    q = pricing.compute_quote(items, 0, _rates(), address_id="a1",
                              window_start=WINDOW, rate_version=pricing.RATE_VERSION)
    return {
        "items": items, "e": 0, "address_id": "a1", "window_start": WINDOW,
        "quote_hash": q["quote_hash"], "quote_total": q["total"],
        "quote_rate_version": q["rate_version"],
        "quote_expires_at": (dt.datetime.now(dt.timezone.utc)
                             + dt.timedelta(minutes=15)).isoformat(),
        "payment_mode": mode,
    }


async def _order(raw, mode="upi", key="k1", items=None):
    conn = AsyncSqliteConn(raw)
    svc = OrderService(OrderRepo(conn), LedgerRepo(conn), pricing, _rates())
    return await svc.create("u1", _payload(mode, items), key)


def _osvc(raw):
    conn = AsyncSqliteConn(raw)
    return OrderService(OrderRepo(conn), LedgerRepo(conn), pricing, _rates())


def _svc(raw):
    conn = AsyncSqliteConn(raw)
    return PaymentService(PaymentRepo(conn), OrderRepo(conn), LedgerRepo(conn),
                          RealUpiProvider())


def _interleave(conn, winner):
    """Run ``winner`` just before this connection's next ``batch``, once."""
    original = conn.batch
    fired = False

    async def batch(stmts):
        nonlocal fired
        if not fired:
            fired = True
            await winner()
        return await original(stmts)

    conn.batch = batch


def _count(raw, table: str, where: str = "1=1", params: tuple = ()) -> int:
    row = raw.execute(
        f"SELECT COUNT(*) c FROM {table} WHERE {where}", params).fetchone()  # noqa: S608
    return int(row["c"])


def _ledger(raw, user_id="u1") -> dict:
    row = raw.execute("SELECT * FROM ledger WHERE customer_id=?", (user_id,)).fetchone()
    return dict(row) if row is not None else {"held": 0, "deposit_paid": 0,
                                              "deposit_refunded": 0, "dues": 0}


async def _seed_credit(conn, sub_id: str, amount: int, user_id: str = "u1") -> None:
    await conn.execute(
        "INSERT INTO subscription_credit_entries(id, subscription_id, user_id, delta, kind,"
        " ref, created_at) VALUES ('ce-seed', ?, ?, ?, 'adjust', 'seed', ?)",
        (sub_id, user_id, amount, dt.datetime.now(dt.timezone.utc).isoformat()),
    )
    await conn.execute(
        "UPDATE subscriptions SET credit_balance_paise=?, billing_status='active' WHERE id=?",
        (amount, sub_id),
    )
    conn.commit()


def _seed_dispatch(raw, *, oid="ox", sid="sx", expiry=None, code="482910"):
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    raw.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill,"
        " deposit_due, cap_charge, total, payment_mode, state, window_start,"
        " idempotency_key, created_at) VALUES (?, 'u1', 'a1', '[]', 2, 1, 5600,"
        " 0, 0, 5600, 'cod', 'dispatched', ?, 'seed:delivery', ?)",
        (oid, WINDOW, now),
    )
    raw.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status)"
        " VALUES ('rdx', '2026-10-03', 'v1', 'z1', 'open')"
    )
    raw.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status, pod_otp, pod_otp_expires_at, pod_attempts)"
        " VALUES (?, 'rdx', ?, 'u1', 0, 2, 1, 1, 'pending', ?, ?, 0)",
        (sid, oid, code, expiry),
    )
    raw.commit()


# -- cancel ---------------------------------------------------------------

async def test_cancel_mid_batch_failure_leaves_no_trace(rzp):
    raw = _conn()
    s = _svc(raw)
    o = await _order(raw, items=CONTAINER)
    intent = await s.intent("u1", o["id"], "fail-1")
    await s.webhook_ingest(*signed_event(intent["provider_ref"], o["total"],
                                         order_id=o["id"]))
    before = (_count(raw, "order_events"), _count(raw, "refunds"),
              _count(raw, "ledger_events"), _count(raw, "subscription_credit_entries"))
    raw.execute(
        "CREATE TRIGGER fail_event BEFORE INSERT ON order_events"
        " BEGIN SELECT RAISE(ABORT, 'forced cancel failure'); END"
    )
    raw.commit()

    with pytest.raises(Exception):
        await OrderRepo(AsyncSqliteConn(raw)).cancel_settle(
            o["id"], {"id": "u1", "role": "user"})

    assert (_count(raw, "order_events"), _count(raw, "refunds"),
            _count(raw, "ledger_events"),
            _count(raw, "subscription_credit_entries")) == before
    row = raw.execute("SELECT state, payment_status FROM orders WHERE id=?",
                      (o["id"],)).fetchone()
    assert row["state"] == "placed" and row["payment_status"] == "paid_upi"
    assert _ledger(raw)["dues"] == 0


async def test_two_cancels_one_event_reversal_refund(rzp):
    raw = _conn()
    s = _svc(raw)
    o = await _order(raw, items=CONTAINER)
    intent = await s.intent("u1", o["id"], "twice-1")
    await s.webhook_ingest(*signed_event(intent["provider_ref"], o["total"],
                                         order_id=o["id"]))
    repo = OrderRepo(AsyncSqliteConn(raw))

    first = await repo.cancel_settle(o["id"], {"id": "u1", "role": "user"})
    with pytest.raises(AlreadyCancelledError) as loser:
        await repo.cancel_settle(o["id"], {"id": "u1", "role": "user"})

    assert loser.value.status_code == 409
    assert loser.value.details["refund"]["id"] == first["refund"]["id"]
    assert _count(raw, "order_events", "to_state='cancelled'") == 1
    assert _count(raw, "ledger_events", "d_deposit < 0") == 1
    assert _count(raw, "refunds", "order_id=?", (o["id"],)) == 1
    led = _ledger(raw)
    assert led["deposit_paid"] == led["deposit_refunded"] == 15000


async def test_cancel_after_webhook_refund_claim_does_not_refund_twice(rzp):
    raw = _conn()
    s = _svc(raw)
    o = await _order(raw, mode="cod")
    await s.payments.reserve_intent(o["id"], o["total"], "cod-link")
    raw.execute("UPDATE payments SET provider_ref='pay_cod_1' WHERE order_id=?",
                (o["id"],))
    raw.commit()
    captured = await s.webhook_ingest(*signed_event(
        "pay_cod_1", o["total"], order_id=o["id"]))
    assert captured["payment"]["_refund_queued"] is True
    pay_id = raw.execute("SELECT id FROM payments WHERE provider_ref='pay_cod_1'"
                         ).fetchone()["id"]

    out = await OrderRepo(AsyncSqliteConn(raw)).cancel_settle(
        o["id"], {"id": "u1", "role": "user"})

    refunds = raw.execute("SELECT * FROM refunds WHERE order_id=?", (o["id"],)).fetchall()
    assert len(refunds) == 1
    assert refunds[0]["payment_id"] == pay_id
    assert out["refund"]["payment_id"] == pay_id
    assert _ledger(raw)["dues"] == 0


# -- webhooks -------------------------------------------------------------

async def test_duplicate_webhook_has_one_payment_and_one_clear(rzp):
    raw = _conn()
    s = _svc(raw)
    o = await _order(raw)
    # Synthetic prior dues on a UPI order exercises the guarded clear path.
    await LedgerRepo(AsyncSqliteConn(raw)).apply_event(
        "u1", d_dues=o["total"], ref=f"order:{o['id']}", actor="u1", reason="cod dues")
    intent = await s.intent("u1", o["id"], "dup-1")

    first = await s.webhook_ingest(*signed_event(
        intent["provider_ref"], o["total"], order_id=o["id"]))
    second = await s.webhook_ingest(*signed_event(
        intent["provider_ref"], o["total"], order_id=o["id"]))

    assert "duplicate" not in first
    assert second["duplicate"] is True
    assert _count(raw, "payments", "order_id=? AND status='paid'", (o["id"],)) == 1
    row = raw.execute("SELECT payment_status FROM orders WHERE id=?",
                      (o["id"],)).fetchone()
    assert row["payment_status"] == "paid_upi"
    assert _ledger(raw)["dues"] == 0
    assert _count(raw, "ledger_events", "d_dues < 0") == 1


async def test_webhook_vs_cancel_exactly_one_refund_per_payment(rzp):
    raw = _conn()
    s = _svc(raw)

    # A: capture first, then cancel.
    a = await _order(raw, key="webhook-first")
    ia = await s.intent("u1", a["id"], "ia")
    await s.webhook_ingest(*signed_event(ia["provider_ref"], a["total"],
                                         order_id=a["id"]))
    await OrderRepo(AsyncSqliteConn(raw)).cancel_settle(
        a["id"], {"id": "u1", "role": "user"})

    # B: cancel first, then the late capture arrives.
    b = await _order(raw, key="cancel-first")
    ib = await s.intent("u1", b["id"], "ib")
    await OrderRepo(AsyncSqliteConn(raw)).cancel_settle(
        b["id"], {"id": "u1", "role": "user"})
    late = await s.webhook_ingest(*signed_event(ib["provider_ref"], b["total"],
                                                order_id=b["id"]))
    assert late["payment"]["_refund_queued"] is True

    for oid in (a["id"], b["id"]):
        row = raw.execute("SELECT state, payment_status FROM orders WHERE id=?",
                          (oid,)).fetchone()
        assert row["state"] == "cancelled"
        assert row["payment_status"] == "unpaid"
        assert _count(raw, "refunds", "order_id=?", (oid,)) == 1
    a_refund = raw.execute("SELECT payment_id FROM refunds WHERE order_id=?",
                           (a["id"],)).fetchone()
    assert a_refund["payment_id"] == a["id"]
    b_pay = raw.execute("SELECT id FROM payments WHERE order_id=?",
                        (b["id"],)).fetchone()
    b_refund = raw.execute("SELECT payment_id FROM refunds WHERE order_id=?",
                           (b["id"],)).fetchone()
    assert b_refund["payment_id"] == b_pay["id"]


async def test_webhook_on_cod_order_refunds_and_keeps_order_unpaid(rzp):
    raw = _conn()
    s = _svc(raw)
    o = await _order(raw, mode="cod")
    await s.payments.reserve_intent(o["id"], o["total"], "cod-only")
    raw.execute("UPDATE payments SET provider_ref='pay_cod_2' WHERE order_id=?",
                (o["id"],))
    raw.commit()

    out = await s.webhook_ingest(*signed_event("pay_cod_2", o["total"],
                                               order_id=o["id"]))

    assert out["payment"]["status"] == "paid"
    assert out["payment"]["_refund_queued"] is True
    row = raw.execute("SELECT payment_mode, payment_status FROM orders WHERE id=?",
                      (o["id"],)).fetchone()
    assert row["payment_mode"] == "cod" and row["payment_status"] == "unpaid"
    refund = raw.execute("SELECT * FROM refunds WHERE order_id=?", (o["id"],)).fetchone()
    assert refund["amount"] == o["total"] and refund["status"] == "pending"


# -- dues -----------------------------------------------------------------

async def test_duplicate_dues_webhook_allocates_once(rzp):
    raw = _conn()
    s = _svc(raw)
    o = await _order(raw, mode="cod")
    await s.cod_confirm("u1", o["id"])
    intent = await s.dues_intent("u1", "dues-dup")

    first = await s.webhook_ingest(*signed_event(
        intent["provider_ref"], o["total"], order_id=None))
    second = await s.webhook_ingest(*signed_event(
        intent["provider_ref"], o["total"], order_id=None))

    assert first["dues_intent"]["status"] == "paid"
    assert second["duplicate"] is True
    assert "_duplicate" not in second["dues_intent"]
    assert _count(raw, "payments") == 1
    assert raw.execute("SELECT SUM(amount) a FROM payments").fetchone()["a"] == o["total"]
    row = raw.execute("SELECT payment_status FROM orders WHERE id=?",
                      (o["id"],)).fetchone()
    assert row["payment_status"] == "paid_upi"
    assert _ledger(raw)["dues"] == 0


async def test_dues_settlement_after_order_cancel_refunds_unallocated(rzp):
    raw = _conn()
    s = _svc(raw)
    a = await _order(raw, mode="cod", key="dues-a")
    await s.cod_confirm("u1", a["id"])
    b = await _order(raw, key="dues-b")
    dues = (await s.get_dues("u1"))["dues"]
    assert dues == a["total"] + b["total"]
    intent = await s.dues_intent("u1", "dues-race")
    intent_id = intent["payment"]["id"]

    await OrderRepo(AsyncSqliteConn(raw)).cancel_settle(
        b["id"], {"id": "u1", "role": "user"})
    out = await s.webhook_ingest(*signed_event(
        intent["provider_ref"], dues, order_id=None))

    assert out["dues_intent"]["status"] == "paid"
    assert out["dues_intent"]["_refund_queued"] is True
    assert _count(raw, "payments", "order_id=?", (b["id"],)) == 0
    refund = raw.execute("SELECT * FROM refunds WHERE payment_id=?",
                         (f"dues:{intent_id}",)).fetchone()
    assert refund["amount"] == b["total"]
    a_row = raw.execute("SELECT payment_status FROM orders WHERE id=?",
                        (a["id"],)).fetchone()
    assert a_row["payment_status"] == "paid_upi"
    assert _ledger(raw)["dues"] == 0


# -- transitions ----------------------------------------------------------

async def test_two_transitions_one_event_one_postpaid_dues(rzp):
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    sub = await SubscriptionService(conn).create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily",
        "payment_method": "upi", "billing_mode": "monthly_postpaid",
        "next_run": DAY,
    })
    o = await _order(raw, key=f"sub:{sub['id']}:{DAY}")
    raw.execute("UPDATE orders SET state='dispatched' WHERE id=?", (o["id"],))
    raw.commit()
    repo = OrderRepo(conn)

    async def winner():
        await OrderRepo(conn).transition(
            o["id"], "delivered", {"id": "v1", "role": "vendor"}, "pod")

    _interleave(conn, winner)
    with pytest.raises(ConflictError) as loser:
        await repo.transition(o["id"], "delivered",
                              {"id": "v1", "role": "vendor"}, "pod")

    assert loser.value.status_code == 409
    state = raw.execute("SELECT state FROM orders WHERE id=?", (o["id"],)).fetchone()
    assert state["state"] == "delivered"
    assert _count(raw, "order_events", "to_state='delivered'") == 1
    assert _count(raw, "ledger_events", "d_dues > 0") == 1


# -- subscription cancel --------------------------------------------------

async def test_subscription_cancel_failure_leaves_credit_untouched(rzp):
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    subs = SubscriptionService(conn)
    sub = await subs.create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily",
        "payment_method": "upi", "billing_mode": "monthly_prepaid",
    })
    await _seed_credit(conn, sub["id"], 84000)
    before = (_count(raw, "refunds"), _count(raw, "subscription_credit_entries"))

    original = conn.batch

    async def boom(_stmts):
        raise RuntimeError("forced cancel batch failure")

    conn.batch = boom
    with pytest.raises(RuntimeError):
        await subs.cancel("u1", sub["id"])
    conn.batch = original

    row = raw.execute("SELECT credit_balance_paise, canceled_at FROM subscriptions"
                      " WHERE id=?", (sub["id"],)).fetchone()
    assert row["credit_balance_paise"] == 84000
    assert row["canceled_at"] is None
    assert (_count(raw, "refunds"),
            _count(raw, "subscription_credit_entries")) == before


async def test_prepaid_and_postpaid_cancel_refund_only_collected_credit(rzp):
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    subs = SubscriptionService(conn)
    pre = await subs.create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily",
        "payment_method": "upi", "billing_mode": "monthly_prepaid",
    })
    await _seed_credit(conn, pre["id"], 84000)
    post = await subs.create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily",
        "payment_method": "upi", "billing_mode": "monthly_postpaid",
    })
    await LedgerRepo(conn).apply_event("u1", d_dues=5600, ref="order:o-post",
                                       reason="postpaid delivery")

    prepaid = await subs.cancel("u1", pre["id"])
    postpaid = await subs.cancel("u1", post["id"])

    assert prepaid["unused_water_refund_paise"] == 84000
    assert prepaid["refund"]["amount"] == 84000
    assert postpaid["unused_water_refund_paise"] == 0
    assert postpaid["refund"] is None
    assert _ledger(raw)["dues"] == 5600  # never forgiven
    assert _count(raw, "refunds") == 1
    assert raw.execute("SELECT amount FROM refunds").fetchone()["amount"] == 84000


# -- delivery-code reissue ------------------------------------------------

async def test_reissue_limit_and_window_reset(rzp):
    raw = _conn()
    now = dt.datetime.now(dt.timezone.utc)
    past = (now - dt.timedelta(minutes=1)).isoformat()
    _seed_dispatch(raw, expiry=past)
    s = _osvc(raw)

    for _ in range(3):
        out = await s.reissue_delivery_code("u1", "ox")
        assert out["reissued"] is True
        raw.execute("UPDATE stops SET pod_otp_expires_at=? WHERE id='sx'", (past,))
        raw.commit()
    with pytest.raises(RateLimitedError) as capped:
        await s.reissue_delivery_code("u1", "ox")
    assert capped.value.status_code == 429
    assert _count(raw, "delivery_code_reissues") == 3

    raw.execute("UPDATE delivery_code_reissues SET created_at=?",
                ((now - dt.timedelta(hours=25)).isoformat(),))
    raw.commit()
    out = await s.reissue_delivery_code("u1", "ox")
    assert out["reissued"] is True
    assert _count(raw, "delivery_code_reissues") == 4


async def test_reissue_pk_conflict_retries_within_limit(rzp):
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    now = dt.datetime.now(dt.timezone.utc)
    past = (now - dt.timedelta(minutes=1)).isoformat()
    _seed_dispatch(raw, expiry=past)
    s = OrderService(OrderRepo(conn), LedgerRepo(conn), pricing, _rates())

    async def winner():
        await s.reissue_delivery_code("u1", "ox")  # claims seq 1
        # Keep the loser's retry eligible: the winner's code is expired again.
        raw.execute("UPDATE stops SET pod_otp_expires_at=? WHERE id='sx'", (past,))
        raw.commit()

    _interleave(conn, winner)
    loser = await s.reissue_delivery_code("u1", "ox")

    assert loser["reissued"] is True
    assert _count(raw, "delivery_code_reissues") == 2
    seqs = [r["seq"] for r in raw.execute(
        "SELECT seq FROM delivery_code_reissues ORDER BY seq").fetchall()]
    assert seqs == [1, 2]

    raw.execute("UPDATE stops SET pod_otp_expires_at=? WHERE id='sx'", (past,))
    raw.commit()
    assert (await s.reissue_delivery_code("u1", "ox"))["reissued"] is True
    raw.execute("UPDATE stops SET pod_otp_expires_at=? WHERE id='sx'", (past,))
    raw.commit()
    with pytest.raises(RateLimitedError):
        await s.reissue_delivery_code("u1", "ox")
    assert _count(raw, "delivery_code_reissues") == 3
