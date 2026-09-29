"""D2 vendor slice tests: service + router (contract §4.7 + §9.2 + §11 + §12 + §14.3).

Service tests run in-memory with 002/003/004 applied. Router tests run a
minimal app (vendor router + central handlers) with get_db overridden and the
REAL auth_deps gate (seeded sessions) — main.py mounting stays integrator-owned.
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
from app.services.vendor_service import (  # noqa: E402
    PayloadMismatchError,
    PodOtpError,
    StaleStopError,
    VendorService,
    _DUTY,
    _QUALITY,
    pod_otp,
    seed_quality,
)

M002 = (API_ROOT / "app" / "db" / "migrations" / "002_auth.sql").read_text()
M003 = (API_ROOT / "app" / "db" / "migrations" / "003_addresses.sql").read_text()
M004 = (API_ROOT / "app" / "db" / "migrations" / "004_orders.sql").read_text()

DAY = _dt.datetime.now(_dt.timezone.utc).date().isoformat()
FUTURE = (_dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(hours=1)).isoformat()


def _conn():
    c = get_connection(":memory:")
    c.executescript(M002 + M003 + M004)
    c.execute(
        "INSERT INTO users(id, phone, role, created_at) VALUES "
        "('v1', '+911111111111', 'vendor', ?), ('v2', '+913333333333', 'vendor', ?),"
        " ('u1', '+912222222222', 'user', ?), ('u9', '+914444444444', 'user', ?)",
        (_dt.datetime.now(_dt.timezone.utc).isoformat(),) * 4,
    )
    c.execute(
        "INSERT INTO addresses(id, user_id, type, lat, lng, pincode, created_at)"
        " VALUES ('a1', 'u1', 'home', 12.9716, 77.5946, '560001', ?)",
        (_dt.datetime.now(_dt.timezone.utc).isoformat(),),
    )
    for oid, state in (("o1", "dispatched"), ("o2", "placed"), ("o9", "dispatched")):
        c.execute(
            "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
            " total, payment_mode, state, window_start, idempotency_key, created_at)"
            " VALUES (?, 'u1', 'a1', '[]', 2, 1, 5600, 15000, 20600, 'cod', ?, '2026-10-01T08:00Z', ?, ?)",
            (oid, state, f"seed:{oid}", _dt.datetime.now(_dt.timezone.utc).isoformat()),
        )
    c.execute(
        "INSERT INTO routes(id, date, vendor_id, zone, status) VALUES ('r1', ?, 'v1', 'z1', 'open')",
        (DAY,),
    )
    stops = [
        ("s1", "o1", 0, 2, 1, "pending"),
        ("s2", "o2", 1, 1, 0, "pending"),
        ("s3", "o2", 2, 1, 0, "pending"),
        ("s4", None, 3, 0, 2, "skipped"),
    ]
    for sid, oid, seq, fe, ee, st in stops:
        c.execute(
            "INSERT INTO stops(id, route_id, order_id, customer_id, seq, fulls_exp,"
            " empties_exp, version, status) VALUES (?, 'r1', ?, 'u1', ?, ?, ?, 1, ?)",
            (sid, oid, seq, fe, ee, st),
        )
    c.execute("UPDATE stops SET version = 2 WHERE id = 's3'")  # reassigned under the vendor
    c.execute(
        "INSERT INTO complaints(id, order_id, user_id, reason_code, text, status, created_at)"
        " VALUES ('c1', 'o1', 'u1', 'short_delivery', 'one jar short', 'open', ?),"
        " ('c9', 'o9', 'u1', 'late_delivery', 'late', 'open', ?)",
        (_dt.datetime.now(_dt.timezone.utc).isoformat(),) * 2,
    )
    c.commit()
    return c


def _svc(c) -> VendorService:
    return VendorService(c)


@pytest.fixture(autouse=True)
def _clean_mem():
    _DUTY.clear()
    _QUALITY.clear()
    yield
    _DUTY.clear()
    _QUALITY.clear()


def _triple(**over) -> dict:
    base = {"fulls_given": 2, "empties_back": 1, "cash": 100, "upi": 0,
            "caps_missing": 0, "version": 1}
    base.update(over)
    return base


# -- duty + route -----------------------------------------------------------

def test_duty_on_off_in_memory():
    c = _conn()
    assert _svc(c).duty("v1", True) == {"vendor_id": "v1", "duty_on": True,
                                        "since": _DUTY["v1"]["since"]}
    assert _svc(c).is_on_duty("v1") is True
    assert _svc(c).duty("v1", False)["duty_on"] is False


def test_today_route_loading_and_skip():
    out = _svc(_conn()).today_route("v1", DAY)
    assert out["route"]["id"] == "r1" and len(out["stops"]) == 4
    assert out["loading"] == {"take_fulls": 4, "expect_empties": 3}
    assert [s["id"] for s in out["skip"]] == ["s4"]
    assert _svc(_conn()).today_route("v1", "2000-01-01")["route"] is None


def test_stop_idor_no_oracle():
    with pytest.raises(AppError) as e:
        _svc(_conn()).get_stop("v2", "s1")  # other vendor's stop == not-found
    assert e.value.code == "NOT_FOUND" and e.value.status_code == 404


# -- triple -------------------------------------------------------------------

def test_triple_ok_ledger_math():
    c = _conn()
    out = _svc(c).triple_commit("v1", "s1", _triple(), "k1")
    assert out["status"] == "done" and out["triple"]["cash"] == 100
    from app.repositories.ledger_repo import LedgerRepo

    assert LedgerRepo(c).get("u1")["held"] == 1  # 2 given − 1 back
    assert c.execute("SELECT COUNT(*) c FROM ledger_events").fetchone()["c"] == 1


def test_triple_stale_version_409():
    with pytest.raises(StaleStopError) as e:
        _svc(_conn()).triple_commit("v1", "s3", _triple(version=1))
    assert e.value.code == "STALE_STOP" and e.value.status_code == 409


def test_triple_tendered_change_invariant_400():
    with pytest.raises(AppError) as e:
        _svc(_conn()).triple_commit("v1", "s1", _triple(tendered=100, change_given=0, cash=50))
    assert e.value.code == "VALIDATION" and e.value.status_code == 400
    assert _conn() is not None  # fresh conn: nothing written anywhere (see ledger test below)


def test_triple_never_negative_422_no_partial_write():
    c = _conn()
    with pytest.raises(AppError) as e:
        _svc(c).triple_commit("v1", "s1", _triple(fulls_given=0, empties_back=1, cash=0))
    assert e.value.code == "HOLD_NEGATIVE" and e.value.status_code == 422
    assert c.execute("SELECT status FROM stops WHERE id = 's1'").fetchone()["status"] == "pending"
    assert c.execute("SELECT COUNT(*) c FROM ledger_events").fetchone()["c"] == 0


def test_triple_idempotent_replay_same_key_once():
    c = _conn()
    s = _svc(c)
    o1 = s.triple_commit("v1", "s1", _triple(), "k1")
    o2 = s.triple_commit("v1", "s1", _triple(), "k1")  # same key+payload → stored outcome
    assert o1 == o2
    from app.repositories.ledger_repo import LedgerRepo

    assert LedgerRepo(c).get("u1")["held"] == 1  # applied exactly once
    with pytest.raises(PayloadMismatchError):
        s.triple_commit("v1", "s1", _triple(cash=5), "k1")  # same key, changed body


# -- PoD ------------------------------------------------------------------------

def test_pod_happy_delivers():
    c = _conn()
    s = _svc(c)
    s.triple_commit("v1", "s1", _triple())
    out = s.pod_complete("v1", "s1", {"delivery_otp": pod_otp("o1", DAY),
                                      "empties_count": 1, "cash": 100, "seal_ok": True})
    assert out["status"] == "done" and out["triple"]["pod"]["seal_ok"] is True
    assert c.execute("SELECT state FROM orders WHERE id = 'o1'").fetchone()["state"] == "delivered"


def test_pod_wrong_otp_401():
    with pytest.raises(PodOtpError) as e:
        _svc(_conn()).pod_complete("v1", "s1", {"delivery_otp": "000000"})
    assert e.value.code == "UNAUTH" and e.value.status_code == 401


def test_pod_gps_drift_flagged_not_blocked():
    c = _conn()
    out = _svc(c).pod_complete("v1", "s1", {"delivery_otp": pod_otp("o1", DAY),
                                            "lat": 13.5, "lng": 78.5})  # ~100km away
    assert out["status"] == "done"  # completes despite drift
    assert out["triple"]["pod"]["gps"]["flagged"] is True
    assert c.execute("SELECT state FROM orders WHERE id = 'o1'").fetchone()["state"] == "delivered"


# -- sync + earnings --------------------------------------------------------------

def test_sync_batch_mixed_then_replay():
    c = _conn()
    s = _svc(c)
    out = s.sync_batch("v1", [{"stop_id": "s2", **_triple(fulls_given=1, empties_back=0)},
                              {"stop_id": "s3", **_triple(version=1)}])
    assert out["applied"] == ["s2"] and out["replayed"] == []
    assert out["rejected"][0]["stop_id"] == "s3" and out["rejected"][0]["code"] == "STALE_STOP"
    from app.repositories.ledger_repo import LedgerRepo

    held = LedgerRepo(c).get("u1")["held"]
    again = s.sync_batch("v1", [{"stop_id": "s2", **_triple(fulls_given=1, empties_back=0)},
                                {"stop_id": "s3", **_triple(version=1)}])
    assert again["replayed"] == ["s2"] and len(again["rejected"]) == 1
    assert LedgerRepo(c).get("u1")["held"] == held  # replay wrote nothing


def test_earnings_totals_and_flagged_hold():
    c = _conn()
    s = _svc(c)
    s.triple_commit("v1", "s1", _triple(cash=100, upi=50))
    s.pod_complete("v1", "s1", {"delivery_otp": pod_otp("o1", DAY), "lat": 13.5, "lng": 78.5})
    s.triple_commit("v1", "s2", _triple(fulls_given=1, empties_back=0, cash=0, upi=200))
    out = s.earnings("v1", DAY)
    assert (out["cash_total"], out["upi_total"], out["stops_done"]) == (100, 250, 2)
    assert out["flagged_stops"] == 1 and out["flagged_hold"] == 150
    assert "held out of payouts" in out["note"]


# -- complaint + quality (§14.3) ------------------------------------------------------

def test_complaint_verify_agree_resolves():
    out = _svc(_conn()).verify_complaint("v1", "c1", True, "short jar redelivered")
    assert out["status"] == "resolved" and out["vendor_agree"] == 1


def test_complaint_verify_disagree_freezes_for_admin():
    out = _svc(_conn()).verify_complaint("v1", "c1", False, "count was correct at door")
    assert out["status"] == "under_review" and out["vendor_agree"] == 0
    with pytest.raises(AppError) as e:  # order not on this vendor's route → 404, no oracle
        _svc(_conn()).verify_complaint("v1", "c9", True, "x")
    assert e.value.code == "NOT_FOUND"


def test_quality_vendor_check_paths():
    c = _conn()
    seed_quality({"id": "q1", "order_id": "o1", "reason_code": "water_quality"})
    agree = _svc(c).vendor_check_quality("v1", "q1", True, "seal", "seal intact, smell off")
    assert agree["status"] == "confirmed" and agree["vendor_agree"] == 1
    seed_quality({"id": "q2", "order_id": "o1", "reason_code": "water_quality"})
    dis = _svc(c).vendor_check_quality("v1", "q2", False, "visual", "looks fine")
    assert dis["status"] == "disputed"  # frozen → 48h admin triage
    with pytest.raises(AppError):
        _svc(c).vendor_check_quality("v1", "missing", True, "", "")


# -- router -------------------------------------------------------------------------

def _client(c):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.deps import get_db
    from app.api.v1.vendor import router
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    app.dependency_overrides[get_db] = lambda: c
    return TestClient(app)


def _session(c, uid, role, token):
    c.execute(
        "INSERT INTO sessions(id, user_id, token_hash, refresh_hash, role, device_fp,"
        " family_id, expires_at, created_at) VALUES (?, ?, ?, ?, ?, 'd', 'f', ?, ?)",
        (f"ses-{uid}", uid, hashlib.sha256(token.encode()).hexdigest(),
         hashlib.sha256(f"r:{token}".encode()).hexdigest(), role, FUTURE, FUTURE),
    )
    c.commit()


def test_router_vendor_gate_and_duty_roundtrip():
    c = _conn()
    _session(c, "v1", "vendor", "tok-vendor")
    _session(c, "u1", "user", "tok-user")
    client = _client(c)
    assert client.get("/v1/vendor/routes/today").status_code == 401  # no token
    assert client.get("/v1/vendor/routes/today",
                      headers={"Authorization": "Bearer tok-user"}).status_code == 403  # wrong role
    r = client.post("/v1/vendor/duty", json={"on": True},
                    headers={"Authorization": "Bearer tok-vendor"})
    assert r.status_code == 200 and r.json() == {"vendor_id": "v1", "duty_on": True,
                                                "since": _DUTY["v1"]["since"]}
    assert client.get("/v1/vendor/routes/today",
                      headers={"Authorization": "Bearer tok-vendor"}).json()["route"]["id"] == "r1"


def test_router_triple_pod_me_validation():
    c = _conn()
    _session(c, "v1", "vendor", "tok-vendor")
    client = _client(c)
    h = {"Authorization": "Bearer tok-vendor"}
    assert client.post("/v1/vendor/stops/s1/triple", json=_triple(), headers=h).status_code == 200
    bad = dict(_triple(), tendered=100, change_given=0, cash=50)
    assert client.post("/v1/vendor/stops/s1/triple", json=bad, headers=h).status_code == 400
    assert client.post("/v1/vendor/stops/s1/pod", json={"delivery_otp": "000000"},
                       headers=h).status_code == 401
    ok = client.post("/v1/vendor/stops/s1/pod",
                     json={"delivery_otp": pod_otp("o1", DAY), "seal_ok": True}, headers=h)
    assert ok.status_code == 200 and ok.json()["triple"]["pod"]["seal_ok"] is True
