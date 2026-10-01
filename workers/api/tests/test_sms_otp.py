"""Server-OTP slice tests: Fast2SMS adapter + service start/verify + router.

Layers (python card: unit -> service -> API):
- adapter unit: FakeSmsProvider records; Fast2SmsProvider without key -> 502.
- service: :memory: sqlite + 002_auth.sql + 008_otp.sql, provider factory
  monkeypatched (no network, no wallet, no DLT).
- router: TestClient over get_db_conn override, real service + fake SMS.
"""
import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.adapters import sms as sms_mod  # noqa: E402
from app.adapters.sms import FakeSmsProvider, Fast2SmsProvider, SmsUpstreamError  # noqa: E402
from app.core.errors import RateLimitedError, ValidationError  # noqa: E402
from app.db import get_connection  # noqa: E402
from app.services.auth_service import AuthService, reset_rate_limits  # noqa: E402

M002 = (API_ROOT / "src" / "app" / "db" / "migrations" / "002_auth.sql").read_text()
M008 = (API_ROOT / "src" / "app" / "db" / "migrations" / "008_otp.sql").read_text()
PHONE = "+919876543210"


@pytest.fixture(autouse=True)
def _clean_rates():
    reset_rate_limits()
    yield
    reset_rate_limits()


def _conn():
    from app.db_d1 import AsyncSqliteConn  # noqa: PLC0415 (facade: same await shape as D1)

    raw = get_connection(":memory:")
    raw.executescript(M002)
    raw.executescript(M008)
    return AsyncSqliteConn(raw)


@pytest.fixture()
def _sms(monkeypatch):
    """Pin the provider seam to fast2sms + a recording fake (no network)."""
    fake = FakeSmsProvider()
    monkeypatch.setattr(sms_mod, "otp_provider", lambda: "fast2sms")
    monkeypatch.setattr(sms_mod, "get_sms_provider", lambda: fake)
    return fake


def _svc(c) -> AuthService:
    return AuthService(c, None)


# -- adapter unit ------------------------------------------------------------

def test_fake_records_and_sends_nothing():
    fake = FakeSmsProvider()
    out = fake.send_otp(PHONE, "123456")
    assert out["provider"] == "fake"
    assert fake.sent == [{"phone": PHONE, "code": "123456"}]


def test_real_without_key_502(monkeypatch):
    monkeypatch.setattr(sms_mod, "otp_provider", lambda: "fast2sms")
    import app.adapters.sms as m  # noqa: PLC0415

    monkeypatch.setattr(m, "_setting", lambda *a, **k: None)
    with pytest.raises(SmsUpstreamError) as e:
        Fast2SmsProvider()
    assert e.value.status_code == 502


def test_factory_default_is_fake():
    assert isinstance(sms_mod.get_sms_provider(), FakeSmsProvider)


# -- service -----------------------------------------------------------------

async def test_start_sms_channel_stores_hash_only(_sms):
    c = _conn()
    out = await _svc(c).otp_start("9876543210", "1.2.3.4")
    assert out["channel"] == "sms"
    assert out["sent_to_masked"] == "+91******3210"
    assert len(_sms.sent) == 1 and _sms.sent[0]["phone"] == PHONE
    row = (await c.execute("SELECT code_hash, attempts FROM otp_codes WHERE phone = ?",
                           (PHONE,))).fetchone()
    assert row is not None and row["attempts"] == 0
    import hashlib

    assert row["code_hash"] == hashlib.sha256(_sms.sent[0]["code"].encode()).hexdigest()
    assert _sms.sent[0]["code"] not in row["code_hash"]  # hash only, never plain


async def test_verify_round_trip_single_use(_sms):
    c = _conn()
    svc = _svc(c)
    await svc.otp_start("9876543210", "1.2.3.4")
    code = _sms.sent[0]["code"]
    out = await svc.otp_verify(None, {"id": "dev-1"}, phone="9876543210", code=code)
    assert out["access_token"] and out["role"] == "user"
    with pytest.raises(ValidationError) as e:  # consumed: replay is a mismatch
        await svc.otp_verify(None, {"id": "dev-1"}, phone="9876543210", code=code)
    assert e.value.status_code == 400


async def test_verify_wrong_code_400(_sms):
    c = _conn()
    svc = _svc(c)
    await svc.otp_start("9876543210", "1.2.3.4")
    with pytest.raises(ValidationError) as e:
        await svc.otp_verify(None, {"id": "dev-1"}, phone="9876543210", code="000000")
    assert e.value.status_code == 400


async def test_verify_expired_400(_sms):
    c = _conn()
    svc = _svc(c)
    await svc.otp_start("9876543210", "1.2.3.4")
    code = _sms.sent[0]["code"]
    await c.execute("UPDATE otp_codes SET expires_at = '2000-01-01T00:00:00+00:00'"
                    " WHERE phone = ?", (PHONE,))
    c.commit()
    with pytest.raises(ValidationError) as e:
        await svc.otp_verify(None, {"id": "dev-1"}, phone="9876543210", code=code)
    assert e.value.status_code == 400


async def test_verify_five_strikes_locks_429(_sms):
    c = _conn()
    svc = _svc(c)
    await svc.otp_start("9876543210", "1.2.3.4")
    for _ in range(5):
        with pytest.raises(ValidationError):
            await svc.otp_verify(None, {"id": "dev-1"}, phone="9876543210", code="000000")
    with pytest.raises(RateLimitedError) as e:  # 6th: burned
        await svc.otp_verify(None, {"id": "dev-1"}, phone="9876543210", code="000000")
    assert e.value.status_code == 429


# -- router ------------------------------------------------------------------

def _client(c):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.deps import get_db_conn
    from app.api.v1 import auth as mod
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(mod.router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: c
    return TestClient(app)


def test_router_sms_start_then_verify_200(_sms):
    c = _conn()
    client = _client(c)
    r = client.post("/v1/auth/otp/start", json={"phone": "9876543210"})
    assert r.status_code == 202, r.text
    assert r.json()["channel"] == "sms"
    code = _sms.sent[0]["code"]
    v = client.post("/v1/auth/otp/verify",
                    json={"phone": "+919876543210", "otp_code": code,
                          "device": {"id": "dev-1"}})
    assert v.status_code == 200, v.text
    assert v.json()["role"] == "user"
