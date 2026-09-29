"""E2 hardening tests: headers, CORS allowlist + preflight, body cap, anon throttle.

Every red path asserts the §0 error envelope {error: {code, message, details, trace_id}}.
"""

import os
import sys
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

import pytest
from fastapi.testclient import TestClient

from app.api.deps import get_settings
from app.api.middleware import reset_throttle
from app.main import create_app

client = TestClient(create_app())
EVIL = "https://evil.example"
ALLOW = "https://app.shodasha.in"


@pytest.fixture(autouse=True)
def _clean_throttle():
    settings = get_settings()
    old_limit = settings.throttle_anon_per_min
    reset_throttle()
    yield
    reset_throttle()
    settings.throttle_anon_per_min = old_limit


def _envelope(body: dict) -> dict:
    err = body["error"]
    assert isinstance(err["code"], str) and err["code"]
    assert isinstance(err["message"], str) and err["message"]
    assert isinstance(err["details"], dict)
    assert isinstance(err["trace_id"], str) and err["trace_id"]
    return err


def test_security_headers_present():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.headers["X-Content-Type-Options"] == "nosniff"
    assert r.headers["X-Frame-Options"] == "DENY"
    assert r.headers["Referrer-Policy"] == "strict-origin-when-cross-origin"
    assert r.headers["Content-Security-Policy"] == "default-src 'self'"


def test_security_headers_on_error_envelope():
    r = client.get("/does-not-exist")
    assert r.status_code == 404
    _envelope(r.json())
    assert r.headers["X-Content-Type-Options"] == "nosniff"
    assert r.headers["Content-Security-Policy"] == "default-src 'self'"


def test_cors_default_deny():
    r = client.get("/v1/catalog", headers={"Origin": EVIL})
    assert "access-control-allow-origin" not in r.headers
    pre = client.options(
        "/v1/catalog",
        headers={"Origin": EVIL, "Access-Control-Request-Method": "GET"},
    )
    assert "access-control-allow-origin" not in pre.headers


def test_cors_allowlist_and_preflight():
    old = os.environ.get("CORS_ORIGINS")
    os.environ["CORS_ORIGINS"] = ALLOW
    get_settings.cache_clear()
    try:
        allowed = TestClient(create_app())
        r = allowed.get("/v1/catalog", headers={"Origin": ALLOW})
        assert r.headers["access-control-allow-origin"] == ALLOW
        pre = allowed.options(
            "/v1/catalog",
            headers={"Origin": ALLOW, "Access-Control-Request-Method": "GET"},
        )
        assert pre.status_code == 200
        assert pre.headers["access-control-allow-origin"] == ALLOW
        bad = allowed.get("/v1/catalog", headers={"Origin": EVIL})
        assert "access-control-allow-origin" not in bad.headers
    finally:
        if old is None:
            os.environ.pop("CORS_ORIGINS", None)
        else:
            os.environ["CORS_ORIGINS"] = old
        get_settings.cache_clear()


def _quote_payload(pad: int = 0) -> dict:
    payload = {
        "items": [{"sku": "refill", "qty": 2}],
        "e": 1,
        "address_id": "a1",
        "window_start": "2026-09-30T08:00:00Z",
    }
    if pad:
        payload["note"] = "x" * pad
    return payload


def test_oversize_body_413_envelope():
    maximum = get_settings().body_max_bytes
    r = client.post("/v1/quotes", json=_quote_payload(pad=maximum + 1024))
    assert r.status_code == 413
    err = _envelope(r.json())
    assert err["code"] == "PAYLOAD_TOO_LARGE"
    assert r.headers["X-Content-Type-Options"] == "nosniff"


def test_normal_post_unaffected_by_body_cap():
    r = client.post("/v1/quotes", json=_quote_payload())
    assert r.status_code == 200, r.text


def test_throttle_burst_429_envelope():
    get_settings().throttle_anon_per_min = 5
    burst = [client.get("/v1/catalog") for _ in range(6)]
    assert [r.status_code for r in burst[:5]] == [200] * 5
    last = burst[5]
    assert last.status_code == 429
    err = _envelope(last.json())
    assert err["code"] == "RATE_LIMITED"
    assert int(last.headers["Retry-After"]) >= 1
    assert last.headers["X-Content-Type-Options"] == "nosniff"


def test_throttle_scoped_to_anon_gets():
    get_settings().throttle_anon_per_min = 5
    for _ in range(6):
        r = client.post("/v1/quotes", json=_quote_payload())
        assert r.status_code == 200, r.text
