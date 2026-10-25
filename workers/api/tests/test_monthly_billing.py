"""026 monthly billing: prepaid/postpaid persist + list + dues provider flag."""
import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db import get_connection  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.repositories.ledger_repo import LedgerRepo  # noqa: E402
from app.repositories.order_repo import OrderRepo  # noqa: E402
from app.repositories.payment_repo import PaymentRepo  # noqa: E402
from app.services.payment_service import PaymentService  # noqa: E402
from app.services.subscription_service import (  # noqa: E402
    SubValidationError,
    SubscriptionService,
)


class _NoOpProvider:
    """Razorpay-only world (ADR-096): get_dues reads UPI_PROVIDER env and
    never calls the injected provider object, so a stub is enough here."""


def _conn():
    c = get_connection(":memory:")
    base = API_ROOT / "src" / "app" / "db" / "migrations"
    for m in ("002_auth.sql", "003_addresses.sql", "004_orders.sql", "012_monthly.sql",
              "022_vendor_leaves_and_sub_cancel.sql", "028_p0_money_monthly.sql"):
        c.executescript((base / m).read_text())
    return c


def _addr(c, user="u1", aid="a1"):
    c.execute("INSERT OR IGNORE INTO addresses(id, user_id) VALUES (?, ?)", (aid, user))
    c.execute("INSERT OR IGNORE INTO users(id, phone, name, role, created_at)"
              " VALUES (?, '+910000000001', 'U', 'user', '2026-01-01T00:00:00+00:00')", (user,))
    c.commit()


async def _mk(c, **over):
    _addr(c)
    kw = {"address_id": "a1", "qty": 2, "schedule_type": "daily",
          "next_run": "2026-10-05", "payment_method": "upi",
          "billing_mode": "monthly_prepaid"}
    kw.update(over)
    return await SubscriptionService(AsyncSqliteConn(c)).create("u1", kw)


async def test_create_monthly_prepaid_upi():
    c = _conn()
    s = await _mk(c)
    assert s["billing_mode"] == "monthly_prepaid"
    assert s["payment_method"] == "upi"


async def test_create_monthly_postpaid_upi():
    c = _conn()
    s = await _mk(c, billing_mode="monthly_postpaid", payment_method="upi")
    assert s["billing_mode"] == "monthly_postpaid"
    assert s["payment_method"] == "upi"


async def test_monthly_cod_rejected():
    c = _conn()
    _addr(c)
    try:
        await _mk(c, billing_mode="monthly_postpaid", payment_method="cod")
    except Exception as e:
        assert getattr(e, "code", "") == "VALIDATION"
    else:
        raise AssertionError("monthly plans must be UPI")


async def test_invalid_billing_mode_rejected():
    c = _conn()
    _addr(c)
    try:
        await SubscriptionService(AsyncSqliteConn(c)).create("u1", {
            "address_id": "a1", "qty": 2, "billing_mode": "yearly"})
    except Exception as e:
        assert getattr(e, "code", "") == "VALIDATION"
    else:
        raise AssertionError("expected VALIDATION")


async def test_plan_qty_over_household_cap_rejected():
    c = _conn()
    _addr(c)
    with pytest.raises(SubValidationError) as e:
        await SubscriptionService(AsyncSqliteConn(c)).create("u1", {
            "address_id": "a1", "qty": 11, "schedule_type": "daily",
            "payment_method": "upi", "billing_mode": "monthly_prepaid"})
    assert e.value.code == "VALIDATION" and e.value.details["max"] == 10
    assert c.execute("SELECT COUNT(*) n FROM subscriptions").fetchone()["n"] == 0


async def test_list_carries_mode_and_estimate():
    c = _conn()
    await _mk(c, qty=2)
    rows = await SubscriptionService(AsyncSqliteConn(c)).list("u1")
    assert rows[0]["billing_mode"] == "monthly_prepaid"
    assert rows[0]["monthly_estimate_paise"] == 2 * 2800 * 30
    assert rows[0]["due_today_paise"] == 2 * 2800


async def test_dues_carries_provider_flag():
    c = _conn()
    _addr(c)
    ac = AsyncSqliteConn(c)
    dues = await PaymentService(PaymentRepo(ac), OrderRepo(ac), LedgerRepo(ac),
                                _NoOpProvider()).get_dues("u1")
    assert dues["provider"] in ("fake", "razorpay")
    assert dues["razorpay_ready"] == (dues["provider"] == "razorpay")


async def test_convergence_without_012():
    # Old DB built from 004 only — service self-heals via PRAGMA + ALTER.
    c = get_connection(":memory:")
    base = API_ROOT / "src" / "app" / "db" / "migrations"
    for m in ("002_auth.sql", "003_addresses.sql", "004_orders.sql"):
        c.executescript((base / m).read_text())
    s = await _mk(c, billing_mode="monthly_postpaid", payment_method="upi")
    assert s["billing_mode"] == "monthly_postpaid"
    assert s["billing_status"] == "active"
    assert s["credit_balance_paise"] == 0
