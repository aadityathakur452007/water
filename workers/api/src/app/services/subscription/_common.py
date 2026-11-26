"""Subscription service — pause / resume / skip / due-run (contract §4.5, EC-S).

Business rules ONLY (python card: services stay DB-agnostic in spirit; SQL is
kept here because the D3 file list allows no new repository file — same
precedent as ``OrderService._idem_get/_idem_put`` touching the connection).

Tiers stay NULL in v1 (tier/discount_pct/perks never written). All dates are
ISO-8601 strings; hold/skip/next_run compare as YYYY-MM-DD; the resume guard
compares full UTC datetimes.

Tunables (contract §8 open until survey): SKIP_CUTOFF_HOUR, RESUME_LEAD_HOURS.
"""

from __future__ import annotations

import datetime as _dt
import sqlite3

from app.core.errors import AppError
from app.db_d1 import AsyncSqliteConn, D1Conn

Conn = D1Conn | AsyncSqliteConn

RESUME_LEAD_HOURS = 24  # Bisleri rule: resume needs >=24h notice (E2)
SKIP_CUTOFF_HOUR = 18  # after 18:00 UTC a same-day skip is late (tunable, §8)

# Phase 7 F4: the only schedules the runner understands (_advance steps
# daily/alternate/weekly/custom; anything else stalls at step 0 forever).
SCHEDULE_TYPES = ("daily", "alternate", "weekly", "custom")
MAX_PLAN_JARS = 10  # same household hard stop as one-time orders


class SubNotFoundError(AppError):
    code = "NOT_FOUND"
    status_code = 404


class SubValidationError(AppError):
    code = "VALIDATION"
    status_code = 400


class ResumeTooSoonError(AppError):
    code = "RESUME_TOO_SOON"
    status_code = 422


class InsufficientCreditError(AppError):
    code = "INSUFFICIENT_CREDIT"
    status_code = 409


from app.core.time_utils import parse_utc_dt as _parse_dt, utc_now as _now  # noqa: F401

def _parse_day(v: object) -> str | None:
    """Any ISO date/datetime -> 'YYYY-MM-DD', else None."""
    if isinstance(v, _dt.date) and not isinstance(v, _dt.datetime):
        return v.isoformat()
    dt = _parse_dt(v)
    if dt is None:
        return None
    return dt.date().isoformat()


def _advance(day: _dt.date, schedule: str, recurrence: str) -> _dt.date:
    step = {"daily": 1, "alternate": 2, "weekly": 7, "monthly": 30}.get((schedule or "").lower(), 0)
    if (schedule or "").lower() == "custom":
        try:
            step = int((recurrence or "7").strip() or "7")
        except (ValueError, AttributeError):
            step = 7
    if step < 1:
        step = 1
    nxt = day + _dt.timedelta(days=step)
    while nxt.weekday() == 6:  # scheduler never generates Sundays (8-8 Sun-closed)
        nxt += _dt.timedelta(days=1)
    return nxt


def _row(r: sqlite3.Row) -> dict:
    return dict(r)


BILLING_MODES = ("per_delivery", "monthly_prepaid", "monthly_postpaid", "daily_bill", "weekly_postpaid")
PAYMENT_METHODS = ("upi", "cod")


_BILLING_COLS = (
    ("billing_mode", "TEXT NOT NULL DEFAULT 'per_delivery'"),
    ("billing_status", "TEXT NOT NULL DEFAULT 'active'"),
    ("credit_balance_paise", "INTEGER NOT NULL DEFAULT 0"),
    ("refund_upi", "TEXT NOT NULL DEFAULT ''"),
)

_billing_ready = False


def reset_billing_mode_cache() -> None:  # tests only
    global _billing_ready
    _billing_ready = False


async def _ensure_billing_mode(conn: Conn) -> None:
    """026/028 convergence: apply-once ALTERs for old DBs (PRAGMA + conditional).

    Precedent: vendor_profile ensure convergence (ADR-065) — ALTER is
    apply-once, CREATE would no-op on the real table. Keeps :memory: test DBs
    built from 004-only harnesses working without a migration run.

    The probe runs once per isolate: migrations are static at runtime, so a
    ready schema costs 0 queries on later calls.
    """
    global _billing_ready
    if _billing_ready:
        return
    try:
        cols = (await conn.execute("PRAGMA table_info(subscriptions)")).fetchall()
        names = {str(dict(r).get("name", "")) for r in cols}
    except Exception:
        return
    if all(name in names for name, _ in _BILLING_COLS):
        _billing_ready = True
        return
    for name, ddl in _BILLING_COLS:
        if name in names:
            continue
        try:
            await conn.execute(f"ALTER TABLE subscriptions ADD COLUMN {name} {ddl}")  # noqa: S608
            conn.commit()
        except Exception:
            try:
                conn.rollback()
            except Exception:
                pass
    # Confirm once: a swallowed ALTER error must not mark a broken schema ready.
    try:
        cols = (await conn.execute("PRAGMA table_info(subscriptions)")).fetchall()
        names = {str(dict(r).get("name", "")) for r in cols}
        _billing_ready = all(name in names for name, _ in _BILLING_COLS)
    except Exception:
        pass


def _due_today(qty: object, sku_mix: object) -> int:
    """Today's dues preview: qty x rate (container 3000, else refill 2800).

    Paid/previous dues stay with GET /billing/dues (no new endpoint here).
    """
    from app.services import pricing  # noqa: PLC0415 (leaf module, no cycle)

    try:
        q = max(0, int(qty or 0))  # type: ignore[arg-type]
    except (TypeError, ValueError):
        q = 0
    rate = pricing.CONTAINER_PAISE if str(sku_mix or "").strip().lower() == "container" else pricing.REFILL_PAISE
    return q * rate


def _monthly_estimate(qty: object, sku_mix: object) -> int:
    """026: 30-day prepaid estimate (qty x rate x 30). Postpaid settles dues."""
    return _due_today(qty, sku_mix) * 30


