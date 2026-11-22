"""Tests for Customer Cancellation Override & Stale Order Delivery Reconciliation."""

import datetime as _dt
import sys
from pathlib import Path
import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.core.state_machines import validate_order_transition
from app.db import get_connection
from app.db_d1 import AsyncSqliteConn
from app.repositories.ledger_repo import LedgerRepo
from app.repositories.order_repo import OrderRepo
from app.services import pricing
from app.services.order_service import OrderService
from app.services.rider_service import RiderService

MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "src" / "app" / "db" / "migrations"


def _setup_db():
    conn = get_connection(":memory:")
    for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
        conn.executescript(path.read_text(encoding="utf-8"))
    conn.commit()
    return conn


def _make_order_service(conn):
    rates = {"refill": 2800, "container": 65000, "deposit": 0}
    return OrderService(OrderRepo(conn), LedgerRepo(conn), pricing, rates)


def test_state_machine_allows_user_override():
    # User can now transition from assigned and dispatched to cancelled
    validate_order_transition("assigned", "cancelled", actor_role="user")
    validate_order_transition("dispatched", "cancelled", actor_role="user")


@pytest.mark.asyncio
async def test_customer_can_cancel_assigned_order_and_alerts_rider():
    conn = _setup_db()
    c = AsyncSqliteConn(conn)
    order_svc = _make_order_service(c)
    rider_svc = RiderService(c)

    # 1. Setup user, vendor, rider, route, order, stop
    await c.execute(
        "INSERT INTO users (id, phone, name, role, created_at) VALUES ('u1', '+919999900001', 'Test Customer', 'user', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO users (id, phone, name, role, created_at) VALUES ('v1', '+919999900002', 'Test Vendor', 'vendor', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO users (id, phone, name, role, assigned_vendor_id, created_at) VALUES ('r1', '+919999900003', 'Test Rider', 'rider', 'v1', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO routes (id, vendor_id, date, status) VALUES ('route1', 'v1', '2026-11-22', 'open')"
    )
    await c.execute(
        "INSERT INTO addresses (id, user_id, label, formatted, pincode, created_at) VALUES ('a1', 'u1', 'Home', 'Plot 10, Bhopal', '462016', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO orders (id, user_id, address_id, items, n, e, water_bill, deposit_due, total, payment_mode, payment_status, state, window_start, idempotency_key, created_at) "
        "VALUES ('ord1', 'u1', 'a1', '[{\"sku\":\"20l_can\",\"qty\":1}]', 1, 0, 2800, 0, 2800, 'cod', 'unpaid', 'assigned', '2026-11-22T08:00:00+05:30', 'idem1', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO stops (id, route_id, order_id, customer_id, rider_id, status, fulls_exp, seq) "
        "VALUES ('stop1', 'route1', 'ord1', 'u1', 'r1', 'pending', 1, 1)"
    )
    c.commit()

    # 2. Customer cancels order while in 'assigned' state
    res = await order_svc.cancel(
        user_id='u1',
        order_id='ord1',
        reason='Changed mind, cancel order',
        idempotency_key='cancel-key-1',
    )
    assert res['state'] == 'cancelled'

    # 3. Check order is cancelled in DB
    ord_row = (await c.execute("SELECT state FROM orders WHERE id = 'ord1'")).fetchone()
    assert ord_row['state'] == 'cancelled'

    # 4. Check stop status is marked failed with failure_reason = 'CANCELLED_BY_CUSTOMER'
    stop_row = (await c.execute("SELECT status, failure_reason FROM stops WHERE id = 'stop1'")).fetchone()
    assert stop_row['status'] == 'failed'
    assert stop_row['failure_reason'] == 'CANCELLED_BY_CUSTOMER'

    # 5. Check rider routes_today reports stop as 'cancelled' and order_state as 'cancelled'
    routes = await rider_svc.routes_today('r1', '2026-11-22')
    assert len(routes['stops']) == 1
    rider_stop = routes['stops'][0]
    assert rider_stop['status'] == 'cancelled'
    assert rider_stop['order_state'] == 'cancelled'
    assert rider_stop['failure_reason'] == 'CANCELLED_BY_CUSTOMER'
    assert routes['summary']['pending'] == 0


@pytest.mark.asyncio
async def test_customer_confirm_delivery_self_attestation_paid():
    conn = _setup_db()
    c = AsyncSqliteConn(conn)
    order_svc = _make_order_service(c)

    await c.execute(
        "INSERT INTO users (id, phone, name, role, created_at) VALUES ('u2', '+919999900011', 'Test Customer 2', 'user', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO users (id, phone, name, role, created_at) VALUES ('v2', '+919999900012', 'Test Vendor 2', 'vendor', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO routes (id, vendor_id, date, status) VALUES ('route2', 'v2', '2026-11-21', 'open')"
    )
    await c.execute(
        "INSERT INTO addresses (id, user_id, label, formatted, pincode, created_at) VALUES ('a2', 'u2', 'Home', 'Plot 20, Bhopal', '462016', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO orders (id, user_id, address_id, items, n, e, water_bill, deposit_due, total, payment_mode, payment_status, state, window_start, idempotency_key, created_at) "
        "VALUES ('ord2', 'u2', 'a2', '[{\"sku\":\"20l_can\",\"qty\":1}]', 1, 0, 2800, 0, 2800, 'cod', 'unpaid', 'assigned', '2026-11-21T08:00:00+05:30', 'idem2', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO stops (id, route_id, order_id, customer_id, status, fulls_exp, seq) "
        "VALUES ('stop2', 'route2', 'ord2', 'u2', 'pending', 1, 1)"
    )
    c.commit()

    # Customer confirms delivery: received = True, cash_paid = True
    res = await order_svc.confirm_delivery(
        user_id='u2',
        order_id='ord2',
        received=True,
        cash_paid=True,
        notes='Rider forgot OTP yesterday',
    )
    assert res['state'] == 'delivered'
    assert res['payment_status'] == 'paid_cash'

    # Check jar custody incremented in ledger
    led = await LedgerRepo(c).get('u2')
    assert led['held'] == 1

    # Check stop is marked done
    stop = (await c.execute("SELECT status FROM stops WHERE id = 'stop2'")).fetchone()
    assert stop['status'] == 'done'


@pytest.mark.asyncio
async def test_customer_confirm_delivery_self_attestation_unpaid_adds_dues():
    conn = _setup_db()
    c = AsyncSqliteConn(conn)
    order_svc = _make_order_service(c)

    await c.execute(
        "INSERT INTO users (id, phone, name, role, created_at) VALUES ('u3', '+919999900021', 'Test Customer 3', 'user', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO users (id, phone, name, role, created_at) VALUES ('v3', '+919999900022', 'Test Vendor 3', 'vendor', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO routes (id, vendor_id, date, status) VALUES ('route3', 'v3', '2026-11-21', 'open')"
    )
    await c.execute(
        "INSERT INTO addresses (id, user_id, label, formatted, pincode, created_at) VALUES ('a3', 'u3', 'Home', 'Plot 30, Bhopal', '462016', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO orders (id, user_id, address_id, items, n, e, water_bill, deposit_due, total, payment_mode, payment_status, state, window_start, idempotency_key, created_at) "
        "VALUES ('ord3', 'u3', 'a3', '[{\"sku\":\"20l_can\",\"qty\":2}]', 2, 0, 5600, 0, 5600, 'cod', 'unpaid', 'assigned', '2026-11-21T08:00:00+05:30', 'idem3', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO stops (id, route_id, order_id, customer_id, status, fulls_exp, seq) "
        "VALUES ('stop3', 'route3', 'ord3', 'u3', 'pending', 2, 1)"
    )
    c.commit()

    # Customer confirms delivery: received = True, cash_paid = False (unpaid cash added to dues)
    res = await order_svc.confirm_delivery(
        user_id='u3',
        order_id='ord3',
        received=True,
        cash_paid=False,
        notes='No cash available, add to dues',
    )
    assert res['state'] == 'delivered'
    assert res['payment_status'] == 'unpaid'

    # Check jar custody incremented (+2 jars)
    led = await LedgerRepo(c).get('u3')
    assert led['held'] == 2

    # Check dues recorded in ledger
    assert led['dues'] == 5600
