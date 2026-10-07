"""028 access-code auth backend slice: generalized codes + register + absolute cap.

DB harness: raw migrations (no init_schema) — M002 (users/sessions) + M010
(config/audit_log) + M014 (access_codes + access_code_login_enabled flag +
sessions.session_expires_at) + M020 (users.email). Router tests use the REAL
auth_deps gates.
"""
import datetime as _dt
import hashlib
import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.core.errors import AppError  # noqa: E402
from app.db import get_connection  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.services.auth_service import AuthService, reset_rate_limits  # noqa: E402

M002 = (API_ROOT / "src" / "app" / "db" / "migrations" / "002_auth.sql").read_text()
M010 = (API_ROOT / "src" / "app" / "db" / "migrations" / "010_config_audit.sql").read_text()
M014 = (API_ROOT / "src" / "app" / "db" / "migrations" / "014_access_codes.sql").read_text()
M020 = (API_ROOT / "src" / "app" / "db" / "migrations" / "020_user_email.sql").read_text()

NOW = _dt.datetime.now(_dt.timezone.utc)
FUTURE = (NOW + _dt.timedelta(days=30)).isoformat()
PAST = (NOW - _dt.timedelta(days=1)).isoformat()

PHONE_V = "+919000000031"  # vendor vv
PHONE_A = "+919000000032"  # admin aa
PHONE_U = "+919000000033"  # plain user uu
PHONE_N = "+919000000034"  # fresh number for register-new
PHONE_B = "+919000000035"  # blank-name user ub
PHONE_X = "+919999999931"  # unknown phone (valid shape)

CODE_V = "access-vendor-11"
CODE_A = "access-admin-22"
CODE_EXP = "access-exp-00"
CODE_REV = "access-rev-00"

GENERIC = "Invalid credentials."


def _H(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()


def _conn(flag=True):
    raw = get_connection(":memory:")
    raw.executescript(M002 + M010 + M014 + M020)
    now = NOW.isoformat()
    raw.execute(
        "INSERT INTO users(id, phone, name, role, kyc_status, created_at) VALUES "
        "('vv', ?, 'Vendor V', 'vendor', 'verified', ?),"
        " ('aa', ?, 'Admin A', 'admin', 'verified', ?),"
        " ('uu', ?, 'User U', 'user', 'unverified', ?),"
        " ('ub', ?, NULL, 'user', 'unverified', ?)",
        (PHONE_V, now, PHONE_A, now, PHONE_U, now, PHONE_B, now),
    )
    raw.execute("UPDATE config SET value = ? WHERE key = 'access_code_login_enabled'",
                ("1" if flag else "0",))
    raw.execute(
        "INSERT INTO access_codes(id, user_id, code_hash, masked_hint, expected_role,"
        " expires_at, revoked_at, last_used_at, created_by, created_at)"
        " VALUES ('cv', 'vv', ?, '••11', 'vendor', ?, NULL, NULL, 'aa', ?),"
        " ('cv-exp', 'vv', ?, '••00', 'vendor', ?, NULL, NULL, 'aa', ?),"
        " ('cv-rev', 'vv', ?, '••00', 'vendor', ?, ?, NULL, 'aa', ?),"
        " ('ca', 'aa', ?, '••22', 'admin', ?, NULL, NULL, 'aa', ?)",
        (_H(CODE_V), FUTURE, now,
         _H(CODE_EXP), PAST, now,
         _H(CODE_REV), FUTURE, now, now,
         _H(CODE_A), FUTURE, now),
    )
    raw.commit()
    return raw


def _svc(raw) -> AuthService:
    return AuthService(AsyncSqliteConn(raw))


def _session(raw, uid, role, token):
    raw.execute(
        "INSERT INTO sessions(id, user_id, token_hash, refresh_hash, role, device_fp,"
        " family_id, expires_at, created_at) VALUES (?, ?, ?, ?, ?, 'd', 'f', ?, ?)",
        (f"ses-{uid}-{token[:6]}", uid, hashlib.sha256(token.encode()).hexdigest(),
         hashlib.sha256(f"r:{token}".encode()).hexdigest(), role, FUTURE, FUTURE),
    )
    raw.commit()


def _client(raw):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.deps import get_db_conn
    from app.api.v1.admin import router as admin_router
    from app.api.v1.auth import router as auth_router
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(auth_router, prefix="/v1")
    app.include_router(admin_router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: AsyncSqliteConn(raw)
    return TestClient(app)


def _audit(raw):
    return {(r["action"], r["entity"], r["entity_id"])
            for r in raw.execute("SELECT action, entity, entity_id FROM audit_log").fetchall()}


# -- register matrix ----------------------------------------------------------

async def test_register_new_user_unverified_plus_session():
    reset_rate_limits()
    raw = _conn()
    out = await _svc(raw).user_register("Naya User", PHONE_N, "naya@gmail.com",
                                        "reg-dev-1", ip="10.0.0.1")
    assert out["role"] == "user" and out["access_token"] and out["refresh_token"]
    assert out["verified"] is False
    row = raw.execute("SELECT role, kyc_status, name, email FROM users WHERE phone = ?",
                      (PHONE_N,)).fetchone()
    assert row["role"] == "user" and row["kyc_status"] == "unverified"
    assert row["name"] == "Naya User" and row["email"] == "naya@gmail.com"


async def test_register_blank_name_filled_once_never_overwritten():
    reset_rate_limits()
    raw = _conn()
    out1 = await _svc(raw).user_register("First Name", PHONE_B, "first@gmail.com",
                                        "reg-dev-2", ip="10.0.0.2")
    assert out1["role"] == "user"
    row = raw.execute("SELECT name, email FROM users WHERE id = 'ub'").fetchone()
    assert row["name"] == "First Name" and row["email"] == "first@gmail.com"
    out2 = await _svc(raw).user_register("Second Name", PHONE_B, "second@gmail.com",
                                        "reg-dev-3", ip="10.0.0.3")
    assert out2["role"] == "user"
    row = raw.execute("SELECT name, email FROM users WHERE id = 'ub'").fetchone()
    assert row["name"] == "First Name" and row["email"] == "first@gmail.com"


async def test_register_staff_number_422():
    reset_rate_limits()
    for phone in (PHONE_V, PHONE_A):
        with pytest.raises(AppError) as e:
            await _svc(_conn()).user_register("Intruder", phone, "i@gmail.com",
                                              "reg-dev-4", ip="10.0.0.4")
        assert e.value.status_code == 422
        assert e.value.code == "ROLE_RESERVED"


async def test_register_bad_phone_400():
    reset_rate_limits()
    with pytest.raises(AppError) as e:
        await _svc(_conn()).user_register("Bad", "123", "b@gmail.com",
                                          "reg-dev-5", ip="10.0.0.5")
    assert e.value.status_code == 400


async def test_register_bad_email_400():
    reset_rate_limits()
    for bad in ("nope", "a@b", "a@b.", "@x.in", "a b@c.in", "other@yahoo.com"):
        with pytest.raises(AppError) as e:
            await _svc(_conn()).user_register("Bad", PHONE_N, bad,
                                              "reg-dev-6", ip="10.0.0.6")
        assert e.value.status_code == 400


async def test_register_rate_limit_phone():
    reset_rate_limits()
    raw = _conn()
    for i in range(5):
        await _svc(raw).user_register(f"Rate {i}", PHONE_N, f"r{i}@gmail.com",
                                      f"reg-dev-rl-{i}", ip=f"10.9.9.{i}")
    with pytest.raises(AppError) as e:
        await _svc(raw).user_register("Rate 5", PHONE_N, "r5@gmail.com",
                                      "reg-dev-rl-5", ip="10.9.9.99")
    assert e.value.status_code == 429


def test_register_router_end_to_end():
    reset_rate_limits()
    client = _client(_conn())
    r = client.post("/v1/auth/user/register",
                    json={"name": "Router User", "email": "router@gmail.com",
                          "phone": PHONE_N, "device": {"id": "reg-dev-9"}})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["role"] == "user" and body["verified"] is False and body["access_token"]
    non_gmail = client.post("/v1/auth/user/register",
                            json={"name": "Non Gmail", "email": "user@yahoo.com",
                                  "phone": PHONE_N, "device": {"id": "reg-dev-9"}})
    assert non_gmail.status_code == 400
    bad = client.post("/v1/auth/user/register",
                      json={"name": "X", "email": "x@gmail.com",
                            "phone": PHONE_V, "device": {"id": "reg-dev-9"}})
    assert bad.status_code == 422
    no_email = client.post("/v1/auth/user/register",
                           json={"name": "No Mail", "phone": PHONE_N,
                                 "device": {"id": "reg-dev-9"}})
    assert no_email.status_code in (400, 422)


# -- code login matrix --------------------------------------------------------

async def test_code_login_vendor_ok_touch_and_audit():
    reset_rate_limits()
    raw = _conn()
    out = await _svc(raw).code_login(PHONE_V, CODE_V, "code-dev-1", expected_role="vendor")
    assert out["role"] == "vendor" and out["access_token"]
    assert raw.execute("SELECT last_used_at FROM access_codes WHERE id = 'cv'").fetchone()["last_used_at"]
    assert ("access.use", "access_codes", "cv") in _audit(raw)


async def test_code_login_admin_ok():
    reset_rate_limits()
    raw = _conn()
    out = await _svc(raw).code_login(PHONE_A, CODE_A, "code-dev-2", expected_role="admin")
    assert out["role"] == "admin" and out["access_token"]


async def test_code_login_no_oracle():
    """Wrong / expired / revoked / wrong-role / unknown / flag-off → one generic 401."""
    reset_rate_limits()
    msgs = []
    cases = [
        (PHONE_V, "wrong-wrong-wrong", "vendor", "code-dev-3"),
        (PHONE_V, CODE_EXP, "vendor", "code-dev-4"),
        (PHONE_V, CODE_REV, "vendor", "code-dev-5"),
        (PHONE_V, CODE_V, "admin", "code-dev-6"),  # vendor code on the admin door
        (PHONE_A, CODE_A, "vendor", "code-dev-7"),  # admin code on the vendor door
        (PHONE_U, CODE_V, "vendor", "code-dev-8"),  # plain user, no code row
        (PHONE_X, CODE_V, "vendor", "code-dev-9"),  # unknown phone
    ]
    for phone, code, role, dev in cases:
        with pytest.raises(AppError) as e:
            await _svc(_conn()).code_login(phone, code, dev, expected_role=role)
        assert e.value.status_code == 401
        msgs.append(e.value.message)
    assert set(msgs) == {GENERIC}


async def test_code_login_flag_off_closed():
    reset_rate_limits()
    with pytest.raises(AppError) as e:
        await _svc(_conn(flag=False)).code_login(PHONE_V, CODE_V, "code-dev-10", expected_role="vendor")
    assert e.value.status_code == 401
    assert e.value.message == GENERIC


async def test_code_login_rate_limit_device():
    reset_rate_limits()
    raw = _conn()
    for _ in range(10):
        with pytest.raises(AppError):
            await _svc(raw).code_login(PHONE_V, "wrong-wrong-wrong", "code-dev-rl", expected_role="vendor")
    with pytest.raises(AppError) as e:
        await _svc(raw).code_login(PHONE_V, "wrong-wrong-wrong", "code-dev-rl", expected_role="vendor")
    assert e.value.status_code == 429


def test_code_login_router_both_doors():
    reset_rate_limits()
    client = _client(_conn())
    rv = client.post("/v1/auth/vendor/login",
                     json={"phone": PHONE_V, "code": CODE_V, "device": {"id": "code-dev-20"}})
    assert rv.status_code == 200, rv.text
    assert rv.json()["role"] == "vendor"
    ra = client.post("/v1/auth/admin/login",
                     json={"phone": PHONE_A, "code": CODE_A, "device": {"id": "code-dev-21"}})
    assert ra.status_code == 200, ra.text
    assert ra.json()["role"] == "admin"
    bad = client.post("/v1/auth/admin/login",
                      json={"phone": PHONE_V, "code": CODE_V, "device": {"id": "code-dev-22"}})
    assert bad.status_code == 401


# -- absolute cap ---------------------------------------------------------------

async def test_refresh_absolute_cap_burns_nothing_but_denies():
    reset_rate_limits()
    raw = _conn()
    out = await _svc(raw).code_login(PHONE_V, CODE_V, "cap-dev-1", expected_role="vendor")
    past = (NOW - _dt.timedelta(days=1)).isoformat()
    raw.execute("UPDATE sessions SET session_expires_at = ? WHERE user_id = 'vv'", (past,))
    raw.commit()
    with pytest.raises(AppError) as e:
        await _svc(raw).refresh(out["refresh_token"], "cap-dev-1")
    assert e.value.status_code == 401
    # Family intact: no burn on cap-expiry (plain 401, row still live).
    row = raw.execute("SELECT revoked_at FROM sessions WHERE user_id = 'vv'").fetchone()
    assert row["revoked_at"] is None


async def test_refresh_rotation_preserves_cap():
    reset_rate_limits()
    raw = _conn()
    out = await _svc(raw).code_login(PHONE_V, CODE_V, "cap-dev-2", expected_role="vendor")
    before = raw.execute("SELECT session_expires_at FROM sessions WHERE user_id = 'vv'").fetchone()["session_expires_at"]
    assert before
    out2 = await _svc(raw).refresh(out["refresh_token"], "cap-dev-2")
    assert out2["access_token"]
    after = raw.execute("SELECT session_expires_at FROM sessions WHERE user_id = 'vv'").fetchone()["session_expires_at"]
    assert after == before


async def test_refresh_backfills_missing_cap():
    reset_rate_limits()
    raw = _conn()
    # Legacy pre-014 row: no cap column value (NULL), created 10d ago.
    created = (NOW - _dt.timedelta(days=10)).isoformat()
    refresh_exp = (NOW + _dt.timedelta(days=7)).isoformat()
    raw.execute(
        "INSERT INTO sessions(id, user_id, token_hash, refresh_hash, role, device_fp,"
        " family_id, expires_at, refresh_expires_at, session_expires_at, created_at)"
        " VALUES ('legacy-1', 'vv', ?, ?, 'vendor', 'cap-dev-3', 'fam-1', ?, ?, NULL, ?)",
        (_H("acc-legacy-1"), _H("ref-legacy-1"), FUTURE, refresh_exp, created),
    )
    raw.commit()
    out = await _svc(raw).refresh("ref-legacy-1", "cap-dev-3")
    assert out["access_token"]
    cap = raw.execute("SELECT session_expires_at FROM sessions WHERE id = 'legacy-1'").fetchone()["session_expires_at"]
    assert cap  # min(refresh_expires_at, created+30d) backfilled


# -- codes CRUD -----------------------------------------------------------------

def test_codes_crud_masked_revoke_kills_login():
    reset_rate_limits()
    raw = _conn()
    _session(raw, "aa", "admin", "tok-admin")
    client = _client(raw)
    ha = {"Authorization": "Bearer tok-admin"}

    issue = client.post("/v1/admin/users/vv/access-codes", json={}, headers=ha)
    assert issue.status_code == 201, issue.text
    body = issue.json()
    assert body["expected_role"] == "vendor"
    assert "code_hash" not in body and "code" in body
    assert body["masked_hint"] == f"••{body['code'][-2:]}"
    assert raw.execute("SELECT code_hash FROM access_codes WHERE id = ?",
                       (body["id"],)).fetchone()["code_hash"] == _H(body["code"])

    listed = client.get("/v1/admin/users/vv/access-codes", headers=ha)
    assert listed.status_code == 200, listed.text
    rows = listed.json()["data"]
    assert rows and all("code_hash" not in r and "code" not in r for r in rows)
    assert {r["id"] for r in rows} >= {"cv", body["id"]}

    assert client.post("/v1/auth/vendor/login",
                       json={"phone": PHONE_V, "code": body["code"],
                             "device": {"id": "code-dev-30"}}).status_code == 200

    rev = client.post(f"/v1/admin/users/vv/access-codes/{body['id']}/revoke", headers=ha)
    assert rev.status_code == 200, rev.text
    bad = client.post("/v1/auth/vendor/login",
                      json={"phone": PHONE_V, "code": body["code"], "device": {"id": "code-dev-31"}})
    assert bad.status_code == 401

    assert client.post("/v1/admin/users/vv/access-codes/nope/revoke", headers=ha).status_code == 404
    actions = _audit(raw)
    assert ("access.issue", "access_codes", body["id"]) in actions
    assert ("access.revoke", "access_codes", body["id"]) in actions


async def test_codes_crud_async_login_revoke():
    reset_rate_limits()
    raw = _conn()
    _session(raw, "aa", "admin", "tok-admin2")
    # Issue directly via repo, login, revoke, login must die.
    from app.repositories.access_code_repo import AccessCodeRepo
    import secrets as _secrets
    import uuid as _uuid
    code = _secrets.token_urlsafe(12)
    cid = _uuid.uuid4().hex
    await AccessCodeRepo(AsyncSqliteConn(raw)).issue(
        code_id=cid, user_id="vv", code_hash=_H(code), masked_hint=f"••{code[-2:]}",
        expected_role="vendor", expires_at=FUTURE, created_by="aa")
    out = await _svc(raw).code_login(PHONE_V, code, "code-dev-32", expected_role="vendor")
    assert out["role"] == "vendor"
    assert await AccessCodeRepo(AsyncSqliteConn(raw)).revoke(cid, "vv") is True
    with pytest.raises(AppError) as e:
        await _svc(raw).code_login(PHONE_V, code, "code-dev-33", expected_role="vendor")
    assert e.value.status_code == 401


def test_codes_refuse_user_and_ghost_and_expiry_bounds():
    reset_rate_limits()
    raw = _conn()
    _session(raw, "aa", "admin", "tok-admin")
    client = _client(raw)
    ha = {"Authorization": "Bearer tok-admin"}
    # role=user never gets codes (422 — they use register).
    assert client.post("/v1/admin/users/uu/access-codes", json={}, headers=ha).status_code == 422
    assert client.get("/v1/admin/users/uu/access-codes", headers=ha).status_code == 422
    assert client.get("/v1/admin/users/ghost/access-codes", headers=ha).status_code == 404
    assert client.post("/v1/admin/users/ghost/access-codes", json={}, headers=ha).status_code == 404
    # Expiry bounds: <1h and >180d rejected; blank defaults to ~90d.
    soon = (NOW + _dt.timedelta(minutes=30)).isoformat()
    far = (NOW + _dt.timedelta(days=181)).isoformat()
    assert client.post("/v1/admin/users/vv/access-codes",
                       json={"expires_at": soon}, headers=ha).status_code == 400
    assert client.post("/v1/admin/users/vv/access-codes",
                       json={"expires_at": far}, headers=ha).status_code == 400
    ok = client.post("/v1/admin/users/aa/access-codes", json={}, headers=ha)
    assert ok.status_code == 201, ok.text
    assert ok.json()["expected_role"] == "admin"
    exp = _dt.datetime.fromisoformat(ok.json()["expires_at"])
    if exp.tzinfo is None:
        exp = exp.replace(tzinfo=_dt.timezone.utc)
    delta = (exp - NOW).days
    assert 85 <= delta <= 95


def test_admin_codes_require_admin_role():
    reset_rate_limits()
    raw = _conn()
    _session(raw, "vv", "vendor", "tok-vv")
    client = _client(raw)
    hv = {"Authorization": "Bearer tok-vv"}
    assert client.get("/v1/admin/users/vv/access-codes", headers=hv).status_code == 403
    assert client.post("/v1/admin/users/vv/access-codes", json={}, headers=hv).status_code == 403
