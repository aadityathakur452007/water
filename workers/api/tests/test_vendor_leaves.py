"""Test vendor leaves request, admin review, and cover vendor routing fallback."""
import sys
from pathlib import Path
import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db import get_connection
from app.db_d1 import AsyncSqliteConn
from app.services.vendor_service import VendorService
from app.services.dispatch_service import route_for_vendor, least_loaded_vendor

MIGS = [
    "002_auth.sql", "003_addresses.sql", "004_orders.sql", "007_ops.sql",
    "010_config_audit.sql", "013_vendor_access.sql", "016_stop_fields.sql", "022_vendor_leaves_and_sub_cancel.sql"
]


def _conn():
    c = get_connection(":memory:")
    for m in MIGS:
        c.executescript((API_ROOT / "src" / "app" / "db" / "migrations" / m).read_text())
    return c


@pytest.mark.asyncio
async def test_vendor_leaves_and_cover_routing():
    raw = _conn()
    conn = AsyncSqliteConn(raw)

    # Seed vendor A (primary) and vendor B (cover)
    raw.execute("INSERT INTO users(id, phone, role, created_at) VALUES ('vA', '9876543210', 'vendor', '2026-09-01T00:00:00Z')")
    raw.execute("INSERT INTO users(id, phone, role, created_at) VALUES ('vB', '9876543211', 'vendor', '2026-09-01T00:00:00Z')")
    raw.execute("INSERT INTO zones(id, pincodes) VALUES ('z1', '560001')")
    raw.execute("INSERT INTO vendor_zones(vendor_id, zone_id, priority) VALUES ('vA', 'z1', 0)")
    raw.execute("INSERT INTO vendor_zones(vendor_id, zone_id, priority) VALUES ('vB', 'z1', 1)")
    raw.execute("INSERT INTO vendor_profile(user_id, active, on_duty) VALUES ('vA', 1, 1)")
    raw.execute("INSERT INTO vendor_profile(user_id, active, on_duty) VALUES ('vB', 1, 1)")
    raw.commit()

    v_svc = VendorService(conn)

    # 1. Vendor A requests leave
    leave = await v_svc.request_leave("vA", "2026-10-10", "2026-10-12", "Diwali vacation")
    assert leave["status"] == "pending"
    assert leave["vendor_id"] == "vA"

    # List leaves
    leaves = await v_svc.list_leaves("vA")
    assert len(leaves) == 1

    # 2. Before approval, route for vA goes to vA
    r_id_before = await route_for_vendor(conn, "vA", "2026-10-11")
    r_row = (await conn.execute("SELECT vendor_id FROM routes WHERE id = ?", (r_id_before,))).fetchone()
    assert r_row["vendor_id"] == "vA"

    # 3. Admin approves leave and assigns vB as cover
    await conn.execute(
        "UPDATE vendor_leaves SET status = 'approved', cover_vendor_id = 'vB' WHERE id = ?",
        (leave["id"],),
    )
    raw.commit()

    # 4. Now route for vA on 2026-10-11 automatically routes to cover vendor vB!
    r_id_after = await route_for_vendor(conn, "vA", "2026-10-11")
    r_row_after = (await conn.execute("SELECT vendor_id FROM routes WHERE id = ?", (r_id_after,))).fetchone()
    assert r_row_after["vendor_id"] == "vB"

    # 5. least_loaded_vendor for 2026-10-11 should exclude vA and pick vB
    best = await least_loaded_vendor(conn, "z1", "2026-10-11")
    assert best is not None
    assert best["vendor_id"] == "vB"
