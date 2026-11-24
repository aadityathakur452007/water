import datetime as _dt
import sys
from pathlib import Path
import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db import get_connection
from app.db_d1 import AsyncSqliteConn
from app.api.v1.admin import admin_suspend_user, admin_unsuspend_user, get_orphan_customers, reassign_vendor_customers, SuspendIn, ReassignCustomersIn
from app.services.dispatch_service import _check_capacity, assign_order, auto_assign_trusted_vendor, CapacityExceededError
from app.services.subscription_service import SubscriptionService
from app.services.rider_service import RiderService
from app.services.vendor_service import VendorService
from app.services.auth_service import AuthService
from app.core.errors import ValidationError

MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "src" / "app" / "db" / "migrations"


def _setup_db():
    conn = get_connection(":memory:")
    for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
        conn.executescript(path.read_text(encoding="utf-8"))
    conn.commit()
    return conn


@pytest.mark.asyncio
async def test_vendor_suspend_cascade_and_reassign():
    conn = _setup_db()
    c = AsyncSqliteConn(conn)
    admin_actor = {"id": "admin_1", "role": "admin"}

    # 1. Seed admin, vendor, rider, customer
    await c.execute("INSERT INTO users (id, phone, name, role, created_at) VALUES ('admin_1', '+917828442476', 'Super Admin', 'admin', datetime('now'))")
    await c.execute("INSERT INTO users (id, phone, name, role, created_at) VALUES ('v1', '+919999900001', 'Vendor One', 'vendor', datetime('now'))")
    await c.execute("INSERT INTO vendor_profile (user_id, active, review_hold) VALUES ('v1', 1, 0)")
    await c.execute("INSERT INTO users (id, phone, name, role, assigned_vendor_id, created_at) VALUES ('r1', '+919999900002', 'Rider One', 'rider', 'v1', datetime('now'))")
    await c.execute("INSERT INTO sessions (id, user_id, token_hash, refresh_hash, expires_at, created_at) VALUES ('s_v1', 'v1', 'h_v1', 'r_v1', '2099-01-01', datetime('now'))")
    await c.execute("INSERT INTO sessions (id, user_id, token_hash, refresh_hash, expires_at, created_at) VALUES ('s_r1', 'r1', 'h_r1', 'r_r1', '2099-01-01', datetime('now'))")

    # Customer assigned to v1
    await c.execute("INSERT INTO users (id, phone, name, role, assigned_vendor_id, created_at) VALUES ('u1', '+919999900003', 'Customer One', 'user', 'v1', datetime('now'))")

    # Pending route & stop for v1
    today = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%d")
    await c.execute("INSERT INTO routes (id, vendor_id, date, status) VALUES ('route_v1', 'v1', ?, 'open')", (today,))
    await c.execute("INSERT INTO stops (id, route_id, rider_id, customer_id, status) VALUES ('stop_1', 'route_v1', 'r1', 'u1', 'pending')")
    c.commit()

    # 2. Suspend vendor v1
    suspend_res = await admin_suspend_user('v1', SuspendIn(reason="Policy violation", level="suspend"), conn=c, user=admin_actor)
    assert suspend_res["suspended"] is True
    assert suspend_res["repooled_stops"] == 1
    assert suspend_res["detached_riders"] == 1

    # Verify vendor profile deactivated
    vp = (await c.execute("SELECT active, review_hold FROM vendor_profile WHERE user_id = 'v1'")).fetchone()
    assert vp["active"] == 0
    assert vp["review_hold"] == 1

    # Verify stop repooled (failed)
    st = (await c.execute("SELECT status FROM stops WHERE id = 'stop_1'")).fetchone()
    assert st["status"] == "failed"

    # Verify rider disassociated and session revoked
    rider_row = (await c.execute("SELECT assigned_vendor_id FROM users WHERE id = 'r1'")).fetchone()
    assert rider_row["assigned_vendor_id"] is None
    rider_sess = (await c.execute("SELECT revoked_at FROM sessions WHERE user_id = 'r1'")).fetchone()
    assert rider_sess["revoked_at"] is not None

    # Verify dispatch refuses suspended vendor
    with pytest.raises(CapacityExceededError):
        await _check_capacity(c, 'v1', need_jars=1, date=today)

    # 3. Check orphan customers
    orphans = await get_orphan_customers('v1', conn=c, user=admin_actor)
    assert orphans["count"] == 1
    assert orphans["customers"][0]["id"] == "u1"
    assert orphans["vendor_suspended"] is True

    # 4. Reassign customers to active vendor v2
    await c.execute("INSERT INTO users (id, phone, name, role, created_at) VALUES ('v2', '+919999900004', 'Vendor Two', 'vendor', datetime('now'))")
    await c.execute("INSERT INTO vendor_profile (user_id, active, review_hold) VALUES ('v2', 1, 0)")
    c.commit()

    reassign_res = await reassign_vendor_customers('v1', ReassignCustomersIn(new_vendor_id='v2', reason="Vendor 1 banned"), conn=c, user=admin_actor)
    assert reassign_res["reassigned_count"] == 1
    assert reassign_res["new_vendor_id"] == "v2"

    u1_row = (await c.execute("SELECT assigned_vendor_id FROM users WHERE id = 'u1'")).fetchone()
    assert u1_row["assigned_vendor_id"] == "v2"


@pytest.mark.asyncio
async def test_mid_cycle_sub_cancel_dues_recovery():
    conn = _setup_db()
    c = AsyncSqliteConn(conn)

    # Seed user, address, subscription
    await c.execute("INSERT INTO users (id, phone, name, role, created_at) VALUES ('u2', '+919999900005', 'Sub User', 'user', datetime('now'))")
    await c.execute("INSERT INTO addresses (id, user_id, label, formatted, pincode, created_at) VALUES ('addr_2', 'u2', 'Home', '123 Main St', '485001', datetime('now'))")
    await c.execute("INSERT INTO subscriptions (id, user_id, address_id, qty, billing_mode, status) VALUES ('sub_test', 'u2', 'addr_2', 1, 'per_delivery', 'active')")
    
    # Delivered order under this subscription that is unpaid
    await c.execute(
        "INSERT INTO orders (id, user_id, address_id, items, n, total, payment_mode, payment_status, state, window_start, idempotency_key, created_at) "
        "VALUES ('ord_sub_1', 'u2', 'addr_2', '[]', 1, 9000, 'cod', 'unpaid', 'delivered', '08:00', 'POST /v1/orders:sub:sub_test:2026-11-24', datetime('now'))"
    )
    c.commit()

    # Cancel subscription
    svc = SubscriptionService(c)
    res = await svc.cancel('u2', 'sub_test', reason="Moving away", upi_id="user@upi")
    assert res["status"] == "canceled"
    assert res["unpaid_dues_posted_paise"] == 9000

    # Verify customer ledger has dues = 9000
    led = (await c.execute("SELECT dues FROM ledger WHERE customer_id = 'u2'")).fetchone()
    assert led["dues"] == 9000

    # Verify Rider route tags amount_due = 9000 and is_monthly_dues = True
    await c.execute("INSERT INTO users (id, phone, name, role, created_at) VALUES ('v_op', '+919999900006', 'Vendor Ops', 'vendor', datetime('now'))")
    await c.execute("INSERT INTO users (id, phone, name, role, assigned_vendor_id, created_at) VALUES ('r_op', '+919999900007', 'Rider Ops', 'rider', 'v_op', datetime('now'))")
    today = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%d")
    await c.execute("INSERT INTO routes (id, vendor_id, date, status) VALUES ('route_op', 'v_op', ?, 'open')", (today,))
    await c.execute("INSERT INTO stops (id, route_id, rider_id, customer_id, order_id, status) VALUES ('stop_op', 'route_op', 'r_op', 'u2', 'ord_sub_1', 'pending')")
    c.commit()

    r_svc = RiderService(c)
    route_data = await r_svc.routes_today('r_op', date=today)
    stops = route_data["stops"]
    assert len(stops) == 1
    assert stops[0]["amount_due"] == 9000
    assert stops[0]["is_monthly_dues"] is True
