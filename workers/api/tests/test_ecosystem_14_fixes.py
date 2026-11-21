import datetime as _dt
import hashlib
import sys
from pathlib import Path
import pytest
from starlette.testclient import TestClient

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.api.deps import get_db_conn
from app.db import get_connection
from app.db_d1 import AsyncSqliteConn
from app.main import create_app
from app.services.rider_service import RiderService
from app.services.vendor_service import VendorService

MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "src" / "app" / "db" / "migrations"


def _setup_db():
    conn = get_connection(":memory:")
    for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
        conn.executescript(path.read_text(encoding="utf-8"))
    conn.commit()
    return conn


@pytest.mark.asyncio
async def test_vendor_delete_rider():
    conn = _setup_db()
    c = AsyncSqliteConn(conn)
    v_svc = VendorService(c)

    # Insert vendor
    await c.execute(
        "INSERT INTO users (id, phone, name, role, created_at) VALUES ('v1', '+919999900001', 'Test Vendor', 'vendor', datetime('now'))"
    )
    # Insert rider
    await c.execute(
        "INSERT INTO users (id, phone, name, role, assigned_vendor_id, created_at) VALUES ('r1', '+919999900002', 'Test Rider', 'rider', 'v1', datetime('now'))"
    )
    # Insert stop assigned to rider
    await c.execute(
        "INSERT INTO routes (id, vendor_id, date, status) VALUES ('route1', 'v1', '2026-11-21', 'open')"
    )
    await c.execute(
        "INSERT INTO stops (id, route_id, rider_id, status) VALUES ('stop1', 'route1', 'r1', 'pending')"
    )
    c.commit()

    # List riders
    riders = await v_svc.list_riders('v1')
    assert len(riders) == 1
    assert riders[0]['id'] == 'r1'

    # Delete rider
    res = await v_svc.delete_rider('v1', 'r1')
    assert res['status'] == 'removed'

    # Verify unassigned
    u = (await c.execute("SELECT assigned_vendor_id FROM users WHERE id = 'r1'")).fetchone()
    assert u['assigned_vendor_id'] is None

    # Verify stop unassigned
    s = (await c.execute("SELECT rider_id FROM stops WHERE id = 'stop1'")).fetchone()
    assert s['rider_id'] is None


@pytest.mark.asyncio
async def test_vendor_cancel_otp_and_rider_cancel_stop():
    conn = _setup_db()
    c = AsyncSqliteConn(conn)
    v_svc = VendorService(c)
    r_svc = RiderService(c)

    # Setup vendor, rider, order, route, stop
    await c.execute(
        "INSERT INTO users (id, phone, name, role, created_at) VALUES ('v1', '+919999900001', 'Test Vendor', 'vendor', datetime('now'))"
    )
    await c.execute(
        "INSERT INTO users (id, phone, name, role, assigned_vendor_id, created_at) VALUES ('r1', '+919999900002', 'Test Rider', 'rider', 'v1', datetime('now'))"
    )
    now_iso = _dt.datetime.now(_dt.timezone.utc).isoformat()
    await c.execute(
        "INSERT INTO orders (id, user_id, address_id, items, n, e, water_bill, deposit_due, total, payment_mode, payment_status, state, window_start, idempotency_key, created_at) "
        "VALUES ('ord1', 'cust1', 'addr1', '[]', 2, 1, 5000, 0, 5000, 'cod', 'unpaid', 'assigned', ?, 'seed:ord1', ?)",
        (now_iso, now_iso),
    )
    await c.execute(
        "INSERT INTO routes (id, vendor_id, date, status) VALUES ('route1', 'v1', '2026-11-21', 'open')"
    )
    await c.execute(
        "INSERT INTO stops (id, route_id, order_id, rider_id, status) VALUES ('stop1', 'route1', 'ord1', 'r1', 'pending')"
    )
    c.commit()

    # Vendor issues cancel OTP
    res_otp = await v_svc.issue_stop_cancel_otp('v1', 'stop1')
    otp = res_otp['cancel_otp']
    assert len(otp) == 4

    # Rider cancels with wrong OTP -> fails
    with pytest.raises(Exception):
        await r_svc.cancel_stop('r1', 'stop1', '0000', 'CUSTOMER_UNREACHABLE')

    # Rider cancels with valid OTP -> succeeds
    res_cancel = await r_svc.cancel_stop('r1', 'stop1', otp, 'CUSTOMER_UNREACHABLE')
    assert res_cancel['status'] == 'cancelled'

    # Verify stop failed and order cancelled
    s = (await c.execute("SELECT status, failure_reason FROM stops WHERE id = 'stop1'")).fetchone()
    assert s['status'] == 'failed'
    assert 'CANCELLED' in s['failure_reason']

    o = (await c.execute("SELECT state FROM orders WHERE id = 'ord1'")).fetchone()
    assert o['state'] == 'cancelled'
