"""C3 orders slice tests: repos + service + router (contract §2 state machine, §10 matrix).

Service/repo tests run in-memory with 004_orders.sql applied. Router tests run a
minimal app (orders router + central handlers) with get_db overridden — main.py
wiring is left for the integrator (other agents own it).
"""
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.core.errors import AppError  # noqa: E402
from app.db import get_connection  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.repositories.ledger_repo import HoldNegativeError, LedgerRepo  # noqa: E402
from app.repositories.order_repo import (  # noqa: E402
    AlreadyCancelledError,
    NeedDispatchOverrideError,
    OrderRepo,
)
from app.services import pricing  # noqa: E402
from app.services.order_service import (  # noqa: E402
    HoldBlockedError,
    IdempotentReplayError,
    OrderService,
    OverLimitError,
    PayloadMismatchError,
    StaleQuoteError,
)

MIGRATION = (API_ROOT / "src" / "app" / "db" / "migrations" / "004_orders.sql").read_text()

WINDOW = "2026-10-01T08:00:00+00:00"


def _rates() -> dict:
    from app.api.deps import get_settings

    s = get_settings()
    return {"refill": s.rate_refill_paise, "container": s.rate_container_paise, "deposit": s.deposit_per_jar_paise}


def _conn():
    c = get_connection(":memory:")
    c.executescript(MIGRATION)
    return c


def _w(c):
    return c if isinstance(c, AsyncSqliteConn) else AsyncSqliteConn(c)


def _svc(c) -> OrderService:
    return OrderService(OrderRepo(_w(c)), LedgerRepo(_w(c)), pricing, _rates())


def _payload(items=None, e=1, **over) -> dict:
    items = items if items is not None else [{"sku": "refill", "qty": 2}]
    q = pricing.compute_quote(items, e, _rates(), address_id="a1", window_start=WINDOW,
                              rate_version=pricing.RATE_VERSION)
    base = {
        "items": items,
        "e": e,
        "address_id": "a1",
        "window_start": WINDOW,
        "quote_hash": q["quote_hash"],
        "quote_total": q["total"],
        "quote_rate_version": q["rate_version"],
        "quote_expires_at": (datetime.now(timezone.utc) + timedelta(minutes=15)).isoformat(),
        "payment_mode": "cod",
    }
    base.update(over)
    return base


# -- create ---------------------------------------------------------------

# 014: refill never deposits; container deposits once, waived after.
async def test_create_ok_freezes_server_totals():
    c = _conn()
    o = await _svc(c).create("u1", _payload(), "k1")
    assert o["state"] == "placed" and o["total"] == 5600
    assert o["idempotency_key"] == "POST /v1/orders:k1"  # scoped key stored
    led = await LedgerRepo(_w(c)).get("u1")
    assert led["deposit_paid"] == 0
    assert (await OrderRepo(_w(c)).events(o["id"]))[0]["to_state"] == "placed"


async def test_container_first_deposit_then_waived():
    c = _conn()
    s = _svc(c)
    cont = _payload(items=[{"sku": "container", "qty": 1}], e=0)
    o1 = await s.create("u1", cont, "kc1")
    assert o1["deposit_due"] == 15000
    led = await LedgerRepo(_w(c)).get("u1")
    assert led["deposit_paid"] == 15000
    # Second container: pre-waiver quote still accepted, order waives to 0.
    o2 = await s.create("u1", cont, "kc2")
    assert o2["deposit_due"] == 0 and o2["total"] == 3000


async def test_stale_quote_409():
    cases = [
        _payload(quote_total=1),  # tampered total
        _payload(quote_expires_at="2020-01-01T00:00:00+00:00"),  # expired
        _payload(quote_rate_version="v9"),  # rate version moved on
    ]
    for i, p in enumerate(cases):
        c = _conn()
        with pytest.raises(StaleQuoteError) as e:
            await _svc(c).create("u1", p, f"k{i}")
        assert e.value.code == "STALE_QUOTE" and e.value.status_code == 409


async def test_over_limit_and_hold_blocked_422():
    c = _conn()
    s = _svc(c)
    big = [{"sku": "refill", "qty": 10}, {"sku": "container", "qty": 1}]
    with pytest.raises(OverLimitError) as e:
        await s.create("u1", _payload(items=big, e=0), "k1")
    assert e.value.code == "OVER_LIMIT" and e.value.status_code == 422
    await LedgerRepo(_w(c)).apply_event("u2", d_held=4, ref="test:seed", reason="held 4 jars")
    with pytest.raises(HoldBlockedError) as e2:
        await s.create("u2", _payload(), "k2")
    assert e2.value.code == "HOLD_BLOCKED" and e2.value.status_code == 422


async def test_idempotent_replay_returns_same_order():
    c = _conn()
    s = _svc(c)
    p = _payload()
    o1 = await s.create("u1", p, "k1")
    with pytest.raises(IdempotentReplayError) as e:
        await s.create("u1", p, "k1")
    assert e.value.code == "IDEMPOTENT_REPLAY" and e.value.details["order"]["id"] == o1["id"]
    assert c.execute("SELECT COUNT(*) c FROM orders").fetchone()["c"] == 1


async def test_payload_mismatch_422():
    c = _conn()
    s = _svc(c)
    await s.create("u1", _payload(), "k1")
    with pytest.raises(PayloadMismatchError) as e:
        await s.create("u1", _payload(payment_mode="upi"), "k1")  # same key, changed body
    assert e.value.code == "PAYLOAD_MISMATCH" and e.value.status_code == 422


# -- cancel (§10) ----------------------------------------------------------

async def test_create_cancel_void_unpaid_bill_zero_deposit_reversed():
    c = _conn()
    s = _svc(c)
    o = await s.create("u1", _payload(), "k1")
    out = await s.cancel("u1", o["id"], "changed mind", "c1")
    assert out == {"order_id": o["id"], "state": "cancelled", "bill_total": 0,
                   "deposit_reversed": 0, "refund": None}
    led = await LedgerRepo(_w(c)).get("u1")
    assert (led["deposit_paid"], led["deposit_refunded"]) == (0, 0)
    assert c.execute("SELECT COUNT(*) c FROM refunds").fetchone()["c"] == 0


async def test_double_cancel_same_key_same_outcome_single_refund_row():
    c = _conn()
    s = _svc(c)
    o = await s.create("u1", _payload(), "k1")
    c.execute("UPDATE orders SET payment_status = 'paid_upi' WHERE id = ?", (o["id"],))
    c.commit()
    out1 = await s.cancel("u1", o["id"], "changed mind", "c1")
    assert out1["refund"]["status"] == "pending" and out1["refund"]["amount"] == o["total"]
    out2 = await s.cancel("u1", o["id"], "changed mind", "c1")  # idempotent replay
    assert out2 == out1
    assert c.execute("SELECT COUNT(*) c FROM refunds").fetchone()["c"] == 1


async def test_double_cancel_new_key_already_cancelled_same_outcome():
    c = _conn()
    s = _svc(c)
    o = await s.create("u1", _payload(), "k1")
    await s.cancel("u1", o["id"], "r1", "c1")
    with pytest.raises(AlreadyCancelledError) as e:
        await s.cancel("u1", o["id"], "r2", "c2")
    assert e.value.code == "ALREADY_CANCELLED" and e.value.status_code == 409
    assert e.value.details["bill_total"] == 0  # same outcome, no new writes


async def test_cancel_assigned_needs_dispatcher():
    c = _conn()
    s = _svc(c)
    o = await s.create("u1", _payload(), "k1")
    r = OrderRepo(_w(c))
    for to in ("accepted", "picked", "packed", "assigned"):
        await r.transition(o["id"], to, {"id": "admin", "role": "admin"}, "ops")
    with pytest.raises(NeedDispatchOverrideError) as e:
        await s.cancel("u1", o["id"], "too late", "c1")
    assert e.value.code == "NEED_DISPATCH_OVERRIDE"
    assert (await r.transition(o["id"], "cancelled", {"id": "d1", "role": "dispatcher"}, "override"))["state"] == "cancelled"


# -- machine + reschedule ---------------------------------------------------

async def test_illegal_transition_409():
    c = _conn()
    o = await _svc(c).create("u1", _payload(), "k1")
    with pytest.raises(AppError) as e:
        await OrderRepo(_w(c)).transition(o["id"], "delivered", {"id": "u1", "role": "user"}, "skip")
    assert e.value.code == "STATE_CONFLICT" and e.value.status_code == 409


async def test_reschedule_pre_dispatch_ok_post_dispatch_409():
    c = _conn()
    s = _svc(c)
    r = OrderRepo(_w(c))
    o = await s.create("u1", _payload(), "k1")
    moved = await s.reschedule("u1", o["id"], "2026-10-01T09:00:00+00:00")
    assert moved["window_start"] == "2026-10-01T09:00:00+00:00" and moved["window_end"] != ""
    for to in ("accepted", "picked", "packed", "assigned", "dispatched"):
        await r.transition(o["id"], to, {"id": "admin", "role": "admin"}, "ops")
    with pytest.raises(AppError) as e:
        await s.reschedule("u1", o["id"], "2026-10-01T10:00:00+00:00")
    assert e.value.code == "STATE_CONFLICT" and e.value.status_code == 409


async def test_cross_user_404_no_oracle():
    c = _conn()
    s = _svc(c)
    o = await s.create("u1", _payload(), "k1")
    assert await OrderRepo(_w(c)).find_owned(o["id"], "u2") is None
    with pytest.raises(AppError) as e:
        await s.detail("u2", o["id"])
    assert e.value.code == "NOT_FOUND" and e.value.status_code == 404


async def test_ledger_never_negative_422():
    c = _conn()
    with pytest.raises(HoldNegativeError) as e:
        await LedgerRepo(_w(c)).apply_event("u1", d_held=-1, ref="test:x", reason="no jars held")
    assert e.value.status_code == 422


# -- router -----------------------------------------------------------------

def _client(c, user="u1"):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.deps import get_db_conn
    from app.api.v1.orders import get_current_user as orders_guard
    from app.api.v1.orders import router
    from app.core.errors import register_exception_handlers
    from app.db_d1 import AsyncSqliteConn

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: AsyncSqliteConn(c)
    # Real session auth (C1) retired the X-User-Id stub: canned user per test.
    app.dependency_overrides[orders_guard] = lambda: {
        "id": user, "role": "user", "phone": "+919000000000",
        "suspended": False, "session_id": "s", "family_id": "f",
        "device_fp": "d",
    }
    client = TestClient(app)
    return client


def test_router_missing_idempotency_key_400():
    client = _client(_conn())
    r = client.post("/v1/orders", json=_payload())
    assert r.status_code == 400 and r.json()["error"]["code"] == "VALIDATION"


def test_router_create_replay_and_cross_user():
    c = _conn()
    client = _client(c)
    p = _payload()
    r1 = client.post("/v1/orders", json=p, headers={"Idempotency-Key": "k1"})
    assert r1.status_code == 201, r1.text
    assert r1.json()["state"] == "placed"
    r2 = client.post("/v1/orders", json=p, headers={"Idempotency-Key": "k1"})
    assert r2.status_code == 409
    assert r2.json()["error"]["code"] == "IDEMPOTENT_REPLAY"
    assert r2.json()["error"]["details"]["order"]["id"] == r1.json()["id"]
    oid = r1.json()["id"]
    assert client.get(f"/v1/orders/{oid}").status_code == 200
    body = client.get(f"/v1/orders/{oid}").json()
    assert body["tracker"]["current"] == "placed" and body["bill"]["total"] == 5600
    assert body["rider"] is None and isinstance(body["events"], list)
    other = _client(c, user="u2")
    assert other.get(f"/v1/orders/{oid}").status_code == 404  # not-yours == not-found


# F1: delivery OTP rides order detail for the owner while a stop is active.
async def test_detail_delivery_otp_visibility_matrix():
    from app.services.vendor_service import pod_otp

    c = _conn()
    now = datetime.now(timezone.utc).isoformat()
    day = "2026-10-03"
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
        " total, payment_mode, state, window_start, idempotency_key, created_at)"
        " VALUES ('od', 'u1', 'a1', '[]', 2, 1, 5600, 15000, 20600, 'cod', 'dispatched', ?, 'seed:od', ?),"
        " ('op', 'u1', 'a1', '[]', 2, 1, 5600, 15000, 20600, 'cod', 'placed', ?, 'seed:op', ?),"
        " ('of', 'u1', 'a1', '[]', 2, 1, 5600, 15000, 20600, 'cod', 'delivered', ?, 'seed:of', ?)",
        (WINDOW, now, WINDOW, now, WINDOW, now),
    )
    c.execute("INSERT INTO routes(id, date, vendor_id, zone, status) VALUES ('rd', ?, 'v1', 'z1', 'open')", (day,))
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status) VALUES ('sd', 'rd', 'od', 'u1', 0, 2, 1, 1, 'pending')")
    c.commit()
    s = _svc(c)
    assert (await s.detail("u1", "od"))["delivery_otp"] == pod_otp("od", day)
    assert (await s.detail("u1", "op"))["delivery_otp"] is None  # no stop yet
    assert (await s.detail("u1", "of"))["delivery_otp"] is None  # terminal
    with pytest.raises(AppError):  # not-yours == not-found, no OTP oracle
        await s.detail("u9", "od")


def test_router_list_pagination_cancel_reschedule():
    c = _conn()
    client = _client(c)
    ids = [client.post("/v1/orders", json=_payload(), headers={"Idempotency-Key": f"k{i}"}).json()["id"]
           for i in range(3)]
    page1 = client.get("/v1/orders", params={"limit": 2}).json()
    assert len(page1["data"]) == 2 and page1["next_cursor"]
    page2 = client.get("/v1/orders", params={"limit": 2, "cursor": page1["next_cursor"]}).json()
    assert len(page2["data"]) == 1 and page2["next_cursor"] is None
    assert {o["id"] for o in page1["data"]} | {o["id"] for o in page2["data"]} == set(ids)
    cancel = client.post(f"/v1/orders/{ids[0]}/cancel", json={"reason": "no need"},
                         headers={"Idempotency-Key": "c1"})
    assert cancel.status_code == 200 and cancel.json()["bill_total"] == 0
    re = client.post(f"/v1/orders/{ids[1]}/reschedule", json={"window_start": "2026-10-01T09:00:00+00:00"})
    assert re.status_code == 200 and re.json()["window_start"] == "2026-10-01T09:00:00+00:00"
