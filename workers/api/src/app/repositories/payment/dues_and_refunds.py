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

class PaymentDuesRefundsMixin:
    async def settle_dues_intent(self, intent: dict, amount: int) -> dict:
        """Settle a dues intent in one CAS batch.

        Allocations are inserted only for orders that are still open at batch
        time. The refund is derived in SQL from the money actually allocated
        (payment rows) plus the ledger remainder, so a cancelled order cannot
        leave customer money stranded. Any over-capture is refunded, never kept.
        """
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
            led = LedgerRepo(self._conn)
            ledger_dues = int((await led.get(user_id))["dues"])
            orders = (await self._conn.execute(
                "SELECT id, total FROM orders WHERE user_id=? AND state NOT IN ('cancelled','rejected')"
                " AND payment_status IN ('unpaid','link_sent','partial_dues') ORDER BY created_at, id",
                (user_id,))).fetchall()
            allocations: list[tuple[str, int, int]] = []
            for o in orders:
                paid = await self.paid_sum_for_order(str(o["id"]))
                due = max(0, int(o["total"]) - int(paid))
                if due <= 0 or remaining <= 0:
                    continue
                alloc = min(due, remaining)
                clear = 0
                if await self._dues_posted(str(o["id"])):
                    # These rupees already sit in ledger.dues: move them off
                    # the ledger exactly once as the order is marked paid,
                    # otherwise the door could collect them twice.
                    clear = min(alloc, ledger_dues)
                    ledger_dues -= clear
                allocations.append((str(o["id"]), alloc, clear))
                remaining -= alloc
            final_clear = min(ledger_dues, remaining) if remaining > 0 and ledger_dues > 0 else 0

            now = _now()
            token = uuid.uuid4().hex
            intent_guard = ("EXISTS (SELECT 1 FROM dues_intents WHERE id=?"
                            " AND settlement_token=?)", (fresh["id"], token))
            stmts: list[tuple[str, tuple]] = [
                (
                    "UPDATE dues_intents SET status='paid', verified_at=?, settlement_token=?"
                    " WHERE id=? AND status!='paid'",
                    (now, token, fresh["id"]),
                ),
            ]
            for order_id, alloc, clear in allocations:
                ref = f"dues:{fresh['id']}:{order_id}"
                stmts.append((
                    "INSERT INTO payments(id, order_id, user_id, amount, method, provider_ref,"
                    " status, created_at, verified_at)"
                    " SELECT ?, o.id, ?, ?, 'upi', ?, 'paid', ?, ?"
                    " FROM orders o WHERE o.id=? AND o.user_id=?"
                    " AND o.state NOT IN ('cancelled','rejected')"
                    " AND o.payment_status IN ('unpaid','link_sent','partial_dues')"
                    f" AND {intent_guard[0]}",
                    (uuid.uuid4().hex, user_id, int(alloc), ref, now, now,
                     order_id, user_id, *intent_guard[1]),
                ))
                stmts.append((
                    "UPDATE orders SET payment_status = CASE"
                    " WHEN (SELECT COALESCE(SUM(amount),0) FROM payments"
                    "       WHERE order_id=? AND status IN ('paid','partial')) >= total"
                    " THEN 'paid_upi' ELSE 'partial_dues' END"
                    " WHERE id=? AND EXISTS (SELECT 1 FROM payments"
                    "                        WHERE provider_ref=? AND status='paid')",
                    (order_id, order_id, ref),
                ))
                stmts.append((
                    "UPDATE payments SET status='failed'"
                    " WHERE order_id=? AND status='link_sent'"
                    " AND EXISTS (SELECT 1 FROM payments"
                    "             WHERE provider_ref=? AND status='paid')",
                    (order_id, ref),
                ))
                if clear > 0:
                    clear_guard = (
                        "EXISTS (SELECT 1 FROM payments WHERE provider_ref=? AND status='paid')"
                        " AND EXISTS (SELECT 1 FROM ledger_events WHERE ref_type='order'"
                        " AND ref_id=? AND kind='dues' AND d_dues>0)",
                        (ref, order_id),
                    )
                    stmts.extend(led.build_event_stmts(
                        user_id, d_dues=-int(clear), ref=ref, actor="upi-webhook",
                        reason="dues upi paid", guard=clear_guard))
            if final_clear > 0:
                stmts.extend(led.build_event_stmts(
                    user_id, d_dues=-int(final_clear), ref=f"dues:{fresh['id']}",
                    actor="upi-webhook", reason="dues upi paid", guard=intent_guard))
            # Refund = captured - allocated payments - ledger remainder. The
            # per-order ledger clears are already represented by their payment
            # rows, so only the exact-intent clear is subtracted here.
            refund_sql = (
                "? - COALESCE((SELECT SUM(amount) FROM payments WHERE provider_ref LIKE ?), 0)"
                " - COALESCE((SELECT SUM(-d_dues) FROM ledger_events"
                "             WHERE ref_type='dues' AND ref_id=?), 0)"
            )
            refund_ref = f"dues:{fresh['id']}"
            pattern = f"{refund_ref}:%"
            stmts.append((
                "INSERT OR IGNORE INTO refunds(id, order_id, subscription_id, payment_id,"
                " amount, method, status, claimed_by, claimed_at, attempts, created_at, done_at)"
                f" SELECT ?, NULL, NULL, ?, {refund_sql}, 'upi', 'pending',"
                f" NULL, NULL, 0, ?, NULL WHERE ({refund_sql}) > 0"
                f" AND {intent_guard[0]}",
                (uuid.uuid4().hex, refund_ref, int(amount), pattern, fresh["id"],
                 now, int(amount), pattern, fresh["id"], *intent_guard[1]),
            ))
            rows = await self._conn.batch(stmts)
            self._conn.commit()
            if rows[0].rowcount == 0:
                current = (await self._conn.execute(
                    "SELECT * FROM dues_intents WHERE id=?", (fresh["id"],))).fetchone()
                if current is not None and current["status"] == "paid":
                    return {**dict(current), "_duplicate": True}
                raise ConflictError(message="Dues intent could not be settled.", details={})
            saved = dict((await self._conn.execute(
                "SELECT * FROM dues_intents WHERE id=?", (fresh["id"],))).fetchone())
            if rows[-1].rowcount > 0:
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
            open_row = (await self._conn.execute(
                "SELECT * FROM dues_intents WHERE user_id=?"
                " AND status IN ('pending','link_sent')"
                " ORDER BY created_at DESC LIMIT 1", (user_id,))).fetchone()
            if open_row is not None:
                intent = dict(open_row)
                if intent.get("provider_ref"):
                    return {"intent": intent,
                            "link": intent.get("provider_link") or _intent_link(
                                str(intent["provider_ref"]), int(intent["amount"])),
                            "provider_ref": intent["provider_ref"]}
                if not _stale(intent["created_at"]):
                    raise IntentPendingError(
                        message="A dues payment link is already being created.",
                        details={})
                await self._conn.execute(
                    "DELETE FROM dues_intents WHERE id=? AND status='pending'",
                    (intent["id"],))
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
            except sqlite3.IntegrityError as e:
                self._conn.rollback()
                current = (await self._conn.execute(
                    "SELECT * FROM dues_intents WHERE user_id=?"
                    " AND status IN ('pending','link_sent')"
                    " ORDER BY created_at DESC LIMIT 1", (user_id,))).fetchone()
                if current is not None and current.get("provider_ref"):
                    intent = dict(current)
                    return {"intent": intent,
                            "link": intent.get("provider_link") or _intent_link(
                                str(intent["provider_ref"]), int(intent["amount"])),
                            "provider_ref": intent["provider_ref"]}
                raise IntentPendingError(
                    message="A dues payment link is already being created.",
                    details={}) from e
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
        from app.core.db_utils import write_audit  # noqa: PLC0415

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
        from app.core.db_utils import write_audit  # noqa: PLC0415

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
