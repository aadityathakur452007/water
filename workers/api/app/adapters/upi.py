"""UPI provider adapter (Adapter + Strategy pattern) — D1 payments slice.

Mirrors ``adapters/firebase.py``: same factory shape (``get_provider``), same
error contract (``AppError`` subclasses → central envelope). Fake is the test
double (approve/decline by ref prefix); Real is the HMAC-SHA256 skeleton.

Strategy note: UPI-vs-COD is a Strategy — ``PaymentService`` picks the path by
``order.payment_mode``; this adapter is only the UPI leg.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import time
import uuid

from app.core.errors import AppError


class UnauthError(AppError):
    code = "UNAUTH"
    status_code = 401


class UpstreamError(AppError):
    code = "UPSTREAM_FAIL"
    status_code = 502


class DuplicateWebhookError(AppError):
    """Nonce/provider_ref already seen — caller maps to 200 no-op (C16)."""

    code = "DUPLICATE_WEBHOOK"
    status_code = 200


WEBHOOK_TOLERANCE_S = 300  # ±5 min (contract §4.6)

_seen_nonces: set[str] = set()  # TODO(D1): persist nonces (multi-instance replay)


def agency_vpa() -> str:
    """Agency collection account — the payee lock (§14.4, C11-fraud kill)."""
    try:
        from app.api.deps import get_settings  # noqa: PLC0415 (light, mirrors firebase.py)

        vpa = getattr(get_settings(), "agency_upi_vpa", None)
        if vpa:
            return str(vpa)
    except Exception:
        pass
    return os.environ.get("AGENCY_UPI_VPA", "shodasha@upi")


class UpiProvider:
    """Interface: create_intent(order) -> {provider_ref, link, payload}."""

    def create_intent(self, order: dict) -> dict:  # pragma: no cover - interface
        raise NotImplementedError

    def verify_webhook(self, raw_body: bytes, signature: str | None) -> dict:  # pragma: no cover
        raise NotImplementedError


class FakeUpiProvider(UpiProvider):
    """Test double: APPROVE* refs approve, DECLINE* refs decline (by prefix)."""

    def create_intent(self, order: dict) -> dict:
        ref = f"FAKE-APPROVE-{str(order.get('id', 'o'))[:8]}-{uuid.uuid4().hex[:4]}"
        amt = f"{int(order.get('total', 0)) / 100:.2f}"
        return {
            "provider_ref": ref,
            "link": f"upi://pay?pa={agency_vpa()}&pn=Shodasha&am={amt}&tr={ref}&cu=INR",
            "payload": {"order_id": order.get("id"), "amount": int(order.get("total", 0))},
        }

    def verify_webhook(self, raw_body: bytes, signature: str | None = None) -> dict:
        try:
            body = json.loads(raw_body.decode() or "{}")
        except (ValueError, UnicodeDecodeError) as e:
            raise UnauthError("Invalid webhook.", {}) from e
        ref = str(body.get("provider_ref", ""))
        status = "declined" if ref.upper().startswith(("DECLINE", "FAKE-DECLINE")) else "approved"
        return {
            "order_id": body.get("order_id"),
            "provider_ref": ref,
            "amount": int(body.get("amount", 0)),
            "payee": body.get("payee", ""),
            "status": status,
        }


class RealUpiProvider(UpiProvider):
    """HMAC-SHA256 skeleton: signature + ±5min timestamp + nonce replay-cache."""

    def create_intent(self, order: dict) -> dict:
        ref = f"upi_{uuid.uuid4().hex[:12]}"
        amt = f"{int(order.get('total', 0)) / 100:.2f}"
        return {
            "provider_ref": ref,
            "link": f"upi://pay?pa={agency_vpa()}&pn=Shodasha&am={amt}&tr={ref}&cu=INR",
            "payload": {"order_id": order.get("id"), "amount": int(order.get("total", 0))},
        }

    def verify_webhook(self, raw_body: bytes, signature: str | None) -> dict:
        secret = os.environ.get("UPI_WEBHOOK_SECRET")
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
        ts = body.get("timestamp", body.get("ts"))
        if ts is None or abs(time.time() - float(ts)) > WEBHOOK_TOLERANCE_S:
            raise UnauthError("Stale webhook.", {})
        nonce = str(body.get("nonce", body.get("event_id", body.get("provider_ref", ""))))
        if nonce and nonce in _seen_nonces:
            raise DuplicateWebhookError("Duplicate delivery.", {"provider_ref": body.get("provider_ref")})
        if nonce:
            _seen_nonces.add(nonce)
        return {
            "order_id": body.get("order_id"),
            "provider_ref": str(body.get("provider_ref", "")),
            "amount": int(body.get("amount", 0)),
            "payee": str(body.get("payee", "")),
            "status": str(body.get("status", "approved")),
        }


def get_provider() -> UpiProvider:
    """DI factory — tests inject FakeUpiProvider directly (mirrors get_verifier)."""
    if os.environ.get("UPI_PROVIDER", "fake").lower() == "real":
        return RealUpiProvider()
    return FakeUpiProvider()
