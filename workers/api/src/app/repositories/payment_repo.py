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


class OverpayError(AppError):
    code = "OVERPAY"
    status_code = 422


class IntentPendingError(AppError):
    code = "INTENT_PENDING"
    status_code = 409


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


def _stale(created_at: object, minutes: int = 10) -> bool:
    """True when a pending reservation is old enough to be safely retried."""
    try:
        created = _dt.datetime.fromisoformat(str(created_at))
    except (TypeError, ValueError):
        return False
    if created.tzinfo is None:
        created = created.replace(tzinfo=_dt.timezone.utc)
    return _dt.datetime.now(_dt.timezone.utc) - created > _dt.timedelta(minutes=minutes)


def _intent_link(provider_ref: str, amount: int) -> str:
    """Rebuild the UPI deep link for an already-minted provider order."""
    return (f"upi://pay?pa={_agency_vpa()}&pn=Shodasha&am={int(amount) / 100:.2f}"
            f"&tr={provider_ref}&cu=INR")


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

    # -- webhook (C16: duplicate ref → existing, no second credit) -------

    async def apply_webhook(self, provider_ref: str, amount: int, payee: str,
                      order_id: str | None = None) -> dict:
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
            try:
                await self._conn.execute(
                    "UPDATE payments SET status='paid', verified_at=? WHERE id=?",
                    (_now(), existing["id"]),
                )
                if order["state"] in ("cancelled", "rejected"):
                    # Money arrived after the order died: record the capture
                    # and queue the exact refund. Never resurrect the order.
                    refund_id = uuid.uuid4().hex
                    await self._conn.execute(
                        "INSERT OR IGNORE INTO refunds(id, order_id, payment_id,"
                        " amount, method, status, claimed_by, claimed_at, attempts, created_at, done_at)"
                        " VALUES (?,?,?,?,?,'pending',NULL,NULL,0,?,NULL)",
                        (refund_id, order["id"], existing["id"], int(amount),
                         str(existing.get("method") or "upi"), _now()),
                    )
                    self._conn.commit()
                    return {**dict((await self._conn.execute(
                        "SELECT * FROM payments WHERE id=?", (existing["id"],))).fetchone()),
                        "_refund_queued": True}
                if order["payment_status"] in ("paid_upi", "paid_cash"):
                    # A second capture for an already-settled order is a
                    # duplicate payment, not extra revenue.
                    refund_id = uuid.uuid4().hex
                    await self._conn.execute(
                        "INSERT OR IGNORE INTO refunds(id, order_id, payment_id,"
                        " amount, method, status, claimed_by, claimed_at, attempts, created_at, done_at)"
                        " VALUES (?,?,?,?,?,'pending',NULL,NULL,0,?,NULL)",
                        (refund_id, order["id"], existing["id"], int(amount),
                         str(existing.get("method") or "upi"), _now()),
                    )
                    self._conn.commit()
                    return {**dict((await self._conn.execute(
                        "SELECT * FROM payments WHERE id=?", (existing["id"],))).fetchone()),
                        "_refund_queued": True}
                await self._conn.execute("UPDATE orders SET payment_status='paid_upi' WHERE id=?",
                                   (order["id"],))
                if await self._dues_posted(order["id"]):
                    led = LedgerRepo(self._conn)
                    dues = int((await led.get(order["user_id"]))["dues"])
                    if dues > 0:  # clear only what this order posted
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

    async def settle_dues_intent(self, intent: dict, amount: int) -> dict:
        """Settle a dues intent against real open-order dues first, then the
        ledger remainder. Any over-capture is queued for refund, never kept."""
        with WRITE_LOCK:
            fresh = (await self._conn.execute(
                "SELECT * FROM dues_intents WHERE id=?", (intent["id"],))).fetchone()
            if fresh is None:
                raise NotFoundError(message="Dues intent not found.", details={})
            if fresh["status"] == "paid":
                return {**dict(fresh), "_duplicate": True}
            if int(amount) != int(fresh["amount"]):
                raise AmountMismatchError(message="Amount does not match the intent.",
                                          details={"expected": int(fresh["amount"])})
            remaining = int(amount)
            user_id = str(fresh["user_id"])
            try:
                led = LedgerRepo(self._conn)
                ledger_dues = int((await led.get(user_id))["dues"])
                orders = (await self._conn.execute(
                    "SELECT id, total FROM orders WHERE user_id=? AND state NOT IN ('cancelled','rejected')"
                    " AND payment_status IN ('unpaid','link_sent','partial_dues') ORDER BY created_at, id",
                    (user_id,))).fetchall()
                for o in orders:
                    paid = await self.paid_sum_for_order(str(o["id"]))
                    due = max(0, int(o["total"]) - int(paid))
                    if due <= 0 or remaining <= 0:
                        continue
                    alloc = min(due, remaining)
                    await self._conn.execute(
                        "INSERT INTO payments(id, order_id, user_id, amount, method, provider_ref,"
                        " status, created_at, verified_at) VALUES (?,?,?,?,?,?,?,?,?)",
                        (uuid.uuid4().hex, str(o["id"]), user_id, int(alloc), "upi",
                         f"dues:{fresh['id']}:{o['id']}", "paid", _now(), _now()))
                    status = "paid_upi" if int(paid) + alloc >= int(o["total"]) else "partial_dues"
                    await self._conn.execute(
                        "UPDATE orders SET payment_status=? WHERE id=?", (status, str(o["id"])))
                    await self._conn.execute(
                        "UPDATE payments SET status='failed' WHERE order_id=? AND status='link_sent'",
                        (str(o["id"]),))
                    if await self._dues_posted(str(o["id"])):
                        # These rupees already sit in ledger.dues: move them
                        # off the ledger exactly once as the order is marked
                        # paid, otherwise the door could collect them twice.
                        pay = min(alloc, ledger_dues)
                        if pay > 0:
                            await led.apply_event(
                                user_id, d_dues=-pay, ref=f"dues:{fresh['id']}:{o['id']}",
                                actor="upi-webhook", reason="dues upi paid", commit=False)
                            ledger_dues -= pay
                    remaining -= alloc
                if remaining > 0 and ledger_dues > 0:
                    pay = min(ledger_dues, remaining)
                    await led.apply_event(user_id, d_dues=-pay, ref=f"dues:{fresh['id']}",
                                          actor="upi-webhook", reason="dues upi paid", commit=False)
                    remaining -= pay
                await self._conn.execute(
                    "UPDATE dues_intents SET status='paid', verified_at=? WHERE id=?",
                    (_now(), fresh["id"]))
                if remaining > 0:
                    await self._conn.execute(
                        "INSERT OR IGNORE INTO refunds(id, order_id, subscription_id, payment_id,"
                        " amount, method, status, claimed_by, claimed_at, attempts, created_at, done_at)"
                        " VALUES (?,NULL,NULL,?,?,'upi','pending',NULL,NULL,0,?,NULL)",
                        (uuid.uuid4().hex, f"dues:{fresh['id']}", int(remaining), _now()))
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            saved = dict((await self._conn.execute(
                "SELECT * FROM dues_intents WHERE id=?", (fresh["id"],))).fetchone())
            if remaining > 0:
                saved["_refund_queued"] = True
            else:
                saved["_duplicate"] = False
            return saved

    async def reserve_dues_intent(self, user_id: str, amount: int, idem_key: str) -> dict:
        """Reserve a dues intent locally before Razorpay. Dues no longer touch
        payments.order_id, so the old FK violation cannot recur."""
        if not idem_key or not str(idem_key).strip():
            raise ValidationError(message="Idempotency-Key header required.", details={})
        if int(amount) <= 0:
            raise ValidationError(message="No dues to pay.", details={})
        scoped = f"POST /v1/payments/dues-intent:{idem_key.strip()}"
        phash = _payload_hash(f"dues:{user_id}", int(amount))
        with WRITE_LOCK:
            stored = (await self._conn.execute(
                "SELECT payload_hash, result, created_at FROM idempotency_keys"
                " WHERE user_id=? AND scoped_key=?", (user_id, scoped))).fetchone()
            if stored is not None:
                if stored["payload_hash"] != phash:
                    raise PayloadMismatchError(
                        message="Idempotency-Key was already used with a different payload.",
                        details={"user_id": user_id})
                result = json.loads(stored["result"] or "{}")
                if result.get("pending"):
                    cached = (await self._conn.execute(
                        "SELECT * FROM dues_intents WHERE id=?",
                        (result.get("intent_id"),))).fetchone()
                    if cached is not None and cached.get("provider_ref"):
                        # Provider order exists; replay it instead of deleting
                        # a live payment link the customer may already have.
                        intent = dict(cached)
                        result = {"intent": intent,
                                  "link": intent.get("provider_link") or _intent_link(
                                      str(intent["provider_ref"]), int(intent["amount"])),
                                  "provider_ref": intent["provider_ref"]}
                        await self._conn.execute(
                            "UPDATE idempotency_keys SET result=? WHERE user_id=? AND scoped_key=?",
                            (json.dumps(result), user_id, scoped))
                        self._conn.commit()
                        return result
                    if not _stale(stored["created_at"]):
                        raise IntentPendingError(message="Dues payment link is still being created.",
                                                 details={})
                    await self._conn.execute(
                        "DELETE FROM idempotency_keys WHERE user_id=? AND scoped_key=?",
                        (user_id, scoped))
                    await self._conn.execute(
                        "DELETE FROM dues_intents WHERE id=? AND status='pending'",
                        (result.get("intent_id"),))
                else:
                    return result
            iid = uuid.uuid4().hex
            try:
                await self._conn.execute(
                    "INSERT INTO dues_intents(id, user_id, amount, provider_ref, provider_link,"
                    " status, created_at, verified_at) VALUES (?,?,?,NULL,NULL,'pending',?,NULL)",
                    (iid, user_id, int(amount), _now()))
                await self._conn.execute(
                    "INSERT INTO idempotency_keys(user_id, scoped_key, order_id, payload_hash, result,"
                    " created_at) VALUES (?,?,?,?,?,?)",
                    (user_id, scoped, iid, phash,
                     json.dumps({"pending": True, "intent_id": iid}), _now()))
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            return {"intent_id": iid, "amount": int(amount)}

    async def attach_dues_intent(self, intent_id: str, user_id: str, idem_key: str,
                                 provider_ref: str, link: str) -> dict:
        scoped = f"POST /v1/payments/dues-intent:{idem_key.strip()}"
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "UPDATE dues_intents SET provider_ref=?, provider_link=?, status='link_sent'"
                    " WHERE id=? AND provider_ref IS NULL", (provider_ref, link, intent_id))
                intent = dict((await self._conn.execute(
                    "SELECT * FROM dues_intents WHERE id=?", (intent_id,))).fetchone())
                result = {"intent": intent, "link": link, "provider_ref": provider_ref}
                await self._conn.execute(
                    "UPDATE idempotency_keys SET result=? WHERE user_id=? AND scoped_key=?",
                    (json.dumps(result), user_id, scoped))
                self._conn.commit()
            except sqlite3.IntegrityError as e:
                self._conn.rollback()
                raise ConflictError(message="Payment reference already exists.", details={}) from e
            except Exception:
                self._conn.rollback()
                raise
            return result

    async def fail_dues_intent(self, intent_id: str, user_id: str, idem_key: str) -> None:
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "DELETE FROM dues_intents WHERE id=? AND status='pending'", (intent_id,))
                await self._conn.execute(
                    "DELETE FROM idempotency_keys WHERE user_id=? AND scoped_key=?",
                    (user_id, f"POST /v1/payments/dues-intent:{idem_key.strip()}"))
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise

    async def find_dues_intent_by_ref(self, provider_ref: str) -> dict | None:
        row = (await self._conn.execute(
            "SELECT * FROM dues_intents WHERE provider_ref=?", (provider_ref,))).fetchone()
        return dict(row) if row is not None else None

    def assert_payee(self, payee: str) -> None:
        if payee != _agency_vpa():
            raise PayeeMismatchError(message="Collection must go to the agency account.",
                                     details={"expected_payee": "agency"})

    # -- vendor cash (paid_cash / partial_dues + ledger dues event) ------

    async def mark_paid_cash(self, order_id: str, amount: int, actor: str) -> dict:
        """Phase 8 §8.3: this wrapper owns the lock+commit for standalone
        callers (admin mark_cash). Vendor cash_post holds the lock itself so
        the payment writes and the in_hand bump commit together — use
        mark_paid_cash_locked there."""
        with WRITE_LOCK:
            try:
                out = await self.mark_paid_cash_locked(order_id, amount, actor)
                self._conn.commit()
                return out
            except Exception:
                self._conn.rollback()
                raise

    async def mark_paid_cash_locked(self, order_id: str, amount: int, actor: str) -> dict:
        """Lock-free core: payment row + paid_cash/partial_dues + dues
        reconcile. Caller holds WRITE_LOCK and commits (single txn with any
        sibling writes, e.g. vendor in_hand — never two txns on D1)."""
        if int(amount) < 0:
            raise ValidationError(message="Invalid cash amount.", details={})
        order = await self._order(order_id)
        if order["payment_status"] in ("paid_upi", "paid_cash"):
            raise ConflictError(message="Order is already paid.", details={"id": order_id})
        paid_before = await self.paid_sum_for_order(order_id)
        remaining = int(order["total"]) - paid_before
        if int(amount) > remaining:
            raise OverpayError(message="Cash exceeds the remaining bill.",
                               details={"remaining": remaining})
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
        from app.services.dispatch_service import write_audit  # noqa: PLC0415 (lazy, cycle-safe)

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
            await write_audit(self._conn, actor=actor_id, action="refund.claim",
                              entity="refunds", entity_id=refund_id)
            self._conn.commit()
            return await self.get_refund(refund_id)

    async def complete_refund(self, refund_id: str, to_status: str, actor_id: str = "") -> dict:
        from app.services.dispatch_service import write_audit  # noqa: PLC0415 (lazy, cycle-safe)

        if to_status not in ("done", "failed"):
            raise ValidationError(message="Invalid refund outcome.", details={})
        with WRITE_LOCK:
            row = (await self._conn.execute(
                "SELECT claimed_by, status FROM refunds WHERE id=?", (refund_id,))).fetchone()
            if row is None or row["status"] != "claimed":
                self._conn.rollback()
                raise RefundClaimError(message="Refund must be claimed before closing.",
                                        details={"id": refund_id})
            if actor_id and str(row["claimed_by"] or "") == str(actor_id):
                # Maker-checker: the claimer never closes their own claim.
                self._conn.rollback()
                raise RefundClaimError(message="Claimer cannot close their own refund.",
                                        details={"id": refund_id})
            cur = await self._conn.execute(
                "UPDATE refunds SET status=?, done_at=? WHERE id=? AND status='claimed'",
                (to_status, _now(), refund_id),
            )
            if cur.rowcount == 0:
                self._conn.rollback()
                raise RefundClaimError(message="Refund must be claimed before closing.",
                                        details={"id": refund_id})
            await write_audit(self._conn, actor=actor_id or "admin", action=f"refund.{to_status}",
                              entity="refunds", entity_id=refund_id)
            self._conn.commit()
            return await self.get_refund(refund_id)
