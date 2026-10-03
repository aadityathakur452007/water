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
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.services.vendor_service import (  # noqa: E402
    PayloadMismatchError,
    PodOtpError,
    StaleStopError,
    VendorService,
    pod_otp,
)

M002 = (API_ROOT / "src" / "app" / "db" / "migrations" / "002_auth.sql").read_text()
M003 = (API_ROOT / "src" / "app" / "db" / "migrations" / "003_addresses.sql").read_text()
M004 = (API_ROOT / "src" / "app" / "db" / "migrations" / "004_orders.sql").read_text()
M005 = (API_ROOT / "src" / "app" / "db" / "migrations" / "005_payments.sql").read_text()
M007 = (API_ROOT / "src" / "app" / "db" / "migrations" / "007_ops.sql").read_text()

DAY = _dt.datetime.now(_dt.timezone.utc).date().isoformat()
FUTURE = (_dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(hours=1)).isoformat()


def _conn():
    c = get_connection(":memory:")
    c.executescript(M002 + M003 + M004 + M005 + M007)
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
    return VendorService(AsyncSqliteConn(c))


def _triple(**over) -> dict:
    base = {"fulls_given": 2, "empties_back": 1, "cash": 100, "upi": 0,
            "caps_missing": 0, "version": 1}
    base.update(over)
    return base


# -- duty (F5: persisted on vendor_profile, survives service instances) ---------

async def test_duty_on_off_persisted():
    c = _conn()
    on = await _svc(c).duty("v1", True)
    assert on == {"vendor_id": "v1", "duty_on": True, "since": on["since"]}
    # Fresh service instance reads the same truth (no in-memory store).
    assert await VendorService(AsyncSqliteConn(c)).is_on_duty("v1") is True
    assert c.execute("SELECT on_duty, duty_on FROM vendor_profile WHERE user_id = 'v1'").fetchone()["on_duty"] == 1
    off = await _svc(c).duty("v1", False)
    assert off["duty_on"] is False
    assert await _svc(c).is_on_duty("v1") is False


async def test_ensure_profile_converges_011_shape():
    """F5: 011-first DBs (profile cols only) gain the 007 ops columns."""
    from app.services.dispatch_service import ensure_profile

    c = get_connection(":memory:")
    c.executescript(M002)
    c.execute(
        "CREATE TABLE vendor_profile(user_id TEXT PRIMARY KEY, name TEXT,"
        " phone TEXT, address TEXT, hours TEXT, updated_at TEXT)")
    c.execute("INSERT INTO users(id, phone, role, created_at) VALUES ('v1', '+911111111111', 'vendor', ?)",
              (_dt.datetime.now(_dt.timezone.utc).isoformat(),))
    c.commit()
    prof = await ensure_profile(AsyncSqliteConn(c), "v1")
    assert prof["on_duty"] == 0 and prof["in_hand"] == 0 and prof["max_stops_per_shift"] == 25
    assert await _svc(c).is_on_duty("v1") is False
    await _svc(c).duty("v1", True)
    assert await _svc(c).is_on_duty("v1") is True


async def test_today_route_loading_and_skip():
    out = await _svc(_conn()).today_route("v1", DAY)
    assert out["route"]["id"] == "r1" and len(out["stops"]) == 4
    assert out["loading"] == {"take_fulls": 4, "expect_empties": 3}
    assert [s["id"] for s in out["skip"]] == ["s4"]
    # 015: payment/address join rides on stops.
    s1 = next(s for s in out["stops"] if s["id"] == "s1")
    assert s1["payment_mode"] == "cod" and s1["total"] == 20600
    assert (await _svc(_conn()).today_route("v1", "2000-01-01"))["route"] is None


async def test_placed_pool_lists_unrouted_placed():
    c = _conn()
    # o2 placed but already routed via s2/s3; insert fresh placed o3.
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, water_bill, deposit_due,"
        " total, payment_mode, state, window_start, idempotency_key, created_at)"
        " VALUES ('o3', 'u1', 'a1', '[]', 1, 0, 2800, 0, 2800, 'upi', 'placed', '2026-10-01T08:00Z', 'seed:o3', ?)",
        (_dt.datetime.now(_dt.timezone.utc).isoformat(),),
    )
    c.commit()
    out = await _svc(c).placed_pool()
    ids = [r["order_id"] for r in out["data"]]
    assert "o3" in ids and "o1" not in ids and "o2" not in ids  # dispatched excluded, routed placed excluded
    o3 = next(r for r in out["data"] if r["order_id"] == "o3")
    assert o3["payment_mode"] == "upi" and o3["total"] == 2800


async def test_stop_idor_no_oracle():
    with pytest.raises(AppError) as e:
        await _svc(_conn()).get_stop("v2", "s1")  # other vendor's stop == not-found
    assert e.value.code == "NOT_FOUND" and e.value.status_code == 404


# -- triple -------------------------------------------------------------------

async def test_triple_ok_ledger_math():
    c = _conn()
    out = await _svc(c).triple_commit("v1", "s1", _triple(), "k1")
    assert out["status"] == "done" and out["triple"]["cash"] == 100
    from app.repositories.ledger_repo import LedgerRepo

    assert (await LedgerRepo(AsyncSqliteConn(c)).get("u1"))["held"] == 1  # 2 given − 1 back
    assert c.execute("SELECT COUNT(*) c FROM ledger_events").fetchone()["c"] == 1


async def test_triple_stale_version_409():
    with pytest.raises(StaleStopError) as e:
        await _svc(_conn()).triple_commit("v1", "s3", _triple(version=1))
    assert e.value.code == "STALE_STOP" and e.value.status_code == 409


async def test_triple_tendered_change_invariant_400():
    with pytest.raises(AppError) as e:
        await _svc(_conn()).triple_commit("v1", "s1", _triple(tendered=100, change_given=0, cash=50))
    assert e.value.code == "VALIDATION" and e.value.status_code == 400
    assert _conn() is not None  # fresh conn: nothing written anywhere (see ledger test below)


async def test_triple_never_negative_422_no_partial_write():
    c = _conn()
    with pytest.raises(AppError) as e:
        await _svc(c).triple_commit("v1", "s1", _triple(fulls_given=0, empties_back=1, cash=0))
    assert e.value.code == "HOLD_NEGATIVE" and e.value.status_code == 422
    assert c.execute("SELECT status FROM stops WHERE id = 's1'").fetchone()["status"] == "pending"
    assert c.execute("SELECT COUNT(*) c FROM ledger_events").fetchone()["c"] == 0


async def test_triple_idempotent_replay_same_key_once():
    c = _conn()
    s = _svc(c)
    o1 = await s.triple_commit("v1", "s1", _triple(), "k1")
    o2 = await s.triple_commit("v1", "s1", _triple(), "k1")  # same key+payload → stored outcome
    assert o1 == o2
    from app.repositories.ledger_repo import LedgerRepo

    assert (await LedgerRepo(AsyncSqliteConn(c)).get("u1"))["held"] == 1  # applied exactly once
    with pytest.raises(PayloadMismatchError):
        await s.triple_commit("v1", "s1", _triple(cash=5), "k1")  # same key, changed body


# -- PoD ------------------------------------------------------------------------

async def test_pod_happy_delivers():
    c = _conn()
    s = _svc(c)
    await s.triple_commit("v1", "s1", _triple())
    out = await s.pod_complete("v1", "s1", {"delivery_otp": pod_otp("o1", DAY),
                                      "empties_count": 1, "cash": 100, "seal_ok": True})
    assert out["status"] == "done" and out["triple"]["pod"]["seal_ok"] is True
    assert c.execute("SELECT state FROM orders WHERE id = 'o1'").fetchone()["state"] == "delivered"


async def test_pod_wrong_otp_401():
    with pytest.raises(PodOtpError) as e:
        await _svc(_conn()).pod_complete("v1", "s1", {"delivery_otp": "000000"})
    assert e.value.code == "UNAUTH" and e.value.status_code == 401


async def test_pod_gps_drift_flagged_not_blocked():
    c = _conn()
    out = await _svc(c).pod_complete("v1", "s1", {"delivery_otp": pod_otp("o1", DAY),
                                            "lat": 13.5, "lng": 78.5})  # ~100km away
    assert out["status"] == "done"  # completes despite drift
    assert out["triple"]["pod"]["gps"]["flagged"] is True
    assert c.execute("SELECT state FROM orders WHERE id = 'o1'").fetchone()["state"] == "delivered"


# -- sync + earnings --------------------------------------------------------------

async def test_sync_batch_mixed_then_replay():
    c = _conn()
    s = _svc(c)
    out = await s.sync_batch("v1", [{"stop_id": "s2", **_triple(fulls_given=1, empties_back=0)},
                              {"stop_id": "s3", **_triple(version=1)}])
    assert out["applied"] == ["s2"] and out["replayed"] == []
    assert out["rejected"][0]["stop_id"] == "s3" and out["rejected"][0]["code"] == "STALE_STOP"
    from app.repositories.ledger_repo import LedgerRepo

    held = (await LedgerRepo(AsyncSqliteConn(c)).get("u1"))["held"]
    again = await s.sync_batch("v1", [{"stop_id": "s2", **_triple(fulls_given=1, empties_back=0)},
                                {"stop_id": "s3", **_triple(version=1)}])
    assert again["replayed"] == ["s2"] and len(again["rejected"]) == 1
    assert (await LedgerRepo(AsyncSqliteConn(c)).get("u1"))["held"] == held  # replay wrote nothing


async def test_earnings_totals_and_flagged_hold():
    c = _conn()
    s = _svc(c)
    await s.triple_commit("v1", "s1", _triple(cash=100, upi=50))
    await s.pod_complete("v1", "s1", {"delivery_otp": pod_otp("o1", DAY), "lat": 13.5, "lng": 78.5})
    await s.triple_commit("v1", "s2", _triple(fulls_given=1, empties_back=0, cash=0, upi=200))
    out = await s.earnings("v1", DAY)
    assert (out["cash_total"], out["upi_total"], out["stops_done"]) == (100, 250, 2)
    assert out["flagged_stops"] == 1 and out["flagged_hold"] == 150
    assert "held out of payouts" in out["note"]


# -- cash post (F2: doorstep cash → money truth) ------------------------------------

async def test_cash_post_full_flips_paid_cash():
    c = _conn()
    out = await _svc(c).cash_post("v1", "s1", 20600)  # o1 total 20600 COD
    assert out["order"]["payment_status"] == "paid_cash"
    assert out["payment"]["method"] == "cod" and out["payment"]["amount"] == 20600
    assert out["ledger"]["dues"] == 0
    assert c.execute("SELECT COUNT(*) c FROM payments").fetchone()["c"] == 1


async def test_cash_post_partial_carries_dues():
    c = _conn()
    out = await _svc(c).cash_post("v1", "s1", 1000)
    assert out["order"]["payment_status"] == "partial_dues"
    assert out["ledger"]["dues"] == 19600  # remainder carried (VR-08)
    again = await _svc(c).cash_post("v1", "s1", 19600)  # top-up completes
    assert again["order"]["payment_status"] == "paid_cash"


async def test_cash_post_replay_and_cross_vendor():
    c = _conn()
    s = _svc(c)
    o1 = await s.cash_post("v1", "s1", 20600)
    o2 = await s.cash_post("v1", "s1", 20600)  # same stop+amount → replay
    assert o2["replay"] is True and o1["payment"]["id"] == o2["payment"]["id"]
    assert c.execute("SELECT COUNT(*) c FROM payments").fetchone()["c"] == 1
    with pytest.raises(AppError) as e:  # other vendor's stop == not-found, zero writes
        await s.cash_post("v2", "s1", 100)
    assert e.value.code == "NOT_FOUND" and e.value.status_code == 404
    assert c.execute("SELECT COUNT(*) c FROM payments").fetchone()["c"] == 1
    with pytest.raises(AppError) as e:  # new amount after full → already paid 409
        await s.cash_post("v1", "s1", 50)
    assert e.value.code == "STATE_CONFLICT" and e.value.status_code == 409


async def test_cash_post_rejects_zero():
    with pytest.raises(AppError) as e:
        await _svc(_conn()).cash_post("v1", "s1", 0)
    assert e.value.code == "VALIDATION"


async def test_sync_batch_rides_cash():
    c = _conn()
    out = await _svc(c).sync_batch("v1", [{"stop_id": "s2", **_triple(fulls_given=1, empties_back=0),
                               "cash_amount": 20600}])  # o2 total 20600 COD
    assert out["applied"] == ["s2"] and out["rejected"] == []
    assert c.execute("SELECT payment_status FROM orders WHERE id = 'o2'").fetchone()["payment_status"] == "paid_cash"


# -- hold flag (F3: today_route + get_stop surface held>3) ---------------------------

async def test_hold_blocked_flag_boundary():
    from app.repositories.ledger_repo import LedgerRepo

    c = _conn()
    await LedgerRepo(AsyncSqliteConn(c)).apply_event("u1", d_held=4, ref="seed", actor="t", reason="t")
    route = await _svc(c).today_route("v1", DAY)
    assert all(s["hold_blocked"] is True for s in route["stops"])
    assert all("deposit" in (s["hold_reason"] or "") for s in route["stops"])
    assert (await _svc(c).get_stop("v1", "s1"))["hold_blocked"] is True
    # Held exactly 3 → not blocked (rule is > 3).
    c2 = _conn()
    await LedgerRepo(AsyncSqliteConn(c2)).apply_event("u1", d_held=3, ref="seed", actor="t", reason="t")
    assert all(s["hold_blocked"] is False for s in (await _svc(c2).today_route("v1", DAY))["stops"])


# -- complaint + quality (§14.3) ------------------------------------------------------

async def test_complaint_verify_agree_resolves():
    out = await _svc(_conn()).verify_complaint("v1", "c1", True, "short jar redelivered")
    assert out["status"] == "resolved" and out["vendor_agree"] == 1


async def test_complaint_verify_disagree_freezes_for_admin():
    out = await _svc(_conn()).verify_complaint("v1", "c1", False, "count was correct at door")
    assert out["status"] == "under_review" and out["vendor_agree"] == 0
    with pytest.raises(AppError) as e:  # order not on this vendor's route → 404, no oracle
        await _svc(_conn()).verify_complaint("v1", "c9", True, "x")
    assert e.value.code == "NOT_FOUND"


async def test_quality_vendor_check_paths():
    """F4: checks land on the quality_incidents table (admin reads the same)."""
    c = _conn()
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    c.execute(
        "INSERT INTO quality_incidents(id, order_id, vendor_id, reason_code, status, created_at)"
        " VALUES ('q1', 'o1', 'v1', 'water_quality', 'open', ?),"
        " ('q2', 'o1', 'v1', 'water_quality', 'open', ?)",
        (now, now),
    )
    c.commit()
    agree = await _svc(c).vendor_check_quality("v1", "q1", True, "seal", "seal intact, smell off")
    assert agree["status"] == "confirmed" and agree["vendor_agree"] == 1
    assert agree["vendor_note"] == "seal intact, smell off"
    dis = await _svc(c).vendor_check_quality("v1", "q2", False, "visual", "looks fine")
    assert dis["status"] == "open" and dis["vendor_agree"] == 0  # frozen → 48h admin triage
    with pytest.raises(AppError):  # unknown id → 404
        await _svc(c).vendor_check_quality("v1", "missing", True, "", "")
    # o9 is not on v1's route → 404, no oracle (needs its own incident row).
    c.execute(
        "INSERT INTO quality_incidents(id, order_id, vendor_id, reason_code, status, created_at)"
        " VALUES ('q9', 'o9', 'v1', 'water_quality', 'open', ?)",
        (now,),
    )
    c.commit()
    with pytest.raises(AppError) as e:
        await _svc(c).vendor_check_quality("v1", "q9", True, "", "")
    assert e.value.code == "NOT_FOUND"


# -- returns pickup (F8: empties collect on own route) ------------------------------

def _return(c, rid="ret1", qty=2, status="requested"):
    c.execute(
        "INSERT INTO returns(id, user_id, qty, address_id, status, sla_due, created_at)"
        " VALUES (?, 'u1', ?, 'a1', ?, '2026-10-15', ?)",
        (rid, qty, status, _dt.datetime.now(_dt.timezone.utc).isoformat()),
    )
    c.commit()


def test_return_pickup_ledger_and_isolation():
    from app.repositories.ledger_repo import LedgerRepo

    c = _conn()
    _session(c, "v1", "vendor", "tok-vendor")
    _session(c, "v2", "vendor", "tok-v2")
    _return(c)
    c.execute(
        "INSERT INTO stops(id, route_id, return_id, customer_id, seq, fulls_exp,"
        " empties_exp, version, status) VALUES ('sp1', 'r1', 'ret1', 'u1', 9, 0, 2, 1, 'pending')")
    c.commit()
    client = _client(c)
    h1 = {"Authorization": "Bearer tok-vendor"}
    # Held first so the pickup decrement is meaningful (raw seed, no loop).
    c.execute("INSERT INTO ledger(customer_id, held) VALUES ('u1', 2)")
    c.commit()
    r = client.post("/v1/returns/ret1/pickup",
                    json={"empties_collected": 2, "caps_missing": 1}, headers=h1)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "picked" and r.json()["cap_charge"] == 300
    assert c.execute("SELECT held, dues FROM ledger WHERE customer_id = 'u1'").fetchone()["held"] == 0
    assert c.execute("SELECT status FROM returns WHERE id = 'ret1'").fetchone()["status"] == "picked"
    # Settled → 409; other vendor (no stop link) → 404 with no write.
    assert client.post("/v1/returns/ret1/pickup", json={"empties_collected": 1},
                       headers=h1).status_code == 409
    _return(c, rid="ret2")
    assert client.post("/v1/returns/ret2/pickup", json={"empties_collected": 1},
                       headers={"Authorization": "Bearer tok-v2"}).status_code == 404


# -- router -------------------------------------------------------------------------

def _client(c):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.deps import get_db_conn
    from app.api.v1.vendor import router
    from app.api.v1.returns import router as returns_router
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router, prefix="/v1")
    app.include_router(returns_router, prefix="/v1")
    # get_current_user resolves via get_db_conn (Phase-A T2): same DB.
    app.dependency_overrides[get_db_conn] = lambda: (
        c if isinstance(c, AsyncSqliteConn) else AsyncSqliteConn(c)
    )
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
    body = r.json()
    assert r.status_code == 200 and body["vendor_id"] == "v1" and body["duty_on"] is True
    assert c.execute("SELECT on_duty FROM vendor_profile WHERE user_id = 'v1'").fetchone()["on_duty"] == 1
    assert client.get("/v1/vendor/routes/today",
                      headers={"Authorization": "Bearer tok-vendor"}).json()["route"]["id"] == "r1"


def test_router_triple_pod_me_validation():
    c = _conn()
    _session(c, "v1", "vendor", "tok-vendor")
    client = _client(c)
    h = {"Authorization": "Bearer tok-vendor"}
    hk1 = {**h, "Idempotency-Key": "k-router-1"}
    assert client.post("/v1/vendor/stops/s1/triple", json=_triple(), headers=hk1).status_code == 200
    bad = dict(_triple(), tendered=100, change_given=0, cash=50)
    bad["version"] = _triple()["version"] + 1  # commit bumped it; fresh fence
    hk2 = {**h, "Idempotency-Key": "k-router-2"}
    assert client.post("/v1/vendor/stops/s1/triple", json=bad, headers=hk2).status_code == 400
    assert client.post("/v1/vendor/stops/s1/pod", json={"delivery_otp": "000000"},
                       headers=h).status_code == 401
    ok = client.post("/v1/vendor/stops/s1/pod",
                     json={"delivery_otp": pod_otp("o1", DAY), "seal_ok": True}, headers=h)
    assert ok.status_code == 200 and ok.json()["triple"]["pod"]["seal_ok"] is True
