"""RealUpiProvider tests — live Razorpay protocol, no real network, ever.

``httpx.post`` is monkeypatched (Orders API) and webhook bodies are
Razorpay-shaped ``payment.*`` events HMAC-signed like Razorpay signs them
(see _rzp.py). Dummy key values only — never real keys.
"""
import sys
import time
from pathlib import Path

import httpx
import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from _rzp import (  # noqa: E402
    DUMMY_KEYS,
    ORDERS_URL,
    real_provider,
    signed_event,
    stub_orders_api,
    use_dummy_keys,
)
from app.adapters.upi import (  # noqa: E402
    IgnoredWebhook,
    RealUpiProvider,
    UnauthError,
    UpstreamError,
    get_provider,
)

ORDER = {"id": "ord_1", "total": 5600}


class _Resp:
    def __init__(self, payload=None, error=None):
        self._payload = payload
        self._error = error

    def raise_for_status(self):
        if self._error is not None:
            raise self._error

    def json(self):
        return self._payload


def test_factory_always_real():
    assert isinstance(get_provider(), RealUpiProvider)


def test_intent_posts_orders_api(monkeypatch):
    use_dummy_keys(monkeypatch)
    seen = stub_orders_api(monkeypatch)
    out = RealUpiProvider().create_intent(ORDER)
    assert seen["url"] == ORDERS_URL
    assert seen["auth"] == (DUMMY_KEYS["UPI_KEY_ID"], DUMMY_KEYS["UPI_KEY_SECRET"])
    assert seen["json"] == {"amount": 5600, "currency": "INR", "receipt": "ord_1",
                            "notes": {"order_id": "ord_1"}}
    assert out["provider_ref"] == "order_TEST1"
    assert "tr=order_TEST1" in out["link"] and "am=56.00" in out["link"]
    assert out["payload"] == {"order_id": "ord_1", "amount": 5600}


def test_intent_http_error_retryable(monkeypatch):
    use_dummy_keys(monkeypatch)

    def fake_post(url, *, auth=None, json=None, timeout=None):
        assert url == ORDERS_URL  # error path still hits the Orders API
        return _Resp(error=httpx.HTTPError("boom"))

    monkeypatch.setattr(httpx, "post", fake_post)
    with pytest.raises(UpstreamError) as e:
        RealUpiProvider().create_intent(ORDER)
    assert e.value.code == "UPSTREAM_FAIL" and e.value.status_code == 502
    assert e.value.details == {"retryable": True}


def test_intent_missing_keys_fail_closed(monkeypatch):
    # Hermetic vs local .env (real test keys wired per ADR-024): blanking wins
    # over the .env file in both os.environ and pydantic-settings precedence.
    monkeypatch.setenv("UPI_KEY_ID", "")
    monkeypatch.setenv("UPI_KEY_SECRET", "")
    with pytest.raises(UpstreamError) as e:
        RealUpiProvider().create_intent(ORDER)
    assert e.value.code == "UPSTREAM_FAIL" and e.value.status_code == 502
    assert e.value.details == {"retryable": False}


def test_webhook_captured_approved(monkeypatch):
    p = real_provider(monkeypatch)
    raw, sig = signed_event("order_ABC", 5600, order_id="ord_1")
    out = p.verify_webhook(raw, sig)
    assert out == {"order_id": "ord_1", "provider_ref": "order_ABC",
                   "amount": 5600, "payee": DUMMY_KEYS["AGENCY_UPI_VPA"],
                   "status": "approved"}


def test_webhook_failed_declined(monkeypatch):
    p = real_provider(monkeypatch)
    raw, sig = signed_event("order_ABC", 5600, event="payment.failed", status="failed")
    assert p.verify_webhook(raw, sig)["status"] == "declined"


def test_webhook_authorized_ignored(monkeypatch):
    # Auto-capture sends authorized first, captured settles. Authorized alone
    # must not mint money — the captured event does that.
    p = real_provider(monkeypatch)
    raw, sig = signed_event("order_ABC", 5600, event="payment.authorized",
                            status="authorized")
    with pytest.raises(IgnoredWebhook):
        p.verify_webhook(raw, sig)


def test_webhook_rejects_bad_signature_and_stale(monkeypatch):
    p = real_provider(monkeypatch)
    raw, _ = signed_event("order_ABC", 5600)
    with pytest.raises(UnauthError):
        p.verify_webhook(raw, "wrong")
    with pytest.raises(UnauthError):
        p.verify_webhook(raw, None)
    stale, stale_sig = signed_event("order_ABC", 5600,
                                    created_at=int(time.time()) - 9999)
    with pytest.raises(UnauthError):
        p.verify_webhook(stale, stale_sig)


def test_webhook_missing_secret_fail_closed(monkeypatch):
    use_dummy_keys(monkeypatch)
    monkeypatch.setenv("UPI_WEBHOOK_SECRET", "")
    raw, sig = signed_event("order_ABC", 5600)
    with pytest.raises(UpstreamError) as e:
        RealUpiProvider().verify_webhook(raw, sig)
    assert e.value.status_code == 502
