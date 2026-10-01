"""Payment repository — the only place that touches ``payments`` SQL.

Paise integers, parameterized writes (ssdlc), one-transaction mutating calls
(WRITE_LOCK). Webhook dedup (C16): UNIQUE(provider_ref) — duplicate delivery
returns the existing row, never a second credit. Payee lock (§14.4): collections
only to ``AGENCY_UPI_VPA``. Refund claim lock (C15): single claimant wins.

Async (Phase-B T2): methods await the shared facade (D1 in prod, sqlite
locally) — call shapes are otherwise unchanged.
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import json
import sqlite3
import uuid

from app.core.errors import AppError, ConflictError, NotFoundError, ValidationError
from app.db import WRITE_LOCK
from app.db_d1 import AsyncSqliteConn, D1Conn
from app.repositories.ledger_repo import LedgerRepo

Conn = D1Conn | AsyncSqliteConn

INTENT_ENDPOINT = "POST /v1/payments/upi-intent"


class AmountMismatchError(AppError):
    code = "AMOUNT_MISMATCH"
    status_code = 422


class PayeeMismatchError(AppError):
    code = "PAYEE_MISMATCH"
    status_code = 422


class PayloadMismatchError(AppError):
    code = "PAYLOAD_MISMATCH"
    status_code = 422


class RefundClaimError(AppError):
    code = "REFUND_CLAIM_CONFLICT"
    status_code = 409


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


def _agency_vpa() -> str:
    try:
        from app.api.deps import get_settings  # noqa: PLC0415

        vpa = getattr(get_settings(), "agency_upi_vpa", None)
        if vpa:
            return str(vpa)
    except Exception:
        pass
    from app.core.worker_env import env_get  # noqa: PLC0415 (request env first)

    return env_get("AGENCY_UPI_VPA", "shodasha@upi")


def _payload_hash(order_id: str, amount: int) -> str:
    return hashlib.sha256(f"{order_id}:{int(amount)}".encode()).hexdigest()


class PaymentRepo:
    def __init__(self, conn: Conn):
        self._conn = conn

    # -- reads ----------------------------------------------------------

    async def get(self, payment_id: str) -> dict | None:
        row = (
            await self._conn.execute("SELECT * FROM payments WHERE id = ?", (payment_id,))
        ).fetchone()
        return dict(row) if row is not None else None

    async def find_by_provider_ref(self, ref: str) -> dict | None:
        row = (
            await self._conn.execute("SELECT * FROM payments WHERE provider_ref = ?", (ref,))
        ).fetchone()
        return dict(row) if row is not None else None

    async def paid_sum_for_order(self, order_id: str) -> int:
        row = (
            await self._conn.execute(
                "SELECT COALESCE(SUM(amount),0) s FROM payments WHERE order_id = ? AND status IN ('paid','partial')",
                (order_id,),
            )
        ).fetchone()
        return int(row["s"])

    async def _order(self, order_id: str) -> dict:
        row = (
            await self._conn.execute("SELECT * FROM orders WHERE id = ?", (order_id,))
        ).fetchone()
        if row is None:
            raise NotFoundError(message="Order not found.", details={"id": order_id})
        return dict(row)

    async def _dues_posted(self, order_id: str) -> bool:
        row = (
            await self._conn.execute(
                "SELECT 1 FROM ledger_events WHERE ref_type='order' AND ref_id=? AND kind='dues' AND d_dues>0 LIMIT 1",
                (order_id,),
            )
        ).fetchone()
        return row is not None

    # -- intent (idempotent, scoped key) --------------------------------

    async def create_intent(self, order_id: str, amount: int, idem_key: str,
                      provider_ref: str | None = None) -> dict:
        if not idem_key or not str(idem_key).strip():
            raise ValidationError(message="Idempotency-Key header required.", details={})
        order = await self._order(order_id)
        if int(amount) != int(order["total"]):
            raise AmountMismatchError(message="Amount does not match the frozen bill.",
                                      details={"expected": int(order["total"])})
        scoped = f"{INTENT_ENDPOINT}:{idem_key.strip()}"
        phash = _payload_hash(order_id, int(amount))
        with WRITE_LOCK:
            stored = (
                await self._conn.execute(
                    "SELECT payload_hash, result FROM idempotency_keys WHERE user_id=? AND scoped_key=?",
                    (order["user_id"], scoped),
                )
            ).fetchone()
            if stored is not None:
                if stored["payload_hash"] != phash:
                    raise PayloadMismatchError(
                        message="Idempotency-Key was already used with a different payload.",
                        details={"order_id": order_id})
                return json.loads(stored["result"])
            ref = provider_ref or f"upi_{uuid.uuid4().hex[:12]}"
            pid = uuid.uuid4().hex
            try:
                await self._conn.execute(
                    "INSERT INTO payments(id, order_id, user_id, amount, method, provider_ref,"
                    " status, created_at, verified_at) VALUES (?,?,?,?,?,?,?, ?, NULL)",
                    (pid, order_id, order["user_id"], int(amount), "upi", ref, "link_sent", _now()),
                )
                await self._conn.execute("UPDATE orders SET payment_status='link_sent' WHERE id=?", (order_id,))
                payment = dict((
                    await self._conn.execute("SELECT * FROM payments WHERE id=?", (pid,))
                ).fetchone())
                await self._conn.execute(
                    "INSERT INTO idempotency_keys(user_id, scoped_key, order_id, payload_hash, result,"
                    " created_at) VALUES (?,?,?,?,?,?)",
                    (order["user_id"], scoped, order_id, phash, json.dumps(payment), _now()),
                )
                self._conn.commit()
            except sqlite3.IntegrityError as e:  # concurrent same-ref race → return winner
                self._conn.rollback()
                dup = await self.find_by_provider_ref(ref)
                if dup is not None:
                    return dup
                raise ConflictError(message="Payment already exists.", details={}) from e
            return payment

    # -- webhook (C16: duplicate ref → existing, no second credit) -------

    async def apply_webhook(self, provider_ref: str, amount: int, payee: str,
                      order_id: str | None = None) -> dict:
        if payee != _agency_vpa():
            raise PayeeMismatchError(message="Collection must go to the agency account.",
                                     details={"expected_payee": "agency"})
        with WRITE_LOCK:
            existing = await self.find_by_provider_ref(provider_ref)
            if existing is not None and existing["status"] == "paid":
                return {**existing, "_duplicate": True}  # 200 no-op, single credit
            if existing is None:
                raise NotFoundError(message="Unknown payment reference.", details={})
            if int(amount) != int(existing["amount"]):
                raise AmountMismatchError(message="Amount does not match the intent.",
                                          details={"expected": int(existing["amount"])})
            order = await self._order(existing["order_id"])
            if int(amount) != int(order["total"]):
                raise AmountMismatchError(message="Amount does not match the frozen bill.",
                                          details={"expected": int(order["total"])})
            try:
                await self._conn.execute(
                    "UPDATE payments SET status='paid', verified_at=? WHERE id=?",
                    (_now(), existing["id"]),
                )
                await self._conn.execute("UPDATE orders SET payment_status='paid_upi' WHERE id=?",
                                   (order["id"],))
                led = LedgerRepo(self._conn)
                dues = int((await led.get(order["user_id"]))["dues"])
                if dues > 0:  # reconcile what COD-confirm posted; UPI-only stays zero
                    await led.apply_event(order["user_id"], d_dues=-min(dues, int(amount)),
                                    ref=f"order:{order['id']}", actor="upi-webhook",
                                    reason="upi paid", commit=False)
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            return dict((
                await self._conn.execute("SELECT * FROM payments WHERE id=?",
                                           (existing["id"],))
            ).fetchone())

    # -- vendor cash (paid_cash / partial_dues + ledger dues event) ------

    async def mark_paid_cash(self, order_id: str, amount: int, actor: str) -> dict:
        if int(amount) < 0:
            raise ValidationError(message="Invalid cash amount.", details={})
        with WRITE_LOCK:
            order = await self._order(order_id)
            if order["payment_status"] in ("paid_upi", "paid_cash"):
                raise ConflictError(message="Order is already paid.", details={"id": order_id})
            paid_before = await self.paid_sum_for_order(order_id)
            total_paid = paid_before + int(amount)
            full = total_paid >= int(order["total"])
            status = "paid_cash" if full else "partial_dues"
            led = LedgerRepo(self._conn)
            dues = int((await led.get(order["user_id"]))["dues"])
            if await self._dues_posted(order_id) and dues > 0:
                await led.apply_event(order["user_id"], d_dues=-min(dues, int(amount)),
                                ref=f"cash:{order_id}", actor=actor,
                                reason="cash collected", commit=False)
            elif not await self._dues_posted(order_id) and dues == 0 and not full:
                # cash without a prior COD-confirm: carry the remainder as dues (VR-08)
                await led.apply_event(order["user_id"], d_dues=int(order["total"]) - total_paid,
                                ref=f"order:{order_id}", actor=actor,
                                reason="cod remainder carried", commit=False)
            pid = uuid.uuid4().hex
            await self._conn.execute(
                "INSERT INTO payments(id, order_id, user_id, amount, method, provider_ref,"
                " status, created_at, verified_at) VALUES (?,?,?,?,?,?,?, ?, ?)",
                (pid, order_id, order["user_id"], int(amount), "cod",
                 f"cash:{order_id}:{uuid.uuid4().hex[:8]}",
                 "paid" if full else "partial", _now(), _now()),
            )
            await self._conn.execute("UPDATE orders SET payment_status=? WHERE id=?", (status, order_id))
            self._conn.commit()
            payment = dict((
                await self._conn.execute("SELECT * FROM payments WHERE id=?", (pid,))
            ).fetchone())
            fresh = await self._order(order_id)
            return {"payment": payment, "order": fresh,
                    "ledger": await led.get(order["user_id"])}

    # -- refunds (C15: single claimant) ----------------------------------

    async def get_refund(self, refund_id: str) -> dict:
        row = (
            await self._conn.execute("SELECT * FROM refunds WHERE id=?", (refund_id,))
        ).fetchone()
        if row is None:
            raise NotFoundError(message="Refund not found.", details={"id": refund_id})
        return dict(row)

    async def claim_refund(self, refund_id: str, actor_id: str) -> dict:
        with WRITE_LOCK:
            cur = await self._conn.execute(
                "UPDATE refunds SET status='claimed', claimed_by=?, claimed_at=?, attempts=attempts+1"
                " WHERE id=? AND status='pending'",
                (actor_id, _now(), refund_id),
            )
            if cur.rowcount == 0:
                self._conn.rollback()
                raise RefundClaimError(message="Refund already claimed or closed.",
                                      details={"id": refund_id})
            self._conn.commit()
            return await self.get_refund(refund_id)

    async def complete_refund(self, refund_id: str, to_status: str) -> dict:
        if to_status not in ("done", "failed"):
            raise ValidationError(message="Invalid refund outcome.", details={})
        with WRITE_LOCK:
            cur = await self._conn.execute(
                "UPDATE refunds SET status=?, done_at=? WHERE id=? AND status='claimed'",
                (to_status, _now(), refund_id),
            )
            if cur.rowcount == 0:
                self._conn.rollback()
                raise RefundClaimError(message="Refund must be claimed before closing.",
                                      details={"id": refund_id})
            self._conn.commit()
            return await self.get_refund(refund_id)
