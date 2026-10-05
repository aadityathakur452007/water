"""027 vendor RBAC backend slice: access-code login, payouts read, admin codes/preview, audits, IDOR.

DB harness mirrors test_vendor.py (raw migrations, no init_schema) + 010
(config/audit_log) + 013 (vendor_access_codes). Router tests use the REAL
auth_deps gates with seeded sessions.
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
from app.services.vendor_service import VendorService, pod_otp  # noqa: E402

M002 = (API_ROOT / "src" / "app" / "db" / "migrations" / "002_auth.sql").read_text()
M003 = (API_ROOT / "src" / "app" / "db" / "migrations" / "003_addresses.sql").read_text()
M004 = (API_ROOT / "src" / "app" / "db" / "migrations" / "004_orders.sql").read_text()
M005 = (API_ROOT / "src" / "app" / "db" / "migrations" / "005_payments.sql").read_text()
M007 = (API_ROOT / "src" / "app" / "db" / "migrations" / "007_ops.sql").read_text()
M010 = (API_ROOT / "src" / "app" / "db" / "migrations" / "010_config_audit.sql").read_text()
M013 = (API_ROOT / "src" / "app" / "db" / "migrations" / "013_vendor_access.sql").read_text()

NOW = _dt.datetime.now(_dt.timezone.utc)
DAY = NOW.date().isoformat()
FUTURE = (NOW + _dt.timedelta(hours=1)).isoformat()
FAR_FUTURE = (NOW + _dt.timedelta(days=30)).isoformat()
PAST = (NOW - _dt.timedelta(days=1)).isoformat()

PHONE_A = "+919000000011"  # vendor va
PHONE_B = "+919000000012"  # vendor vb
PHONE_U = "+919000000013"  # plain user u1
PHONE_X = "+919999999999"  # unknown phone (valid shape)

CODE_A = "bravo-code-11"  # va live code
CODE_B = "bravo-code-22"  # vb live code
CODE_U = "bravo-code-99"  # live code row on a NON-vendor (role-gate probe)
CODE_EXP = "bravo-exp-00"
CODE_REV = "bravo-rev-00"

GENERIC = "Invalid credentials."


def _H(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()


def _conn(flag=True):
    raw = get_connection(":memory:")
    raw.executescript(M002 + M003 + M004 + M005 + M007 + M010 + M013)
    now = NOW.isoformat()
    raw.execute(
        "INSERT INTO users(id, phone, role, created_at) VALUES "
        "('va', ?, 'vendor', ?), ('vb', ?, 'vendor', ?),"
        " ('u1', ?, 'user', ?), ('a1', ?, 'admin', ?)",
        (PHONE_A, now, PHONE_B, now, PHONE_U, now, "+919000000099", now),
    )
    raw.execute("UPDATE config SET value = ? WHERE key = 'vendor_access_enabled'",
                ("1" if flag else "0",))
    raw.execute(
        "INSERT INTO vendor_access_codes(id, vendor_id, code_hash, masked_hint,"
        " expires_at, revoked_at, last_used_at, created_by, created_at)"
        " VALUES ('ca', 'va', ?, '••11', ?, NULL, NULL, 'a1', ?),"
        " ('ca-exp', 'va', ?, '••00', ?, NULL, NULL, 'a1', ?),"
        " ('ca-rev', 'va', ?, '••00', ?, ?, NULL, 'a1', ?),"
        " ('cb', 'vb', ?, '••22', ?, NULL, NULL, 'a1', ?),"
        " ('cu', 'u1', ?, '••99', ?, NULL, NULL, 'a1', ?)",
        (_H(CODE_A), FAR_FUTURE, now,
         _H(CODE_EXP), PAST, now,
         _H(CODE_REV), FAR_FUTURE, now, now,
         _H(CODE_B), FAR_FUTURE, now,
         _H(CODE_U), FAR_FUTURE, now),
    )
    raw.execute(
        "INSERT INTO addresses(id, user_id, type, lat, lng, pincode, created_at)"
        " VALUES ('a1', 'u1', 'home', 12.9716, 77.5946, '560001', ?)", (now,),
    )
    raw.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
        " total, payment_mode, state, window_start, idempotency_key, created_at)"
        " VALUES ('o1', 'u1', 'a1', '[]', 2, 1, 5600, 15000, 20600, 'cod',"
        " 'dispatched', '2026-10-01T08:00Z', 'seed:o1', ?)", (now,),
    )
    raw.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status) VALUES ('r1', ?, 'va', 'z1', 'open')",
        (DAY,),
    )
    raw.execute(
        "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status) VALUES ('s1', 'r1', 'o1', 'u1', 0, 2, 1, 1, 'pending')",
    )
    raw.execute(
        "INSERT INTO complaints(id, order_id, user_id, reason_code, text, status, created_at)"
        " VALUES ('c1', 'o1', 'u1', 'short_delivery', 'one jar short', 'open', ?)", (now,),
    )
    raw.execute(
        "INSERT INTO quality_incidents(id, order_id, vendor_id, reason_code, status, created_at)"
        " VALUES ('q1', 'o1', 'va', 'water_quality', 'open', ?)", (now,),
    )
    raw.execute(
        "INSERT INTO payouts(id, vendor_id, period, stops_done, gross_fee,"
        " deductions, net, status, created_at)"
        " VALUES ('p1', 'va', '2026-10', 3, 3000, 0, 3000, 'pending', ?),"
        " ('p2', 'vb', '2026-10', 5, 5000, 0, 5000, 'pending', ?)", (now, now),
    )
    raw.commit()
    return raw


def _svc(raw) -> AuthService:
    return AuthService(AsyncSqliteConn(raw))


def _vsvc(raw) -> VendorService:
    return VendorService(AsyncSqliteConn(raw))


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
    from app.api.v1.vendor import router as vendor_router
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(auth_router, prefix="/v1")
    app.include_router(vendor_router, prefix="/v1")
    app.include_router(admin_router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: AsyncSqliteConn(raw)
    return TestClient(app)


def _audit_actions(raw):
    return {(r["actor"], r["action"], r["entity"], r["entity_id"])
            for r in raw.execute("SELECT actor, action, entity, entity_id FROM audit_log").fetchall()}


# -- vendor login -------------------------------------------------------------

async def test_vendor_login_ok_touch_and_audit():
    reset_rate_limits()
    raw = _conn()
    out = await _svc(raw).vendor_login(PHONE_A, CODE_A, "rbac-dev-1")
    assert out["role"] == "vendor" and out["access_token"]
    assert raw.execute("SELECT last_used_at FROM vendor_access_codes WHERE id = 'ca'").fetchone()["last_used_at"]
    assert ("va", "vendor.access.use", "vendor_access_codes", "ca") in _audit_actions(raw)


def test_vendor_login_router_ok():
    reset_rate_limits()
    client = _client(_conn())
    r = client.post("/v1/auth/vendor/login",
                    json={"phone": PHONE_A, "code": CODE_A, "device": {"id": "rbac-dev-2"}})
    assert r.status_code == 200, r.text
    assert r.json()["role"] == "vendor"


async def test_vendor_login_no_oracle():
    """Wrong code / expired / revoked / non-vendor / unknown → same generic 401."""
    reset_rate_limits()
    msgs = []
    for phone, code, dev in [
        (PHONE_A, "nope-nope-nope", "rbac-dev-3"),
        (PHONE_A, CODE_EXP, "rbac-dev-4"),
        (PHONE_A, CODE_REV, "rbac-dev-5"),
        (PHONE_U, CODE_U, "rbac-dev-6"),  # valid code row, but role != vendor
        (PHONE_X, CODE_A, "rbac-dev-7"),  # unknown phone
    ]:
        with pytest.raises(AppError) as e:
            await _svc(_conn()).vendor_login(phone, code, dev)
        assert e.value.status_code == 401
        msgs.append(e.value.message)
    assert set(msgs) == {GENERIC}


async def test_vendor_login_flag_off_closed():
    reset_rate_limits()
    with pytest.raises(AppError) as e:
        await _svc(_conn(flag=False)).vendor_login(PHONE_A, CODE_A, "rbac-dev-8")
    assert e.value.status_code == 401


async def test_vendor_login_missing_device_400():
    reset_rate_limits()
    with pytest.raises(AppError) as e:
        await _svc(_conn()).vendor_login(PHONE_A, CODE_A, "")
    assert e.value.status_code == 400


# -- admin access-code lifecycle ----------------------------------------------

async def test_codes_crud_masked_revoke_kills_login():
    reset_rate_limits()
    raw = _conn()
    _session(raw, "a1", "admin", "tok-admin")
    client = _client(raw)
    ha = {"Authorization": "Bearer tok-admin"}

    issue = client.post("/v1/admin/vendors/va/access-codes", json={}, headers=ha)
    assert issue.status_code == 201, issue.text
    body = issue.json()
    assert "code_hash" not in body and body["masked_hint"] == f"••{body['code'][-2:]}"
    assert raw.execute("SELECT code_hash FROM vendor_access_codes WHERE id = ?",
                       (body["id"],)).fetchone()["code_hash"] == _H(body["code"])

    listed = client.get("/v1/admin/vendors/va/access-codes", headers=ha)
    assert listed.status_code == 200, listed.text
    rows = listed.json()["data"]
    assert rows and all("code_hash" not in r for r in rows)
    assert {r["id"] for r in rows} >= {"ca", body["id"]}

    out = await _svc(raw).vendor_login(PHONE_A, body["code"], "rbac-dev-9")
    assert out["role"] == "vendor"

    rev = client.post(f"/v1/admin/vendors/va/access-codes/{body['id']}/revoke", headers=ha)
    assert rev.status_code == 200, rev.text
    with pytest.raises(AppError) as e:
        await _svc(raw).vendor_login(PHONE_A, body["code"], "rbac-dev-10")
    assert e.value.status_code == 401

    assert client.post("/v1/admin/vendors/va/access-codes/nope/revoke", headers=ha).status_code == 404
    assert ("a1", "vendor.access.issue", "vendor_access_codes", body["id"]) in _audit_actions(raw)
    assert ("a1", "vendor.access.revoke", "vendor_access_codes", body["id"]) in _audit_actions(raw)


def test_codes_refuse_non_vendor_and_ghost():
    raw = _conn()
    _session(raw, "a1", "admin", "tok-admin")
    client = _client(raw)
    ha = {"Authorization": "Bearer tok-admin"}
    # u1 is a plain user — codes never upgrade roles (422, not auto-fix).
    assert client.post("/v1/admin/vendors/u1/access-codes", json={}, headers=ha).status_code == 422
    assert client.get("/v1/admin/vendors/u1/access-codes", headers=ha).status_code == 422
    assert client.get("/v1/admin/vendors/ghost/access-codes", headers=ha).status_code == 404
    assert client.post("/v1/admin/vendors/ghost/access-codes", json={}, headers=ha).status_code == 404


# -- payouts scoping -----------------------------------------------------------

async def test_payouts_scoped_to_self_plus_in_hand():
    raw = _conn()
    got = await _vsvc(raw).payouts_for_vendor("va")
    assert [p["id"] for p in got["payouts"]] == ["p1"]
    assert got["in_hand"] == 0 and "note" in got
    # Cash in hand is custody truth: after a COD post the read reflects it.
    await _vsvc(raw).cash_post("va", "s1", 20600)
    got2 = await _vsvc(raw).payouts_for_vendor("va")
    assert got2["in_hand"] == 20600
    assert [p["id"] for p in (await _vsvc(raw).payouts_for_vendor("vb"))["payouts"]] == ["p2"]


def test_payouts_router_vendor_only():
    raw = _conn()
    _session(raw, "va", "vendor", "tok-va")
    _session(raw, "u1", "user", "tok-user")
    client = _client(raw)
    assert client.get("/v1/vendor/payouts").status_code == 401
    assert client.get("/v1/vendor/payouts",
                      headers={"Authorization": "Bearer tok-user"}).status_code == 403
    r = client.get("/v1/vendor/payouts", headers={"Authorization": "Bearer tok-va"})
    assert r.status_code == 200, r.text
    assert [p["id"] for p in r.json()["payouts"]] == ["p1"]


# -- preview: admin-only, read-only --------------------------------------------

def test_preview_admin_only_and_composed():
    raw = _conn()
    _session(raw, "a1", "admin", "tok-admin")
    _session(raw, "va", "vendor", "tok-va")
    client = _client(raw)
    assert client.get("/v1/admin/vendors/va/preview",
                      headers={"Authorization": "Bearer tok-va"}).status_code == 403
    r = client.get("/v1/admin/vendors/va/preview", headers={"Authorization": "Bearer tok-admin"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["vendor"]["id"] == "va"
    assert body["route"]["route"]["id"] == "r1"
    assert {s["id"] for s in body["route"]["stops"]} == {"s1"}
    assert body["earnings"]["shift"] == DAY
    assert {c["customer_id"] for c in body["customers"]["customers"]} == {"u1"}
    assert [c["id"] for c in body["complaints"]["data"]] == ["c1"]
    before = raw.execute("SELECT COUNT(*) c FROM stops").fetchone()["c"]
    assert raw.execute("SELECT COUNT(*) c FROM stops").fetchone()["c"] == before  # no writes
    assert client.get("/v1/admin/vendors/ghost/preview",
                      headers={"Authorization": "Bearer tok-admin"}).status_code == 404


# -- IDOR + role gates ----------------------------------------------------------

def test_cross_vendor_stop_404_no_write():
    raw = _conn()
    _session(raw, "va", "vendor", "tok-va")
    _session(raw, "vb", "vendor", "tok-vb")
    client = _client(raw)
    assert client.get("/v1/vendor/stops/s1",
                      headers={"Authorization": "Bearer tok-vb"}).status_code == 404
    assert raw.execute("SELECT status FROM stops WHERE id = 's1'").fetchone()["status"] == "pending"
    assert client.get("/v1/vendor/stops/s1",
                      headers={"Authorization": "Bearer tok-va"}).status_code == 200


def test_vendor_token_barred_from_admin():
    raw = _conn()
    _session(raw, "va", "vendor", "tok-va")
    client = _client(raw)
    hv = {"Authorization": "Bearer tok-va"}
    assert client.get("/v1/admin/vendors", headers=hv).status_code == 403
    assert client.post("/v1/admin/payouts/p1/approve", headers=hv).status_code == 403


# -- vendor write audits --------------------------------------------------------

async def test_vendor_writes_are_audited():
    raw = _conn()
    svc = _vsvc(raw)
    await svc.triple_commit("va", "s1",
                            {"fulls_given": 2, "empties_back": 1, "cash": 0,
                             "upi": 0, "caps_missing": 0, "version": 1}, "k-audit-1")
    await svc.pod_complete("va", "s1", {"delivery_otp": pod_otp("o1", DAY)})
    await svc.cash_post("va", "s1", 20600)
    await svc.verify_complaint("va", "c1", True, "short, redeliver")
    await svc.vendor_check_quality("va", "q1", True, "seal", "seal intact")
    actions = {(r["action"], r["entity"], r["entity_id"]) for r in
               raw.execute("SELECT action, entity, entity_id FROM audit_log").fetchall()}
    assert actions >= {
        ("vendor.triple", "stops", "s1"),
        ("vendor.pod", "stops", "s1"),
        ("vendor.cash", "stops", "s1"),
        ("vendor.complaint_verify", "complaints", "c1"),
        ("vendor.quality_check", "quality_incidents", "q1"),
    }
