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

from app.db import get_connection, init_schema  # noqa: E402
from app.jobs.scheduler import (  # noqa: E402
    collect_reminders,
    purge_expired,
    run_due_subscriptions,
)
from app.repositories.ledger_repo import LedgerRepo  # noqa: E402
from app.services.subscription_service import SubscriptionService  # noqa: E402

MIGS = ["002_auth.sql", "003_addresses.sql", "004_orders.sql", "005_payments.sql",
        "006_aftermath.sql", "007_ops.sql"]
DAY = "2026-09-29"


def _conn():
    c = get_connection(":memory:")
    for m in MIGS:
        c.executescript((API_ROOT / "app" / "db" / "migrations" / m).read_text())
    init_schema(c)  # slice-1 config/audit_log shape
    return c


def _addr(c, user="u1", aid="a1"):
    c.execute("INSERT OR IGNORE INTO addresses(id, user_id) VALUES (?, ?)", (aid, user))
    c.commit()


def _sub(c, user="u1", next_run=DAY, qty=2, **over):
    _addr(c, user, over.get("address_id", "a1"))
    return SubscriptionService(c).create(user, {
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

def test_due_run_creates_orders_once_replay_same_day_no_dupes():
    c = _conn()
    s = _sub(c, next_run=DAY)
    out1 = run_due_subscriptions(c, DAY)
    assert len(out1["created"]) == 1 and out1["failed"] == []
    got = out1["created"][0]
    assert got["sub_id"] == s["id"] and got["user_id"] == "u1"
    assert got["total"] == 2 * 2800 + 2 * 15000  # fresh quote: water + full deposit (e=0)
    assert c.execute("SELECT COUNT(*) n FROM orders").fetchone()["n"] == 1
    out2 = run_due_subscriptions(c, DAY)  # idempotent replay
    assert out2["created"] == [] and out2["failed"] == []
    assert c.execute("SELECT COUNT(*) n FROM orders").fetchone()["n"] == 1


def test_due_run_auto_resume_fires_and_skips_failures_individually():
    c = _conn()
    svc = SubscriptionService(c)
    paused = _sub(c, next_run="2026-09-25")
    svc.pause("u1", paused["id"], "2026-09-24", "2026-09-26")  # hold_to < today
    big = _sub(c, user="u2", address_id="a2", next_run=DAY, qty=11)  # OVER_LIMIT: fails alone
    out = run_due_subscriptions(c, DAY)
    assert {r["sub_id"] for r in out["resumed"]} == {paused["id"]}
    assert svc.get_owned("u1", paused["id"])["status"] == "active"
    assert {f["sub_id"] for f in out["failed"]} == {big["id"]}
    assert out["failed"][0]["code"] == "OVER_LIMIT"
    assert {g["sub_id"] for g in out["created"]} == {paused["id"]}  # rest still created


# -- reminders ----------------------------------------------------------

def test_reminder_payloads_dues_low_balance_resume_no_sending():
    c = _conn()
    LedgerRepo(c).apply_event("u1", d_dues=5000, ref="order:o1", reason="dues carried")
    LedgerRepo(c).apply_event("u2", d_held=2, ref="stop:s1", reason="2 jars out, no deposit")
    s = _sub(c, user="u3", next_run="2026-10-10")
    SubscriptionService(c).pause("u3", s["id"], DAY, "2026-09-30")  # hold_to = today+1
    out = collect_reminders(c, DAY)
    assert [(d["user_id"], d["dues_paise"]) for d in out["dues"]] == [("u1", 5000)]
    assert out["dues"][0]["kind"] == "dues_reminder" and "fcm" in out["dues"][0]["channels"]
    assert [(l["user_id"], l["shortfall_paise"]) for l in out["low_balance"]] == [("u2", 30000)]
    assert [(r["user_id"], r["sub_id"]) for r in out["resume"]] == [("u3", s["id"])]
    assert out["total"] == 3
    for group in (out["dues"], out["low_balance"], out["resume"]):  # payloads only
        for p in group:
            assert {"kind", "user_id", "message", "channels"} <= set(p)


# -- purge --------------------------------------------------------------

def test_purge_deletes_only_expired_money_audit_survives():
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
    out = purge_expired(c)
    assert out["idempotency_72h_deleted"] == 3
    assert out["idempotency_30d_deleted"] == 1
    assert out["audit_ops_deleted"] == 1
    assert out["audit_money_deleted"] == 1
    assert out["expired_quotes"] == 0 and "stateless" in out["quotes_note"]
    left_idem = {r["scoped_key"] for r in c.execute("SELECT scoped_key FROM idempotency_keys")}
    assert left_idem == {"POST /v1/orders:k-fresh", "POST /v1/payments/upi-intent:k-mid"}
    left_audit = {(r["action"], r["entity"]) for r in c.execute("SELECT action, entity FROM audit_log")}
    assert left_audit == {("audit.read", "audit_log"), ("ledger.adjust", "ledger")}
    replay = purge_expired(c)  # idempotent: second run deletes nothing
    assert replay["idempotency_72h_deleted"] == replay["idempotency_30d_deleted"] == 0
    assert replay["audit_ops_deleted"] == replay["audit_money_deleted"] == 0
