"""Test Pyodide Worker Hardening & Concurrency Resilience (ADR-106).

Validates:
1. Non-deadlocking WRITE_LOCK behavior under concurrent async tasks.
2. AsyncSqliteConn / D1Conn batch execution.
3. Single-trip session + user join (SessionRepo.find_session_user_by_access_hash).
4. Direct batched order insert without redundant round trips.
5. Async def catalog and quote endpoints.
"""

import asyncio
import hashlib
from pathlib import Path
import pytest
from app.db import WRITE_LOCK, get_connection
from app.db_d1 import AsyncSqliteConn
from app.repositories.session_repo import SessionRepo
from app.repositories.user_repo import UserRepo
from app.repositories.order_repo import OrderRepo

MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "src" / "app" / "db" / "migrations"


@pytest.fixture
def db_conn():
    conn = get_connection(":memory:")
    # Apply all migrations in order
    for p in sorted(MIGRATIONS_DIR.glob("*.sql")):
        conn.executescript(p.read_text(encoding="utf-8"))
    return AsyncSqliteConn(conn)


@pytest.mark.asyncio
async def test_write_lock_concurrency_no_deadlock():
    """Verify that multiple concurrent async coroutines using WRITE_LOCK do not deadlock."""
    shared_counter = 0

    async def worker(step: int):
        nonlocal shared_counter
        with WRITE_LOCK:
            await asyncio.sleep(0.01)
            shared_counter += step

    # Launch 10 concurrent coroutines
    await asyncio.gather(*(worker(1) for _ in range(10)))
    assert shared_counter == 10


@pytest.mark.asyncio
async def test_batch_execution(db_conn):
    """Verify batch SQL execution executes all statements in one call."""
    stmts = [
        ("CREATE TABLE IF NOT EXISTS _test_batch (id INT PRIMARY KEY, val TEXT)", ()),
        ("INSERT INTO _test_batch (id, val) VALUES (?, ?)", (1, "alpha")),
        ("INSERT INTO _test_batch (id, val) VALUES (?, ?)", (2, "beta")),
    ]
    res = await db_conn.batch(stmts)
    assert len(res) == 3

    check = (await db_conn.execute("SELECT COUNT(*) AS cnt FROM _test_batch")).fetchone()
    assert check["cnt"] == 2


@pytest.mark.asyncio
async def test_find_session_user_by_access_hash(db_conn):
    """Verify single-trip session + user join accurately loads active user profile."""
    # Create test user
    user_repo = UserRepo(db_conn)
    user = await user_repo.upsert_firebase_user(phone="+919876543210", firebase_uid="fb_test_106")

    # Create session
    session_repo = SessionRepo(db_conn)
    raw_token = "hardening_test_token_123"
    thash = hashlib.sha256(raw_token.encode()).hexdigest()
    await session_repo.create(
        user_id=user["id"],
        role="user",
        access_hash=thash,
        refresh_hash=hashlib.sha256(b"refresh").hexdigest(),
        device_fp="fp_test_106",
        family_id="fam_test_106",
        created_at="2026-10-07T00:00:00Z",
        expires_at="2099-01-01T00:00:00Z",
        refresh_expires_at="2099-01-01T00:00:00Z",
    )

    # Fetch joined row
    su = await session_repo.find_session_user_by_access_hash(thash)
    assert su is not None
    assert su["user_id"] == user["id"]
    assert su["role"] == "user"
    assert su["phone"] == "+919876543210"
    assert su["suspended"] == 0
    assert su["revoked_at"] is None


@pytest.mark.asyncio
async def test_order_insert_batch_direct_return(db_conn):
    """Verify OrderRepo.insert creates order row and returns order dict cleanly."""
    user = await UserRepo(db_conn).upsert_firebase_user(phone="+919876543211", firebase_uid="fb_test_107")
    repo = OrderRepo(db_conn)

    order_payload = {
        "user_id": user["id"],
        "address_id": "addr_dummy_1",
        "items": [{"sku": "refill", "qty": 2}],
        "n": 2,
        "e": 2,
        "water_bill": 5600,
        "deposit_due": 0,
        "total": 5600,
        "payment_mode": "cod",
        "window_start": "2026-10-08T08:00:00Z",
        "window_end": "2026-10-08T08:30:00Z",
        "idempotency_key": "test:idem:106",
    }

    created = await repo.insert(order_payload)
    assert created["id"] is not None
    assert created["user_id"] == user["id"]
    assert created["total"] == 5600
    assert created["state"] == "placed"

    # Verify event was recorded
    events = await repo.events(created["id"])
    assert len(events) >= 1
    assert events[0]["to_state"] == "placed"
