"""Order service — business rules ONLY (no SQL here beyond repo calls, no FastAPI).

Owns: quote re-verification (server-computed money, SEC-P), policy gates
(OVER_LIMIT N>10, HOLD_BLOCKED held>3), §10 cancel matrix, reschedule guard.
Idempotency: scoped keys ``endpoint:key`` UNIQUE(user_id, scoped_key);
same-payload replay returns the original outcome, changed payload -> 422.
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import json

from app.core.errors import AppError, ConflictError, NotFoundError, ValidationError
from app.repositories.ledger_repo import LedgerRepo
from app.repositories.order_repo import (
    AlreadyCancelledError,
    NeedDispatchOverrideError,
    OrderRepo,
)

CREATE_ENDPOINT = "POST /v1/orders"
MAX_JARS_PER_ORDER = 10  # EC-O03 hard stop; >10 = tanker-stop, contact support
HOLD_BLOCK_LIMIT = 3  # VR-12: held > 3 blocks new orders until jars return
RESCHEDULABLE = {"placed", "accepted", "picked", "packed"}  # pre-dispatch only


class StaleQuoteError(AppError):
    code = "STALE_QUOTE"
    status_code = 409


class OverLimitError(AppError):
    code = "OVER_LIMIT"
    status_code = 422


class HoldBlockedError(AppError):
    code = "HOLD_BLOCKED"
    status_code = 422


class PayloadMismatchError(AppError):
    code = "PAYLOAD_MISMATCH"
    status_code = 422


class IdempotentReplayError(AppError):
    code = "IDEMPOTENT_REPLAY"
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


def _payload_hash(payload: dict) -> str:
    canonical = json.dumps(
        {
            "items": sorted(
                ({"sku": i["sku"], "qty": int(i["qty"])} for i in payload.get("items", [])),
                key=lambda x: (x["sku"], x["qty"]),
            ),
            "e": int(payload.get("e", 0)),
            "address_id": payload.get("address_id", ""),
            "window_start": payload.get("window_start", ""),
            "quote_hash": payload.get("quote_hash", ""),
            "quote_total": int(payload.get("quote_total", 0)),
            "payment_mode": payload.get("payment_mode", "cod"),
        },
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical.encode()).hexdigest()


class OrderService:
    """Service-per-use-case for orders (python card: services stay DB-agnostic)."""

    def __init__(self, order_repo: OrderRepo, ledger_repo: LedgerRepo, pricing, rates: dict):
        self.orders = order_repo
        self.ledger = ledger_repo
        self.pricing = pricing
        self.rates = rates

    # -- create -----------------------------------------------------------

    async def create(self, user_id: str, payload: dict, idempotency_key: str) -> dict:
        if not idempotency_key or not str(idempotency_key).strip():
            raise ValidationError(message="Idempotency-Key header required.", details={})
        scoped = f"{CREATE_ENDPOINT}:{idempotency_key}"
        phash = _payload_hash(payload)
        existing = await self.orders.find_by_scoped_key(user_id, scoped)
        if existing is not None:
            self._check_replay(existing, phash)
        items = [{"sku": i["sku"], "qty": int(i["qty"])} for i in payload.get("items", [])]
        e = int(payload.get("e", 0))
        n = sum(i["qty"] for i in items)
        if n < 1 or e > n:
            raise ValidationError(message="Invalid items/empties.", details={"n": n, "e": e})

        # Quote re-verification: recompute server-side, compare total + hash (C5).
        current_rv = str(getattr(self.pricing, "RATE_VERSION", "v1"))
        if str(payload.get("quote_rate_version", "")) != current_rv:
            raise StaleQuoteError(message="Rate version moved. Please re-quote.",
                                   details={"quote_rate_version": payload.get("quote_rate_version"),
                                            "current": current_rv})
        # Once-only wallet-held deposit: refill never, container only when
        # ledger holds < one deposit. Accept the pre-waiver quote too so old
        # /quotes estimates (full deposit) don't STALE-loop the first waived order.
        led_now = await self.ledger.get(user_id)
        held_paid = int(led_now.get("deposit_paid", 0)) - int(led_now.get("deposit_refunded", 0))
        try:
            q = self.pricing.compute_quote(
                items, e, self.rates,
                address_id=payload.get("address_id", ""),
                window_start=payload.get("window_start", ""),
                rate_version=current_rv,
                deposit_already_paid_paise=held_paid,
            )
            q_full = self.pricing.compute_quote(
                items, e, self.rates,
                address_id=payload.get("address_id", ""),
                window_start=payload.get("window_start", ""),
                rate_version=current_rv,
                deposit_already_paid_paise=0,
            )
        except ValueError as ex:
            raise ValidationError(message=str(ex), details={}) from ex
        if int(payload.get("quote_total", -1)) == int(q_full["total"]) and payload.get("quote_hash") == q_full["quote_hash"]:
            pass  # pre-waiver estimate: totals below use the waived q
        elif int(payload.get("quote_total", -1)) != int(q["total"]) or payload.get("quote_hash") != q["quote_hash"]:
            raise StaleQuoteError(message="Quote changed or mismatched. Please re-quote.",
                                   details={"expected_total": q["total"]})
        expires = _parse_dt(payload.get("quote_expires_at"))
        if expires is None or expires <= _now():
            raise StaleQuoteError(message="Quote expired. Please re-quote.", details={})

        if q["n_total"] > MAX_JARS_PER_ORDER:
            raise OverLimitError(
                message="Maximum 10 jars per order. For larger (tanker) requirements, please contact support.",
                details={"n": q["n_total"], "max": MAX_JARS_PER_ORDER},
            )
        if int(led_now.get("held", 0)) > HOLD_BLOCK_LIMIT:
            raise HoldBlockedError(
                message="Too many jars held. Return empties to order again.",
                details={"held": int(led_now.get("held", 0)), "max": HOLD_BLOCK_LIMIT},
            )

        window_end = self._window_end(str(payload.get("window_start", "")))
        order = {
            "user_id": user_id,
            "address_id": payload["address_id"],
            "items": items,
            "n": n,
            "e": e,
            "water_bill": q["water_bill"],
            "deposit_due": q["deposit_due"],
            "total": q["total"],
            "payment_mode": payload.get("payment_mode", "cod"),
            "window_start": payload["window_start"],
            "window_end": window_end,
            "idempotency_key": scoped,
            "payload_hash": phash,
            "quote_hash": q["quote_hash"],
            "quote_rate_version": current_rv,
            "_actor": user_id,
        }
        try:
            return await self.orders.insert(
                order,
                {"customer_id": user_id, "actor": user_id, "reason": "order deposit"},
            )
        except ConflictError:
            # Lost a concurrent insert race: fall back to the replay path.
            existing = await self.orders.find_by_scoped_key(user_id, scoped)
            if existing is not None:
                self._check_replay(existing, phash)
            raise

    @staticmethod
    def _check_replay(existing: dict, phash: str) -> None:
        if existing.get("payload_hash") != phash:
            raise PayloadMismatchError(
                message="Idempotency-Key was already used with a different payload.",
                details={"order_id": existing["id"]},
            )
        raise IdempotentReplayError(message="Duplicate request: returning the original order.",
                                    details={"order": existing})

    # -- read -------------------------------------------------------------

    async def detail(self, user_id: str, order_id: str) -> dict:
        order = await self.orders.find_owned(order_id, user_id)
        if order is None:
            raise NotFoundError(message="Order not found.", details={"id": order_id})
        events = await self.orders.events(order_id)
        # F1: PoD delivery code for the owner, only while a stop is active.
        # Hidden before assignment (no route yet) and after terminal states.
        delivery_otp: str | None = None
        if order["state"] in ("assigned", "dispatched"):
            day = await self.orders.route_date_for_order(order_id)
            if day is not None:
                from app.services.vendor_service import pod_otp

                delivery_otp = pod_otp(order_id, day)
        return {
            **order,
            "delivery_otp": delivery_otp,
            "tracker": {"steps": ["placed", "packed", "dispatched", "delivered"], "current": order["state"]},
            "rider": None,  # populated once assigned (assignment slice owns stops/routes)
            "bill": {
                "water_bill": order["water_bill"],
                "deposit_due": order["deposit_due"],
                "cap_charge": order["cap_charge"],
                "total": order["total"],
                "payment_status": order["payment_status"],
            },
            "events": events,
        }

    async def list(self, user_id: str, limit: int = 20, cursor: str | None = None) -> dict:
        data, next_cursor = await self.orders.list_by_user(user_id, limit, cursor)
        return {"data": data, "next_cursor": next_cursor}

    # -- cancel (§10 matrix) ----------------------------------------------

    async def cancel(self, user_id: str, order_id: str, reason: str, idempotency_key: str) -> dict:
        if not idempotency_key or not str(idempotency_key).strip():
            raise ValidationError(message="Idempotency-Key header required.", details={})
        order = await self.orders.find_owned(order_id, user_id)
        if order is None:
            raise NotFoundError(message="Order not found.", details={"id": order_id})
        scoped = f"POST /v1/orders/{order_id}/cancel:{idempotency_key}"
        phash = hashlib.sha256(reason.encode()).hexdigest()
        stored = await self._idem_get(user_id, scoped)
        if stored is not None:
            if stored["payload_hash"] != phash:
                raise PayloadMismatchError(
                    message="Idempotency-Key was already used with a different payload.",
                    details={"order_id": order_id},
                )
            return json.loads(stored["result"])  # same-outcome replay, zero new writes
        state = order["state"]
        if state == "cancelled":
            # Different key, already settled: same outcome, no second refund row.
            raise AlreadyCancelledError(
                message="Order already cancelled.",
                details=await self._cancelled_outcome(order_id),
            )
        if state == "delivered":
            raise ConflictError(
                message="Delivered orders cannot be cancelled. Please raise a complaint.",
                details={"from": state, "to": "cancelled"},
            )
        if state in {"assigned", "dispatched"}:
            raise NeedDispatchOverrideError(
                message="Post-assign cancel needs the dispatcher. Call support to cancel.",
                details={"from": state, "to": "cancelled"},
            )
        outcome = await self.orders.cancel_settle(order_id, {"id": user_id, "role": "user"})
        await self._idem_put(user_id, scoped, order_id, phash, outcome)
        return outcome

    async def _cancelled_outcome(self, order_id: str) -> dict:
        row = (await self.orders._conn.execute(
            "SELECT id, user_id, deposit_due FROM orders WHERE id = ?", (order_id,)
        )).fetchone()
        refund = (await self.orders._conn.execute(
            "SELECT id, payment_id, amount, method, status, claimed_by, claimed_at"
            " FROM refunds WHERE order_id = ?",
            (order_id,),
        )).fetchone()
        return {
            "order_id": order_id,
            "state": "cancelled",
            "bill_total": 0,
            "deposit_reversed": int(row["deposit_due"]) if row else 0,
            "refund": dict(refund) if refund is not None else None,
        }

    # -- reschedule (pre-dispatch only) ------------------------------------

    async def reschedule(self, user_id: str, order_id: str, window_start: str) -> dict:
        order = await self.orders.find_owned(order_id, user_id)
        if order is None:
            raise NotFoundError(message="Order not found.", details={"id": order_id})
        if order["state"] not in RESCHEDULABLE:
            raise ConflictError(
                message="Reschedule is allowed only before dispatch. Call support to cancel instead.",
                details={"from": order["state"], "to": order["state"]},
            )
        return await self.orders.update_window(
            order_id, window_start, self._window_end(window_start), {"id": user_id, "role": "user"}
        )

    # -- internals --------------------------------------------------------

    @staticmethod
    def _window_end(window_start: str) -> str:
        dt = _parse_dt(window_start)
        if dt is None:
            return ""
        return (dt + _dt.timedelta(minutes=30)).isoformat()

    async def _idem_get(self, user_id: str, scoped: str) -> dict | None:
        row = (await self.orders._conn.execute(
            "SELECT payload_hash, result FROM idempotency_keys WHERE user_id = ? AND scoped_key = ?",
            (user_id, scoped),
        )).fetchone()
        return dict(row) if row is not None else None

    async def _idem_put(self, user_id: str, scoped: str, order_id: str, phash: str, outcome: dict) -> None:
        from app.db import WRITE_LOCK

        with WRITE_LOCK:
            await self.orders._conn.execute(
                "INSERT OR IGNORE INTO idempotency_keys(user_id, scoped_key, order_id,"
                " payload_hash, result, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                (user_id, scoped, order_id, phash, json.dumps(outcome), _now().isoformat()),
            )
            self.orders._conn.commit()
