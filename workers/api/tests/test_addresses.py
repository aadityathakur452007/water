"""C2 slice-2 tests: addresses CRUD + IDOR + GPS/pincode guards + order lock.

Router tests run against the real B1 envelope handlers (register_exception_handlers)
with a local stub for get_current_user ONLY (C1 owns app.api.auth_deps — this file
never creates it). DB is :memory: sqlite with init_schema + 003_addresses.sql applied,
so the migration file itself is exercised. `orders` table: slice-3 owns it — tests guard
with a sqlite_master check and create a minimal table only when absent.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.db import get_connection, init_schema  # noqa: E402


def _apply_migration(conn) -> None:
    mig = Path(__file__).resolve().parents[1] / "app" / "db" / "migrations" / "003_addresses.sql"
    conn.executescript(mig.read_text())
    conn.commit()


def _make_client(user_id: str = "user_a"):
    from fastapi import FastAPI

    from app.api.v1 import addresses as mod
    from app.core.errors import register_exception_handlers

    conn = get_connection(":memory:")
    init_schema(conn)
    _apply_migration(conn)
    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(mod.router, prefix="/v1")
    state = {"user_id": user_id}

    def _stub_user():
        return {"id": state["user_id"], "role": "user"}

    def _stub_db():
        yield conn

    app.dependency_overrides[mod.get_current_user] = _stub_user
    app.dependency_overrides[mod.get_db] = _stub_db
    pytest.importorskip("httpx")
    from fastapi.testclient import TestClient

    return TestClient(app), conn, state


def _payload(**over) -> dict:
    d = {
        "type": "home",
        "lat": 12.9716,
        "lng": 77.5946,
        "accuracy_m": 10,
        "place_id": "stub-place",
        "formatted": "1 Main St",
        "landmark": "near park",
        "label": "Home",
        "pincode": "560001",
        "lift_flag": False,
    }
    d.update(over)
    return d


def _table_exists(conn, name: str) -> bool:
    return (
        conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
        ).fetchone()
        is not None
    )


def _ensure_orders_table(conn) -> None:
    if not _table_exists(conn, "orders"):
        conn.execute(
            "CREATE TABLE orders(id TEXT PRIMARY KEY, user_id TEXT, address_id TEXT, state TEXT)"
        )
        conn.commit()


def test_create_and_list():
    c, _conn, _st = _make_client()
    r = c.post("/v1/addresses", json=_payload())
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["pincode"] == "560001" and body["serviceable"] is True
    assert body["needs_pin_confirm"] is False
    r = c.post("/v1/addresses", json=_payload(type="office", label="Work"))
    assert r.status_code == 201, r.text
    r = c.get("/v1/addresses")
    assert r.status_code == 200
    assert len(r.json()) == 2


def test_update_and_delete():
    c, _conn, _st = _make_client()
    addr_id = c.post("/v1/addresses", json=_payload()).json()["id"]
    r = c.patch(f"/v1/addresses/{addr_id}", json={"landmark": "opp. metro"})
    assert r.status_code == 200, r.text
    assert r.json()["landmark"] == "opp. metro"
    r = c.delete(f"/v1/addresses/{addr_id}")
    assert r.status_code == 204, r.text
    assert c.get("/v1/addresses").json() == []
    r = c.patch(f"/v1/addresses/{addr_id}", json={"landmark": "x"})
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "NOT_FOUND"


def test_cross_user_404_idor():
    c, _conn, state = _make_client("user_a")
    addr_id = c.post("/v1/addresses", json=_payload()).json()["id"]
    state["user_id"] = "user_b"  # attacker switches identity
    r = c.patch(f"/v1/addresses/{addr_id}", json={"landmark": "hijack"})
    assert r.status_code == 404, r.text
    assert r.json()["error"]["code"] == "NOT_FOUND"  # same shape, never 403 oracle
    r = c.delete(f"/v1/addresses/{addr_id}")
    assert r.status_code == 404
    ids = [a["id"] for a in c.get("/v1/addresses").json()]
    assert addr_id not in ids  # B's list never leaks A's rows


def test_bad_pincode_400():
    c, _conn, _st = _make_client()
    for bad in ("abc", "012345", "12345"):
        r = c.post("/v1/addresses", json=_payload(pincode=bad))
        assert r.status_code == 400, (bad, r.text)
        assert r.json()["error"]["code"] == "VALIDATION"


def test_zero_zero_rejected():
    c, _conn, _st = _make_client()
    r = c.post("/v1/addresses", json=_payload(lat=0, lng=0))
    assert r.status_code == 400, r.text


def test_undispatched_order_blocks_edit():
    c, conn, _st = _make_client()
    addr_id = c.post("/v1/addresses", json=_payload()).json()["id"]
    _ensure_orders_table(conn)  # table check per brief; minimal stand-in if slice-3 absent
    conn.execute(
        "INSERT INTO orders(id, user_id, address_id, state) VALUES (?, ?, ?, ?)",
        ("o1", "user_a", addr_id, "placed"),
    )
    conn.commit()
    r = c.patch(f"/v1/addresses/{addr_id}", json={"landmark": "locked?"})
    assert r.status_code == 409, r.text
    assert r.json()["error"]["code"] == "STATE_CONFLICT"
    r = c.delete(f"/v1/addresses/{addr_id}")
    assert r.status_code == 409
    conn.execute("UPDATE orders SET state = 'delivered' WHERE id = 'o1'")
    conn.commit()
    r = c.patch(f"/v1/addresses/{addr_id}", json={"landmark": "unlocked"})
    assert r.status_code == 200, r.text
    assert r.json()["landmark"] == "unlocked"


def test_coarse_gps_sets_pin_flag():
    c, _conn, _st = _make_client()
    r = c.post("/v1/addresses", json=_payload(accuracy_m=150))
    assert r.status_code == 201, r.text
    assert r.json()["needs_pin_confirm"] is True
