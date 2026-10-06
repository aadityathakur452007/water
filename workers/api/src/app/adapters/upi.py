"""UPI provider adapter (Adapter + Strategy pattern) — Razorpay only.

Single production provider: Razorpay Orders for intents + Razorpay webhook
events for settlement. There is no fake/test double in this module — tests
stub the HTTP boundary (``httpx.post``) and sign real-shaped webhook bodies
(see tests/_rzp.py), so this file only ever speaks the live protocol.

Secrets (all via ``wrangler secret put``, never in code): UPI_KEY_ID,
UPI_KEY_SECRET (Orders API basic auth), UPI_WEBHOOK_SECRET (webhook HMAC),
AGENCY_UPI_VPA (display + link payee).

Strategy note: UPI-vs-COD is a Strategy — ``PaymentService`` picks the path by
``order.payment_mode``; this adapter is only the UPI leg.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import time

import httpx

from app.core.worker_env import env_get as _worker_env_get

from app.core.errors import AppError


class UnauthError(AppError):
    code = "UNAUTH"
    status_code = 401


class UpstreamError(AppError):
    code = "UPSTREAM_FAIL"
    status_code = 502


class IgnoredWebhook(AppError):
    """Verified-but-not-actionable event (e.g. payment.authorized under
    auto-capture, or non-payment events) — caller maps to 200 no-op so
    Razorpay stops retrying. Replay safety for real money comes from the
    payments table itself (UNIQUE provider_ref + paid→duplicate no-op in
    ``apply_webhook``), which holds across Worker isolates unlike memory."""

    code = "IGNORED_WEBHOOK"
    status_code = 200


WEBHOOK_TOLERANCE_S = 300  # ±5 min (contract §4.6)

RAZORPAY_ORDERS_URL = "https://api.razorpay.com/v1/orders"

# Razorpay event names we act on. Everything else verified-but-ignored.
_EVENT_CAPTURED = "payment.captured"
_EVENT_FAILED = "payment.failed"


def _setting(env_name: str, default=None):
    """Worker env wins, process env second, .env-backed Settings third.

    Adapters must never read os.environ alone: local dev keeps secrets in the
    gitignored .env file (which only pydantic-settings loads), and on Workers
    os.environ is empty — vars/secrets live on the request env object.
    """
    direct = _worker_env_get(env_name)
    if direct not in (None, ""):
        return direct
    try:
        from app.core.config import Settings  # noqa: PLC0415 (lazy, mirrors firebase.py)

        value = getattr(Settings(), env_name.lower(), None)
        return value if value not in (None, "") else default
    except Exception:
        return default


def agency_vpa() -> str:
    """Agency collection account — the payee lock (§14.4, C11-fraud kill)."""
    return str(_setting("AGENCY_UPI_VPA", "shodasha@upi"))


class UpiProvider:
    """Interface: create_intent(order) -> {provider_ref, link, payload}."""

    def create_intent(self, order: dict) -> dict:  # pragma: no cover - interface
        raise NotImplementedError

    def verify_webhook(self, raw_body: bytes, signature: str | None) -> dict:  # pragma: no cover
        raise NotImplementedError


class RealUpiProvider(UpiProvider):
    """Razorpay Orders-backed intents; Razorpay-shaped webhook verify.

    Create: POST api.razorpay.com/v1/orders (basic auth key_id:secret,
    amount in paise, receipt = our order id, notes.order_id echoed back).
    Missing keys → UPSTREAM_FAIL 502 (fail-closed; reads like dues/invoice/
    cod-confirm never touch the provider so they keep working).
    """

    def create_intent(self, order: dict) -> dict:
        key_id = _setting("UPI_KEY_ID")
        key_secret = _setting("UPI_KEY_SECRET")
        if not key_id or not key_secret:
            raise UpstreamError("UPI provider not configured.", {"retryable": False})
        amount = int(order.get("total", 0))
        receipt = str(order.get("id", ""))
        try:
            resp = httpx.post(
                RAZORPAY_ORDERS_URL,
                auth=(key_id, key_secret),
                json={"amount": amount, "currency": "INR", "receipt": receipt,
                      "notes": {"order_id": receipt}},
                timeout=10.0,
            )
            resp.raise_for_status()
            ref = str(resp.json().get("id") or "")
        except Exception as e:
            raise UpstreamError("UPI provider unreachable.", {"retryable": True}) from e
        if not ref:
            raise UpstreamError("UPI provider unreachable.", {"retryable": True})
        amt = f"{amount / 100:.2f}"
        return {
            "provider_ref": ref,
            "link": f"upi://pay?pa={agency_vpa()}&pn=Shodasha&am={amt}&tr={ref}&cu=INR",
            "payload": {"order_id": order.get("id"), "amount": amount},
        }

    def verify_webhook(self, raw_body: bytes, signature: str | None) -> dict:
        """Verify a Razorpay webhook event and normalize it for settlement.

        Authenticity = HMAC-SHA256(raw_body, UPI_WEBHOOK_SECRET) matching the
        signature header (only Razorpay + us know the secret), plus
        ``created_at`` freshness. The returned ``payee`` is the agency VPA by
        construction: a verified event for an order minted under our key can
        only settle into our account (documented, not re-derived — Razorpay
        payloads carry the payer VPA, never the payee).
        """
        secret = _setting("UPI_WEBHOOK_SECRET")
        if not secret:
            raise UpstreamError("UPI provider not configured.", {"retryable": True})
        if not signature:
            raise UnauthError("Invalid webhook.", {})
        sig = signature.removeprefix("sha256=").strip()
        expect = hmac.new(secret.encode(), raw_body, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expect, sig):
            raise UnauthError("Invalid webhook.", {})
        try:
            body = json.loads(raw_body.decode() or "{}")
        except (ValueError, UnicodeDecodeError) as e:
            raise UnauthError("Invalid webhook.", {}) from e
        created = body.get("created_at")
        try:
            age = abs(time.time() - float(created))  # type: ignore[arg-type]
        except (TypeError, ValueError):
            raise UnauthError("Stale webhook.", {}) from None
        if age > WEBHOOK_TOLERANCE_S:
            raise UnauthError("Stale webhook.", {})
        event = str(body.get("event") or "")
        entity = ((body.get("payload") or {}).get("payment") or {}).get("entity") or {}
        ref = str(entity.get("order_id") or "")
        if not ref:
            raise UnauthError("Invalid webhook.", {})
        status = str(entity.get("status") or "")
        if event == _EVENT_FAILED or status == "failed":
            status = "declined"
        elif event == _EVENT_CAPTURED and status in ("captured", "authorized"):
            status = "approved"
        else:
            # Verified but not actionable (e.g. payment.authorized under
            # auto-capture — the captured event settles it; anything
            # non-payment). 200 no-op so Razorpay stops retrying.
            raise IgnoredWebhook("Event ignored.", {"event": event})
        notes = entity.get("notes") or {}
        return {
            "order_id": notes.get("order_id"),
            "provider_ref": ref,
            "amount": int(entity.get("amount", 0)),
            "payee": agency_vpa(),
            "status": status,
        }


def get_provider() -> UpiProvider:
    """DI factory — always the live Razorpay provider.

    Keys are checked lazily per call (missing → UPSTREAM_FAIL 502), so
    provider-free reads (dues/invoice/cod-confirm) keep working with zero
    secrets configured. Tests stub the HTTP boundary, never this factory.
    """
    return RealUpiProvider()
