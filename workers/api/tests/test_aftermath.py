"""D3 aftermath tests: subs pause/resume/skip/process_due, returns SLA,
complaint windows + photo reject, ratings once + shortcut, device scoping,
005 migration idempotency, FCM adapter.

Service tests run in-memory with 002+003+004+005 applied (the real chain).
Router tests mount each bare router under /v1 with canned session users
(same override pattern as test_orders.py).
"""
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.adapters.fcm import FakeFcm, RealFcm, StubError, notify  # noqa: E402
from app.core.errors import AppError  # noqa: E402
from app.db import get_connection  # noqa: E402
from app.db_d1 import AsyncSqliteConn  # noqa: E402
from app.services.subscription_service import (  # noqa: E402
    ResumeTooSoonError,
    SubValidationError,
    SubscriptionService,
)

MIGS = ["002_auth.sql", "003_addresses.sql", "004_orders.sql", "006_aftermath.sql"]


def _conn():
    c = get_connection(":memory:")
    for m in MIGS:
        c.executescript((API_ROOT / "src" / "app" / "db" / "migrations" / m).read_text())
    return c


def _addr(c, user="u1", aid="a1"):
    c.execute("INSERT OR IGNORE INTO addresses(id, user_id) VALUES (?, ?)", (aid, user))
    c.commit()


async def _sub(c, user="u1", **over):
    _addr(c, user, over.get("address_id", "a1"))
    return await SubscriptionService(AsyncSqliteConn(c)).create(user, {
        "address_id": over.get("address_id", "a1"),
        "qty": over.get("qty", 2),
        "schedule_type": over.get("schedule_type", "daily"),
        "next_run": over.get("next_run", "2026-09-30"),
    })


def _order(c, oid, user="u1", state="delivered", delivered_ago=None):
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, payment_mode,"
        " state, window_start, idempotency_key, created_at)"
        " VALUES (?, ?, 'a1', '[]', 1, 0, 'cod', ?, '2026-09-29T08:00:00+00:00', ?, ?)",
        (oid, user, state, f"k-{oid}", "2026-09-29T08:00:00+00:00"),
    )
    if delivered_ago is not None:
        ts = (datetime.now(timezone.utc) - delivered_ago).isoformat()
        c.execute(
            "INSERT INTO order_events(id, order_id, from_state, to_state, actor_id,"
            " actor_role, reason, created_at) VALUES (?, ?, 'dispatched', 'delivered',"
            " 'v1', 'vendor', 'pod', ?)",
            (f"ev-{oid}", oid, ts),
        )
    c.commit()


def _client(router_mod, c, user="u1"):
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api import auth_deps
    from app.api.deps import get_db_conn
    from app.core.errors import register_exception_handlers

    app = FastAPI()
    register_exception_handlers(app)
    app.include_router(router_mod.router, prefix="/v1")
    app.dependency_overrides[get_db_conn] = lambda: AsyncSqliteConn(c)
    canned = {"id": user, "role": "user", "phone": "+919000000000",
              "suspended": False, "session_id": "s", "family_id": "f", "device_fp": "d"}
    app.dependency_overrides[auth_deps.get_current_user] = lambda: canned
    return TestClient(app)


# -- migration ------------------------------------------------------------

def test_005_applies_cleanly_and_reruns():
    c = _conn()
    tables = {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    for t in ("subscriptions", "returns", "complaints", "ratings", "skips", "device_tokens"):
        assert t in tables
    c.executescript((API_ROOT / "src" / "app" / "db" / "migrations" / "006_aftermath.sql").read_text())
    assert c.execute("SELECT COUNT(*) c FROM subscriptions").fetchone()["c"] == 0


# -- subscriptions --------------------------------------------------------

async def test_sub_create_tier_stays_null_v1():
    c = _conn()
    s = await _sub(c)
    assert (s["tier"], s["discount_pct"], s["perks"]) == (None, None, None)
    assert s["status"] == "active" and s["schedule_type"] == "daily"


async def test_pause_bad_range_400():
    c = _conn()
    s = await _sub(c)
    svc = SubscriptionService(AsyncSqliteConn(c))
    with pytest.raises(SubValidationError):
        await svc.create("u1", {"address_id": "a1", "qty": 0})
    with pytest.raises(AppError) as e:
        await svc.pause("u1", s["id"], "2026-10-05", "2026-10-01")
    assert e.value.status_code == 400


async def test_resume_guard_late_422_with_next_valid():
    c = _conn()
    s = await _sub(c)
    svc = SubscriptionService(AsyncSqliteConn(c))
    await svc.pause("u1", s["id"], "2026-10-01", "2026-10-10")
    now = datetime(2026, 9, 29, 10, 0, tzinfo=timezone.utc)
    with pytest.raises(ResumeTooSoonError) as e:
        await svc.resume("u1", s["id"], (now + timedelta(hours=2)).isoformat(), now=now)
    assert e.value.code == "RESUME_TOO_SOON" and e.value.status_code == 422
    assert "next_valid_date" in e.value.details
    ok = await svc.resume("u1", s["id"], (now + timedelta(hours=25)).isoformat(), now=now)
    assert ok["status"] == "active" and ok["hold_from"] is None


async def test_router_late_resume_422():
    from app.api.v1 import subscriptions as subs_mod
    c, client = _conn(), None
    s = await _sub(c)
    await SubscriptionService(AsyncSqliteConn(c)).pause("u1", s["id"], "2026-10-01", "2026-10-10")
    client = _client(subs_mod, c)
    pref = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    r = client.post(f"/v1/subscriptions/{s['id']}/resume", json={"preferred_date": pref})
    assert r.status_code == 422 and r.json()["error"]["code"] == "RESUME_TOO_SOON"


async def test_skip_cutoff_late_flag():
    c = _conn()
    s = await _sub(c)
    svc = SubscriptionService(AsyncSqliteConn(c))
    day = "2026-09-29"
    early = datetime(2026, 9, 29, 9, 0, tzinfo=timezone.utc)
    late = datetime(2026, 9, 29, 19, 0, tzinfo=timezone.utc)
    assert (await svc.skip("u1", s["id"], day, now=early))["late_skip"] is False
    c.execute("DELETE FROM skips WHERE sub_id = ?", (s["id"],))
    c.commit()
    out = await svc.skip("u1", s["id"], day, now=late)
    assert out["late_skip"] is True and "cta" in out


async def test_process_due_generates_and_autoresumes_idempotently():
    c = _conn()
    svc = SubscriptionService(AsyncSqliteConn(c))
    due = await _sub(c, next_run="2026-09-29")
    paused = await _sub(c, next_run="2026-09-20")
    await svc.pause("u1", paused["id"], "2026-09-20", "2026-09-25")  # hold_to < today
    held = await _sub(c, next_run="2026-09-29")
    await svc.pause("u1", held["id"], "2026-09-29", "2026-10-05")  # still held
    out1 = await svc.process_due("2026-09-29")
    assert {g["sub_id"] for g in out1["generated"]} == {due["id"]}
    assert {r["sub_id"] for r in out1["resumed"]} == {paused["id"]}
    assert (await svc.get_owned("u1", paused["id"]))["status"] == "active"
    out2 = await svc.process_due("2026-09-29")  # idempotent replay
    assert out2 == {"date": "2026-09-29", "generated": [], "resumed": []}
    assert (await svc.get_owned("u1", due["id"]))["next_run"] > "2026-09-29"


def test_router_sub_crud_owner_scoped():
    from app.api.v1 import subscriptions as subs_mod
    c = _conn()
    _addr(c)
    client = _client(subs_mod, c)
    r = client.post("/v1/subscriptions",
                    json={"address_id": "a1", "qty": 2, "schedule_type": "weekly"})
    assert r.status_code == 201, r.text
    sid = r.json()["id"]
    assert client.get("/v1/subscriptions").json()["data"][0]["id"] == sid
    other = _client(subs_mod, c, user="u2")
    assert other.get("/v1/subscriptions").json() == {"data": []}
    assert other.post(f"/v1/subscriptions/{sid}/pause",
                      json={"hold_from": "2026-10-01", "hold_to": "2026-10-03"}
                      ).status_code == 404  # not-yours == not-found


def test_router_sub_estimate_and_schedule_allowlist():
    """Phase 7 F4/F5: server first-cycle amount; unknown schedules 400."""
    from app.api.v1 import subscriptions as subs_mod
    c = _conn()
    _addr(c)
    client = _client(subs_mod, c)
    r = client.post("/v1/subscriptions/estimate", json={"qty": 2, "sku_mix": "refill"})
    assert r.status_code == 200, r.text
    assert r.json()["total"] == 5600  # 2x refill, refill never deposits
    r = client.post("/v1/subscriptions/estimate", json={"qty": 1, "sku_mix": "container"})
    assert r.json()["total"] == 3000 + 15000  # fresh wallet: deposit due
    bad = client.post("/v1/subscriptions",
                      json={"address_id": "a1", "qty": 2, "schedule_type": "monthly"})
    assert bad.status_code == 400
    ok = client.post("/v1/subscriptions",
                     json={"address_id": "a1", "qty": 2, "schedule_type": "weekly"})
    assert ok.status_code == 201, ok.text
    assert ok.json()["first_cycle_estimate"]["total"] == 5600


# -- returns --------------------------------------------------------------

def test_return_sla_text_and_history():
    from app.api.v1 import returns as ret_mod
    c = _conn()
    _addr(c)
    client = _client(ret_mod, c)
    r = client.post("/v1/returns", json={"qty": 3, "address_id": "a1"})
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["status"] == "requested" and body["id"]
    assert "10 working days" in body["message"] and body["sla_due"] in body["message"]
    assert body["sla_due"] > "2026-09-29"
    hist = client.get("/v1/returns").json()["data"]
    assert [x["id"] for x in hist] == [body["id"]]
    assert _client(ret_mod, c, user="u2").get("/v1/returns").json() == {"data": []}


# -- complaints -----------------------------------------------------------

def test_complaint_quality_window_25h_expires():
    from app.api.v1 import complaints as comp_mod
    c = _conn()
    _order(c, "o1", delivered_ago=timedelta(hours=25))
    client = _client(comp_mod, c)
    r = client.post("/v1/complaints",
                    json={"order_id": "o1", "reason_code": "water_quality", "text": "smells"})
    assert r.status_code == 422 and r.json()["error"]["code"] == "DISPUTE_EXPIRED"


def test_complaint_general_window_4d_expires_but_2d_ok():
    from app.api.v1 import complaints as comp_mod
    c = _conn()
    _order(c, "o1", delivered_ago=timedelta(days=4, hours=1))
    _order(c, "o2", delivered_ago=timedelta(days=2))
    client = _client(comp_mod, c)
    old = client.post("/v1/complaints",
                      json={"order_id": "o1", "reason_code": "late_delivery", "text": "late"})
    assert old.status_code == 422
    ok = client.post("/v1/complaints",
                     json={"order_id": "o2", "reason_code": "late_delivery", "text": "late"})
    assert ok.status_code == 201 and ok.json()["status"] == "open"


def test_complaint_photo_rejected_400_and_disagreement_under_review():
    from app.api.v1 import complaints as comp_mod
    c = _conn()
    _order(c, "o1", delivered_ago=timedelta(hours=1))
    client = _client(comp_mod, c)
    photo = client.post("/v1/complaints",
                        json={"order_id": "o1", "reason_code": "water_quality",
                              "text": "x", "photos": ["img1"]})
    assert photo.status_code == 400 and photo.json()["error"]["code"] == "PHOTOS_V2"
    cid = client.post("/v1/complaints",
                      json={"order_id": "o1", "reason_code": "water_quality",
                            "text": "particles"}).json()["id"]
    c.execute("UPDATE complaints SET vendor_agree = 0 WHERE id = ?", (cid,))
    c.commit()
    listed = client.get("/v1/complaints").json()["data"]
    assert listed[0]["status"] == "under_review"


def test_complaint_text_cap_and_not_delivered():
    from app.api.v1 import complaints as comp_mod
    c = _conn()
    _order(c, "o1", state="dispatched", delivered_ago=None)
    client = _client(comp_mod, c)
    assert client.post("/v1/complaints",
                       json={"order_id": "o1", "reason_code": "other", "text": "x" * 501}
                       ).status_code == 400
    assert client.post("/v1/complaints",
                       json={"order_id": "o1", "reason_code": "other", "text": "ok"}
                       ).status_code == 409


# -- ratings --------------------------------------------------------------

def test_rating_once_and_shortcut_flag():
    from app.api.v1 import ratings as rate_mod
    c = _conn()
    _order(c, "o1", delivered_ago=timedelta(hours=1))
    _order(c, "o2", delivered_ago=timedelta(hours=1))
    _order(c, "o3", state="dispatched", delivered_ago=None)
    client = _client(rate_mod, c)
    r1 = client.post("/v1/orders/o1/rating", json={"stars": 5})
    assert r1.status_code == 201 and r1.json()["complaint_shortcut"] is False
    assert client.post("/v1/orders/o1/rating", json={"stars": 4}
                       ).status_code == 409  # once per order
    r2 = client.post("/v1/orders/o2/rating", json={"stars": 2})
    assert r2.json()["complaint_shortcut"] is True  # <=3 offers complaint path
    assert client.post("/v1/orders/o2/rating", json={"stars": 6}).status_code == 400
    assert client.post("/v1/orders/o3/rating", json={"stars": 5}).status_code == 409


# -- devices --------------------------------------------------------------

def test_device_upsert_scoping():
    from app.api.v1 import devices as dev_mod
    c = _conn()
    a, b = _client(dev_mod, c), _client(dev_mod, c, user="u2")
    assert a.post("/v1/devices",
                  json={"device_id": "d1", "fcm_token": "t1", "platform": "android"}
                  ).status_code == 201
    assert a.post("/v1/devices",
                  json={"device_id": "d1", "fcm_token": "t2", "platform": "android"}
                  ).json()["updated"] is True  # upsert same user+device
    assert b.request("DELETE", "/v1/devices", json={"device_id": "d1"}
                     ).status_code == 404  # not-yours
    assert a.request("DELETE", "/v1/devices", json={"device_id": "d1"}
                     ).json()["deleted"] is True
    assert a.request("DELETE", "/v1/devices", json={"device_id": "d1"}
                     ).status_code == 404


# -- fcm ------------------------------------------------------------------

def test_fcm_fake_records_real_stubbed_notify_never_raises():
    fake = FakeFcm()
    mid = fake.send("tok", "Arriving", "Your window 8:00-8:30", {"order": "o1"})
    assert fake.sent[0]["id"] == mid and fake.sent[0]["token"] == "tok"
    with pytest.raises(StubError):
        RealFcm(project_id="x").send("tok", "t", "b")
    assert notify(fake, "tok", "t", "b") is True
    assert notify(None, "tok", "t", "b") is False  # no sender configured

    class Broken:
        def send(self, *a, **k):
            raise RuntimeError("down")

    assert notify(Broken(), "tok", "t", "b") is False  # never raises to callers
