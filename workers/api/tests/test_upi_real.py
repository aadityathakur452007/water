"""RealUpiProvider Razorpay-Orders tests — no real network, ever.

``httpx.post`` is monkeypatched, so no HTTP leaves the process; the fake
asserts URL, basic auth, and body. Dummy key values only — never real keys.
"""
import os
import sys
from pathlib import Path

import httpx
import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

os.environ.setdefault("AGENCY_UPI_VPA", "shodasha@upi")

from app.adapters.upi import (  # noqa: E402
    FakeUpiProvider,
    RealUpiProvider,
    UpstreamError,
    get_provider,
)

ORDERS_URL = "https://api.razorpay.com/v1/orders"
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


def _keys(monkeypatch):
    monkeypatch.setenv("UPI_KEY_ID", "kid_123")
    monkeypatch.setenv("UPI_KEY_SECRET", "ksec_456")


def test_real_success_posts_orders_api(monkeypatch):
    _keys(monkeypatch)
    seen = {}

    def fake_post(url, *, auth=None, json=None, timeout=None):
        seen.update(url=url, auth=auth, json=json, timeout=timeout)
        return _Resp({"id": "order_ABC"})

    monkeypatch.setattr(httpx, "post", fake_post)
    out = RealUpiProvider().create_intent(ORDER)
    assert seen["url"] == ORDERS_URL
    assert seen["auth"] == ("kid_123", "ksec_456")
    assert seen["json"] == {"amount": 5600, "currency": "INR", "receipt": "ord_1",
                            "notes": {"order_id": "ord_1"}}
    assert out["provider_ref"] == "order_ABC"
    assert "tr=order_ABC" in out["link"] and "am=56.00" in out["link"]
    assert out["link"].startswith("upi://pay?") and out["link"].endswith("&cu=INR")
    assert out["payload"] == {"order_id": "ord_1", "amount": 5600}


def test_real_http_error_retryable(monkeypatch):
    _keys(monkeypatch)

    def fake_post(url, *, auth=None, json=None, timeout=None):
        assert url == ORDERS_URL  # error path still hits the Orders API
        return _Resp(error=httpx.HTTPError("boom"))

    monkeypatch.setattr(httpx, "post", fake_post)
    with pytest.raises(UpstreamError) as e:
        RealUpiProvider().create_intent(ORDER)
    assert e.value.code == "UPSTREAM_FAIL" and e.value.status_code == 502
    assert e.value.details == {"retryable": True}


def test_real_missing_keys_configure(monkeypatch):
    # Hermetic vs local .env (real test keys wired per ADR-024): blanking wins
    # over the .env file in both os.environ and pydantic-settings precedence.
    monkeypatch.setenv("UPI_KEY_ID", "")
    monkeypatch.setenv("UPI_KEY_SECRET", "")
    with pytest.raises(UpstreamError) as e:
        RealUpiProvider().create_intent(ORDER)
    assert e.value.code == "UPSTREAM_FAIL" and e.value.status_code == 502
    assert e.value.details == {"retryable": False}


def test_fake_default_untouched(monkeypatch):
    monkeypatch.delenv("UPI_PROVIDER", raising=False)
    assert isinstance(get_provider(), FakeUpiProvider)
    monkeypatch.setenv("UPI_PROVIDER", "fake")
    assert isinstance(get_provider(), FakeUpiProvider)
    out = FakeUpiProvider().create_intent(ORDER)
    assert out["provider_ref"].startswith("FAKE-APPROVE-")
    assert out["link"].startswith("upi://pay?")


def test_factory_gate_razorpay(monkeypatch):
    monkeypatch.setenv("UPI_PROVIDER", "razorpay")
    assert isinstance(get_provider(), RealUpiProvider)
    monkeypatch.setenv("UPI_PROVIDER", "real")  # old alias no longer real
    assert isinstance(get_provider(), FakeUpiProvider)
