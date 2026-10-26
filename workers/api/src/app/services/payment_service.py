"""Payment service — business rules ONLY (no SQL beyond repo calls, no FastAPI).

Owns: UPI-vs-COD Strategy pick, intent idempotency, webhook verify→reconcile,
COD-confirm dues posting, refund claim→done/failed (C15), dues/invoice math
(bill = water+deposit+cap+previous−payments, partials carried VR-08).
"""

from __future__ import annotations

import logging

from app.core.errors import ConflictError, NotFoundError, ValidationError
from app.services.order_service import COD_MAX_PAISE, CodNotAllowedError

log = logging.getLogger(__name__)

UNPAID = ("unpaid", "link_sent", "partial_dues")
INTERNAL_FIELDS = ("settlement_token", "mutation_token", "refund_id")


def _public(row: dict) -> dict:
    """Strip CAS/internal money markers from an API-bound row."""
    return {k: v for k, v in row.items() if k not in INTERNAL_FIELDS}


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
        if order.get("state") in ("cancelled", "rejected"):
            raise ConflictError(message="Order cannot be paid.", details={"id": order_id})
        if order.get("payment_mode") != "upi":
            raise ValidationError(message="Order is not a UPI order.", details={})
        if order.get("payment_status") in ("paid_upi", "paid_cash"):
            raise ConflictError(message="Order is already paid.", details={"id": order_id})
        reserved = await self.payments.reserve_intent(
            order_id, int(order["total"]), idempotency_key.strip())
        if "payment" in reserved:  # replay: same link, provider not called again
            return reserved
        try:
            created = self.provider.create_intent(order)
        except Exception:
            await self.payments.fail_intent(reserved["payment_id"], idempotency_key.strip())
            raise
        return await self.payments.attach_intent(
            reserved["payment_id"], idempotency_key.strip(),
            created["provider_ref"], created["link"])

    # -- webhook ingest (verify → reconcile → best-effort FCM note) ------

    async def webhook_ingest(self, raw_body: bytes, signature: str | None) -> dict:
        from app.adapters.upi import IgnoredWebhook  # noqa: PLC0415 (avoid cycle)
        from app.services.subscription_service import SubscriptionService  # noqa: PLC0415

        try:
            event = self.provider.verify_webhook(raw_body, signature)
        except IgnoredWebhook as e:
            return {"ok": True, "ignored": True, "details": e.details}
        if event.get("status") == "declined":
            return {"ok": True, "declined": True, "provider_ref": event.get("provider_ref")}
        ref = str(event.get("provider_ref", ""))
        amount = int(event.get("amount", 0))
        billing = SubscriptionService(self.payments.conn)
        charge = await billing.find_charge_by_ref(ref)
        if charge is not None:
            self.payments.assert_payee(str(event.get("payee", "")))
            settled = await billing.settle_charge(ref, amount)
            self._notify_paid({"order_id": f"sub:{settled['subscription_id']}",
                               "provider_ref": ref})
            return {"ok": True, "charge": settled}
        dues_intent = await self.payments.find_dues_intent_by_ref(ref)
        if dues_intent is not None:
            self.payments.assert_payee(str(event.get("payee", "")))
            settled = await self.payments.settle_dues_intent(dues_intent, amount)
            duplicate = bool(settled.pop("_duplicate", False))
            refund_queued = bool(settled.pop("_refund_queued", False))
            public = _public(settled)
            if refund_queued:
                public["_refund_queued"] = True
            if duplicate:
                return {"ok": True, "duplicate": True, "dues_intent": public}
            return {"ok": True, "dues_intent": public}
        payment = await self.payments.apply_webhook(
            ref, amount, str(event.get("payee", "")), order_id=event.get("order_id"),
        )
        duplicate = bool(payment.pop("_duplicate", False))
        refund_queued = bool(payment.pop("_refund_queued", False))
        public = _public(payment)
        if refund_queued:
            public["_refund_queued"] = True
        if not duplicate:
            self._notify_paid(public)  # best-effort; never fails the webhook
            return {"ok": True, "payment": public}
        return {"ok": True, "duplicate": True, "payment": public}

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

    async def switch_to_cod(self, user_id: str, order_id: str) -> dict:
        """Fallback for a live UPI order whose payment cannot start.

        The SAME order becomes COD (no cancel/re-order), its open UPI link is
        voided, and COD dues are posted exactly once. Repeated calls replay the
        same state; an order with captured money is never converted.
        """
        order = await self.orders.find_owned(order_id, user_id)
        if order is None:
            raise NotFoundError(message="Order not found.", details={"id": order_id})
        if order.get("payment_mode") == "cod":
            return await self.cod_confirm(user_id, order_id)
        if order.get("payment_mode") != "upi":
            raise ValidationError(message="Order cannot be switched to COD.", details={})
        if int(order["total"]) > COD_MAX_PAISE:
            raise CodNotAllowedError(
                message="Cash on Delivery is available only up to Rs 2,000. "
                        "Choose UPI for this order.",
                details={"total": int(order["total"]), "max": COD_MAX_PAISE},
            )
        led = await self.ledger.get(user_id)
        if int(led.get("dues", 0)) > COD_MAX_PAISE:
            raise CodNotAllowedError(
                message="Cash on Delivery is unavailable with dues over Rs 2,000. "
                        "Pay your dues first.",
                details={"dues": int(led.get("dues", 0)), "max": COD_MAX_PAISE},
            )
        await self.payments.switch_to_cod(order_id, user_id)
        return await self.cod_confirm(user_id, order_id)

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
        """Reserve a dues intent, then mint the Razorpay order. This never
        writes the synthetic 'dues:<user>' order id that broke the FK live."""
        if not idempotency_key or not str(idempotency_key).strip():
            raise ValidationError(message="Idempotency-Key header required.", details={})
        dues = int((await self.get_dues(user_id))["dues"])
        if dues <= 0:
            raise ValidationError(message="No dues to pay.", details={})
        key = idempotency_key.strip()
        reserved = await self.payments.reserve_dues_intent(user_id, dues, key)
        if "intent" in reserved:  # replay
            return {**reserved, "payment": reserved["intent"]}
        try:
            created = self.provider.create_intent(
                {"id": reserved["intent_id"], "total": dues})
        except Exception:
            await self.payments.fail_dues_intent(reserved["intent_id"], user_id, key)
            raise
        out = await self.payments.attach_dues_intent(
            reserved["intent_id"], user_id, key, created["provider_ref"], created["link"])
        return {**out, "payment": out["intent"]}

    # -- monthly prepaid top-up intent -------------------------------------

    async def subscription_intent(self, user_id: str, sub_id: str,
                                  idempotency_key: str) -> dict:
        """Reserve one prepaid top-up, then mint the provider order."""
        from app.services.subscription_service import SubscriptionService  # noqa: PLC0415

        key = (idempotency_key or "").strip()
        if not key:
            raise ValidationError(message="Idempotency-Key header required.", details={})
        billing = SubscriptionService(self.payments.conn)
        reserved = await billing.begin_charge(user_id, sub_id, key)
        if "charge" in reserved:  # replay: same link, provider not called again
            return reserved
        try:
            created = self.provider.create_intent(
                {"id": reserved["charge_id"], "total": int(reserved["amount"])})
        except Exception:
            await billing.fail_charge(reserved["charge_id"], user_id, key)
            raise
        return await billing.attach_charge(
            reserved["charge_id"], user_id, key,
            created["provider_ref"], created["link"])

    # -- dues / invoice reads ----------------------------------------------

    async def get_dues(self, user_id: str) -> dict:
        led = await self.ledger.get(user_id)
        rows = (await self.payments._conn.execute(
            "SELECT id, total, payment_status FROM orders WHERE user_id=?"
            " AND state NOT IN ('cancelled','rejected')"
            " AND payment_status IN ('unpaid','link_sent','partial_dues')"
            " ORDER BY created_at, id",
            (user_id,),
        )).fetchall()
        order_ids = [r["id"] for r in rows]
        paid_by_order = await self.payments.paid_sums_for_orders(order_ids)
        dues_posted = await self.payments.dues_posted_for_orders(order_ids)
        lines = []
        order_due = 0
        for r in rows:
            paid = int(paid_by_order.get(r["id"], 0))
            due = max(0, int(r["total"]) - paid)
            # COD remainders are already carried in ledger.dues; including
            # them again here would double-count the same rupees.
            if r["id"] not in dues_posted:
                order_due += due
            lines.append({"order_id": r["id"], "total": int(r["total"]),
                          "paid": paid, "due": due, "status": r["payment_status"]})
        dues = int(led["dues"]) + int(order_due)
        vpa = self.agency_vpa
        if vpa is None:
            from app.adapters.upi import agency_vpa as _vpa  # noqa: PLC0415

            vpa = _vpa()
        # 026 Razorpay-truth: upi:// pay_link is informational only — no UPI VPA
        # is configured (UPI_PROVIDER defaults to fake), so the app must never
        # auto-launch it. Razorpay webhook is the money truth.
        try:
            from app.adapters.upi import _setting as _upi_setting  # noqa: PLC0415

            provider = str(_upi_setting("UPI_PROVIDER", "fake")).lower()
        except Exception:
            provider = "fake"
        provider = "razorpay" if provider == "razorpay" else "fake"
        pay_link = (f"upi://pay?pa={vpa}&pn=Shodasha&am={dues / 100:.2f}&cu=INR"
                    if dues > 0 else None)
        return {"dues": dues, "lines": lines, "pay_link": pay_link,
                "provider": provider, "razorpay_ready": provider == "razorpay"}

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
