"""Scheduler jobs — idempotent, infra-free (future cron/Workers Cron Trigger calls these).

Each job takes ``conn`` (DI, same seam as the services), returns a result dict,
and never sends anything itself: ``collect_reminders`` returns payloads for the
FCM/WhatsApp senders; ``run_due_subscriptions`` creates real orders.

CLI: ``python -m app.jobs.scheduler [db_path]`` runs all three + prints JSON.
"""

from __future__ import annotations

import datetime as _dt
import json
import sqlite3
import sys

from app.core.errors import AppError
from app.db import WRITE_LOCK
from app.repositories.ledger_repo import LedgerRepo
from app.repositories.order_repo import OrderRepo
from app.services import pricing
from app.services.order_service import IdempotentReplayError, OrderService
from app.services.subscription_service import SubscriptionService

# Retention (contract §0 + §2 audit note): orders/triples 72h, payments/refunds
# 30d; money audit rows 1yr, operational reads 90d.
ORDERS_RETENTION_H = 72
PAYMENTS_RETENTION_D = 30
OPS_AUDIT_RETENTION_D = 90
MONEY_AUDIT_RETENTION_D = 365

# Scoped-key classes: payments/refunds purge at 30d, everything order/triple at
# 72h (cancel keys are order writes → 72h; refund-claim keys match '%refund%').
PAY_KEY_PREFIX = "POST /v1/payments"

# audit_log rows matching these (action + entity, lowercase) are money/role/state
# writes → 1yr; everything else is an operational read → 90d.
MONEY_KEEP = ("ledger", "dues", "refund", "payment", "payout", "invoice",
              "deposit", "config", "cancel_override", "write_off")

QUOTE_TTL_MIN = 15
SUB_WINDOW_START = "08:00:00+00:00"  # subs carry free-text window; orders need an ISO slot


def _now() -> _dt.datetime:
    return _dt.datetime.now(_dt.timezone.utc)


def _rates() -> dict:
    try:
        from app.api.deps import get_settings  # noqa: PLC0415

        s = get_settings()
        return {"refill": int(s.rate_refill_paise), "container": int(s.rate_container_paise),
                "deposit": int(s.deposit_per_jar_paise)}
    except Exception:
        return {"refill": pricing.REFILL_PAISE, "container": pricing.CONTAINER_PAISE,
                "deposit": pricing.DEPOSIT_PAISE}


def _order_service(conn: sqlite3.Connection) -> OrderService:
    return OrderService(OrderRepo(conn), LedgerRepo(conn), pricing, _rates())


def run_due_subscriptions(conn: sqlite3.Connection, today: object = None) -> dict:
    """Run ``process_due`` then create one order per descriptor, fresh quote.

    Idempotent per day: ``process_due`` advances ``next_run`` (replay ⇒ empty)
    AND the order key ``sub:{sub}:{date}`` replays to the original order.
    One bad descriptor never blocks the rest (→ ``failed`` with code/message).
    """
    due = SubscriptionService(conn).process_due(today)
    date = due["date"]
    svc = _order_service(conn)
    created: list[dict] = []
    failed: list[dict] = []
    for d in due["generated"]:
        sku = str(d.get("sku_mix") or "refill").lower()
        items = [{"sku": sku if sku in ("refill", "container") else "refill", "qty": int(d["qty"])}]
        window_start = f"{d['date']}T{SUB_WINDOW_START}"
        try:
            q = pricing.compute_quote(items, 0, _rates(), address_id=d["address_id"],
                                      window_start=window_start, rate_version=pricing.RATE_VERSION)
            payload = {
                "items": items, "e": 0, "address_id": d["address_id"], "window_start": window_start,
                "quote_hash": q["quote_hash"], "quote_total": q["total"],
                "quote_rate_version": q["rate_version"],
                "quote_expires_at": (_now() + _dt.timedelta(minutes=QUOTE_TTL_MIN)).isoformat(),
                "payment_mode": d.get("payment_method") if d.get("payment_method") in ("upi", "cod") else "cod",
            }
            order = svc.create(str(d["user_id"]), payload, f"sub:{d['sub_id']}:{date}")
            created.append({"order_id": order["id"], "sub_id": d["sub_id"],
                            "user_id": d["user_id"], "total": order["total"]})
        except IdempotentReplayError as e:
            order = (e.details or {}).get("order") or {}
            created.append({"order_id": order.get("id"), "sub_id": d["sub_id"],
                            "user_id": d["user_id"], "total": order.get("total"), "replayed": True})
        except AppError as e:
            failed.append({"sub_id": d["sub_id"], "user_id": d["user_id"],
                           "code": e.code, "message": e.message})
        except Exception as e:  # never let one descriptor kill the run
            failed.append({"sub_id": d["sub_id"], "user_id": d["user_id"],
                           "code": "SERVER", "message": str(e)[:200]})
    return {"date": date, "created": created, "resumed": due["resumed"], "failed": failed}


def collect_reminders(conn: sqlite3.Connection, today: object = None) -> dict:
    """Build reminder payloads only — no sending (FCM/WhatsApp senders own that).

    dues: ledger.dues > 0 · low_balance: held jars not covered by deposit net ·
    resume: paused subs whose hold_to falls within [today, today+2d].
    """
    tday = str(today) if today is not None else _now().date().isoformat()
    horizon = (_dt.date.fromisoformat(tday) + _dt.timedelta(days=2)).isoformat()
    deposit = _rates()["deposit"]
    dues = [{"kind": "dues_reminder", "user_id": r["customer_id"], "dues_paise": int(r["dues"]),
             "message": f"Rs {int(r['dues']) / 100:.2f} due. Pay via UPI or at the door.",
             "channels": ["fcm", "whatsapp"]}
            for r in conn.execute("SELECT customer_id, dues FROM ledger WHERE dues > 0").fetchall()]
    low = []
    for r in conn.execute("SELECT customer_id, held, deposit_paid, deposit_refunded FROM ledger").fetchall():
        net = int(r["deposit_paid"]) - int(r["deposit_refunded"])
        cover = int(r["held"]) * deposit
        if int(r["held"]) > 0 and net < cover:
            low.append({"kind": "low_balance", "user_id": r["customer_id"], "held": int(r["held"]),
                        "deposit_net_paise": net, "shortfall_paise": cover - net,
                        "message": f"Deposit short by Rs {(cover - net) / 100:.2f} for {r['held']} jars held.",
                        "channels": ["fcm", "whatsapp"]})
    resume = [{"kind": "resume_reminder", "user_id": r["user_id"], "sub_id": r["id"],
               "hold_to": r["hold_to"],
               "message": f"Subscription resumes after {r['hold_to']}. Reply to extend the hold.",
               "channels": ["fcm", "whatsapp"]}
              for r in conn.execute(
                  "SELECT id, user_id, hold_to FROM subscriptions WHERE status = 'paused'"
                  " AND hold_to IS NOT NULL AND hold_to >= ? AND hold_to <= ?", (tday, horizon)).fetchall()]
    return {"date": tday, "dues": dues, "low_balance": low, "resume": resume,
            "total": len(dues) + len(low) + len(resume)}


def _cols(conn: sqlite3.Connection, table: str) -> set[str]:
    try:
        return {r["name"] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()}
    except sqlite3.OperationalError:
        return set()


def purge_expired(conn: sqlite3.Connection, now: _dt.datetime | None = None) -> dict:
    """Delete rows past retention; idempotent (replay deletes nothing new).

    Quotes are stateless (TTL enforced at POST /v1/orders) → count + note only.
    """
    now = now or _now()
    cutoff_72h = (now - _dt.timedelta(hours=ORDERS_RETENTION_H)).isoformat()
    cutoff_30d = (now - _dt.timedelta(days=PAYMENTS_RETENTION_D)).isoformat()
    cutoff_ops = (now - _dt.timedelta(days=OPS_AUDIT_RETENTION_D)).isoformat()
    cutoff_money = (now - _dt.timedelta(days=MONEY_AUDIT_RETENTION_D)).isoformat()
    pay_filter = "(scoped_key LIKE 'POST /v1/payments%' OR scoped_key LIKE '%refund%')"
    with WRITE_LOCK:
        try:
            cur = conn.execute(
                f"DELETE FROM idempotency_keys WHERE created_at < ? AND {pay_filter}", (cutoff_30d,))
            n_30d = cur.rowcount or 0
            cur = conn.execute(
                f"DELETE FROM idempotency_keys WHERE created_at < ? AND NOT {pay_filter}", (cutoff_72h,))
            n_72h = cur.rowcount or 0
        except sqlite3.OperationalError:
            n_72h = n_30d = 0
        n_ops = n_money = 0
        if "created_at" in _cols(conn, "audit_log"):
            old = conn.execute(
                "SELECT rowid AS rid, COALESCE(action,'') AS action, COALESCE(entity,'') AS entity"
                " FROM audit_log WHERE created_at < ?", (cutoff_ops,)).fetchall()
            kill_ops, maybe_money = [], []
            for r in old:
                blob = f"{r['action']} {r['entity']}".lower()
                (maybe_money if any(k in blob for k in MONEY_KEEP) else kill_ops).append(r["rid"])
            if kill_ops:
                conn.execute(f"DELETE FROM audit_log WHERE rowid IN ({','.join('?' * len(kill_ops))})",
                             kill_ops)
                n_ops = len(kill_ops)
            if maybe_money:
                ancient = conn.execute(
                    f"SELECT rowid AS rid FROM audit_log WHERE created_at < ? AND rowid IN"
                    f" ({','.join('?' * len(maybe_money))})", (cutoff_money, *maybe_money)).fetchall()
                if ancient:
                    ids = [r["rid"] for r in ancient]
                    conn.execute(f"DELETE FROM audit_log WHERE rowid IN ({','.join('?' * len(ids))})", ids)
                    n_money = len(ids)
        quotes = 0
        if "quotes" in {r[0] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'").fetchall()}:
            if "expires_at" in _cols(conn, "quotes"):
                cur = conn.execute("DELETE FROM quotes WHERE expires_at < ?", (now.isoformat(),))
                quotes = cur.rowcount or 0
        conn.commit()
    return {"idempotency_72h_deleted": n_72h, "idempotency_30d_deleted": n_30d,
            "audit_ops_deleted": n_ops, "audit_money_deleted": n_money,
            "expired_quotes": quotes,
            "quotes_note": "quotes are stateless (15-min TTL enforced at POST /v1/orders); nothing stored"}


def run_all(conn: sqlite3.Connection, today: object = None,
            now: _dt.datetime | None = None) -> dict:
    """Run every job once; returns the combined summary."""
    return {"due": run_due_subscriptions(conn, today),
            "reminders": collect_reminders(conn, today),
            "purge": purge_expired(conn, now)}


def main(argv: list[str] | None = None) -> dict:
    """CLI: ``python -m app.jobs.scheduler [db_path]`` — prints JSON summary."""
    from app.db import get_connection  # noqa: PLC0415

    args = argv if argv is not None else sys.argv[1:]
    conn = get_connection(args[0]) if args else get_connection()
    try:
        summary = run_all(conn)
    finally:
        conn.close()
    print(json.dumps(summary, default=str))
    return summary


if __name__ == "__main__":
    main()
