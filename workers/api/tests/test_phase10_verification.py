"""Phase 10 verification gap tests (ADR-092): the §10.1 rows with no prior
proof — sync 200-scale + ordering, sync replay vs changed server state,
rate-limit cross-isolate via D1, triple parallel same-key. Backend-only,
existing harness shapes, no new fixtures.
"""
import asyncio
import datetime as _dt
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
M005 = (API_ROOT / "src" / "app" / "db" / "migrations" / "005_payments.sql").read_text()
M007 = (API_ROOT / "src" / "app" / "db" / "migrations" / "007_ops.sql").read_text()
M019 = (API_ROOT / "src" / "app" / "db" / "migrations" / "019_rate_counters.sql").read_text()

NOW = _dt.datetime.now(_dt.timezone.utc).isoformat()
DAY = _dt.datetime.now(_dt.timezone.utc).date().isoformat()


def _conn(n_stops=0):
    c = get_connection(":memory:")
    c.executescript(M002 + M003 + M004 + M005 + M007)
    c.execute(
        "INSERT INTO users(id, phone, role, created_at) VALUES "
        "('v1', '+911111111111', 'vendor', ?), ('u1', '+912222222222', 'user', ?)",
        (NOW, NOW),
    )
    c.execute(
        "INSERT INTO addresses(id, user_id, type, lat, lng, pincode, created_at)"
        " VALUES ('a1', 'u1', 'home', 12.9716, 77.5946, '560001', ?)", (NOW,),
    )
    for i in range(max(n_stops, 1)):
        oid = f"o{i}"
        c.execute(
            "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
            " total, payment_mode, state, window_start, idempotency_key, created_at)"
            " VALUES (?, 'u1', 'a1', '[]', 2, 1, 5600, 15000, 20600, 'cod',"
            " 'dispatched', '2026-10-01T08:00Z', ?, ?)",
            (oid, f"seed:{oid}", NOW),
        )
    c.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status) VALUES ('r1', ?, 'v1', 'z1', 'open')",
        (DAY,),
    )
    for i in range(n_stops):
        c.execute(
            "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
            " empties_exp, version, status) VALUES (?, 'r1', ?, 'u1', ?, 2, 1, 1, 'pending')",
            (f"s{i}", f"o{i}", i),
        )
    c.commit()
    return c


def _triple(**over):
    base = {"fulls_given": 2, "empties_back": 1, "cash": 0, "upi": 0,
            "caps_missing": 0, "version": 1}
    base.update(over)
    return base


# -- §10.1: sync_batch 200-row scale + partial ordering --------------------------

async def test_sync_batch_200_mixed_buckets_keep_input_order():
    """200 items (router cap): 100 fresh → applied, 50 same-payload replays,
    50 stale versions → rejected; each bucket preserves input order and the
    ledger shows exactly the 100 fresh applies (no double-apply)."""
    c = _conn(150)
    svc = VendorService(AsyncSqliteConn(c))
    items = []
    for i in range(100):
        items.append({"stop_id": f"s{i}", **_triple()})
    for i in range(50):
        items.append({"stop_id": f"s{i}", **_triple()})  # same payload → replay
    for i in range(100, 150):
        items.append({"stop_id": f"s{i}", **_triple(version=999)})  # stale → reject
    out = await svc.sync_batch("v1", items)
    assert out["applied"] == [f"s{i}" for i in range(100)]
    assert out["replayed"] == [f"s{i}" for i in range(50)]
    assert [r["stop_id"] for r in out["rejected"]] == [f"s{i}" for i in range(100, 150)]
    assert all(r["code"] == "STALE_STOP" for r in out["rejected"])
    held = c.execute("SELECT held FROM ledger WHERE customer_id = 'u1'").fetchone()[0]
    assert held == 100  # 100 × (2 fulls − 1 empty), replays add nothing


# -- §10.1: outbox replay vs changed server state -----------------------------------

async def test_sync_replay_after_server_reassign_rejects_no_double_apply():
    """Queued triple (v1) applied; server reassigns (version bump, triple
    cleared); the vendor edits offline and syncs the same-version payload →
    STALE_STOP rejected, ledger untouched (server wins, never double-apply)."""
    c = _conn(1)
    svc = VendorService(AsyncSqliteConn(c))
    first = await svc.sync_batch("v1", [{"stop_id": "s0", **_triple()}])
    assert first["applied"] == ["s0"]
    held_after_first = c.execute("SELECT held FROM ledger WHERE customer_id = 'u1'").fetchone()[0]
    # Server-side change: dispatch reassign bumps the fence and clears the row.
    c.execute("UPDATE stops SET version = 2, triple = NULL, status = 'pending' WHERE id = 's0'")
    c.commit()
    out = await svc.sync_batch("v1", [{"stop_id": "s0", **_triple(fulls_given=3)}])
    assert out["applied"] == [] and out["replayed"] == []
    assert len(out["rejected"]) == 1 and out["rejected"][0]["code"] == "STALE_STOP"
    held = c.execute("SELECT held FROM ledger WHERE customer_id = 'u1'").fetchone()[0]
    assert held == held_after_first


# -- §10.1: rate-limit cross-isolate (fresh L1, D1 truth denies) ---------------------

async def test_rate_limit_cross_isolate_d1_denies_with_fresh_l1():
    """Simulates a second isolate: L1 reset (empty), D1 holds 5 counts →
    the 6th attempt still 429s from D1 truth with Retry-After details."""
    from app.core.errors import RateLimitedError  # noqa: PLC0415
    from app.services.auth_service import AuthService, reset_rate_limits  # noqa: PLC0415

    reset_rate_limits()
    c = _conn()
    c.executescript(M019)
    c.commit()
    phone, ip = "+919876543210", "9.9.9.9"
    svc = AuthService(AsyncSqliteConn(c))
    for _ in range(5):
        await svc.otp_start(phone, ip)
    # Fresh isolate: new service instance + empty L1.
    reset_rate_limits()
    fresh = AuthService(AsyncSqliteConn(c))
    with pytest.raises(RateLimitedError) as exc:
        await fresh.otp_start(phone, ip)
    assert exc.value.details["retry_after_s"] >= 1
    reset_rate_limits()


# -- §10.1: triple parallel same-key (twin of the Phase 8 cash test) ------------------

async def test_triple_concurrent_same_key_single_apply():
    """Concurrent duplicate triple commits: one applies, the other replays
    the stored outcome; the ledger shows a single effect."""
    c = _conn(1)
    svc = VendorService(AsyncSqliteConn(c))
    payload = _triple()
    results = await asyncio.gather(
        svc.triple_commit("v1", "s0", dict(payload), "k-triple-1"),
        svc.triple_commit("v1", "s0", dict(payload), "k-triple-1"),
        return_exceptions=True,
    )
    ok = [r for r in results if not isinstance(r, Exception)]
    # Sequential event loop: the loser replays the stored outcome (triple's
    # keyed replay returns the stored dict bare — no "replay" flag, unlike
    # the keyless same-payload path). Single ledger effect either way.
    assert len(ok) == 2 and ok[0] == ok[1]
    held = c.execute("SELECT held FROM ledger WHERE customer_id = 'u1'").fetchone()[0]
    assert held == 1  # single (2 − 1) effect
