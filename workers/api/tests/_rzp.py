"""Shared Razorpay test kit: dummy keys, stubbed Orders API, signed webhooks.

No network, no secrets. The production adapter (app/adapters/upi.py) speaks
only the live Razorpay protocol, so payment tests build on these helpers
instead of a fake provider: intents stub the HTTP boundary (``httpx.post``),
webhooks are real-shaped ``payment.captured``/``payment.failed`` events signed
with HMAC-SHA256 exactly like Razorpay signs them.
"""
import hashlib
import hmac
import json
import time

import httpx

DUMMY_KEYS = {
    "UPI_KEY_ID": "test_kid_123",
    "UPI_KEY_SECRET": "test_ksec_456",
    "UPI_WEBHOOK_SECRET": "test_whsec_789",
    "AGENCY_UPI_VPA": "shodasha@upi",
}

ORDERS_URL = "https://api.razorpay.com/v1/orders"


class _OrdersResp:
    def __init__(self, ref):
        self._ref = ref

    def raise_for_status(self):
        return None

    def json(self):
        return {"id": self._ref}


def use_dummy_keys(monkeypatch):
    """Dummy Razorpay keys win over any local .env (pydantic env > file)."""
    for k, v in DUMMY_KEYS.items():
        monkeypatch.setenv(k, v)
    from app.api.deps import get_settings  # noqa: PLC0415
    get_settings.cache_clear()


def stub_orders_api(monkeypatch, prefix="order_TEST"):
    """Stub httpx.post → unique Razorpay order refs. Returns seen-requests."""
    seen = {"n": 0}

    def fake_post(url, *, auth=None, json=None, timeout=None):
        seen["n"] += 1
        seen.update(url=url, auth=auth, json=json, timeout=timeout)
        return _OrdersResp(f"{prefix}{seen['n']}")

    monkeypatch.setattr(httpx, "post", fake_post)
    return seen


def real_provider(monkeypatch, prefix="order_TEST"):
    """Live-code RealUpiProvider with dummy keys + stubbed HTTP (no network)."""
    from app.adapters.upi import RealUpiProvider  # noqa: PLC0415 (after env)

    use_dummy_keys(monkeypatch)
    stub_orders_api(monkeypatch, prefix)
    return RealUpiProvider()


def signed_event(ref, amount, order_id="ord_1", event="payment.captured",
                 status="captured", secret=DUMMY_KEYS["UPI_WEBHOOK_SECRET"],
                 created_at=None):
    """(raw_body, signature) for a Razorpay payment event, HMAC-signed."""
    body = json.dumps({
        "entity": "event",
        "event": event,
        "created_at": created_at if created_at is not None else int(time.time()),
        "payload": {"payment": {"entity": {
            "id": "pay_TEST", "order_id": ref, "amount": amount,
            "status": status, "notes": {"order_id": order_id},
        }}},
    }).encode()
    sig = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    return body, sig
