"""Subscription cancellation: honest money, bottle return scheduling."""
import sys
from pathlib import Path
import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db import get_connection
from app.db_d1 import AsyncSqliteConn
from app.services.subscription_service import SubscriptionService, SubValidationError
from app.repositories.ledger_repo import LedgerRepo

MIGS = [
    "002_auth.sql", "003_addresses.sql", "004_orders.sql", "005_payments.sql",
    "006_aftermath.sql", "010_config_audit.sql", "012_monthly.sql",
    "019_rate_counters.sql", "021_return_upi.sql",
    "022_vendor_leaves_and_sub_cancel.sql", "028_p0_money_monthly.sql",
    "029_p0_correctness.sql",
]


def _conn():
    c = get_connection(":memory:")
    for m in MIGS:
        c.executescript((API_ROOT / "src" / "app" / "db" / "migrations" / m).read_text())
    return c


async def _seed_credit(conn, sub_id: str, user_id: str, amount: int, created: str):
    await conn.execute(
        "INSERT INTO subscription_credit_entries(id, subscription_id, user_id, delta, kind,"
        " ref, created_at) VALUES ('ce-seed', ?, ?, ?, 'adjust', 'seed', ?)",
        (sub_id, user_id, amount, created),
    )
    await conn.execute(
        "UPDATE subscriptions SET credit_balance_paise=?, billing_status='active' WHERE id=?",
        (amount, sub_id),
    )
    conn.commit()


@pytest.mark.asyncio
async def test_per_delivery_cancel_refunds_nothing_and_returns_bottles():
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    raw.execute("INSERT INTO addresses(id, user_id) VALUES ('a1', 'u1')")
    raw.commit()

    await LedgerRepo(conn).apply_event("u1", d_held=1, d_deposit=15000,
                                       reason="initial container deposit")

    svc = SubscriptionService(conn)
    sub = await svc.create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily",
        "payment_method": "upi", "sku_mix": "refill",
    })
    res = await svc.cancel("u1", sub["id"], reason="Relocating", upi_id="user@oksbi")

    assert res["status"] == "canceled"
    assert res["is_prepaid"] is False
    assert res["unused_water_refund_paise"] == 0
    assert res["refund"] is None  # no money was ever collected
    assert res["jars_to_return"] == 1
    assert res["deposit_refund_expected_paise"] == 15000
    assert res["return_id"] is not None

    ret_row = (await conn.execute("SELECT * FROM returns WHERE id = ?",
                                  (res["return_id"],))).fetchone()
    assert ret_row is not None and ret_row["upi_id"] == "user@oksbi"
    assert ret_row["status"] == "requested"

    with pytest.raises(SubValidationError):
        await svc.pause("u1", sub["id"], "2026-10-10", "2026-10-15")
    with pytest.raises(SubValidationError):
        await svc.cancel("u1", sub["id"], reason="Cancel again")

    all_subs = await svc.list("u1")
    assert all_subs[0]["status"] == "canceled"


@pytest.mark.asyncio
async def test_prepaid_cancel_refunds_real_remaining_credit():
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    raw.execute("INSERT INTO addresses(id, user_id) VALUES ('a1', 'u1')")
    raw.commit()

    svc = SubscriptionService(conn)
    sub = await svc.create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily",
        "payment_method": "upi", "billing_mode": "monthly_prepaid",
    })
    assert sub["billing_status"] == "pending_payment"
    await _seed_credit(conn, sub["id"], "u1", 84000, "2026-10-01T00:00:00+00:00")

    res = await svc.cancel("u1", sub["id"], reason="Moving away")

    assert res["is_prepaid"] is True
    assert res["unused_water_refund_paise"] == 84000
    assert res["refund"]["amount"] == 84000
    refund = (await conn.execute("SELECT * FROM refunds WHERE id=?",
                                 (res["refund"]["id"],))).fetchone()
    assert refund["subscription_id"] == sub["id"]
    assert refund["order_id"] is None and refund["status"] == "pending"
    row = (await conn.execute("SELECT billing_status, credit_balance_paise FROM subscriptions"
                              " WHERE id=?", (sub["id"],))).fetchone()
    assert row["billing_status"] == "canceled" and row["credit_balance_paise"] == 0


@pytest.mark.asyncio
async def test_cancel_never_writes_off_ledger_dues():
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    raw.execute("INSERT INTO addresses(id, user_id) VALUES ('a1', 'u1')")
    raw.commit()
    await LedgerRepo(conn).apply_event("u1", d_dues=5600, ref="order:o1", reason="cod dues")

    svc = SubscriptionService(conn)
    sub = await svc.create("u1", {
        "address_id": "a1", "qty": 1, "schedule_type": "daily",
        "payment_method": "upi", "billing_mode": "monthly_prepaid",
    })
    await _seed_credit(conn, sub["id"], "u1", 84000, "2026-10-01T00:00:00+00:00")

    await svc.cancel("u1", sub["id"], reason="Stop")
    led = await LedgerRepo(conn).get("u1")
    assert led["dues"] == 5600  # cancellation never forgave real debt
