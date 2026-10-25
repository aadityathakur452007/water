"""Scheduler job tests: due-run idempotency, auto-resume, reminders, purge.

In-memory DB with the real migration chain (002+003+004+005+006+007) plus the
landed slice-1 audit_log shape — same pattern as test_dispatch_admin.py.
"""
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.core.errors import AppError  # noqa: E402
from app.db import get_connection, init_schema  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.jobs.scheduler import (  # noqa: E402
    collect_reminders,
    cron_tick,
    purge_delivery_codes,
    purge_expired,
    run_due_subscriptions,
)
from app.repositories.ledger_repo import LedgerRepo  # noqa: E402
from app.services.order_service import OrderService  # noqa: E402
from app.services.subscription_service import SubscriptionService  # noqa: E402

MIGS = ["002_auth.sql", "003_addresses.sql", "004_orders.sql", "005_payments.sql",
        "006_aftermath.sql", "007_ops.sql", "010_config_audit.sql", "012_monthly.sql",
        "015_pod_otp.sql", "019_rate_counters.sql", "022_vendor_leaves_and_sub_cancel.sql",
        "027_pod_otp_lifecycle.sql", "028_p0_money_monthly.sql",
        "029_p0_correctness.sql"]
DAY = "2026-09-29"


def _conn():
    c = get_connection(":memory:")
    for m in MIGS:
        c.executescript((API_ROOT / "src" / "app" / "db" / "migrations" / m).read_text())
    init_schema(c)  # slice-1 config/audit_log shape
    return c


def _addr(c, user="u1", aid="a1"):
    c.execute("INSERT OR IGNORE INTO addresses(id, user_id) VALUES (?, ?)", (aid, user))
    c.commit()


async def _sub(c, user="u1", next_run=DAY, qty=2, **over):
    _addr(c, user, over.get("address_id", "a1"))
    return await SubscriptionService(AsyncSqliteConn(c)).create(user, {
        "address_id": over.get("address_id", "a1"), "qty": qty,
        "schedule_type": over.get("schedule_type", "daily"), "next_run": next_run,
        **{k: v for k, v in over.items() if k not in ("address_id",)},
    })


def _idem(c, user, scoped, age):
    ts = (datetime.now(timezone.utc) - age).isoformat()
    c.execute("INSERT INTO idempotency_keys(user_id, scoped_key, order_id, payload_hash,"
              " result, created_at) VALUES (?, ?, 'o1', 'h', '{}', ?)", (user, scoped, ts))


def _audit(c, action, entity, age):
    ts = (datetime.now(timezone.utc) - age).isoformat()
    c.execute("INSERT INTO audit_log(actor, action, entity, entity_id, trace_id, created_at)"
              " VALUES ('admin', ?, ?, 'e1', 't', ?)", (action, entity, ts))


# -- due run ------------------------------------------------------------

async def test_due_run_creates_orders_once_replay_same_day_no_dupes():
    c = _conn()
    s = await _sub(c, next_run=DAY)
    out1 = await run_due_subscriptions(AsyncSqliteConn(c), DAY)
    assert len(out1["created"]) == 1 and out1["failed"] == []
    got = out1["created"][0]
    assert got["sub_id"] == s["id"] and got["user_id"] == "u1"
    assert got["total"] == 2 * 2800  # 014: refill never deposits (e=0)
    assert c.execute("SELECT COUNT(*) n FROM orders").fetchone()["n"] == 1
    out2 = await run_due_subscriptions(AsyncSqliteConn(c), DAY)  # idempotent replay
    assert out2["created"] == [] and out2["failed"] == []
    assert c.execute("SELECT COUNT(*) n FROM orders").fetchone()["n"] == 1


async def test_due_run_auto_resume_fires_and_skips_failures_individually():
    c = _conn()
    svc = SubscriptionService(AsyncSqliteConn(c))
    paused = await _sub(c, next_run="2026-09-25")
    await svc.pause("u1", paused["id"], "2026-09-24", "2026-09-26")  # hold_to < today
    big = await _sub(c, user="u2", address_id="a2", next_run=DAY)
    # Legacy row: the create API now caps plans at 10, so seed the bad qty
    # directly to keep the scheduler's per-plan failure isolation covered.
    c.execute("UPDATE subscriptions SET qty=11 WHERE id=?", (big["id"],))
    c.commit()
    out = await run_due_subscriptions(AsyncSqliteConn(c), DAY)
    assert {r["sub_id"] for r in out["resumed"]} == {paused["id"]}
    assert (await svc.get_owned("u1", paused["id"]))["status"] == "active"
    assert {f["sub_id"] for f in out["failed"]} == {big["id"]}
    assert out["failed"][0]["code"] == "OVER_LIMIT"
    assert {g["sub_id"] for g in out["created"]} == {paused["id"]}  # rest still created


async def test_due_creation_failure_leaves_next_run_and_retries(monkeypatch):
    c = _conn()
    s = await _sub(c, next_run=DAY)
    calls = {"fail": True}
    original = OrderService.create

    async def flaky(self, *args, **kwargs):
        if calls["fail"]:
            raise AppError(message="forced creation failure", details={})
        return await original(self, *args, **kwargs)

    monkeypatch.setattr(OrderService, "create", flaky)
    out1 = await run_due_subscriptions(AsyncSqliteConn(c), DAY)
    assert out1["created"] == [] and len(out1["failed"]) == 1
    row = c.execute(
        "SELECT next_run, due_attempts, due_retry_at, due_last_error"
        " FROM subscriptions WHERE id=?", (s["id"],)).fetchone()
    assert row["next_run"] == DAY
    assert row["due_attempts"] == 1 and row["due_retry_at"] is not None
    assert "forced creation failure" in row["due_last_error"]
    assert c.execute("SELECT COUNT(*) n FROM orders").fetchone()["n"] == 0

    # Simulate the 15-minute backoff elapsing.
    c.execute("UPDATE subscriptions SET due_retry_at=NULL WHERE id=?", (s["id"],))
    c.commit()
    calls["fail"] = False
    out2 = await run_due_subscriptions(AsyncSqliteConn(c), DAY)
    assert len(out2["created"]) == 1 and out2["failed"] == []
    assert c.execute("SELECT COUNT(*) n FROM orders").fetchone()["n"] == 1
    row = c.execute(
        "SELECT next_run, due_attempts, due_retry_at FROM subscriptions WHERE id=?",
        (s["id"],)).fetchone()
    assert row["next_run"] > DAY and row["due_attempts"] == 0
    assert row["due_retry_at"] is None


async def test_due_advance_failure_replays_same_order(monkeypatch):
    c = _conn()
    s = await _sub(c, next_run=DAY)
    calls = {"fail": True}
    original = SubscriptionService.advance_due

    async def flaky(self, *args, **kwargs):
        if calls["fail"]:
            raise AppError(message="forced advance failure", details={})
        return await original(self, *args, **kwargs)

    monkeypatch.setattr(SubscriptionService, "advance_due", flaky)
    out1 = await run_due_subscriptions(AsyncSqliteConn(c), DAY)
    assert out1["created"] == [] and len(out1["failed"]) == 1
    assert c.execute("SELECT COUNT(*) n FROM orders").fetchone()["n"] == 1
    row = c.execute("SELECT next_run FROM subscriptions WHERE id=?",
                    (s["id"],)).fetchone()
    assert row["next_run"] == DAY

    c.execute("UPDATE subscriptions SET due_retry_at=NULL WHERE id=?", (s["id"],))
    c.commit()
    calls["fail"] = False
    out2 = await run_due_subscriptions(AsyncSqliteConn(c), DAY)
    assert len(out2["created"]) == 1
    assert out2["created"][0]["replayed"] is True
    assert c.execute("SELECT COUNT(*) n FROM orders").fetchone()["n"] == 1
    row = c.execute("SELECT next_run, due_attempts FROM subscriptions WHERE id=?",
                    (s["id"],)).fetchone()
    assert row["next_run"] > DAY and row["due_attempts"] == 0


async def test_due_limit_60_drains_100_subs_over_three_ticks():
    c = _conn()
    for _ in range(100):
        await _sub(c, next_run=DAY, qty=1)
    conn = AsyncSqliteConn(c)

    first = await run_due_subscriptions(conn, DAY)
    assert first["due_backlog"] == 100
    assert len(first["created"]) == 60
    assert c.execute("SELECT COUNT(*) n FROM orders").fetchone()["n"] == 60

    second = await run_due_subscriptions(conn, DAY)
    assert second["due_backlog"] == 40
    assert len(second["created"]) == 40
    assert c.execute("SELECT COUNT(*) n FROM orders").fetchone()["n"] == 100

    third = await run_due_subscriptions(conn, DAY)
    assert third["due_backlog"] == 0
    assert third["created"] == []
    assert c.execute("SELECT COUNT(*) n FROM orders").fetchone()["n"] == 100


async def test_held_range_sub_does_not_consume_the_due_page():
    c = _conn()
    held = await _sub(c, next_run=DAY, qty=1)
    due = await _sub(c, user="u2", address_id="a2", next_run=DAY, qty=1)
    c.execute("UPDATE subscriptions SET hold_from='2026-09-28', hold_to='2026-09-30'"
              " WHERE id=?", (held["id"],))
    c.commit()

    out = await run_due_subscriptions(AsyncSqliteConn(c), DAY)
    assert out["due_backlog"] == 1
    assert [g["sub_id"] for g in out["created"]] == [due["id"]]
    row = c.execute("SELECT next_run FROM subscriptions WHERE id=?",
                    (held["id"],)).fetchone()
    assert row["next_run"] == DAY


async def test_due_backoff_grows_and_caps_at_24h():
    c = _conn()
    s = await _sub(c, next_run=DAY, qty=1)
    svc = SubscriptionService(AsyncSqliteConn(c))
    delays = []
    for _ in range(9):
        out = await svc.record_due_failure(s["id"], "SERVER", "boom")
        delays.append(out["retry_after_s"])
    assert delays == [900, 1800, 3600, 7200, 14400, 28800, 57600, 86400, 86400]
    row = c.execute("SELECT due_attempts FROM subscriptions WHERE id=?",
                    (s["id"],)).fetchone()
    assert row["due_attempts"] == 9


# -- reminders ----------------------------------------------------------

async def test_reminder_payloads_dues_low_balance_resume_no_sending():
    c = _conn()
    led = LedgerRepo(AsyncSqliteConn(c))
    await led.apply_event("u1", d_dues=5000, ref="order:o1", reason="dues carried")
    await led.apply_event("u2", d_held=2, ref="stop:s1", reason="2 jars out, no deposit")
    s = await _sub(c, user="u3", next_run="2026-10-10")
    await SubscriptionService(AsyncSqliteConn(c)).pause("u3", s["id"], DAY, "2026-09-30")  # hold_to = today+1
    out = await collect_reminders(AsyncSqliteConn(c), DAY)
    assert [(d["user_id"], d["dues_paise"]) for d in out["dues"]] == [("u1", 5000)]
    assert out["dues"][0]["kind"] == "dues_reminder" and "fcm" in out["dues"][0]["channels"]
    assert [(low["user_id"], low["shortfall_paise"]) for low in out["low_balance"]] == [("u2", 30000)]
    assert [(r["user_id"], r["sub_id"]) for r in out["resume"]] == [("u3", s["id"])]
    assert out["total"] == 3
    for group in (out["dues"], out["low_balance"], out["resume"]):  # payloads only
        for p in group:
            assert {"kind", "user_id", "message", "channels"} <= set(p)


# -- purge --------------------------------------------------------------

async def test_purge_deletes_only_expired_money_audit_survives():
    c = _conn()
    _idem(c, "u1", "POST /v1/orders:k-old", timedelta(days=4))  # 72h class, expired
    _idem(c, "u1", "POST /v1/orders:k-fresh", timedelta(hours=1))  # kept
    _idem(c, "u1", "POST /v1/vendor/stops/x/triple:k-old", timedelta(days=4))  # expired
    _idem(c, "u1", "POST /v1/payments/upi-intent:k-old", timedelta(days=31))  # 30d, expired
    _idem(c, "u1", "POST /v1/payments/upi-intent:k-mid", timedelta(days=10))  # kept
    _idem(c, "u1", "POST /v1/orders/o1/cancel:k-old", timedelta(days=4))  # cancel = order write, expired
    _audit(c, "metrics.read", "metrics", timedelta(days=100))  # ops, expired
    _audit(c, "audit.read", "audit_log", timedelta(days=1))  # ops, fresh → kept
    _audit(c, "ledger.adjust", "ledger", timedelta(days=100))  # money, <1yr → kept
    _audit(c, "dues.write_off", "ledger", timedelta(days=400))  # money, >1yr → purged
    out = await purge_expired(AsyncSqliteConn(c))
    assert out["idempotency_72h_deleted"] == 3
    assert out["idempotency_30d_deleted"] == 1
    assert out["audit_ops_deleted"] == 1
    assert out["audit_money_deleted"] == 1
    assert out["expired_quotes"] == 0 and "stateless" in out["quotes_note"]
    left_idem = {r["scoped_key"] for r in c.execute("SELECT scoped_key FROM idempotency_keys")}
    assert left_idem == {"POST /v1/orders:k-fresh", "POST /v1/payments/upi-intent:k-mid"}
    left_audit = {(r["action"], r["entity"]) for r in c.execute("SELECT action, entity FROM audit_log")}
    assert left_audit == {("audit.read", "audit_log"), ("ledger.adjust", "ledger")}
    replay = await purge_expired(AsyncSqliteConn(c))  # idempotent: second run deletes nothing
    assert replay["idempotency_72h_deleted"] == replay["idempotency_30d_deleted"] == 0
    assert replay["audit_ops_deleted"] == replay["audit_money_deleted"] == 0


async def test_purge_delivery_codes_expiry_and_closed_only():
    c = _conn()
    now = datetime.now(timezone.utc)
    past = (now - timedelta(minutes=1)).isoformat()
    future = (now + timedelta(hours=12)).isoformat()
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill,"
        " deposit_due, total, payment_mode, state, window_start, idempotency_key,"
        " created_at) VALUES"
        " ('od', 'u1', 'a1', '[]', 2, 1, 5600, 0, 5600, 'cod', 'dispatched',"
        " '2026-10-01T08:00:00+00:00', 'seed:od', ?),"
        " ('oc', 'u1', 'a1', '[]', 2, 1, 5600, 0, 5600, 'cod', 'cancelled',"
        " '2026-10-01T08:00:00+00:00', 'seed:oc', ?)",
        (now.isoformat(), now.isoformat()),
    )
    c.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status)"
        " VALUES ('rd', '2026-10-01', 'v1', 'z1', 'open')"
    )
    c.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status, pod_otp, pod_otp_expires_at, triple) VALUES"
        " ('expired', 'rd', 'od', 'u1', 0, 2, 1, 1, 'pending', '111111', ?, '{}'),"
        " ('closed', 'rd', 'od', 'u1', 1, 2, 1, 1, 'done', '222222', ?,"
        "  '{\"pod\": {\"seal_ok\": true}}'),"
        " ('tripled', 'rd', 'od', 'u1', 2, 2, 1, 1, 'done', '333333', ?, '{}'),"
        " ('failed', 'rd', 'od', 'u1', 3, 2, 1, 1, 'failed', '444444', ?, '{}'),"
        " ('cancelled', 'rd', 'oc', 'u1', 0, 2, 1, 1, 'pending', '555555', ?, '{}')",
        (past, future, future, future, future),
    )
    c.commit()

    out = await purge_delivery_codes(AsyncSqliteConn(c), now)
    assert out == {"expired_cleared": 1, "terminal_cleared": 3, "reissues_deleted": 0}
    rows = {r["id"]: r for r in c.execute(
        "SELECT id, pod_otp, pod_otp_expires_at FROM stops"
    ).fetchall()}
    assert rows["expired"]["pod_otp"] is None
    assert rows["expired"]["pod_otp_expires_at"] == past  # tombstone retained
    assert rows["closed"]["pod_otp"] is None
    assert rows["failed"]["pod_otp"] is None
    assert rows["cancelled"]["pod_otp"] is None
    # Triple but no PoD yet: the customer is still at the door, keep the code.
    assert rows["tripled"]["pod_otp"] == "333333"
    assert (await purge_delivery_codes(AsyncSqliteConn(c), now)) == {
        "expired_cleared": 0, "terminal_cleared": 0, "reissues_deleted": 0}


async def test_purge_500_audit_rows_chunks_and_replays_clean():
    c = _conn()
    old = (datetime.now(timezone.utc) - timedelta(days=100)).isoformat()
    fresh = datetime.now(timezone.utc).isoformat()
    c.executemany(
        "INSERT INTO audit_log(actor, action, entity, entity_id, trace_id, created_at)"
        " VALUES ('admin', 'metrics.read', 'metrics', 'e1', 't', ?)",
        [(old,)] * 505,
    )
    c.execute(
        "INSERT INTO audit_log(actor, action, entity, entity_id, trace_id, created_at)"
        " VALUES ('admin', 'metrics.read', 'metrics', 'e1', 't', ?)", (fresh,))
    c.commit()

    out = await purge_expired(AsyncSqliteConn(c))
    assert out["audit_ops_deleted"] == 505
    assert c.execute("SELECT COUNT(*) n FROM audit_log").fetchone()["n"] == 1
    replay = await purge_expired(AsyncSqliteConn(c))
    assert replay["audit_ops_deleted"] == 0


async def test_cron_tick_summary_has_roundtrips_and_due_backlog():
    c = _conn()
    await _sub(c, next_run=DAY, qty=1)
    out = await cron_tick(AsyncSqliteConn(c), DAY)
    assert out["due"]["due_backlog"] == 1
    assert out["due"]["processed"] == 1
    assert out["db_roundtrips"] > 0
    assert out["db_queries"] >= out["db_roundtrips"]
    assert "duration_ms" in out
