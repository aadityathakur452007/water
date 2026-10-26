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
import hashlib
import json
import sqlite3
import uuid

from app.core.errors import AppError
from app.db import WRITE_LOCK
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


def _now() -> _dt.datetime:
    return _dt.datetime.now(_dt.timezone.utc)


def _parse_dt(v: object) -> _dt.datetime | None:
    if isinstance(v, _dt.datetime):
        dt = v
    elif isinstance(v, str):
        try:
            dt = _dt.datetime.fromisoformat(v)
        except ValueError:
            return None
    else:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=_dt.timezone.utc)
    return dt


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


BILLING_MODES = ("per_delivery", "monthly_prepaid", "monthly_postpaid")
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


class SubscriptionService:
    """Owner-scoped subscription use-cases (IDOR: miss -> 404, no oracle)."""

    def __init__(self, conn: Conn):
        self._conn = conn

    async def estimate_first_cycle(self, user_id: str, qty: int, sku_mix: str) -> dict:
        """Phase 7 F5: server first-cycle amount (water + once-only deposit).

        Same math the doorstep order will carry: dominant-SKU water bill +
        container deposit unless the wallet already holds one. Pure read —
        the sheet shows this on Pay instead of client math.
        """
        from app.repositories.ledger_repo import LedgerRepo  # noqa: PLC0415 (lazy, light)
        from app.services import pricing  # noqa: PLC0415 (leaf module, no cycle)

        q = max(0, int(qty or 0))
        sku = "container" if str(sku_mix or "").strip().lower() == "container" else "refill"
        try:
            from app.api.deps import get_settings  # noqa: PLC0415 (cached global)

            s = get_settings()
            rates = {"refill": int(s.rate_refill_paise), "container": int(s.rate_container_paise),
                     "deposit": int(s.deposit_per_jar_paise)}
        except Exception:
            rates = {"refill": pricing.REFILL_PAISE, "container": pricing.CONTAINER_PAISE,
                     "deposit": pricing.DEPOSIT_PAISE}
        try:
            paid = int((await LedgerRepo(self._conn).get(user_id)).get("deposit_paid", 0))
        except Exception:
            paid = 0
        quote = pricing.compute_quote([{"sku": sku, "qty": q}], 0, rates,
                                      deposit_already_paid_paise=paid)
        return {"water_bill": quote["water_bill"], "deposit_due": quote["deposit_due"],
                "total": quote["total"], "rate_version": quote["rate_version"],
                # Monthly prepaid charges water only; the jar deposit stays a
                # first-delivery charge so cancelling cannot strand it.
                "monthly_topup_paise": int(quote["water_bill"]) * 30}

    # -- create / list ----------------------------------------------------

    async def create(self, user_id: str, payload: dict, idempotency_key: str = "") -> dict:
        qty = int(payload.get("qty", 0))
        if qty < 1:
            raise SubValidationError(message="Quantity must be >= 1.", details={})
        if qty > MAX_PLAN_JARS:
            raise SubValidationError(
                message="Maximum 10 jars per plan. Reduce the quantity.",
                details={"qty": qty, "max": MAX_PLAN_JARS})
        address_id = str(payload.get("address_id") or "").strip()
        if not address_id:
            raise SubValidationError(message="address_id required.", details={})
        if not await self._owned_address(user_id, address_id):
            raise SubNotFoundError(message="Address not found.", details={"id": address_id})
        schedule = str(payload.get("schedule_type") or "daily")
        if schedule not in SCHEDULE_TYPES:
            raise SubValidationError(
                message=f"schedule_type must be one of {', '.join(SCHEDULE_TYPES)}.",
                details={"schedule_type": schedule})
        recurrence = str(payload.get("recurrence") or "")
        payment_method = str(payload.get("payment_method") or "cod").strip().lower()
        if payment_method not in PAYMENT_METHODS:
            raise SubValidationError(
                message="payment_method must be upi or cod.",
                details={"payment_method": payment_method})
        billing_mode = str(payload.get("billing_mode") or "per_delivery").strip().lower()
        if billing_mode not in BILLING_MODES:
            raise SubValidationError(
                message="billing_mode must be per_delivery, monthly_prepaid or monthly_postpaid.",
                details={"billing_mode": billing_mode})
        if billing_mode in ("monthly_prepaid", "monthly_postpaid") and payment_method != "upi":
            raise SubValidationError(
                message="Monthly plans are paid by UPI.",
                details={"billing_mode": billing_mode, "payment_method": payment_method})
        key = (idempotency_key or "").strip()
        scoped = f"POST /v1/subscriptions:{key}" if key else ""
        idem_phash = hashlib.sha256(json.dumps(
            {"a": address_id, "q": qty, "s": schedule, "r": recurrence,
             "p": payment_method, "b": billing_mode},
            sort_keys=True).encode()).hexdigest() if key else ""
        if key:
            # Double-tap guard: same sheet-open key replays the minted row.
            row = (await self._conn.execute(
                "SELECT payload_hash, result FROM idempotency_keys WHERE user_id=? AND scoped_key=?",
                (user_id, scoped),
            )).fetchone()
            if row is not None:
                if row["payload_hash"] != idem_phash:
                    from app.repositories.payment_repo import PayloadMismatchError  # noqa: PLC0415 (lazy, light)

                    raise PayloadMismatchError(
                        message="Idempotency-Key was already used with a different payload.",
                        details={"user_id": user_id})
                out = json.loads(row["result"])
                out["first_cycle_estimate"] = await self.estimate_first_cycle(
                    user_id, qty, payload.get("sku_mix"))
                return out
        next_run = _parse_day(payload.get("next_run")) or self._default_next_run()
        await _ensure_billing_mode(self._conn)
        sub = {
            "id": uuid.uuid4().hex,
            "user_id": user_id,
            "address_id": address_id,
            "qty": qty,
            "sku_mix": str(payload.get("sku_mix") or "refill"),
            "window": str(payload.get("window") or ""),
            "next_run": next_run,
            "schedule_type": schedule,
            "recurrence": recurrence,
            "payment_method": payment_method,
            "billing_mode": billing_mode,
            "billing_status": "pending_payment" if billing_mode == "monthly_prepaid" else "active",
            "status": "active",
        }
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "INSERT INTO subscriptions(id, user_id, address_id, qty, sku_mix, window,"
                    " next_run, schedule_type, recurrence, payment_method, billing_mode,"
                    " billing_status, credit_balance_paise,"
                    " tier, discount_pct, perks, status, hold_from, hold_to)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0,"
                    " NULL, NULL, NULL, 'active', NULL, NULL)",
                    (sub["id"], user_id, address_id, qty, sub["sku_mix"], sub["window"],
                     next_run, schedule, recurrence, sub["payment_method"], sub["billing_mode"],
                     sub["billing_status"]),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        out = await self.get_owned(user_id, sub["id"]) or sub
        out["first_cycle_estimate"] = await self.estimate_first_cycle(
            user_id, qty, payload.get("sku_mix"))
        if key:
            with WRITE_LOCK:
                try:
                    await self._conn.execute(
                        "INSERT OR IGNORE INTO idempotency_keys(user_id, scoped_key, order_id,"
                        " payload_hash, result, created_at) VALUES (?,?,?,?,?,?)",
                        (user_id, scoped, sub["id"], idem_phash,
                         json.dumps(out), _dt.datetime.now(_dt.timezone.utc).isoformat()),
                    )
                    self._conn.commit()
                except Exception:
                    self._conn.rollback()
                    raise
        return out

    async def list(self, user_id: str) -> list[dict]:
        await _ensure_billing_mode(self._conn)
        rows = (await self._conn.execute(
            "SELECT * FROM subscriptions WHERE user_id = ? ORDER BY rowid", (user_id,)
        )).fetchall()
        return [self._decorate_sub(_row(r)) for r in rows]

    async def get_owned(self, user_id: str, sub_id: str) -> dict | None:
        await _ensure_billing_mode(self._conn)
        row = (await self._conn.execute(
            "SELECT * FROM subscriptions WHERE id = ? AND user_id = ?", (sub_id, user_id)
        )).fetchone()
        return self._decorate_sub(_row(row)) if row is not None else None

    @staticmethod
    def _decorate_sub(d: dict) -> dict:
        if d.get("canceled_at"):
            d["status"] = "canceled"
        d.setdefault("billing_mode", "per_delivery")
        d.setdefault("payment_method", "cod")
        d.setdefault("billing_status", "active")
        d.setdefault("credit_balance_paise", 0)
        due_today = _due_today(d.get("qty"), d.get("sku_mix"))
        d["due_today_paise"] = due_today
        d["monthly_estimate_paise"] = _monthly_estimate(d.get("qty"), d.get("sku_mix"))
        d["low_balance"] = bool(
            d.get("billing_mode") == "monthly_prepaid"
            and not d.get("canceled_at")
            and int(d.get("credit_balance_paise") or 0) < due_today
        )
        return d

    # -- monthly prepaid billing ------------------------------------------

    async def begin_charge(self, user_id: str, sub_id: str, idem_key: str) -> dict:
        """Reserve one prepaid top-up BEFORE calling Razorpay.

        One open charge per plan (partial unique index) makes a double tap
        return the same link instead of minting two provider orders.
        """
        from app.repositories.payment_repo import (  # noqa: PLC0415 (lazy, cycle-safe)
            IntentPendingError, PayloadMismatchError, _intent_link as _link, _stale,
        )

        key = (idem_key or "").strip()
        if not key:
            raise SubValidationError(message="Idempotency-Key header required.", details={})
        sub = await self.get_owned(user_id, sub_id)
        if sub is None:
            raise SubNotFoundError(message="Subscription not found.", details={"id": sub_id})
        if sub.get("canceled_at"):
            raise SubValidationError(message="Cannot top up a canceled subscription.",
                                     details={"id": sub_id})
        if sub.get("billing_mode") != "monthly_prepaid":
            raise SubValidationError(message="Subscription is not monthly prepaid.",
                                     details={"id": sub_id})
        if sub.get("payment_method") != "upi":
            raise SubValidationError(message="Prepaid top-ups are paid by UPI.", details={})
        amount = int((await self.estimate_first_cycle(
            user_id, int(sub["qty"]), sub.get("sku_mix")))["monthly_topup_paise"])
        if amount <= 0:
            raise SubValidationError(message="Nothing to charge.", details={})
        scoped = f"POST /v1/payments/subscription-intent:{key}"
        phash = hashlib.sha256(f"{sub_id}:{amount}".encode()).hexdigest()
        now = _dt.datetime.now(_dt.timezone.utc).isoformat()
        with WRITE_LOCK:
            stored = (await self._conn.execute(
                "SELECT payload_hash, result, created_at FROM idempotency_keys"
                " WHERE user_id=? AND scoped_key=?", (user_id, scoped))).fetchone()
            if stored is not None:
                if stored["payload_hash"] != phash:
                    raise PayloadMismatchError(
                        message="Idempotency-Key was already used with a different payload.",
                        details={"subscription_id": sub_id})
                result = json.loads(stored["result"] or "{}")
                if result.get("pending"):
                    cached = (await self._conn.execute(
                        "SELECT * FROM subscription_charges WHERE id=?",
                        (result.get("charge_id"),))).fetchone()
                    if cached is not None and cached.get("provider_ref"):
                        charge = dict(cached)
                        result = {"charge": charge,
                                  "link": charge.get("provider_link") or _link(
                                      str(charge["provider_ref"]), int(charge["amount"])),
                                  "provider_ref": charge["provider_ref"]}
                        await self._conn.execute(
                            "UPDATE idempotency_keys SET result=? WHERE user_id=? AND scoped_key=?",
                            (json.dumps(result), user_id, scoped))
                        self._conn.commit()
                        return result
                    if not _stale(stored["created_at"]):
                        raise IntentPendingError(
                            message="Payment link is still being created.",
                            details={"subscription_id": sub_id})
                    await self._conn.execute(
                        "DELETE FROM idempotency_keys WHERE user_id=? AND scoped_key=?",
                        (user_id, scoped))
                    await self._conn.execute(
                        "DELETE FROM subscription_charges WHERE id=? AND status='pending'",
                        (result.get("charge_id"),))
                else:
                    return result
            open_row = (await self._conn.execute(
                "SELECT * FROM subscription_charges WHERE subscription_id=?"
                " AND status IN ('pending','link_sent') ORDER BY created_at DESC LIMIT 1",
                (sub_id,))).fetchone()
            if open_row is not None:
                charge = dict(open_row)
                if charge["status"] == "link_sent" and charge.get("provider_ref"):
                    result = {"charge": charge,
                              "link": charge.get("provider_link") or _link(
                                  str(charge["provider_ref"]), int(charge["amount"])),
                              "provider_ref": charge["provider_ref"]}
                    await self._conn.execute(
                        "INSERT OR IGNORE INTO idempotency_keys(user_id, scoped_key, order_id,"
                        " payload_hash, result, created_at) VALUES (?,?,?,?,?,?)",
                        (user_id, scoped, charge["id"], phash, json.dumps(result), now))
                    self._conn.commit()
                    return result
                if not _stale(charge["created_at"]):
                    raise IntentPendingError(
                        message="A top-up is already being created.",
                        details={"subscription_id": sub_id})
                await self._conn.execute(
                    "UPDATE subscription_charges SET status='failed' WHERE id=?", (charge["id"],))
            cid = uuid.uuid4().hex
            try:
                await self._conn.execute(
                    "INSERT INTO subscription_charges(id, subscription_id, user_id, amount,"
                    " provider_ref, provider_link, status, created_at, verified_at)"
                    " VALUES (?,?,?,?,NULL,NULL,'pending',?,NULL)",
                    (cid, sub_id, user_id, amount, now))
                await self._conn.execute(
                    "INSERT INTO idempotency_keys(user_id, scoped_key, order_id, payload_hash, result,"
                    " created_at) VALUES (?,?,?,?,?,?)",
                    (user_id, scoped, cid, phash,
                     json.dumps({"pending": True, "charge_id": cid}), now))
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            return {"charge_id": cid, "amount": amount, "subscription_id": sub_id}

    async def attach_charge(self, charge_id: str, user_id: str, idem_key: str,
                            provider_ref: str, link: str) -> dict:
        scoped = f"POST /v1/payments/subscription-intent:{(idem_key or '').strip()}"
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "UPDATE subscription_charges SET provider_ref=?, provider_link=?,"
                    " status='link_sent' WHERE id=? AND provider_ref IS NULL",
                    (provider_ref, link, charge_id))
                charge = dict((await self._conn.execute(
                    "SELECT * FROM subscription_charges WHERE id=?", (charge_id,))).fetchone())
                result = {"charge": charge, "link": link, "provider_ref": provider_ref}
                await self._conn.execute(
                    "UPDATE idempotency_keys SET result=? WHERE user_id=? AND scoped_key=?",
                    (json.dumps(result), user_id, scoped))
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            return result

    async def fail_charge(self, charge_id: str, user_id: str, idem_key: str) -> None:
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "DELETE FROM subscription_charges WHERE id=? AND status='pending'", (charge_id,))
                await self._conn.execute(
                    "DELETE FROM idempotency_keys WHERE user_id=? AND scoped_key=?",
                    (user_id, f"POST /v1/payments/subscription-intent:{(idem_key or '').strip()}"))
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise

    async def find_charge_by_ref(self, provider_ref: str) -> dict | None:
        row = (await self._conn.execute(
            "SELECT * FROM subscription_charges WHERE provider_ref=?", (provider_ref,))).fetchone()
        return dict(row) if row is not None else None

    async def settle_charge(self, provider_ref: str, amount: int) -> dict:
        from app.repositories.payment_repo import AmountMismatchError  # noqa: PLC0415

        with WRITE_LOCK:
            charge = await self.find_charge_by_ref(provider_ref)
            if charge is None:
                raise SubNotFoundError(message="Top-up intent not found.", details={})
            if charge["status"] == "paid":
                return {**charge, "_duplicate": True}
            if int(amount) != int(charge["amount"]):
                raise AmountMismatchError(message="Amount does not match the top-up.",
                                          details={"expected": int(charge["amount"])})
            sub = (await self._conn.execute(
                "SELECT * FROM subscriptions WHERE id=?", (charge["subscription_id"],))).fetchone()
            if sub is None:
                raise SubNotFoundError(message="Subscription not found.", details={})
            now = _dt.datetime.now(_dt.timezone.utc).isoformat()
            try:
                if sub.get("canceled_at") or sub.get("billing_status") == "canceled":
                    await self._conn.batch([
                        ("UPDATE subscription_charges SET status='paid', verified_at=? WHERE id=?",
                         (now, charge["id"])),
                        ("INSERT OR IGNORE INTO refunds(id, order_id, subscription_id, payment_id,"
                         " amount, method, upi_id, status, claimed_by, claimed_at, attempts,"
                         " created_at, done_at)"
                         " VALUES (?, NULL, ?, ?, ?, 'upi', ?, 'pending', NULL, NULL, 0, ?, NULL)",
                         (uuid.uuid4().hex, charge["subscription_id"], f"charge:{charge['id']}",
                          int(amount), str(sub.get("refund_upi") or ""), now)),
                    ])
                    self._conn.commit()
                    return {**charge, "status": "paid", "refund_queued": True,
                            "credited_paise": 0}
                # One atomic batch: ledger entry + balance recomputed from the
                # ledger (never a blind increment, so a retry cannot double-credit).
                await self._conn.batch([
                    ("INSERT OR IGNORE INTO subscription_credit_entries(id, subscription_id, user_id,"
                     " delta, kind, ref, created_at) VALUES (?,?,?,?,?,?,?)",
                     (uuid.uuid4().hex, charge["subscription_id"], charge["user_id"],
                      int(amount), "topup", f"charge:{charge['id']}", now)),
                    ("UPDATE subscriptions SET credit_balance_paise = (SELECT COALESCE(SUM(delta), 0)"
                     " FROM subscription_credit_entries WHERE subscription_id = ?),"
                     " billing_status='active' WHERE id=?",
                     (charge["subscription_id"], charge["subscription_id"])),
                    ("UPDATE subscription_charges SET status='paid', verified_at=? WHERE id=?",
                     (now, charge["id"])),
                ])
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            return {**charge, "status": "paid", "credited_paise": int(amount)}

    async def settle_prepaid_order(self, sub_id: str, order_id: str, amount: int) -> dict:
        """Debit one delivery from prepaid credit and mark the order paid.

        Runs once per order: the credit entry ref is UNIQUE, so a retry cannot
        debit twice. Deposit (container plans) stays on the order as dues.
        """
        now = _dt.datetime.now(_dt.timezone.utc).isoformat()
        with WRITE_LOCK:
            sub = (await self._conn.execute(
                "SELECT * FROM subscriptions WHERE id=?", (sub_id,))).fetchone()
            if sub is None or sub.get("canceled_at"):
                raise SubValidationError(message="Subscription cannot be charged.",
                                         details={"id": sub_id})
            balance = int(sub.get("credit_balance_paise") or 0)
            if balance < int(amount):
                raise InsufficientCreditError(
                    message="Prepaid balance is too low for this delivery.",
                    details={"balance": balance, "needed": int(amount)})
            try:
                await self._conn.batch([
                    ("INSERT OR IGNORE INTO subscription_credit_entries(id, subscription_id, user_id,"
                     " delta, kind, ref, created_at) VALUES (?,?,?,?,?,?,?)",
                     (uuid.uuid4().hex, sub_id, str(sub["user_id"]), -int(amount), "order",
                      f"order:{order_id}", now)),
                    # Balance is always the ledger sum: a replayed debit is a no-op.
                    ("UPDATE subscriptions SET credit_balance_paise = (SELECT COALESCE(SUM(delta), 0)"
                     " FROM subscription_credit_entries WHERE subscription_id = ?) WHERE id=?",
                     (sub_id, sub_id)),
                    ("INSERT OR IGNORE INTO payments(id, order_id, user_id, amount, method, provider_ref,"
                     " status, created_at, verified_at) VALUES (?,?,?,?,?,?,?,?,?)",
                     (uuid.uuid4().hex, order_id, str(sub["user_id"]), int(amount), "upi",
                      f"subcredit:{sub_id}:{order_id}", "paid", now, now)),
                    ("UPDATE orders SET payment_status = CASE WHEN"
                     " (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE order_id = ?"
                     "  AND status IN ('paid','partial')) >= total"
                     " THEN 'paid_upi' ELSE 'partial_dues' END WHERE id=?",
                     (order_id, order_id)),
                ])
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            fresh = (await self._conn.execute(
                "SELECT credit_balance_paise FROM subscriptions WHERE id=?", (sub_id,))).fetchone()
            return {"subscription_id": sub_id, "order_id": order_id,
                    "debited_paise": int(amount),
                    "credit_balance_paise": int(fresh["credit_balance_paise"]) if fresh else 0}

    def build_restore_order_credit_stmts(
        self,
        order_id: str,
        *,
        sub_id: str,
        total: int,
        now: str,
        guard: tuple[str, tuple] | None = None,
    ) -> list[tuple[str, tuple]]:
        """Build the credit-restore statements for a cancel batch.

        The plan must still be live; when it is gone the statements no-op and
        the caller refunds the credit as real money instead.
        """
        where, guard_params = guard if guard else ("", ())
        suffix = f" AND {where}" if where else ""
        active = "canceled_at IS NULL AND billing_status != 'canceled'"
        return [
            (
                "INSERT OR IGNORE INTO subscription_credit_entries(id, subscription_id,"
                " user_id, delta, kind, ref, created_at)"
                " SELECT ?, id, user_id, ?, 'order_refund', ?, ? FROM subscriptions"
                f" WHERE id=? AND {active}{suffix}",
                (uuid.uuid4().hex, int(total), f"order:{order_id}", now, sub_id,
                 *guard_params),
            ),
            (
                "UPDATE subscriptions SET credit_balance_paise = (SELECT COALESCE(SUM(delta), 0)"
                " FROM subscription_credit_entries WHERE subscription_id = ?)"
                f" WHERE id=? AND {active}{suffix}",
                (sub_id, sub_id, *guard_params),
            ),
            (
                "UPDATE payments SET status='failed' WHERE order_id=?"
                " AND provider_ref LIKE 'subcredit:%'"
                " AND EXISTS (SELECT 1 FROM subscriptions WHERE id=?"
                f" AND {active}{suffix})",
                (order_id, sub_id, *guard_params),
            ),
        ]

    async def restore_order_credit(self, order_id: str, commit: bool = True) -> int:
        """Return a canceled prepaid order's water cost to the plan wallet.

        Returns 0 when the plan itself is gone — the caller then treats the
        amount as a real refund instead of inventing wallet money.
        """
        now = _dt.datetime.now(_dt.timezone.utc).isoformat()
        with WRITE_LOCK:
            rows = (await self._conn.execute(
                "SELECT amount, provider_ref FROM payments WHERE order_id=?"
                " AND provider_ref LIKE 'subcredit:%' AND status IN ('paid','partial')",
                (order_id,))).fetchall()
            if not rows:
                return 0
            total = sum(int(r["amount"]) for r in rows)
            try:
                sub_id = str(rows[0]["provider_ref"]).split(":")[1]
            except (IndexError, TypeError):
                return 0
            sub = (await self._conn.execute(
                "SELECT canceled_at, billing_status FROM subscriptions WHERE id=?",
                (sub_id,))).fetchone()
            if sub is None or sub.get("canceled_at") or sub.get("billing_status") == "canceled":
                return 0
            cur_rows = await self._conn.batch(self.build_restore_order_credit_stmts(
                order_id, sub_id=sub_id, total=total, now=now))
            if not cur_rows:
                return 0
            if commit:
                self._conn.commit()
            return int(total)


    async def cancel(self, user_id: str, sub_id: str, reason: str = "", upi_id: str = "") -> dict:
        """Stop future deliveries and refund ONLY collected prepaid credit.

        One batch: the CAS marks the plan canceled, then the return, credit,
        and refund rows are written, and the balance is zeroed last. A failure
        rolls back the whole batch, so credit is never zeroed without its
        refund row. No invented 30-day proration, no ledger write-off: v1 has
        no subscription-level prepaid money outside monthly_prepaid, and dues
        stay owed until actually paid.
        """
        sub = await self.get_owned(user_id, sub_id)
        if sub is None:
            raise SubNotFoundError(message="Subscription not found.", details={"id": sub_id})
        if sub.get("canceled_at") or sub.get("status") == "canceled":
            raise SubValidationError(message="Subscription is already canceled.", details={"id": sub_id})

        from app.services import pricing

        is_prepaid = str(sub.get("billing_mode") or "per_delivery") == "monthly_prepaid"
        remaining = max(0, int(sub.get("credit_balance_paise") or 0)) if is_prepaid else 0
        from app.repositories.ledger_repo import LedgerRepo
        led = await LedgerRepo(self._conn).get(user_id)
        held_jars = max(0, int(led.get("held", 0)))
        return_id = None
        deposit_rate = pricing.DEPOSIT_PAISE
        jars_to_return = min(held_jars, int(sub.get("qty", 1))) if held_jars > 0 else 0
        now_str = _dt.datetime.now(_dt.timezone.utc).isoformat()
        refund = None
        if remaining > 0:
            refund = {
                "id": uuid.uuid4().hex,
                "amount": remaining,
                "status": "pending",
                "method": "upi",
            }
        if jars_to_return > 0:
            return_id = uuid.uuid4().hex
            from app.api.v1.returns import _sla_due  # noqa: PLC0415

            return_sla = _sla_due()

        returns_cols = {r["name"] for r in (
            await self._conn.execute("SELECT name FROM pragma_table_info('returns')")
        ).fetchall()}
        has_return_upi = "upi_id" in returns_cols
        guard = ("EXISTS (SELECT 1 FROM subscriptions WHERE id = ? AND canceled_at = ?)",
                 (sub_id, now_str))
        with WRITE_LOCK:
            stmts: list[tuple[str, tuple]] = [
                (
                    "UPDATE subscriptions SET status = 'paused', canceled_at = ?,"
                    " cancel_reason = ?, refund_amount_paise = ?, billing_status = 'canceled',"
                    " refund_upi = ? WHERE id = ? AND canceled_at IS NULL",
                    (now_str, reason or "Customer canceled subscription", remaining,
                     (upi_id or "").strip(), sub_id),
                ),
            ]
            if return_id is not None:
                if has_return_upi:
                    stmts.append((
                        "INSERT INTO returns(id, user_id, qty, address_id, status, sla_due,"
                        " created_at, upi_id) SELECT ?, ?, ?, ?, 'requested', ?, ?, ?"
                        f" WHERE {guard[0]}",
                        (return_id, user_id, jars_to_return, sub["address_id"],
                         return_sla, now_str, (upi_id or "").strip(), *guard[1]),
                    ))
                else:
                    stmts.append((
                        "INSERT INTO returns(id, user_id, qty, address_id, status, sla_due,"
                        " created_at) SELECT ?, ?, ?, ?, 'requested', ?, ?"
                        f" WHERE {guard[0]}",
                        (return_id, user_id, jars_to_return, sub["address_id"],
                         return_sla, now_str, *guard[1]),
                    ))
            if refund is not None:
                stmts.append((
                    "INSERT INTO refunds(id, order_id, subscription_id, payment_id, amount,"
                    " method, upi_id, status, claimed_by, claimed_at, attempts, created_at,"
                    " done_at) SELECT ?, NULL, ?, ?, ?, 'upi', ?, 'pending', NULL, NULL, 0, ?, NULL"
                    f" WHERE {guard[0]}",
                    (refund["id"], sub_id, f"subcancel:{sub_id}", remaining,
                     (upi_id or "").strip(), now_str, *guard[1]),
                ))
                stmts.append((
                    "INSERT INTO subscription_credit_entries(id, subscription_id, user_id,"
                    " delta, kind, ref, created_at) SELECT ?, ?, ?, ?, 'cancel_refund', ?, ?"
                    f" WHERE {guard[0]}",
                    (uuid.uuid4().hex, sub_id, user_id, -remaining,
                     f"cancel:{sub_id}", now_str, *guard[1]),
                ))
            stmts.append((
                "UPDATE subscriptions SET credit_balance_paise = 0"
                f" WHERE id = ? AND {guard[0]}",
                (sub_id, *guard[1]),
            ))
            rows = await self._conn.batch(stmts)
            self._conn.commit()
            if rows[0].rowcount == 0:
                fresh = (await self._conn.execute(
                    "SELECT canceled_at FROM subscriptions WHERE id = ?", (sub_id,)
                )).fetchone()
                if fresh is not None and fresh.get("canceled_at"):
                    raise SubValidationError(
                        message="Subscription is already canceled.", details={"id": sub_id})
                raise SubValidationError(
                    message="Subscription could not be canceled.", details={"id": sub_id})

        return {
            "id": sub_id,
            "status": "canceled",
            "canceled_at": now_str,
            "is_prepaid": is_prepaid,
            "unused_water_refund_paise": remaining,
            "refund": refund,
            "return_id": return_id,
            "jars_to_return": jars_to_return,
            "deposit_refund_expected_paise": jars_to_return * deposit_rate,
            "message": (
                "Subscription canceled. Future deliveries are stopped. "
                "If a refund is due, we will process it to your UPI after pickup. "
                "Nothing is refunded for deliveries that were never paid."
            ),
        }

    # -- pause / resume / skip --------------------------------------------

    async def pause(self, user_id: str, sub_id: str, hold_from: object, hold_to: object) -> dict:
        sub = await self.get_owned(user_id, sub_id)
        if sub is None:
            raise SubNotFoundError(message="Subscription not found.", details={"id": sub_id})
        if sub.get("canceled_at"):
            raise SubValidationError(message="Cannot modify a canceled subscription.", details={"id": sub_id})
        dfrom, dto = _parse_day(hold_from), _parse_day(hold_to)
        if dfrom is None or dto is None or dfrom > dto:
            raise SubValidationError(
                message="hold_from must be <= hold_to (YYYY-MM-DD).",
                details={"hold_from": hold_from, "hold_to": hold_to},
            )
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "UPDATE subscriptions SET status = 'paused', hold_from = ?, hold_to = ?"
                    " WHERE id = ?",
                    (dfrom, dto, sub_id),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return await self.get_owned(user_id, sub_id)  # type: ignore[return-value]

    async def resume(
        self, user_id: str, sub_id: str, preferred_date: object,
        now: _dt.datetime | None = None,
    ) -> dict:
        sub = await self.get_owned(user_id, sub_id)
        if sub is None:
            raise SubNotFoundError(message="Subscription not found.", details={"id": sub_id})
        if sub.get("canceled_at"):
            raise SubValidationError(message="Cannot modify a canceled subscription.", details={"id": sub_id})
        now = now or _now()
        pref = _parse_dt(preferred_date)
        if pref is None:
            raise SubValidationError(message="preferred_date must be ISO-8601.", details={})
        earliest = now + _dt.timedelta(hours=RESUME_LEAD_HOURS)
        if pref < earliest:  # >=24h guard (Bisleri ≥24h resume)
            raise ResumeTooSoonError(
                message="Resume needs 24h notice. Pick a later date.",
                details={"preferred_date": str(preferred_date),
                         "next_valid_date": earliest.isoformat()},
            )
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "UPDATE subscriptions SET status = 'active', hold_from = NULL,"
                    " hold_to = NULL, next_run = ? WHERE id = ?",
                    (pref.date().isoformat(), sub_id),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return await self.get_owned(user_id, sub_id)  # type: ignore[return-value]

    async def skip(
        self, user_id: str, sub_id: str, date: object,
        now: _dt.datetime | None = None,
    ) -> dict:
        sub = await self.get_owned(user_id, sub_id)
        if sub is None:
            raise SubNotFoundError(message="Subscription not found.", details={"id": sub_id})
        if sub.get("canceled_at"):
            raise SubValidationError(message="Cannot modify a canceled subscription.", details={"id": sub_id})
        day = _parse_day(date)
        now = now or _now()
        if day is None:
            raise SubValidationError(message="date must be YYYY-MM-DD.", details={})
        if day < now.date().isoformat():
            raise SubValidationError(message="Cannot skip a past date.", details={"date": day})
        late = 1 if (day == now.date().isoformat() and now.hour >= SKIP_CUTOFF_HOUR) else 0
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "INSERT OR IGNORE INTO skips(id, sub_id, date, late) VALUES (?, ?, ?, ?)",
                    (uuid.uuid4().hex, sub_id, day, late),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        row = (await self._conn.execute(
            "SELECT id, sub_id, date, late FROM skips WHERE sub_id = ? AND date = ?",
            (sub_id, day),
        )).fetchone()
        out = _row(row)
        out["late_skip"] = bool(out["late"])
        if out["late_skip"]:
            out["cta"] = "Late skip — please call support so the vendor is informed."
        return out

    # -- due runner (job-callable; future cron calls this, never HTTP) -----

    async def process_due(self, today: object = None, limit: int = 60) -> dict:
        """Generate due-run descriptors + fire auto-resumes.

        Generated descriptors are NOT advanced here: the caller creates the
        order (and settles prepaid credit) first, then calls ``advance_due``.
        A failed creation leaves ``next_run`` due and records a backoff, so a
        cron failure can never skip a delivery. Skipped Sundays and resumes
        still advance in this pass. Bounded to ``limit`` rows per tick.
        """
        tday = _parse_day(today) if today is not None else _now().date().isoformat()
        assert tday is not None, "today must be a date"
        now = _now().isoformat()
        await _ensure_billing_mode(self._conn)
        resumed: list[dict] = []
        generated: list[dict] = []
        low_balance: list[dict] = []
        with WRITE_LOCK:
            try:
                paused = (await self._conn.execute(
                    "SELECT id, user_id FROM subscriptions"
                    " WHERE status = 'paused' AND canceled_at IS NULL"
                    " AND billing_status != 'pending_payment'"
                    " AND hold_to IS NOT NULL AND hold_to < ?"
                    " ORDER BY id LIMIT ?",
                    (tday, int(limit)),
                )).fetchall()
                for p in paused:
                    cur = await self._conn.execute(
                        "UPDATE subscriptions SET status = 'active',"
                        " hold_from = NULL, hold_to = NULL"
                        " WHERE id = ? AND status = 'paused'",
                        (p["id"],),
                    )
                    if cur.rowcount:
                        resumed.append({"sub_id": p["id"], "user_id": p["user_id"]})
                due = (await self._conn.execute(
                    "SELECT * FROM subscriptions"
                    " WHERE status = 'active' AND canceled_at IS NULL AND next_run <> ''"
                    " AND next_run <= ?"
                    " AND (due_retry_at IS NULL OR due_retry_at <= ?)"
                    " AND NOT (hold_from IS NOT NULL AND hold_to IS NOT NULL"
                    "          AND hold_from <= next_run AND next_run <= hold_to)"
                    " ORDER BY next_run, id LIMIT ?",
                    (tday, now, int(limit)),
                )).fetchall()
                for s in due:
                    d = _dt.date.fromisoformat(s["next_run"])
                    if d.weekday() == 6 or await self._skipped(s["id"], d.isoformat()):
                        await self._advance_past(s, _dt.date.fromisoformat(tday))
                        continue
                    billing = str(s.get("billing_mode") or "per_delivery")
                    if str(s.get("billing_status") or "active") == "pending_payment":
                        low_balance.append({
                            "sub_id": s["id"], "user_id": s["user_id"],
                            "reason": "payment_pending",
                        })
                        continue
                    if billing == "monthly_prepaid":
                        need = _due_today(s["qty"], s["sku_mix"])
                        if int(s.get("credit_balance_paise") or 0) < need:
                            low_balance.append({
                                "sub_id": s["id"], "user_id": s["user_id"],
                                "reason": "low_balance", "needed_paise": need,
                                "balance_paise": int(s.get("credit_balance_paise") or 0),
                            })
                            continue
                    generated.append({
                        "sub_id": s["id"], "user_id": s["user_id"],
                        "address_id": s["address_id"], "qty": s["qty"],
                        "sku_mix": s["sku_mix"], "window": s["window"],
                        "payment_method": s.get("payment_method", "cod"),
                        "billing_mode": billing,
                        "date": d.isoformat(),
                    })
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return {"date": tday, "generated": generated, "resumed": resumed,
                "low_balance": low_balance}

    async def due_backlog(self, today: object = None) -> int:
        """Count due subs with the same filters as ``process_due``."""
        tday = _parse_day(today) if today is not None else _now().date().isoformat()
        assert tday is not None, "today must be a date"
        row = (await self._conn.execute(
            "SELECT COUNT(*) c FROM subscriptions"
            " WHERE status = 'active' AND canceled_at IS NULL AND next_run <> ''"
            " AND next_run <= ?"
            " AND (due_retry_at IS NULL OR due_retry_at <= ?)"
            " AND NOT (hold_from IS NOT NULL AND hold_to IS NOT NULL"
            "          AND hold_from <= next_run AND next_run <= hold_to)",
            (tday, _now().isoformat()),
        )).fetchone()
        return int(row["c"]) if row is not None else 0

    async def advance_due(self, sub_id: str, expected_next_run: str,
                          today: object = None) -> bool:
        """Advance ``next_run`` only if it still equals the processed date.

        Called after the order exists and prepaid credit is settled. A lost
        CAS means another tick already advanced it; harmless. Resets retry
        state so the plan is eligible on its next schedule.
        """
        sub = (await self._conn.execute(
            "SELECT next_run, schedule_type, recurrence FROM subscriptions WHERE id = ?",
            (sub_id,),
        )).fetchone()
        if sub is None or str(sub["next_run"]) != str(expected_next_run):
            return False
        tday = _parse_day(today) if today is not None else _now().date().isoformat()
        assert tday is not None, "today must be a date"
        nxt = _advance(_dt.date.fromisoformat(str(expected_next_run)),
                       sub["schedule_type"], sub["recurrence"])
        guard = 0
        while (nxt <= _dt.date.fromisoformat(tday) or nxt.weekday() == 6) and guard < 370:
            guard += 1
            if nxt.weekday() == 6:
                nxt += _dt.timedelta(days=1)
            else:
                nxt = _advance(nxt, sub["schedule_type"], sub["recurrence"])
        with WRITE_LOCK:
            cur = await self._conn.execute(
                "UPDATE subscriptions SET next_run = ?, due_attempts = 0,"
                " due_last_error = NULL, due_retry_at = NULL"
                " WHERE id = ? AND next_run = ?",
                (nxt.isoformat(), sub_id, str(expected_next_run)),
            )
            self._conn.commit()
            return cur.rowcount > 0

    async def record_due_failure(self, sub_id: str, code: str,
                                 message: str = "") -> dict:
        """Record a failed due run and back off 15m → 24h (no dead-letter)."""
        row = (await self._conn.execute(
            "SELECT due_attempts FROM subscriptions WHERE id = ?", (sub_id,)
        )).fetchone()
        attempts = int(row["due_attempts"] or 0) + 1 if row is not None else 1
        delay = min(15 * 60 * (2 ** (attempts - 1)), 24 * 3600)
        retry_at = (_now() + _dt.timedelta(seconds=delay)).isoformat()
        with WRITE_LOCK:
            await self._conn.execute(
                "UPDATE subscriptions SET due_attempts = due_attempts + 1,"
                " due_last_error = ?, due_retry_at = ? WHERE id = ?",
                (str(message or code)[:200], retry_at, sub_id),
            )
            self._conn.commit()
        return {"sub_id": sub_id, "attempts": attempts, "code": code,
                "retry_at": retry_at, "retry_after_s": delay}

    # -- internals --------------------------------------------------------

    async def _advance_past(self, sub: dict, today: _dt.date) -> None:
        nxt = _advance(_dt.date.fromisoformat(sub["next_run"]),
                       sub["schedule_type"], sub["recurrence"])
        guard = 0
        while (nxt <= today or nxt.weekday() == 6) and guard < 370:
            guard += 1
            if nxt.weekday() == 6:
                nxt += _dt.timedelta(days=1)
            else:
                nxt = _advance(nxt, sub["schedule_type"], sub["recurrence"])
        await self._conn.execute(
            "UPDATE subscriptions SET next_run = ? WHERE id = ? AND next_run = ?",
            (nxt.isoformat(), sub["id"], sub["next_run"]),
        )

    async def _skipped(self, sub_id: str, day: str) -> bool:
        return (await self._conn.execute(
            "SELECT 1 FROM skips WHERE sub_id = ? AND date = ?", (sub_id, day)
        )).fetchone() is not None

    async def _owned_address(self, user_id: str, address_id: str) -> bool:
        try:
            row = (await self._conn.execute(
                "SELECT 1 FROM addresses WHERE id = ? AND user_id = ?", (address_id, user_id)
            )).fetchone()
        except Exception:
            return True  # addresses slice not migrated yet -> don't block
        return row is not None

    def _default_next_run(self) -> str:
        nxt = _now().date() + _dt.timedelta(days=1)
        while nxt.weekday() == 6:
            nxt += _dt.timedelta(days=1)
        return nxt.isoformat()
