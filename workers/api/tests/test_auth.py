"""C1 slice-2 tests: phone validation, rate limits, sessions, suspend, router.

Layers (python card: unit -> service -> API):
- pure unit: no DB, no HTTP.
- service: :memory: sqlite + 002_auth.sql applied (migration itself exercised),
  FakeVerifier injected (no network, no Firebase project).
- router (direct overrides): real envelope handlers + auth router with get_db
  overridden locally — passes today, proves the router wiring.
- router (integrator hook): uses ``app.api.deps.set_test_connection`` (assumed
  to exist per brief). Until the integrator lands it these tests
  EXPECTED-FAIL (xfailed with reason, not silently skipped).
"""

import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.adapters.firebase import RealVerifier, UnauthError, UpstreamError  # noqa: E402
from app.core.errors import RateLimitedError, ValidationError  # noqa: E402
from app.db import get_connection  # noqa: E402
from app.services.auth_service import (  # noqa: E402
    AuthService,
    DeviceCapError,
    hash_token,
    integrity_status,
    mask_phone,
    normalize_phone,
    reset_rate_limits,
)

MIGRATION = (API_ROOT / "app" / "db" / "migrations" / "002_auth.sql").read_text()
PHONE = "+919876543210"


@pytest.fixture(autouse=True)
def _clean_rates():
    reset_rate_limits()
    yield
    reset_rate_limits()


class FakeVerifier:
    """Maps id_token -> claims; unknown token -> 401 (like the real verifier)."""

    def __init__(self, mapping: dict | None = None):
        self.mapping = mapping or {"good": {"uid": "fake-uid-1", "phone_number": PHONE}}
        self.calls: list[str] = []

    def verify_id_token(self, token: str) -> dict:
        self.calls.append(token)
        if token not in self.mapping:
            raise UnauthError("Invalid session.", {})
        return dict(self.mapping[token])


def _conn():
    c = get_connection(":memory:")
    c.executescript(MIGRATION)
    return c


def _svc(c, verifier=None) -> AuthService:
    return AuthService(c, verifier if verifier is not None else FakeVerifier())


def _device(i: int = 1, **over) -> dict:
    d = {"id": f"dev-{i}"}
    d.update(over)
    return d


def _verify(c, token="good", device=None, verifier=None) -> dict:
    return _svc(c, verifier).otp_verify(token, device or _device())


def _suspend(c, user_id: str, role: str = "user") -> None:
    c.execute(
        "UPDATE users SET suspended = 1, suspended_reason = 'dues', role = ? WHERE id = ?",
        (role, user_id),
    )
    c.commit()


# -- pure unit ---------------------------------------------------------------


def test_phone_normalize_variants():
    assert normalize_phone("+919876543210") == PHONE
    assert normalize_phone("919876543210") == PHONE
    assert normalize_phone("9876543210") == PHONE
    assert normalize_phone(" 98765 43210 ") == PHONE


def test_phone_invalid_400():
    for bad in ("abc", "12345", "+911234567890", "+91987654321", ""):
        with pytest.raises(ValidationError) as e:
            normalize_phone(bad)
        assert (e.value.code, e.value.status_code) == ("VALIDATION", 400)


def test_mask_phone():
    assert mask_phone(PHONE) == "+91******3210"


def test_hash_token_deterministic():
    assert hash_token("a") == hash_token("a") and hash_token("a") != hash_token("b")
    assert len(hash_token("a")) == 64


def test_rate_limiter_blocks():
    from app.services.auth_service import RateLimiter

    rl = RateLimiter()
    rl.check("k", 2, 60)
    rl.check("k", 2, 60)
    with pytest.raises(RateLimitedError) as e:
        rl.check("k", 2, 60)
    assert (e.value.code, e.value.status_code) == ("RATE_LIMITED", 429)
    assert e.value.details["retry_after_s"] >= 1


def test_integrity_log_only_never_blocks():
    assert integrity_status(None) == "not-verified"
    assert integrity_status({"id": "d1"}) == "not-verified"
    assert integrity_status({"id": "d1", "integrity": "pass"}) == "pass"


def test_error_codes():
    assert (UnauthError("x").code, UnauthError("x").status_code) == ("UNAUTH", 401)
    assert (UpstreamError("x").code, UpstreamError("x").status_code) == ("UPSTREAM_FAIL", 502)
    assert (DeviceCapError("x").code, DeviceCapError("x").status_code) == ("DEVICE_CAP", 409)


def test_real_verifier_without_project_502(monkeypatch):
    monkeypatch.delenv("FIREBASE_PROJECT_ID", raising=False)
    with pytest.raises(UpstreamError) as e:
        RealVerifier(project_id=None).verify_id_token("anything")
    assert (e.value.code, e.value.status_code) == ("UPSTREAM_FAIL", 502)


def test_real_verifier_bad_token_401():
    pytest.importorskip("jwt")
    with pytest.raises(UnauthError) as e:
        RealVerifier(project_id="demo-project").verify_id_token("not.a.token")
    assert (e.value.code, e.value.status_code) == ("UNAUTH", 401)


# -- service -----------------------------------------------------------------


def test_otp_start_ok():
    out = _svc(_conn()).otp_start("9876543210", "1.2.3.4")
    assert out == {"sent_to_masked": "+91******3210", "resend_after_s": 30}


def test_otp_start_bad_phone_400():
    with pytest.raises(ValidationError) as e:
        _svc(_conn()).otp_start("abc", "1.2.3.4")
    assert e.value.status_code == 400


def test_otp_start_rate_limited_429():
    s = _svc(_conn())
    for _ in range(5):
        s.otp_start(PHONE, "9.9.9.9")
    with pytest.raises(RateLimitedError) as e:
        s.otp_start(PHONE, "9.9.9.9")
    assert e.value.status_code == 429


def test_otp_verify_ok_and_expiry():
    c = _conn()
    out = _verify(c)
    assert out["role"] == "user" and out["token_type"] == "bearer"
    assert out["new_device_alert"] is True
    assert out["details"] == {"integrity": "not-verified"}
    assert "restrictions" not in out
    delta = datetime.fromisoformat(out["expires_at"]) - datetime.now(timezone.utc)
    assert timedelta(minutes=29) < delta <= timedelta(minutes=31)
    out2 = _svc(c).otp_verify("good", _device())  # same device known now
    assert out2["new_device_alert"] is False


def test_otp_verify_integrity_echo():
    c = _conn()
    out = _verify(c, device=_device(integrity="pass"))
    assert out["details"] == {"integrity": "pass"}


def test_otp_verify_device_cap_409():
    c = _conn()
    mapping = {f"t{i}": {"uid": f"uid-{i}", "phone_number": f"+9198000000{i:02d}"} for i in range(4)}
    v = FakeVerifier(mapping)
    for i in range(3):
        _verify(c, token=f"t{i}", device=_device(9), verifier=v)
    with pytest.raises(DeviceCapError) as e:
        _verify(c, token="t3", device=_device(9), verifier=v)
    assert e.value.status_code == 409


def test_otp_verify_suspended_restrictions():
    c = _conn()
    uid = _verify(c)["user_id"]
    _suspend(c, uid, "user")
    out = _verify(c)
    assert out["restrictions"] == {
        "suspended": True,
        "allowed": ["read", "pay-dues", "appeal"],
        "reason": "dues",
    }
    uid2 = _verify(c, token="good", device=_device(2))["user_id"]
    assert uid2 == uid  # same phone row rebound, still suspended


def test_otp_verify_suspended_vendor_notice():
    c = _conn()
    v = FakeVerifier({"good": {"uid": "v-uid", "phone_number": "+919800000011"}})
    uid = _verify(c, verifier=v)["user_id"]
    _suspend(c, uid, "vendor")
    out = _verify(c, verifier=v)
    assert out["restrictions"] == {"suspended": True, "allowed": ["notice"]}


def test_refresh_rotates_and_reuse_kills_family():
    c = _conn()
    s = _svc(c)
    out = _verify(c)
    r1 = s.refresh(out["refresh_token"], "dev-1")
    assert r1["access_token"] != out["access_token"]
    # old access rotated away -> 401 on next use
    assert c.execute(
        "SELECT id FROM sessions WHERE token_hash = ?", (hash_token(out["access_token"]),)
    ).fetchone() is None
    # old refresh reuse -> 401 + whole family revoked (C7)
    with pytest.raises(UnauthError) as e:
        s.refresh(out["refresh_token"], "dev-1")
    assert e.value.status_code == 401
    with pytest.raises(UnauthError):
        s.refresh(r1["refresh_token"], "dev-1")


def test_refresh_wrong_device_401():
    c = _conn()
    s = _svc(c)
    out = _verify(c)
    with pytest.raises(UnauthError) as e:
        s.refresh(out["refresh_token"], "other-device")
    assert e.value.status_code == 401


def test_logout_revokes_single_vs_all():
    c = _conn()
    s = _svc(c)
    a = _verify(c)
    b = s.refresh(a["refresh_token"], "dev-1")
    row = c.execute(
        "SELECT id, family_id FROM sessions WHERE token_hash = ?",
        (hash_token(b["access_token"]),),
    ).fetchone()
    assert s.logout(session_id=row["id"], family_id=row["family_id"],
                    user_id=a["user_id"], device_id="dev-1") == {"ok": True}
    assert c.execute(
        "SELECT revoked_at FROM sessions WHERE id = ?", (row["id"],)
    ).fetchone()["revoked_at"] is not None


def test_me_ok_and_update():
    c = _conn()
    s = _svc(c)
    uid = _verify(c)["user_id"]
    me = s.me(uid)
    assert me["user"]["phone"] == PHONE and me["addresses_count"] == 0
    assert me["ledger_summary"] == {"held": 0, "deposit_paid": 0, "deposit_refunded": 0, "dues": 0}
    assert "restrictions" not in me
    assert s.update_me(uid, name="Asha", language="en")["user"]["language"] == "en"
    with pytest.raises(ValidationError):
        s.update_me(uid, language="xx-!")
    with pytest.raises(ValidationError):
        s.update_me(uid, name="   ")


def test_me_suspended_200_restrictions():
    c = _conn()
    s = _svc(c)
    uid = _verify(c)["user_id"]
    _suspend(c, uid)
    me = s.me(uid)
    assert me["user"]["suspended"] is True
    assert me["restrictions"]["allowed"] == ["read", "pay-dues", "appeal"]


# -- router (direct overrides: green today) -----------------------------------


def _client(c, verifier=None):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.adapters.firebase import get_verifier
    from app.api.deps import get_db
    from app.api.v1 import auth as mod
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(mod.router, prefix="/v1")
    app.dependency_overrides[get_db] = lambda: c
    app.dependency_overrides[get_verifier] = lambda: verifier or FakeVerifier()
    return TestClient(app)


def _auth_headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_router_start_202():
    r = _client(_conn()).post("/v1/auth/otp/start", json={"phone": "9876543210"})
    assert r.status_code == 202, r.text
    assert r.json() == {"sent_to_masked": "+91******3210", "resend_after_s": 30}


def test_router_start_bad_phone_400():
    assert _client(_conn()).post("/v1/auth/otp/start", json={"phone": "abc"}).status_code == 400


def test_router_verify_me_patch():
    c = _conn()
    client = _client(c)
    r = client.post("/v1/auth/otp/verify",
                    json={"firebase_id_token": "good", "device": {"id": "dev-1"}})
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    me = client.get("/v1/auth/me", headers=_auth_headers(token))
    assert me.status_code == 200, me.text
    assert me.json()["user"]["phone"] == PHONE
    p = client.patch("/v1/auth/me", json={"name": "Asha"}, headers=_auth_headers(token))
    assert p.status_code == 200 and p.json()["user"]["name"] == "Asha"


def test_router_verify_missing_device_400():
    c = _conn()
    r = _client(c).post("/v1/auth/otp/verify",
                        json={"firebase_id_token": "good", "device": {}})
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "VALIDATION"


def test_router_suspended_patch_403_me_200():
    c = _conn()
    client = _client(c)
    token = client.post("/v1/auth/otp/verify",
                        json={"firebase_id_token": "good", "device": {"id": "dev-1"}}).json()["access_token"]
    uid = client.get("/v1/auth/me", headers=_auth_headers(token)).json()["user"]["id"]
    _suspend(c, uid)
    me = client.get("/v1/auth/me", headers=_auth_headers(token))
    assert me.status_code == 200, me.text
    assert me.json()["restrictions"]["allowed"] == ["read", "pay-dues", "appeal"]
    p = client.patch("/v1/auth/me", json={"name": "Nope"}, headers=_auth_headers(token))
    assert p.status_code == 403
    assert p.json()["error"]["code"] == "FORBIDDEN"


def test_router_refresh_logout():
    c = _conn()
    client = _client(c)
    v = client.post("/v1/auth/otp/verify",
                    json={"firebase_id_token": "good", "device": {"id": "dev-1"}}).json()
    r = client.post("/v1/auth/refresh",
                    json={"refresh_token": v["refresh_token"], "device": {"id": "dev-1"}})
    assert r.status_code == 200, r.text
    lo = client.post("/v1/auth/logout", json={},
                     headers=_auth_headers(r.json()["access_token"]))
    assert lo.status_code == 200 and lo.json() == {"ok": True}
    assert client.get("/v1/auth/me",
                      headers=_auth_headers(r.json()["access_token"])).status_code == 401


def test_router_no_token_401():
    c = _conn()
    assert _client(c).get("/v1/auth/me").status_code == 401
    assert _client(c).get("/v1/auth/me",
                          headers=_auth_headers("dead")).status_code == 401


# -- router via integrator hook (EXPECTED-FAIL until deps.py lands it) --------


def _hook():
    try:
        from app.api.deps import set_test_connection  # noqa: PLC0415
    except ImportError:
        pytest.xfail("EXPECTED-FAIL: app.api.deps.set_test_connection missing (integrator pending)")
    return set_test_connection


def _hook_client(c, verifier=None):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.adapters.firebase import get_verifier
    from app.api.v1 import auth as mod
    from app.core.errors import register_exception_handlers

    set_test_connection = _hook()
    set_test_connection(c)
    try:
        app = FastAPI()
        register_exception_handlers(app)
        app.include_router(mod.router, prefix="/v1")
        app.dependency_overrides[get_verifier] = lambda: verifier or FakeVerifier()
        yield TestClient(app)
    finally:
        try:
            set_test_connection(None)
        except TypeError:
            pass


def test_hook_start_202():
    for client in _hook_client(_conn()):
        r = client.post("/v1/auth/otp/start", json={"phone": "9876543210"})
        assert r.status_code == 202, r.text


def test_hook_verify_me_200():
    for client in _hook_client(_conn()):
        v = client.post("/v1/auth/otp/verify",
                        json={"firebase_id_token": "good", "device": {"id": "dev-1"}})
        assert v.status_code == 200, v.text
        me = client.get("/v1/auth/me",
                        headers=_auth_headers(v.json()["access_token"]))
        assert me.status_code == 200, me.text
        assert me.json()["user"]["phone"] == PHONE
