"""Test subscription cancellation, proration refund, and bottle return scheduling."""
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
    "002_auth.sql", "003_addresses.sql", "004_orders.sql",
    "006_aftermath.sql", "021_return_upi.sql", "022_vendor_leaves_and_sub_cancel.sql"
]


def _conn():
    c = get_connection(":memory:")
    for m in MIGS:
        c.executescript((API_ROOT / "src" / "app" / "db" / "migrations" / m).read_text())
    return c


@pytest.mark.asyncio
async def test_subscription_cancellation_proration_and_return():
    raw = _conn()
    conn = AsyncSqliteConn(raw)
    raw.execute("INSERT INTO addresses(id, user_id) VALUES ('a1', 'u1')")
    raw.commit()

    # Pre-seed ledger with 1 held jar (e.g. from starting service)
    await LedgerRepo(conn).apply_event("u1", d_held=1, d_deposit=15000, reason="initial container deposit")

    svc = SubscriptionService(conn)
    sub = await svc.create("u1", {
        "address_id": "a1",
        "qty": 1,
        "schedule_type": "daily",
        "payment_method": "upi",  # prepaid
        "sku_mix": "refill",
    })
    sub_id = sub["id"]

    # Now cancel the subscription
    res = await svc.cancel("u1", sub_id, reason="Relocating to another city", upi_id="user@oksbi")

    assert res["status"] == "canceled"
    assert res["is_prepaid"] is True
    # 30 days * 1 jar * 2800 paise = 84000 paise (₹840) unused
    assert res["unused_water_refund_paise"] == 84000
    assert res["jars_to_return"] == 1
    assert res["deposit_refund_expected_paise"] == 15000
    assert res["return_id"] is not None

    # Check that return row was created with UPI ID
    ret_row = (await conn.execute("SELECT * FROM returns WHERE id = ?", (res["return_id"],))).fetchone()
    assert ret_row is not None
    assert ret_row["user_id"] == "u1"
    assert ret_row["qty"] == 1
    assert ret_row["upi_id"] == "user@oksbi"
    assert ret_row["status"] == "requested"

    # Verify subscription cannot be modified after cancel
    with pytest.raises(SubValidationError):
        await svc.pause("u1", sub_id, "2026-10-10", "2026-10-15")

    with pytest.raises(SubValidationError):
        await svc.cancel("u1", sub_id, reason="Cancel again")

    # Verify list reflects canceled status
    all_subs = await svc.list("u1")
    assert len(all_subs) == 1
    assert all_subs[0]["status"] == "canceled"
