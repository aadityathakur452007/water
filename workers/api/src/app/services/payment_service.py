"""Payment service — business rules ONLY (no SQL beyond repo calls, no FastAPI).

Owns: UPI-vs-COD Strategy pick, intent idempotency, webhook verify→reconcile,
COD-confirm dues posting, refund claim→done/failed (C15), dues/invoice math
(bill = water+deposit+cap+previous−payments, partials carried VR-08).
"""

from __future__ import annotations

import logging

from app.core.errors import ConflictError, NotFoundError, ValidationError

log = logging.getLogger(__name__)

UNPAID = ("unpaid", "link_sent", "partial_dues")


class PaymentService:
    def __init__(self, payments, orders, ledger, provider, agency_vpa: str | None = None):
        self.payments = payments
        self.orders = orders
        self.ledger = ledger
        self.provider = provider
        self.agency_vpa = agency_vpa

    # -- UPI intent (idempotent) -----------------------------------------

    async def intent(self, user_id: str, order_id: str, idempotency_key: str) -> dict:
        if not idempotency_key or not str(idempotency_key).strip():
            raise ValidationError(message="Idempotency-Key header required.", details={})
        order = await self.orders.find_owned(order_id, user_id)
        if order is None:
            raise NotFoundError(message="Order not found.", details={"id": order_id})
        if order.get("payment_mode") != "upi":
            raise ValidationError(message="Order is not a UPI order.", details={})
        if order.get("payment_status") in ("paid_upi", "paid_cash"):
            raise ConflictError(message="Order is already paid.", details={"id": order_id})
        created = self.provider.create_intent(order)
        payment = await self.payments.create_intent(
            order_id, int(order["total"]), idempotency_key.strip(),
            provider_ref=created["provider_ref"],
        )
        return {"payment": payment, "link": created["link"],
                "provider_ref": created["provider_ref"]}

    # -- webhook ingest (verify → reconcile → best-effort FCM note) ------

    async def webhook_ingest(self, raw_body: bytes, signature: str | None) -> dict:
        from app.adapters.upi import DuplicateWebhookError  # noqa: PLC0415 (avoid cycle)

        try:
            event = self.provider.verify_webhook(raw_body, signature)
        except DuplicateWebhookError as e:
            return {"ok": True, "duplicate": True, "details": e.details}
        if event.get("status") == "declined":
            return {"ok": True, "declined": True, "provider_ref": event.get("provider_ref")}
        payment = await self.payments.apply_webhook(
            str(event.get("provider_ref", "")), int(event.get("amount", 0)),
            str(event.get("payee", "")), order_id=event.get("order_id"),
        )
        if not payment.pop("_duplicate", False):
            self._notify_paid(payment)  # best-effort; never fails the webhook
            return {"ok": True, "payment": payment}
        return {"ok": True, "duplicate": True, "payment": payment}

    @staticmethod
    def _notify_paid(payment: dict) -> None:
        # No real push (no secrets): durable outbox ONLY if a table exists —
        # no conn here, so structured log with order_id+provider_ref; the
        # future sender fans out via device_tokens / fcm.queue_or_log.
        try:  # FCM push-only receipt; failures must not roll back money (Observer stub)
            log.info("payment receipt order=%s ref=%s", payment.get("order_id"),
                     payment.get("provider_ref"))
        except Exception:  # noqa: BLE001, S110
            pass

    # -- COD (unpaid until vendor cash posts) -----------------------------

    async def cod_confirm(self, user_id: str, order_id: str) -> dict:
        order = await self.orders.find_owned(order_id, user_id)
        if order is None:
            raise NotFoundError(message="Order not found.", details={"id": order_id})
        if order.get("payment_mode") != "cod":
            raise ValidationError(message="Order is not a COD order.", details={})
        if order.get("payment_status") not in UNPAID:
            return await self._bill(user_id, order)
        if not await self.payments._dues_posted(order_id):  # idempotent: post once
            await self.ledger.apply_event(user_id, d_dues=int(order["total"]),
                                    ref=f"order:{order_id}", actor=user_id,
                                    reason="cod dues")
        return await self._bill(user_id, await self.orders.find_owned(order_id, user_id))

    async def mark_cash(self, order_id: str, amount: int, actor_id: str) -> dict:
        return await self.payments.mark_paid_cash(order_id, int(amount), actor_id)

    # -- refunds: claim → done/failed (C15) --------------------------------

    async def claim_refund(self, actor_id: str, refund_id: str) -> dict:
        return await self.payments.claim_refund(refund_id, actor_id)

    async def complete_refund(self, actor_id: str, refund_id: str, to_status: str) -> dict:
        """Close a claimed refund (maker-checker: claimer ≠ closer, enforced in
        the repo). `done` = status settlement only — the actual provider payout
        moves out-of-band (out of scope, noted per spec)."""
        return await self.payments.complete_refund(refund_id, to_status, actor_id)

    # -- dues-pay intent (settles ledger dues over UPI) ---------------------

    async def dues_intent(self, user_id: str, idempotency_key: str) -> dict:
        """Intent row for the current full dues (no order): the signed webhook
        settles it like any intent (dues branch, no order flip)."""
        if not idempotency_key or not str(idempotency_key).strip():
            raise ValidationError(message="Idempotency-Key header required.", details={})
        dues = int((await self.get_dues(user_id))["dues"])
        if dues <= 0:
            raise ValidationError(message="No dues to pay.", details={})
        created = self.provider.create_intent({"id": f"dues-{user_id}", "total": dues})
        payment = await self.payments.create_dues_intent(
            user_id, dues, idempotency_key.strip(), created["provider_ref"])
        return {"payment": payment, "link": created["link"],
                "provider_ref": created["provider_ref"]}

    # -- dues / invoice reads ----------------------------------------------

    async def get_dues(self, user_id: str) -> dict:
        led = await self.ledger.get(user_id)
        rows = (await self.payments._conn.execute(
            "SELECT id, total, payment_status FROM orders WHERE user_id=? AND payment_status IN"
            " ('unpaid','link_sent','partial_dues')",
            (user_id,),
        )).fetchall()
        lines = []
        link_pending = 0
        for r in rows:
            paid = await self.payments.paid_sum_for_order(r["id"])
            due = max(0, int(r["total"]) - int(paid))
            lines.append({"order_id": r["id"], "total": int(r["total"]),
                          "paid": int(paid), "due": due, "status": r["payment_status"]})
            if r["payment_status"] == "link_sent":
                link_pending += int(r["total"])
        dues = int(led["dues"]) + link_pending  # COD remainders live in ledger; UPI links pending
        vpa = self.agency_vpa
        if vpa is None:
            from app.adapters.upi import agency_vpa as _vpa  # noqa: PLC0415

            vpa = _vpa()
        pay_link = (f"upi://pay?pa={vpa}&pn=Shodasha&am={dues / 100:.2f}&cu=INR"
                    if dues > 0 else None)
        return {"dues": dues, "lines": lines, "pay_link": pay_link}

    async def get_invoice(self, user_id: str, order_id: str) -> dict:
        order = await self.orders.find_owned(order_id, user_id)
        if order is None:
            raise NotFoundError(message="Order not found.", details={"id": order_id})
        led = await self.ledger.get(user_id)
        paid = await self.payments.paid_sum_for_order(order_id)
        amount_due = max(0, int(order["total"]) - int(paid))
        if await self.payments._dues_posted(order_id):
            previous = max(0, int(led["dues"]) - amount_due)  # exclude this order's remainder
        else:
            previous = int(led["dues"])
        return {
            "order_id": order_id,
            "water_bill": int(order["water_bill"]),
            "deposit_due": int(order["deposit_due"]),
            "cap_charge": int(order.get("cap_charge", 0)),
            "total": int(order["total"]),
            "paid": int(paid),
            "amount_due": amount_due,
            "previous_dues": previous,
            "total_due": amount_due + previous,
            "payment_status": order["payment_status"],
            "payment_mode": order["payment_mode"],
        }

    async def _bill(self, user_id: str, order: dict) -> dict:
        dues = await self.get_dues(user_id)
        return {
            "order_id": order["id"],
            "payment_status": order["payment_status"],
            "bill": {
                "water_bill": int(order["water_bill"]),
                "deposit_due": int(order["deposit_due"]),
                "cap_charge": int(order.get("cap_charge", 0)),
                "total": int(order["total"]),
                "payment_status": order["payment_status"],
            },
            "dues": dues["dues"],
        }
