"""011_port tests: full address format + server vendor profile/slots + stops-derived
customers + vendor complaint queue (wrong-repo Phase-1/Phase-2 gaps, ADR-055).

DB is :memory: sqlite with 002/003/004 + 011 applied, so the migration file
itself is exercised. Router tests use the REAL vendor gate (seeded sessions).
"""
import datetime as _dt
import hashlib
import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db import get_connection  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.services.vendor_service import VendorService  # noqa: E402

M002 = (API_ROOT / "src" / "app" / "db" / "migrations" / "002_auth.sql").read_text()
M003 = (API_ROOT / "src" / "app" / "db" / "migrations" / "003_addresses.sql").read_text()
M004 = (API_ROOT / "src" / "app" / "db" / "migrations" / "004_orders.sql").read_text()
M011 = (API_ROOT / "src" / "app" / "db" / "migrations" / "011_port.sql").read_text()

DAY = _dt.datetime.now(_dt.timezone.utc).date().isoformat()
FUTURE = (_dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(hours=1)).isoformat()
NOW = _dt.datetime.now(_dt.timezone.utc).isoformat()


def _conn():
    c = get_connection(":memory:")
    c.executescript(M002 + M003 + M004 + M011)
    c.execute(
        "INSERT INTO users(id, phone, name, role, created_at) VALUES "
        "('v1', '+911111111111', 'Vendor One', 'vendor', ?),"
        " ('u1', '+912222222222', 'Cust One', 'user', ?)",
        (NOW, NOW),
    )
    c.execute(
        "INSERT INTO addresses(id, user_id, type, lat, lng, pincode, created_at)"
        " VALUES ('a1', 'u1', 'home', 12.9716, 77.5946, '560001', ?)",
        (NOW,),
    )
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
        " total, payment_mode, state, window_start, idempotency_key, created_at)"
        " VALUES ('o1', 'u1', 'a1', '[]', 2, 1, 5600, 15000, 20600, 'cod',"
        " 'dispatched', '2026-10-01T08:00Z', 'seed:o1', ?)",
        (NOW,),
    )
    c.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status) VALUES ('r1', ?, 'v1', 'z1', 'open')",
        (DAY,),
    )
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status) VALUES ('s1', 'r1', 'o1', 'u1', 0, 2, 1, 1, 'pending')",
    )
    c.execute(
        "INSERT INTO complaints(id, order_id, user_id, reason_code, text, status, created_at)"
        " VALUES ('c1', 'o1', 'u1', 'short_delivery', 'one jar short', 'open', ?)",
        (NOW,),
    )
    c.commit()
    return c


def _svc(c) -> VendorService:
    return VendorService(AsyncSqliteConn(c))


# -- addresses: full format round-trip -----------------------------------------

async def test_address_full_format_roundtrip():
    from app.repositories.address_repo import AddressRepo

    c = _conn()
    repo = AddressRepo(AsyncSqliteConn(c))
    created = await repo.create("u1", {
        "type": "home", "lat": 12.9, "lng": 77.5, "pincode": "560002",
        "label": "Ghar", "formatted": "12 Main", "house": "12", "street": "Main Rd",
        "area": "Indiranagar", "phone": "9876543210",
    })
    assert created["house"] == "12" and created["area"] == "Indiranagar"
    assert created["phone"] == "9876543210"
    patched = await repo.update_owned(created["id"], "u1", {"street": "Cross Rd"})
    assert patched["street"] == "Cross Rd" and patched["house"] == "12"
    listed = await repo.list_by_user("u1")
    assert any(a["id"] == created["id"] and a["area"] == "Indiranagar" for a in listed)


# -- vendor profile + slots -----------------------------------------------------

async def test_profile_blank_then_save_then_partial():
    c = _conn()
    s = _svc(c)
    blank = await s.profile_get("v1")
    assert blank["name"] == "" and blank["updated_at"] is None
    saved = await s.profile_save("v1", {"name": "Ramu", "hours": "8-8"})
    assert saved["name"] == "Ramu" and saved["hours"] == "8-8"
    partial = await s.profile_save("v1", {"phone": "+919999999999"})
    assert partial["phone"] == "+919999999999" and partial["name"] == "Ramu"


async def test_slots_set_get_cap():
    from app.core.errors import AppError

    c = _conn()
    s = _svc(c)
    assert (await s.slots_get("v1"))["slots"] == {}
    out = await s.slots_set("v1", {"morning": True, "evening": False})
    assert out["slots"] == {"morning": True, "evening": False}
    with pytest.raises(AppError) as e:
        await s.slots_set("v1", {f"s{i}": True for i in range(51)})
    assert e.value.code == "VALIDATION"


async def test_address_fields_capped_500():
    from pydantic import ValidationError as PydanticError

    from app.repositories.address_repo import AddressRepo
    from app.schemas.addresses import AddressIn

    c = _conn()
    repo = AddressRepo(AsyncSqliteConn(c))
    long = "x" * 501
    with pytest.raises(PydanticError):
        AddressIn(type="home", lat=12.9, lng=77.5, pincode="560002", house=long)
    from app.core.errors import AppError

    with pytest.raises(AppError) as e:
        await repo.create("u1", {
            "type": "home", "lat": 12.9, "lng": 77.5, "pincode": "560002",
            "area": long,
        })
    assert e.value.code == "VALIDATION"


# -- customers from stops + complaint queue -------------------------------------

async def test_today_customers_groups_stops():
    out = await _svc(_conn()).today_customers("v1", DAY)
    assert out["date"] == DAY and len(out["customers"]) == 1
    cust = out["customers"][0]
    assert cust["customer_id"] == "u1" and cust["customer_name"] == "Cust One"
    assert cust["customer_phone"] == "+912222222222"
    assert cust["fulls_exp"] == 2 and cust["stops"][0]["stop_id"] == "s1"


async def test_vendor_complaints_queue():
    out = await _svc(_conn()).vendor_complaints("v1")
    assert [c["id"] for c in out["data"]] == ["c1"]
    assert (await _svc(_conn()).vendor_complaints("nope"))["data"] == []


# -- router ---------------------------------------------------------------------

def _client(c):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.deps import get_db_conn
    from app.api.v1.vendor import router
    from app.api.v1 import addresses as addr_mod
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    app.include_router(addr_mod.router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: AsyncSqliteConn(c)
    return TestClient(app)


def _session(c, uid, role, token):
    c.execute(
        "INSERT INTO sessions(id, user_id, token_hash, refresh_hash, role, device_fp,"
        " family_id, expires_at, created_at) VALUES (?, ?, ?, ?, ?, 'd', 'f', ?, ?)",
        (f"ses-{uid}", uid, hashlib.sha256(token.encode()).hexdigest(),
         hashlib.sha256(f"r:{token}".encode()).hexdigest(), role, FUTURE, FUTURE),
    )
    c.commit()


def test_router_new_endpoints_gated_and_roundtrip():
    c = _conn()
    _session(c, "v1", "vendor", "tok-vendor")
    _session(c, "u1", "user", "tok-user")
    client = _client(c)
    vh = {"Authorization": "Bearer tok-vendor"}
    uh = {"Authorization": "Bearer tok-user"}
    assert client.get("/v1/vendor/profile", headers=uh).status_code == 403
    assert client.get("/v1/vendor/customers", headers=uh).status_code == 403
    r = client.patch("/v1/vendor/profile", json={"name": "Ramu"}, headers=vh)
    assert r.status_code == 200 and r.json()["name"] == "Ramu"
    assert client.get("/v1/vendor/profile", headers=vh).json()["name"] == "Ramu"
    r = client.put("/v1/vendor/slots", json={"slots": {"morning": True}}, headers=vh)
    assert r.status_code == 200 and r.json()["slots"] == {"morning": True}
    r = client.get("/v1/vendor/customers", headers=vh)
    assert r.status_code == 200 and r.json()["customers"][0]["customer_id"] == "u1"
    r = client.get("/v1/vendor/complaints", headers=vh)
    assert r.status_code == 200 and [x["id"] for x in r.json()["data"]] == ["c1"]
    r = client.post("/v1/addresses", json={
        "type": "home", "lat": 12.9, "lng": 77.5, "pincode": "560002",
        "house": "12", "street": "Main Rd", "area": "Indiranagar", "phone": "9876543210",
    }, headers=uh)
    assert r.status_code == 201 and r.json()["area"] == "Indiranagar"
