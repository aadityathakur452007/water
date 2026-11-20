"""Regression tests for VULN-002 — rider sign-in must not be phone-only.

A rider's mobile number is easy to learn (it is printed on the delivery sheet
and shared with customers), so possessing it must never open the delivery
route and its cash list. The vendor mints a code at onboarding; only its hash
is stored, with ``expected_role='rider'``.
"""

import pytest

from app.services.auth_service import reset_rate_limits
from tests.test_rider_dispatch import NOW_ISO, POD_EXPIRY, _client, _hash, _seed_db

PHONE = "9876500003"
CODE = "135790"


@pytest.fixture(autouse=True)
# The per-phone limiter is process-wide (5/15 min); these tests are about the
# code requirement, not throttling, and OTP-01 covers the lockout itself.
def _fresh_limits():
    reset_rate_limits()
    yield


def _login(client, **overrides):
    body = {"phone": PHONE, "name": "Rider Shyam", "code": CODE,
            "device": {"id": "device-1"}}
    body.update(overrides)
    return client.post("/v1/auth/rider/login", json=body)


def test_phone_alone_is_not_acceptable():
    client = _client(_seed_db())
    res = client.post("/v1/auth/rider/login",
                      json={"phone": PHONE, "device": {"id": "device-1"}})
    assert res.status_code in (400, 422)  # code is a required field


def test_wrong_code_is_rejected_generically():
    client = _client(_seed_db())
    res = _login(client, code="000000")
    assert res.status_code == 401
    assert "invalid credentials" in res.json()["error"]["message"].lower()


def test_valid_code_signs_the_rider_in():
    client = _client(_seed_db())
    res = _login(client)
    assert res.status_code == 200
    body = res.json()
    assert body["role"] == "rider"
    assert body["user_id"] == "r1"
    assert body["access_token"]


def test_code_minted_for_another_role_cannot_open_the_rider_door():
    conn = _seed_db()
    conn.execute(
        "INSERT INTO access_codes (id, user_id, code_hash, masked_hint, expected_role,"
        " expires_at, revoked_at, last_used_at, created_by, created_at)"
        " VALUES ('ac-vendor-role', 'r1', ?, '••11', 'vendor', ?, NULL, NULL, 'v1', ?)",
        (_hash("111111"), POD_EXPIRY, NOW_ISO),
    )
    conn.commit()
    res = _login(_client(conn), code="111111")
    assert res.status_code == 401


def test_revoked_code_is_rejected():
    conn = _seed_db()
    conn.execute("UPDATE access_codes SET revoked_at = ? WHERE id = 'ac-r1'", (NOW_ISO,))
    conn.commit()
    assert _login(_client(conn)).status_code == 401


def test_expired_code_is_rejected():
    conn = _seed_db()
    conn.execute("UPDATE access_codes SET expires_at = ? WHERE id = 'ac-r1'", (NOW_ISO,))
    conn.commit()
    assert _login(_client(conn)).status_code == 401


def test_suspended_rider_with_a_valid_code_is_rejected():
    conn = _seed_db()
    conn.execute("UPDATE users SET suspended = 1 WHERE id = 'r1'")
    conn.commit()
    assert _login(_client(conn)).status_code == 401


def _reissue(client, rider_id, token="token-vendor"):
    return client.post(f"/v1/vendor/riders/{rider_id}/code",
                       headers={"Authorization": f"Bearer {token}"})


def test_reissue_rotates_the_code_and_the_old_one_stops_working():
    client = _client(_seed_db())
    assert _login(client).status_code == 200

    res = _reissue(client, "r1")
    assert res.status_code == 200
    fresh = res.json()["access_code"]
    assert fresh != CODE and res.json()["access_code_expires_at"]

    assert _login(client, code=CODE, device={"id": "device-old"}).status_code == 401
    assert _login(client, code=fresh, device={"id": "device-new"}).status_code == 200


def test_reissue_is_scoped_to_the_callers_own_riders():
    conn = _seed_db()
    conn.execute("UPDATE users SET assigned_vendor_id = 'vend-b' WHERE id = 'r1'")
    conn.commit()
    assert _reissue(_client(conn), "r1").status_code == 404
    assert _reissue(_client(conn), "no-such-rider").status_code == 404


def test_a_rider_cannot_issue_codes():
    client = _client(_seed_db())
    assert _reissue(client, "r1", token="token-rider").status_code == 403


def test_re_onboarding_rotates_the_code_too():
    conn = _seed_db()
    client = _client(conn)
    res = client.post("/v1/vendor/riders",
                      headers={"Authorization": "Bearer token-vendor"},
                      json={"name": "Rider Shyam", "phone": PHONE})
    assert res.status_code == 201
    assert _login(client, code=CODE, device={"id": "device-old"}).status_code == 401


def test_vendor_onboarding_returns_a_code_that_actually_signs_the_rider_in():
    conn = _seed_db()
    client = _client(conn)
    created = client.post(
        "/v1/vendor/riders",
        headers={"Authorization": "Bearer token-vendor"},
        json={"name": "Kailash Delivery", "phone": "9876543210"},
    )
    assert created.status_code == 201
    rider = created.json()
    assert len(rider["access_code"]) == 6
    assert rider["access_code_expires_at"]

    res = client.post(
        "/v1/auth/rider/login",
        json={"phone": "9876543210", "name": "Kailash Delivery",
              "code": rider["access_code"], "device": {"id": "device-kailash"}},
    )
    assert res.status_code == 200
    assert res.json()["user_id"] == rider["id"]
