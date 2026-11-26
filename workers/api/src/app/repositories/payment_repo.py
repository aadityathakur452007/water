from __future__ import annotations

import json
import sqlite3
import uuid

from app.core.errors import ConflictError, NotFoundError, ValidationError
from app.db import WRITE_LOCK
from app.repositories.ledger_repo import LedgerRepo
from app.repositories.payment._common import (  # noqa: F401
    AmountMismatchError,
    Conn,
    INTENT_ENDPOINT,
    IntentPendingError,
    OverpayError,
    PayeeMismatchError,
    PayloadMismatchError,
    RefundClaimError,
    _CHUNK,
    _agency_vpa,
    _can_mark_paid,
    _intent_link,
    _now,
    _payload_hash,
    _payment_guard,
    _refund_worthy,
    _stale,
)

from app.repositories.payment.dues_and_refunds import PaymentDuesRefundsMixin


class PaymentRepo(PaymentDuesRefundsMixin):
    def __init__(self, conn: Conn):
        self._conn = conn

    @property
    def conn(self) -> Conn:
        return self._conn

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

    async def paid_sums_for_orders(self, order_ids: list[str]) -> dict[str, int]:
        """Paid-to-date per order (chunked for D1's parameter cap)."""
        ids = list(dict.fromkeys(o for o in order_ids if o))
        out: dict[str, int] = {}
        for i in range(0, len(ids), _CHUNK):
            chunk = ids[i:i + _CHUNK]
            marks = ",".join("?" * len(chunk))
            rows = (await self._conn.execute(
                "SELECT order_id, COALESCE(SUM(amount),0) AS paid FROM payments"
                f" WHERE order_id IN ({marks}) AND status IN ('paid','partial')"
                " GROUP BY order_id",
                tuple(chunk),
            )).fetchall()
            out.update({r["order_id"]: int(r["paid"]) for r in rows})
        return out

    async def list_user_payments(self, user_id: str, limit: int = 50) -> list[dict]:
        rows = (
            await self._conn.execute(
                "SELECT p.id, p.order_id, p.amount, p.method, p.provider_ref, p.status, p.created_at, p.verified_at,"
                " COALESCE(o.n, 0) as jars_count, COALESCE(o.deposit_due, 0) as deposit_due, COALESCE(o.water_bill, 0) as water_bill"
                " FROM payments p LEFT JOIN orders o ON o.id = p.order_id"
                " WHERE p.user_id = ? ORDER BY p.created_at DESC LIMIT ?",
                (user_id, max(1, min(int(limit), 100))),
            )
        ).fetchall()
        return [dict(r) for r in rows]

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

    async def dues_posted_for_orders(self, order_ids: list[str]) -> set[str]:
        """Order ids that already have a positive dues ledger event."""
        ids = list(dict.fromkeys(o for o in order_ids if o))
        out: set[str] = set()
        for i in range(0, len(ids), _CHUNK):
            chunk = ids[i:i + _CHUNK]
            marks = ",".join("?" * len(chunk))
            rows = (await self._conn.execute(
                "SELECT DISTINCT ref_id FROM ledger_events WHERE ref_type='order'"
                f" AND kind='dues' AND d_dues>0 AND ref_id IN ({marks})",
                tuple(chunk),
            )).fetchall()
            out.update(r["ref_id"] for r in rows)
        return out

    # -- intent (reserve locally BEFORE the provider call) ----------------

    async def reserve_intent(self, order_id: str, amount: int, idem_key: str) -> dict:
        """Reserve the idempotency key + payment row, then let the caller mint
        the provider order. Same key replays the stored link; a concurrent
        request gets 409 INTENT_PENDING instead of a second Razorpay order."""
        if not idem_key or not str(idem_key).strip():
            raise ValidationError(message="Idempotency-Key header required.", details={})
        order = await self._order(order_id)
        if order["state"] in ("cancelled", "rejected"):
            raise ConflictError(message="Order cannot be paid.", details={"id": order_id})
        if order["payment_status"] in ("paid_upi", "paid_cash"):
            raise ConflictError(message="Order is already paid.", details={"id": order_id})
        if int(amount) != int(order["total"]):
            raise AmountMismatchError(message="Amount does not match the frozen bill.",
                                      details={"expected": int(order["total"])})
        scoped = f"{INTENT_ENDPOINT}:{idem_key.strip()}"
        phash = _payload_hash(order_id, int(amount))
        with WRITE_LOCK:
            stored = (
                await self._conn.execute(
                    "SELECT payload_hash, result, created_at FROM idempotency_keys"
                    " WHERE user_id=? AND scoped_key=?",
                    (order["user_id"], scoped),
                )
            ).fetchone()
            if stored is not None:
                if stored["payload_hash"] != phash:
                    raise PayloadMismatchError(
                        message="Idempotency-Key was already used with a different payload.",
                        details={"order_id": order_id})
                result = json.loads(stored["result"] or "{}")
                if result.get("pending"):
                    cached = (await self._conn.execute(
                        "SELECT * FROM payments WHERE id=?",
                        (result.get("payment_id"),))).fetchone()
                    if cached is not None and cached.get("provider_ref"):
                        # Provider succeeded, cache write didn't: rebuild the
                        # same link instead of minting a second Razorpay order.
                        payment = dict(cached)
                        result = {"payment": payment,
                                  "link": _intent_link(str(payment["provider_ref"]),
                                                       int(payment["amount"])),
                                  "provider_ref": payment["provider_ref"]}
                        await self._conn.execute(
                            "UPDATE idempotency_keys SET result=? WHERE user_id=? AND scoped_key=?",
                            (json.dumps(result), order["user_id"], scoped))
                        self._conn.commit()
                        return result
                    if not _stale(stored["created_at"]):
                        raise IntentPendingError(
                            message="Payment link is still being created.",
                            details={"order_id": order_id})
                    # Stale reservation: drop BOTH rows. Leaving the link_sent
                    # payment behind would block the retry forever (open_row).
                    await self._conn.execute(
                        "DELETE FROM payments WHERE id=? AND status='link_sent'",
                        (result.get("payment_id"),))
                    await self._conn.execute(
                        "UPDATE orders SET payment_status='unpaid'"
                        " WHERE id=? AND payment_status='link_sent'", (order_id,))
                    await self._conn.execute(
                        "DELETE FROM idempotency_keys WHERE user_id=? AND scoped_key=?",
                        (order["user_id"], scoped))
                else:
                    return result
            open_row = (await self._conn.execute(
                "SELECT * FROM payments WHERE order_id=? AND status='link_sent' LIMIT 1",
                (order_id,))).fetchone()
            if open_row is not None:
                payment = dict(open_row)
                if not payment.get("provider_ref"):
                    if not _stale(payment["created_at"]):
                        raise IntentPendingError(message="A payment link is already open.",
                                                 details={"order_id": order_id})
                    await self._conn.execute(
                        "DELETE FROM payments WHERE id=? AND status='link_sent'",
                        (payment["id"],))
                    await self._conn.execute(
                        "UPDATE orders SET payment_status='unpaid'"
                        " WHERE id=? AND payment_status='link_sent'", (order_id,))
                else:
                    # Replay the live link for a new key: one order, one
                    # provider intent, no duplicate Razorpay order.
                    result = {"payment": payment,
                              "link": _intent_link(str(payment["provider_ref"]),
                                                   int(payment["amount"])),
                              "provider_ref": payment["provider_ref"]}
                    await self._conn.execute(
                        "INSERT OR IGNORE INTO idempotency_keys(user_id, scoped_key, order_id,"
                        " payload_hash, result, created_at) VALUES (?,?,?,?,?,?)",
                        (order["user_id"], scoped, order_id, phash, json.dumps(result), _now()))
                    self._conn.commit()
                    return result
            pid = uuid.uuid4().hex
            try:
                await self._conn.execute(
                    "INSERT INTO payments(id, order_id, user_id, amount, method, provider_ref,"
                    " status, created_at, verified_at) VALUES (?,?,?,?,?,NULL,'link_sent',?,NULL)",
                    (pid, order_id, order["user_id"], int(amount), "upi", _now()),
                )
                await self._conn.execute(
                    "UPDATE orders SET payment_status='link_sent' WHERE id=?", (order_id,))
                await self._conn.execute(
                    "INSERT INTO idempotency_keys(user_id, scoped_key, order_id, payload_hash, result,"
                    " created_at) VALUES (?,?,?,?,?,?)",
                    (order["user_id"], scoped, order_id, phash,
                     json.dumps({"pending": True, "payment_id": pid}), _now()),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            return {"payment_id": pid, "amount": int(amount), "user_id": order["user_id"]}

    async def attach_intent(self, payment_id: str, idem_key: str, provider_ref: str,
                            link: str) -> dict:
        """Attach the provider ref/link to a reserved intent and cache the
        replay response under the same idempotency key."""
        with WRITE_LOCK:
            row = (await self._conn.execute(
                "SELECT order_id, user_id FROM payments WHERE id=?", (payment_id,))).fetchone()
            if row is None:
                raise NotFoundError(message="Payment intent not found.", details={})
            scoped = f"{INTENT_ENDPOINT}:{idem_key.strip()}"
            try:
                await self._conn.execute(
                    "UPDATE payments SET provider_ref=? WHERE id=? AND provider_ref IS NULL",
                    (provider_ref, payment_id))
                payment = dict((await self._conn.execute(
                    "SELECT * FROM payments WHERE id=?", (payment_id,))).fetchone())
                result = {"payment": payment, "link": link, "provider_ref": provider_ref}
                await self._conn.execute(
                    "UPDATE idempotency_keys SET result=? WHERE user_id=? AND scoped_key=?",
                    (json.dumps(result), row["user_id"], scoped))
                self._conn.commit()
            except sqlite3.IntegrityError as e:
                self._conn.rollback()
                raise ConflictError(message="Payment reference already exists.", details={}) from e
            except Exception:
                self._conn.rollback()
                raise
            return result

    async def fail_intent(self, payment_id: str, idem_key: str) -> None:
        """Provider failed before returning: drop the reservation so the same
        key can retry. No money moved, so no audit row is owed."""
        with WRITE_LOCK:
            row = (await self._conn.execute(
                "SELECT order_id, user_id FROM payments WHERE id=?", (payment_id,))).fetchone()
            if row is None:
                self._conn.rollback()
                return
            try:
                await self._conn.execute(
                    "DELETE FROM payments WHERE id=? AND status='link_sent'", (payment_id,))
                await self._conn.execute(
                    "UPDATE orders SET payment_status='unpaid' WHERE id=? AND payment_status='link_sent'",
                    (row["order_id"],))
                await self._conn.execute(
                    "DELETE FROM idempotency_keys WHERE user_id=? AND scoped_key=?",
                    (row["user_id"], f"{INTENT_ENDPOINT}:{idem_key.strip()}"))
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise

    async def switch_to_cod(self, order_id: str, user_id: str) -> dict:
        """Convert one unpaid UPI order to COD in one CAS batch (no cancel/re-order).

        Naturally idempotent: a COD order is returned unchanged. An open UPI
        link is marked failed so a customer cannot pay the same order twice;
        any already-captured payment stays authoritative and blocks the move.
        """
        with WRITE_LOCK:
            order = (await self._conn.execute(
                "SELECT * FROM orders WHERE id=? AND user_id=?", (order_id, user_id))).fetchone()
            if order is None:
                self._conn.rollback()
                raise NotFoundError(message="Order not found.", details={"id": order_id})
            if order["state"] in ("cancelled", "rejected"):
                self._conn.rollback()
                raise ConflictError(message="Order cannot be paid.", details={"id": order_id})
            if order["payment_mode"] == "cod":
                self._conn.rollback()
                return dict(order)
            if order["payment_status"] in ("paid_upi", "paid_cash", "partial_dues"):
                self._conn.rollback()
                raise ConflictError(
                    message="This order already has a payment. Pay the remaining balance instead.",
                    details={"id": order_id, "payment_status": order["payment_status"]})
            captured = (await self._conn.execute(
                "SELECT 1 FROM payments WHERE order_id=? AND status IN ('paid','partial') LIMIT 1",
                (order_id,))).fetchone()
            if captured is not None:
                self._conn.rollback()
                raise ConflictError(
                    message="This order already has a payment. Pay the remaining balance instead.",
                    details={"id": order_id})
            rows = await self._conn.batch([
                (
                    "UPDATE orders SET payment_mode='cod', payment_status='unpaid'"
                    " WHERE id=? AND user_id=? AND payment_mode!='cod'"
                    " AND payment_status NOT IN ('paid_upi','paid_cash','partial_dues')"
                    " AND NOT EXISTS (SELECT 1 FROM payments WHERE order_id=?"
                    "                 AND status IN ('paid','partial'))",
                    (order_id, user_id, order_id),
                ),
                (
                    "UPDATE payments SET status='failed'"
                    " WHERE order_id=? AND status='link_sent'"
                    " AND EXISTS (SELECT 1 FROM orders WHERE id=? AND payment_mode='cod')",
                    (order_id, order_id),
                ),
            ])
            self._conn.commit()
            if rows[0].rowcount == 0:
                fresh = (await self._conn.execute(
                    "SELECT * FROM orders WHERE id=? AND user_id=?",
                    (order_id, user_id))).fetchone()
                if fresh is None:
                    raise NotFoundError(message="Order not found.", details={"id": order_id})
                if fresh["payment_mode"] == "cod":
                    return dict(fresh)
                raise ConflictError(
                    message="This order already has a payment. Pay the remaining balance instead.",
                    details={"id": order_id, "payment_status": fresh["payment_status"]})
            fresh = (await self._conn.execute(
                "SELECT * FROM orders WHERE id=?", (order_id,))).fetchone()
            return dict(fresh)

    # -- webhook (C16: duplicate ref → existing, no second credit) -------

    async def apply_webhook(self, provider_ref: str, amount: int, payee: str,
                      order_id: str | None = None) -> dict:
        """Settle one provider capture in a single CAS batch.

        Exactly one of "mark the order paid" and "queue a refund" applies at
        batch time, expressed in SQL. A concurrent cancel either claims the
        payment first (this batch then refunds nothing) or loses the order CAS
        (this batch refunds its own capture). ``_duplicate`` /
        ``_refund_queued`` are internal response flags.
        """
        self.assert_payee(payee)
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

            now = _now()
            token = uuid.uuid4().hex
            refund_id = uuid.uuid4().hex
            pay_guard = _payment_guard(existing["id"], token)
            refund_guard = _refund_worthy(order["id"])
            paid_guard = _can_mark_paid(order["id"])
            stmts: list[tuple[str, tuple]] = [
                (
                    "UPDATE payments SET status='paid', verified_at=?, settlement_token=?"
                    " WHERE id=? AND status!='paid'",
                    (now, token, existing["id"]),
                ),
                (
                    "UPDATE payments SET refund_id=?"
                    " WHERE id=? AND refund_id IS NULL"
                    f" AND {pay_guard[0]} AND {refund_guard[0]}",
                    (refund_id, existing["id"], *pay_guard[1], *refund_guard[1]),
                ),
                (
                    "INSERT OR IGNORE INTO refunds(id, order_id, payment_id, amount, method,"
                    " status, claimed_by, claimed_at, attempts, created_at, done_at)"
                    " SELECT ?, ?, ?, ?, ?, 'pending', NULL, NULL, 0, ?, NULL"
                    " WHERE EXISTS (SELECT 1 FROM payments WHERE id=? AND refund_id=?)",
                    (refund_id, order["id"], existing["id"], int(amount),
                     str(existing.get("method") or "upi"), now, existing["id"], refund_id),
                ),
                (
                    "UPDATE orders SET payment_status='paid_upi'"
                    f" WHERE id=? AND {paid_guard[0]} AND {pay_guard[0]}",
                    (order["id"], *paid_guard[1], *pay_guard[1]),
                ),
                (
                    # A refunded capture never leaves a stale "link_sent" on a
                    # COD/dead order: cash is still due at the door.
                    "UPDATE orders SET payment_status='unpaid'"
                    " WHERE id=? AND payment_status='link_sent'"
                    f" AND {pay_guard[0]} AND {refund_guard[0]}",
                    (order["id"], *pay_guard[1], *refund_guard[1]),
                ),
            ]
            if await self._dues_posted(order["id"]):
                led = LedgerRepo(self._conn)
                dues = int((await led.get(order["user_id"]))["dues"])
                if dues > 0:  # clear only what this order posted
                    # The clear runs after the order CAS, so its guard is the
                    # post-state "this batch marked it paid_upi" plus the
                    # payment token — not the pre-state _can_mark_paid check.
                    guard_sql = (
                        f"{pay_guard[0]}"
                        " AND EXISTS (SELECT 1 FROM orders WHERE id=?"
                        "             AND payment_status='paid_upi')"
                        " AND EXISTS (SELECT 1 FROM ledger_events WHERE ref_type='order'"
                        " AND ref_id=? AND kind='dues' AND d_dues>0)"
                    )
                    guard_params = (*pay_guard[1], order["id"], order["id"])
                    stmts.extend(led.build_event_stmts(
                        order["user_id"], d_dues=-min(dues, int(amount)),
                        ref=f"payment:{existing['id']}", actor="upi-webhook",
                        reason="upi paid", guard=(guard_sql, guard_params)))
            rows = await self._conn.batch(stmts)
            self._conn.commit()
            if rows[0].rowcount == 0:
                fresh = (await self._conn.execute(
                    "SELECT * FROM payments WHERE id=?", (existing["id"],))).fetchone()
                if fresh is not None and fresh["status"] == "paid":
                    return {**dict(fresh), "_duplicate": True}
                raise ConflictError(message="Payment could not be settled.", details={})
            saved = dict((await self._conn.execute(
                "SELECT * FROM payments WHERE id=?", (existing["id"],))).fetchone())
            if rows[1].rowcount > 0:
                saved["_refund_queued"] = True
            return saved

    def assert_payee(self, payee: str) -> None:
        if payee != _agency_vpa():
            raise PayeeMismatchError(message="Collection must go to the agency account.",
                                     details={"expected_payee": "agency"})
