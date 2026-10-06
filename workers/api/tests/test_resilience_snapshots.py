"""Tests for resilience, address freezing, damaged container accounting, and RTO stop failure."""
import json
import sys
from pathlib import Path
import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db import get_connection
from app.db_d1 import AsyncSqliteConn
from app.repositories.address_repo import AddressRepo
from app.repositories.order_repo import OrderRepo
from app.repositories.ledger_repo import LedgerRepo
from app.services import pricing
from app.services.order_service import OrderService
from app.services.vendor_service import VendorService
from app.services.dispatch_service import route_for_vendor

MIGS = [
    "002_auth.sql", "003_addresses.sql", "004_orders.sql", "005_payments.sql",
    "006_aftermath.sql", "007_ops.sql", "010_config_audit.sql", "011_port.sql",
    "013_vendor_access.sql", "016_stop_fields.sql", "022_vendor_leaves_and_sub_cancel.sql",
    "023_resilience_and_snapshots.sql"
]


def _conn():
    c = get_connection(":memory:")
    for m in MIGS:
        c.executescript((API_ROOT / "src" / "app" / "db" / "migrations" / m).read_text())
    return c


def _order_svc(conn) -> OrderService:
    rates = {"refill": 8000, "container": 15000, "deposit": 15000}
    return OrderService(OrderRepo(conn), LedgerRepo(conn), pricing, rates)


@pytest.mark.asyncio
async def test_address_snapshot_preservation_on_edit():
    raw = _conn()
    conn = AsyncSqliteConn(raw)

    # 1. Seed user and address
    raw.execute("INSERT INTO users(id, phone, name, role, created_at) VALUES ('u1', '9999999999', 'Ramesh', 'user', '2026-09-01T00:00:00Z')")
    raw.execute("INSERT INTO users(id, phone, name, role, created_at) VALUES ('v1', '8888888888', 'Vendor Vijay', 'vendor', '2026-09-01T00:00:00Z')")
    raw.execute("INSERT INTO zones(id, pincodes) VALUES ('z1', '560001')")
    raw.execute("INSERT INTO vendor_zones(vendor_id, zone_id, priority) VALUES ('v1', 'z1', 0)")
    raw.execute("INSERT INTO vendor_profile(user_id, active, on_duty) VALUES ('v1', 1, 1)")
    
    addr_repo = AddressRepo(conn)
    addr = await addr_repo.create("u1", {
        "type": "home",
        "lat": 12.9716,
        "lng": 77.5946,
        "formatted": "Flat 402, Sunshine Apts, MG Road, Bengaluru",
        "pincode": "560001",
        "label": "Home",
        "house": "402",
        "street": "Sunshine Apts",
        "area": "MG Road",
        "phone": "9999999999",
    })
    addr_id = addr["id"]
    raw.commit()

    # 2. Place order with address
    o_svc = _order_svc(conn)
    rates = {"refill": 8000, "container": 15000, "deposit": 15000}
    q = pricing.compute_quote(
        [{"sku": "refill", "qty": 1}],
        1,
        rates,
        address_id=addr_id,
        window_start="2026-10-15T08:00:00Z",
        rate_version=pricing.RATE_VERSION,
    )
    order = await o_svc.create("u1", {
        "items": [{"sku": "refill", "qty": 1}],
        "e": 1,
        "address_id": addr_id,
        "window_start": "2026-10-15T08:00:00Z",
        "quote_hash": q["quote_hash"],
        "quote_total": q["total"],
        "quote_rate_version": q["rate_version"],
        "quote_expires_at": "2026-10-15T09:00:00Z",
        "payment_mode": "cod",
    }, "idem_order_1")
    order_id = order["id"]

    # 3. User updates their profile address to a totally different place
    raw.execute("""
        UPDATE addresses
        SET formatted = 'Villa 10, New Horizon, Chennai', pincode = '600001'
        WHERE id = ?
    """, (addr_id,))
    raw.commit()

    # Verify the order's frozen snapshot did NOT mutate
    detail = await o_svc.detail("u1", order_id)
    assert detail["delivery_address"] is not None
    assert detail["delivery_address"]["formatted"] == "Flat 402, Sunshine Apts, MG Road, Bengaluru"
    assert detail["delivery_address"]["pincode"] == "560001"

    # 4. Check vendor's today route stop overlays the frozen address
    r_id = await route_for_vendor(conn, "v1", "2026-10-15")
    raw.execute("""
        INSERT INTO stops(id, route_id, order_id, customer_id, seq, status)
        VALUES ('stop_1', ?, ?, 'u1', 1, 'pending')
    """, (r_id, order_id))
    raw.commit()

    v_svc = VendorService(conn)
    route_data = await v_svc.today_route("v1", "2026-10-15")
    assert len(route_data["stops"]) == 1
    stop = route_data["stops"][0]
    assert stop["address_text"] == "Flat 402, Sunshine Apts, MG Road, Bengaluru"
    assert stop["pincode"] == "560001"
    assert stop["customer_name"] == "Ramesh"


@pytest.mark.asyncio
async def test_damaged_empties_triple_commit():
    raw = _conn()
    conn = AsyncSqliteConn(raw)

    raw.execute("INSERT INTO users(id, phone, role, created_at) VALUES ('u2', '9999999998', 'user', '2026-09-01T00:00:00Z')")
    raw.execute("INSERT INTO users(id, phone, role, created_at) VALUES ('v2', '8888888887', 'vendor', '2026-09-01T00:00:00Z')")
    raw.execute("INSERT INTO vendor_profile(user_id, active, on_duty) VALUES ('v2', 1, 1)")
    # Customer currently holds 3 empty containers in ledger
    raw.execute("INSERT INTO ledger(customer_id, held, deposit_paid) VALUES ('u2', 3, 45000)")
    raw.execute("""
        INSERT INTO orders(id, user_id, address_id, items, n, payment_mode, window_start, idempotency_key, state, created_at)
        VALUES ('ord_2', 'u2', 'dummy_addr', '[{"sku":"refill","qty":2}]', 2, 'cod', '2026-10-06T08:00:00Z', 'idem_ord_2', 'dispatched', '2026-10-06T00:00:00Z')
    """)

    r_id = await route_for_vendor(conn, "v2", "2026-10-06")
    raw.execute("""
        INSERT INTO stops(id, route_id, order_id, customer_id, seq, status, version)
        VALUES ('stop_2', ?, 'ord_2', 'u2', 1, 'pending', 1)
    """, (r_id,))
    raw.commit()

    v_svc = VendorService(conn)
    # Delivered 2 new jars, customer returned 2 bottles, but 1 is badly cracked/damaged!
    result = await v_svc.triple_commit(
        "v2", "stop_2",
        {
            "fulls_given": 2,
            "empties_back": 2,
            "damaged_empties": 1,
            "empty_condition": "Cracked base / leaking",
            "cash": 16000,
            "version": 1
        },
        idempotency_key="idem_test_damaged_1"
    )

    assert result["status"] == "done"
    assert result["triple"]["damaged_empties"] == 1
    assert result["triple"]["empty_condition"] == "cracked base / leaking"

    # Held math:
    # Started with 3 held.
    # fulls_given = 2.
    # usable_empties = 2 - 1 = 1.
    # d_held = 2 - 1 = +1.
    # new held = 3 + 1 = 4 (customer still owes for the broken jar).
    held_row = (await conn.execute("SELECT held FROM ledger WHERE customer_id = 'u2'")).fetchone()
    assert held_row["held"] == 4

    # Verify damaged_containers audit table
    dmg_row = (await conn.execute("SELECT * FROM damaged_containers WHERE stop_id = 'stop_2'")).fetchone()
    assert dmg_row is not None
    assert dmg_row["qty"] == 1
    assert dmg_row["condition"] == "cracked base / leaking"
    assert dmg_row["vendor_id"] == "v2"


@pytest.mark.asyncio
async def test_fail_stop_rto_flow():
    raw = _conn()
    conn = AsyncSqliteConn(raw)

    raw.execute("INSERT INTO users(id, phone, role, created_at) VALUES ('u3', '9999999997', 'user', '2026-09-01T00:00:00Z')")
    raw.execute("INSERT INTO users(id, phone, role, created_at) VALUES ('v3', '8888888886', 'vendor', '2026-09-01T00:00:00Z')")
    raw.execute("INSERT INTO vendor_profile(user_id, active, on_duty) VALUES ('v3', 1, 1)")
    raw.execute("""
        INSERT INTO orders(id, user_id, address_id, items, n, payment_mode, window_start, idempotency_key, state, created_at)
        VALUES ('ord_3', 'u3', 'dummy_addr', '[{"sku":"refill","qty":1}]', 1, 'cod', '2026-10-06T08:00:00Z', 'idem_ord_3', 'dispatched', '2026-10-06T00:00:00Z')
    """)

    r_id = await route_for_vendor(conn, "v3", "2026-10-06")
    raw.execute("""
        INSERT INTO stops(id, route_id, order_id, customer_id, seq, status, version)
        VALUES ('stop_3', ?, 'ord_3', 'u3', 1, 'pending', 1)
    """, (r_id,))
    raw.commit()

    v_svc = VendorService(conn)
    fail_res = await v_svc.fail_stop(
        "v3", "stop_3",
        reason_code="DOOR_LOCKED",
        note="Tried calling 3 times, door locked."
    )

    assert fail_res["status"] == "failed"
    assert "DOOR_LOCKED" in fail_res["failure_reason"]

    # Verify stop in DB
    stop_row = (await conn.execute("SELECT status, failure_reason FROM stops WHERE id = 'stop_3'")).fetchone()
    assert stop_row["status"] == "failed"
    assert "DOOR_LOCKED" in stop_row["failure_reason"]

    # Verify order state transitioned to failed
    ord_row = (await conn.execute("SELECT state FROM orders WHERE id = 'ord_3'")).fetchone()
    assert ord_row["state"] == "failed"
