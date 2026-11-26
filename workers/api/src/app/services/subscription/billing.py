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

class SubBillingMixin:
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
        """Delegate to repositories.order_repo.build_restore_order_credit_stmts."""
        from app.repositories.order_repo import build_restore_order_credit_stmts  # noqa: PLC0415

        return build_restore_order_credit_stmts(
            order_id, sub_id=sub_id, total=total, now=now, guard=guard
        )

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
        deposit_paid = max(0, int(led.get("deposit_paid", 0)) - int(led.get("deposit_refunded", 0)))
        deposit_rate = pricing.DEPOSIT_PAISE or (deposit_paid // held_jars if held_jars > 0 and deposit_paid > 0 else 0)
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
            from app.core.time_utils import sla_due  # noqa: PLC0415

            return_sla = sla_due()

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

            # Mid-cycle cancellation: calculate all unpaid delivered jars under this subscription
            # so customer owes the money and vendor/rider will collect at doorstep.
            unpaid_orders = (await self._conn.execute(
                "SELECT id, total FROM orders WHERE user_id = ? AND state = 'delivered'"
                " AND payment_status NOT IN ('paid_upi', 'paid_cash')"
                " AND (idempotency_key LIKE ? OR idempotency_key LIKE ?)",
                (user_id, f"%:sub:{sub_id}:%", f"%sub_{sub_id}%"),
            )).fetchall()

            unpaid_dues_posted = 0
            for uo in unpaid_orders:
                posted = (await self._conn.execute(
                    "SELECT 1 FROM ledger_events WHERE customer_id = ? AND ref_type = 'order' AND ref_id = ? AND kind = 'dues' AND d_dues > 0 LIMIT 1",
                    (user_id, uo["id"]),
                )).fetchone()
                if posted is None:
                    paid_res = (await self._conn.execute(
                        "SELECT COALESCE(SUM(amount), 0) AS paid FROM payments WHERE order_id = ? AND status IN ('paid', 'partial')",
                        (uo["id"],),
                    )).fetchone()
                    paid_val = int(paid_res["paid"]) if paid_res else 0
                    due_val = max(0, int(uo["total"]) - paid_val)
                    if due_val > 0:
                        unpaid_dues_posted += due_val
                        stmts.extend(LedgerRepo(self._conn).build_event_stmts(
                            user_id,
                            d_dues=due_val,
                            ref=f"order:{uo['id']}",
                            actor="system",
                            reason=f"mid-cycle sub cancellation unpaid delivery for sub {sub_id}",
                            guard=guard,
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
            "unpaid_dues_posted_paise": unpaid_dues_posted,
            "deposit_refund_expected_paise": jars_to_return * deposit_rate,
            "message": (
                "Subscription canceled. Future deliveries are stopped. "
                "If a refund is due, we will process it to your UPI after pickup. "
                "Nothing is refunded for deliveries that were never paid."
            ),
        }
