from __future__ import annotations

import datetime as _dt
import hashlib
import json
import uuid

from app.db import WRITE_LOCK
from app.services.subscription._common import (  # noqa: F401
    BILLING_MODES,
    Conn,
    InsufficientCreditError,
    MAX_PLAN_JARS,
    PAYMENT_METHODS,
    RESUME_LEAD_HOURS,
    ResumeTooSoonError,
    SCHEDULE_TYPES,
    SKIP_CUTOFF_HOUR,
    SubNotFoundError,
    SubValidationError,
    _advance,
    _due_today,
    _ensure_billing_mode,
    _monthly_estimate,
    _now,
    _parse_day,
    _parse_dt,
    _row,
)

from app.services.subscription._common import reset_billing_mode_cache  # noqa: F401
from app.services.subscription.billing import SubBillingMixin
from app.services.subscription.schedule import SubScheduleMixin


class SubscriptionService(SubBillingMixin, SubScheduleMixin):
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
        from app.core.config import get_settings  # noqa: PLC0415

        s = get_settings()
        rates = {"refill": int(s.rate_refill_paise), "container": int(s.rate_container_paise),
                 "deposit": int(s.deposit_per_jar_paise)}
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
                message=f"billing_mode must be one of {', '.join(BILLING_MODES)}.",
                details={"billing_mode": billing_mode})
        if billing_mode == "monthly_prepaid" and payment_method != "upi":
            raise SubValidationError(
                message="Monthly prepaid plans are paid by UPI.",
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
        subs = [self._decorate_sub(_row(r)) for r in rows]
        if not subs:
            return []
        today_str = _now().date().isoformat()
        try:
            orders = (await self._conn.execute(
                "SELECT id, state, delivery_otp, window_start, idempotency_key FROM orders"
                " WHERE user_id = ? AND state IN ('placed', 'accepted', 'picked', 'packed', 'assigned', 'dispatched')"
                " AND idempotency_key LIKE 'sub:%'",
                (user_id,),
            )).fetchall()
            today_orders = {}
            for o in orders:
                parts = (o["idempotency_key"] or "").split(":")
                if len(parts) >= 3 and parts[2] == today_str:
                    today_orders[parts[1]] = {
                        "order_id": o["id"],
                        "state": o["state"],
                        "delivery_otp": o["delivery_otp"],
                        "window_start": o["window_start"],
                    }
            for s in subs:
                if s.get("id") in today_orders:
                    s["today_order"] = today_orders[s["id"]]
        except Exception:
            pass
        return subs

    async def get_owned(self, user_id: str, sub_id: str) -> dict | None:
        await _ensure_billing_mode(self._conn)
        row = (await self._conn.execute(
            "SELECT * FROM subscriptions WHERE id = ? AND user_id = ?", (sub_id, user_id)
        )).fetchone()
        if row is None:
            return None
        sub = self._decorate_sub(_row(row))
        today_str = _now().date().isoformat()
        try:
            o = (await self._conn.execute(
                "SELECT id, state, delivery_otp, window_start FROM orders"
                " WHERE user_id = ? AND state IN ('placed', 'accepted', 'picked', 'packed', 'assigned', 'dispatched')"
                " AND idempotency_key = ?",
                (user_id, f"sub:{sub_id}:{today_str}"),
            )).fetchone()
            if o is not None:
                sub["today_order"] = {
                    "order_id": o["id"],
                    "state": o["state"],
                    "delivery_otp": o["delivery_otp"],
                    "window_start": o["window_start"],
                }
        except Exception:
            pass
        return sub

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
