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

M002 = (API_ROOT / "src" / "app" / "db" / "migrations" / "002_auth.sql").read_text()
M003 = (API_ROOT / "src" / "app" / "db" / "migrations" / "003_addresses.sql").read_text()
M004 = (API_ROOT / "src" / "app" / "db" / "migrations" / "004_orders.sql").read_text()
M005 = (API_ROOT / "src" / "app" / "db" / "migrations" / "005_payments.sql").read_text()
M007 = (API_ROOT / "src" / "app" / "db" / "migrations" / "007_ops.sql").read_text()
M010 = (API_ROOT / "src" / "app" / "db" / "migrations" / "010_config_audit.sql").read_text()
M014 = (API_ROOT / "src" / "app" / "db" / "migrations" / "014_access_codes.sql").read_text()
M015 = (API_ROOT / "src" / "app" / "db" / "migrations" / "015_pod_otp.sql").read_text()
M016 = (API_ROOT / "src" / "app" / "db" / "migrations" / "016_stop_fields.sql").read_text()
M019 = (API_ROOT / "src" / "app" / "db" / "migrations" / "019_rate_counters.sql").read_text()
M024 = (API_ROOT / "src" / "app" / "db" / "migrations" / "024_user_assigned_vendor.sql").read_text()
M027 = (API_ROOT / "src" / "app" / "db" / "migrations" / "027_pod_otp_lifecycle.sql").read_text()
M028 = (API_ROOT / "src" / "app" / "db" / "migrations" / "028_p0_money_monthly.sql").read_text()
M029 = (API_ROOT / "src" / "app" / "db" / "migrations" / "029_p0_correctness.sql").read_text()
M030 = (API_ROOT / "src" / "app" / "db" / "migrations" / "030_rider_dispatch.sql").read_text()

DAY = (_dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(hours=5, minutes=30)).date().isoformat()
NOW_ISO = _dt.datetime.now(_dt.timezone.utc).isoformat()
POD_OTP = "654321"
POD_EXPIRY = (_dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(hours=12)).isoformat()


def _hash(t: str) -> str:
    return hashlib.sha256(t.encode()).hexdigest()


def _seed_db():
    c = get_connection(":memory:")
    c.executescript(
        M002 + M003 + M004 + M005 + M007 + M010 + M014 + M015 + M016 + M019 + M024 + M027 + M028 + M029 + M030
    )
    # Enable access codes if needed
    c.execute("INSERT OR REPLACE INTO config (key, value) VALUES ('access_code_login_enabled', '1')")

    # Seed vendor, customer, and rider
    c.execute(
        "INSERT INTO users (id, phone, name, role, created_at) VALUES "
        "('v1', '+919876500001', 'Vendor Alpha', 'vendor', ?), "
        "('u1', '+919876500002', 'Customer Ram', 'user', ?), "
        "('r1', '+919876500003', 'Rider Shyam', 'rider', ?)",
        (NOW_ISO, NOW_ISO, NOW_ISO),
    )
    c.execute("UPDATE users SET assigned_vendor_id = 'v1' WHERE id = 'r1'")

    # Seed address with lift flag
    c.execute(
        "INSERT INTO addresses (id, user_id, type, label, formatted, landmark, pincode, lift_flag, created_at) "
        "VALUES ('a1', 'u1', 'home', 'Home', 'Flat 402, Royal Palms, MP Nagar', 'Near Bank', '462001', 1, ?)",
        (NOW_ISO,),
    )

    # Seed order with POD OTP
    c.execute(
        "INSERT INTO orders (id, user_id, address_id, items, n, e, water_bill, deposit_due, total, payment_mode, payment_status, state, window_start, idempotency_key, created_at) "
        "VALUES ('o1', 'u1', 'a1', '[]', 2, 1, 14000, 0, 14000, 'cod', 'unpaid', 'dispatched', ?, 'seed:o1', ?)",
        (NOW_ISO, NOW_ISO),
    )

    # Seed route and stop
    c.execute(
        "INSERT INTO routes (id, date, vendor_id, zone, status) VALUES ('route-1', ?, 'v1', 'zone-a', 'open')",
        (DAY,),
    )
    c.execute(
        "INSERT INTO stops (id, route_id, order_id, customer_id, seq, fulls_exp, empties_exp, status, pod_otp, pod_otp_expires_at, pod_attempts, rider_id) "
        "VALUES ('stop-1', 'route-1', 'o1', 'u1', 1, 2, 2, 'pending', ?, ?, 0, 'r1')",
        (POD_OTP, POD_EXPIRY),
    )

    # Seed the vendor-issued rider sign-in code (plaintext 135790)
    c.execute(
        "INSERT INTO access_codes (id, user_id, code_hash, masked_hint, expected_role, "
        "expires_at, revoked_at, last_used_at, created_by, created_at) "
        "VALUES ('ac-r1', 'r1', ?, '••90', 'rider', ?, NULL, NULL, 'v1', ?)",
        (_hash("135790"), POD_EXPIRY, NOW_ISO),
    )

    # Seed auth sessions
    c.execute(
        "INSERT INTO sessions (id, user_id, role, device_fp, token_hash, refresh_hash, family_id, expires_at, refresh_expires_at, session_expires_at, created_at) "
        "VALUES ('sess-v1', 'v1', 'vendor', 'dev-v1', ?, 'ref-v1', 'fam-v1', ?, ?, ?, ?), "
        "('sess-r1', 'r1', 'rider', 'dev-r1', ?, 'ref-r1', 'fam-r1', ?, ?, ?, ?)",
        (_hash("token-vendor"), POD_EXPIRY, POD_EXPIRY, POD_EXPIRY, NOW_ISO,
         _hash("token-rider"), POD_EXPIRY, POD_EXPIRY, POD_EXPIRY, NOW_ISO),
    )
    c.commit()
    return c


def _client(conn):
    app = create_app()
    app.dependency_overrides[get_db_conn] = lambda: AsyncSqliteConn(conn)
    return TestClient(app)


def test_rider_login_unregistered():
    conn = _seed_db()
    client = _client(conn)
    res = client.post(
        "/v1/auth/rider/login",
        json={"phone": "9999999999", "name": "Unknown", "code": "135790",
              "device": {"id": "device-1"}},
    )
    assert res.status_code == 401
    # Generic message: the door must not reveal whether the number exists.
    assert "invalid credentials" in res.json()["error"]["message"].lower()


def test_rider_login_success():
    conn = _seed_db()
    client = _client(conn)
    res = client.post(
        "/v1/auth/rider/login",
        json={"phone": "9876500003", "name": "Rider Shyam", "code": "135790",
              "device": {"id": "device-1"}},
    )
    assert res.status_code == 200
    data = res.json()
    assert "access_token" in data
    assert data["role"] == "rider"
    assert data["user_id"] == "r1"


def test_vendor_onboard_and_list_riders():
    conn = _seed_db()
    client = _client(conn)
    # Vendor onboards new rider
    res = client.post(
        "/v1/vendor/riders",
        headers={"Authorization": "Bearer token-vendor"},
        json={"name": "Kailash Delivery", "phone": "9876543210"},
    )
    assert res.status_code == 201
    rider_data = res.json()
    assert rider_data["name"] == "Kailash Delivery"
    assert rider_data["phone"] == "+919876543210"
    assert rider_data["vendor_id"] == "v1"

    # Vendor lists riders
    res_list = client.get(
        "/v1/vendor/riders",
        headers={"Authorization": "Bearer token-vendor"},
    )
    assert res_list.status_code == 200
    riders = res_list.json()["data"]
    assert any(r["phone"] == "+919876543210" for r in riders)
    assert any(r["phone"] == "+919876500003" for r in riders)


def test_rider_routes_today():
    conn = _seed_db()
    client = _client(conn)
    res = client.get(
        "/v1/rider/routes/today",
        headers={"Authorization": "Bearer token-rider"},
    )
    assert res.status_code == 200
    data = res.json()
    assert data["summary"]["total"] == 1
    assert data["summary"]["pending"] == 1
    assert len(data["stops"]) == 1

    stop = data["stops"][0]
    assert stop["id"] == "stop-1"
    assert stop["customer_name"] == "Customer Ram"
    assert stop["quantity"] == 2
    assert stop["amount_due"] == 14000
    assert stop["address"]["has_lift"] is True
    assert "Royal Palms" in stop["address"]["formatted"]


def test_rider_complete_stop_wrong_otp():
    conn = _seed_db()
    client = _client(conn)
    res = client.post(
        "/v1/rider/stops/stop-1/complete",
        headers={"Authorization": "Bearer token-rider"},
        json={"delivery_otp": "000000", "empties_count": 2, "cash": 140},
    )
    assert res.status_code in (400, 404, 422)


def test_rider_complete_stop_success():
    conn = _seed_db()
    client = _client(conn)
    res = client.post(
        "/v1/rider/stops/stop-1/complete",
        headers={"Authorization": "Bearer token-rider"},
        json={"delivery_otp": "654321", "empties_count": 2, "cash": 140},
    )
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "delivered"
    assert data["stop_id"] == "stop-1"

    # Verify stop is marked done in today's route
    res_today = client.get(
        "/v1/rider/routes/today",
        headers={"Authorization": "Bearer token-rider"},
    )
    assert res_today.status_code == 200
    assert res_today.json()["summary"]["delivered"] == 1
    assert res_today.json()["summary"]["pending"] == 0


def test_rider_pod_validation_ssdlc():
    conn = _seed_db()
    client = _client(conn)
    # Non-numeric OTP rejected by Pydantic validation
    res = client.post(
        "/v1/rider/stops/stop-1/complete",
        headers={"Authorization": "Bearer token-rider"},
        json={"delivery_otp": "abcd12", "empties_count": 2, "cash": 140},
    )
    assert res.status_code == 400


def test_rider_cannot_complete_other_rider_stop():
    conn = _seed_db()
    # Explicitly assign stop-1 to a different rider 'rider-other'
    conn.execute("UPDATE stops SET rider_id = 'rider-other' WHERE id = 'stop-1'")
    conn.commit()

    client = _client(conn)
    # rider-1 tries to complete rider-other's stop -> 404
    res = client.post(
        "/v1/rider/stops/stop-1/complete",
        headers={"Authorization": "Bearer token-rider"},
        json={"delivery_otp": "654321", "empties_count": 2, "cash": 140},
    )
    assert res.status_code == 404
    assert "Stop not found" in res.json().get("detail", "") or "Stop not found" in res.json().get("error", {}).get("message", "")


def test_rider_completes_unassigned_links_rider():
    conn = _seed_db()
    # Stop-1 is unassigned (rider_id IS NULL)
    conn.execute("UPDATE stops SET rider_id = NULL WHERE id = 'stop-1'")
    conn.commit()

    client = _client(conn)
    res = client.post(
        "/v1/rider/stops/stop-1/complete",
        headers={"Authorization": "Bearer token-rider"},
        json={"delivery_otp": "654321", "empties_count": 2, "cash": 140},
    )
    assert res.status_code == 200

    # Verify stop is now linked to rider-1
    row = conn.execute("SELECT rider_id FROM stops WHERE id = 'stop-1'").fetchone()
    assert row["rider_id"] == "r1"


def test_rider_unmasked_phone_and_empties_cap():
    conn = _seed_db()
    # Customer u1 holds 1 jar, orders 10 jars -> max_empties must be 1
    conn.execute(
        "INSERT OR REPLACE INTO ledger (customer_id, held, dues) "
        "VALUES ('u1', 1, 0)"
    )
    conn.execute("UPDATE stops SET fulls_exp = 10 WHERE id = 'stop-1'")
    conn.commit()
    client = _client(conn)
    res = client.get("/v1/rider/routes/today", headers={"Authorization": "Bearer token-rider"})
    assert res.status_code == 200
    stop = res.json()["stops"][0]
    assert stop["customer_phone"] == "+919876500002"
    assert stop["jars_held"] == 1
    assert stop["max_empties"] == 1


def test_rider_active_sub_zero_cash_and_deduped_cancelled_dues():
    conn = _seed_db()
    # Seed ledger dues = 9000 (Rs 90) and a second stop for the same customer u1
    conn.execute(
        "INSERT OR REPLACE INTO ledger (customer_id, held, dues) "
        "VALUES ('u1', 2, 9000)"
    )
    conn.execute(
        "INSERT INTO orders (id, user_id, address_id, items, n, water_bill, deposit_due, total, "
        "payment_mode, payment_status, state, window_start, window_end, idempotency_key, created_at) "
        "VALUES ('ord-2', 'u1', 'addr-1', '[{\"sku\":\"refill\",\"qty\":1}]', 1, 7000, 0, 7000, 'cod', 'unpaid', 'assigned', "
        f"'{DAY}T07:00:00+00:00', '{DAY}T12:00:00+00:00', 'idem-ord-2', '{NOW_ISO}')"
    )
    conn.execute(
        "INSERT INTO stops (id, route_id, order_id, customer_id, seq, fulls_exp, empties_exp, "
        "status, pod_otp, pod_otp_expires_at, pod_attempts, rider_id) "
        "VALUES ('stop-2', 'route-1', 'ord-2', 'u1', 2, 1, 1, 'pending', '1234', '2099-01-01T00:00:00+00:00', 0, 'r1')"
    )
    # Case 1: Active monthly subscription -> ₹0 due on both stops
    conn.execute(
        "INSERT INTO subscriptions (id, user_id, address_id, qty, status) "
        "VALUES ('sub-1', 'u1', 'addr-1', 1, 'active')"
    )
    conn.commit()
    client = _client(conn)
    res1 = client.get("/v1/rider/routes/today", headers={"Authorization": "Bearer token-rider"})
    assert res1.status_code == 200
    stops1 = res1.json()["stops"]
    assert all(s["amount_due"] == 0 and not s["is_monthly_dues"] for s in stops1)

    # Case 2: Inactive/paused/cancelled subscription -> dues shown ONLY on first pending stop, not duplicated
    conn.execute("UPDATE subscriptions SET status = 'paused' WHERE id = 'sub-1'")
    conn.commit()
    res2 = client.get("/v1/rider/routes/today", headers={"Authorization": "Bearer token-rider"})
    assert res2.status_code == 200
    stops2 = res2.json()["stops"]
    assert stops2[0]["is_monthly_dues"] is True
    assert stops2[0]["amount_due"] == 14000  # max(14000 order, 9000 dues)
    assert stops2[1]["is_monthly_dues"] is False
    assert stops2[1]["amount_due"] == 7000  # only order_amt, NOT duplicated 9000 dues!
