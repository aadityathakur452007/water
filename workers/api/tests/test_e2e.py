"""E4 backend E2E: full order lifecycle through the REAL app (main.create_app).

Covers user-flows.md flow 1 (first order) + flow 5 (payment) end to end:
otp start->verify->me, address, quote, order create (201 + deposit math),
COD confirm -> dues, admin-assign, vendor triple + PoD -> delivered,
ledger/dues/reconcile consistency, second order -> cancel (void + reversal),
plus ssdlc abuse cases (cross-user 404, tampered total, double-cancel).

Patterns reused from test_auth.py (FakeVerifier), test_orders.py (quote-bound
payload builder), test_payments.py (FakeUpiProvider), test_vendor.py (session
seed shape). Only new file: this one.

Deviations (no HTTP path exists in v1, driven direct-DB and noted):
- placed->accepted->picked->packed and assigned->dispatched go through
  OrderRepo.transition: no API endpoint exposes accept/pick/pack/dispatch.
- payments router calls module-global get_provider() directly (not Depends),
  so the fake is patched at app.api.v1.payments.get_provider; auth uses
  Depends(get_verifier) so dependency_overrides applies there.
"""

import hashlib
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.adapters.firebase import UnauthError  # noqa: E402
from app.db import get_connection, init_schema  # noqa: E402

MIGRATIONS = [
    "002_auth.sql",
    "003_addresses.sql",
    "004_orders.sql",
    "005_payments.sql",
    "006_aftermath.sql",
    "007_ops.sql",
]

USER_PHONE = "+919876543210"
USER2_PHONE = "+919876543211"
VENDOR_PHONE = "+919876543212"
ADMIN_PHONE = "+919876543213"
WINDOW = "2026-10-01T08:00:00+00:00"
FUTURE = (datetime.now(timezone.utc) + timedelta(days=365)).isoformat()
NOW = datetime.now(timezone.utc).isoformat()


class FakeVerifier:
    """Maps id_token -> claims; unknown token -> 401 (mirrors test_auth.py)."""

    def __init__(self, mapping):
        self.mapping = mapping

    def verify_id_token(self, token: str) -> dict:
        if token not in self.mapping:
            raise UnauthError("Invalid session.", {})
        return dict(self.mapping[token])


@pytest.fixture()
def client(monkeypatch):
    from fastapi.testclient import TestClient

    from app.adapters.firebase import get_verifier
    from app.adapters.upi import FakeUpiProvider
    from app.api import deps as deps_mod
    from app.api.v1 import payments as payments_mod
    from app.main import create_app

    c = get_connection(":memory:")
    for name in MIGRATIONS:
        c.executescript((API_ROOT / "src" / "app" / "db" / "migrations" / name).read_text())
    init_schema(c)  # config/audit_log shape (admin writes audit)
    c.commit()

    deps_mod.set_test_connection(c)  # belt-and-braces alongside the override
    monkeypatch.setattr(payments_mod, "get_provider", lambda: FakeUpiProvider())

    app = create_app()
    app.dependency_overrides[deps_mod.get_db] = lambda: c
    app.dependency_overrides[get_verifier] = lambda: FakeVerifier(
        {
            "good-user": {"uid": "fake-uid-user", "phone_number": USER_PHONE},
            "good-user2": {"uid": "fake-uid-user2", "phone_number": USER2_PHONE},
        }
    )
    try:
        yield TestClient(app), c
    finally:
        deps_mod.set_test_connection(None)


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _quote_payload(address_id):
    return {
        "items": [{"sku": "refill", "qty": 2}],
        "e": 1,
        "address_id": address_id,
        "window_start": WINDOW,
    }


def _order_payload(quote, address_id, mode="cod"):
    return {
        "items": [{"sku": "refill", "qty": 2}],
        "e": 1,
        "address_id": address_id,
        "window_start": WINDOW,
        "quote_hash": quote["quote_hash"],
        "quote_total": quote["total"],
        "quote_rate_version": "v1",
        "quote_expires_at": (datetime.now(timezone.utc) + timedelta(minutes=15)).isoformat(),
        "payment_mode": mode,
    }


def _seed_admin_vendor(conn):
    """Direct-DB seed: zone + vendor/admin users + sessions (no HTTP path)."""
    from app.services.dispatch_service import ensure_profile  # noqa: E402

    conn.execute("INSERT INTO zones(id, name, pincodes, active) VALUES ('z1', 'Z1', '560001', 1)")
    for uid, phone, role in (
        ("vendor-1", VENDOR_PHONE, "vendor"),
        ("admin-1", ADMIN_PHONE, "admin"),
    ):
        conn.execute(
            "INSERT INTO users(id, phone, name, role, language, kyc_status, suspended, created_at)"
            " VALUES (?, ?, ?, ?, 'hi', 'verified', 0, ?)",
            (uid, phone, role.title(), role, NOW),
        )
        conn.execute(
            "INSERT INTO sessions(id, user_id, token_hash, refresh_hash, role, device_fp,"
            " family_id, expires_at, created_at) VALUES (?, ?, ?, ?, ?, 'd', 'f', ?, ?)",
            (
                f"ses-{uid}", uid,
                hashlib.sha256(f"tok-{uid}".encode()).hexdigest(),
                hashlib.sha256(f"r:tok-{uid}".encode()).hexdigest(),
                role, FUTURE, FUTURE,
            ),
        )
    conn.execute("INSERT INTO vendor_zones(vendor_id, zone_id, priority) VALUES ('vendor-1', 'z1', 0)")
    ensure_profile(conn, "vendor-1")
    conn.commit()


def _drive_to(conn, order_id, *states):
    from app.repositories.order_repo import OrderRepo  # noqa: E402

    repo = OrderRepo(conn)
    for to in states:
        repo.transition(order_id, to, {"id": "admin-1", "role": "admin"}, "e2e drive")


def test_e2e_full_lifecycle(client):
    http, conn = client

    # (1) otp start -> verify -> me -------------------------------------------
    r = http.post("/v1/auth/otp/start", json={"phone": USER_PHONE})
    assert r.status_code == 202, r.text
    assert r.json()["sent_to_masked"] == "+91******3210"
    r = http.post(
        "/v1/auth/otp/verify",
        json={"firebase_id_token": "good-user", "device": {"id": "dev-e2e"}},
    )
    assert r.status_code == 200, r.text
    user_tok = r.json()["access_token"]
    assert r.json()["role"] == "user"
    me = http.get("/v1/auth/me", headers=_auth(user_tok))
    assert me.status_code == 200, me.text
    user_id = me.json()["user"]["id"]
    assert me.json()["user"]["phone"] == USER_PHONE
    assert me.json()["ledger_summary"] == {
        "held": 0, "deposit_paid": 0, "deposit_refunded": 0, "dues": 0,
    }

    # (2) address create -------------------------------------------------------
    r = http.post(
        "/v1/addresses",
        json={"type": "home", "lat": 12.9716, "lng": 77.5946, "pincode": "560001"},
        headers=_auth(user_tok),
    )
    assert r.status_code == 201, r.text
    address_id = r.json()["id"]

    # (3) quote: 2 refills (5600) + (2-1) x Rs150 deposit (15000) = 20600 ------
    quote = http.post("/v1/quotes", json=_quote_payload(address_id)).json()
    assert (quote["water_bill"], quote["deposit_due"], quote["total"]) == (5600, 15000, 20600)

    # (4) order create: 201 + server-frozen totals + deposit ledger entry ------
    r = http.post(
        "/v1/orders", json=_order_payload(quote, address_id),
        headers={**_auth(user_tok), "Idempotency-Key": "e2e-o1"},
    )
    assert r.status_code == 201, r.text
    order = r.json()
    assert (order["state"], order["total"]) == ("placed", 20600)
    assert (order["water_bill"], order["deposit_due"]) == (5600, 15000)
    oid = order["id"]
    me = http.get("/v1/auth/me", headers=_auth(user_tok)).json()
    assert me["ledger_summary"]["deposit_paid"] == 15000

    # (5) COD confirm -> dues --------------------------------------------------
    r = http.post(f"/v1/orders/{oid}/cod-confirm", headers=_auth(user_tok))
    assert r.status_code == 200, r.text
    assert r.json()["payment_status"] == "unpaid" and r.json()["dues"] == 20600
    assert http.get("/v1/billing/dues", headers=_auth(user_tok)).json()["dues"] == 20600
    inv = http.get(f"/v1/invoices/{oid}", headers=_auth(user_tok)).json()
    assert inv["total"] == 20600 and inv["amount_due"] == 20600

    # (6) admin seed direct-DB -> assign to vendor ------------------------------
    _seed_admin_vendor(conn)
    _drive_to(conn, oid, "accepted", "picked", "packed")
    r = http.post(
        f"/v1/admin/orders/{oid}/assign", json={"vendor_id": "vendor-1"},
        headers=_auth("tok-admin-1"),
    )
    assert r.status_code == 200, r.text
    stop_id = r.json()["stop_id"]
    assert r.json()["version"] == 1

    # (7) vendor triple + PoD -> delivered --------------------------------------
    r = http.post(
        f"/v1/vendor/stops/{stop_id}/triple",
        json={"fulls_given": 2, "empties_back": 1, "cash": 0, "upi": 0,
              "caps_missing": 0, "version": 1},
        headers=_auth("tok-vendor-1"),
    )
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "done"
    _drive_to(conn, oid, "dispatched")
    from app.services.vendor_service import pod_otp  # noqa: E402

    today = datetime.now(timezone.utc).date().isoformat()
    r = http.post(
        f"/v1/vendor/stops/{stop_id}/pod",
        json={"delivery_otp": pod_otp(oid, today), "seal_ok": True},
        headers=_auth("tok-vendor-1"),
    )
    assert r.status_code == 200, r.text
    detail = http.get(f"/v1/orders/{oid}", headers=_auth(user_tok)).json()
    assert detail["state"] == "delivered"
    assert detail["bill"]["total"] == 20600

    # (8) ledger/dues/reconcile consistent ---------------------------------------
    me = http.get("/v1/auth/me", headers=_auth(user_tok)).json()["ledger_summary"]
    assert (me["held"], me["deposit_paid"], me["deposit_refunded"]) == (1, 15000, 0)
    inv = http.get(f"/v1/invoices/{oid}", headers=_auth(user_tok)).json()
    assert inv["water_bill"] + inv["deposit_due"] + inv["cap_charge"] - inv["paid"] == inv["amount_due"]
    assert inv["amount_due"] == 20600  # COD unpaid: bill = water+deposit-payments
    dues = http.get("/v1/billing/dues", headers=_auth(user_tok)).json()
    assert dues["dues"] == 20600
    assert any(line["order_id"] == oid and line["due"] == 20600 for line in dues["lines"])
    rec = http.get("/v1/admin/reconciliation", headers=_auth("tok-admin-1")).json()
    assert rec["jars_out"] == me["held"] == 1
    assert rec["deposit_liability"] == me["deposit_paid"] - me["deposit_refunded"] == 15000
    assert rec["dues_receivable"] == 20600

    # (9) second order -> cancel -> void + deposit reversal, bill 0 --------------
    r = http.post(
        "/v1/orders", json=_order_payload(quote, address_id),
        headers={**_auth(user_tok), "Idempotency-Key": "e2e-o2"},
    )
    assert r.status_code == 201, r.text
    oid2 = r.json()["id"]
    r = http.post(
        f"/v1/orders/{oid2}/cancel", json={"reason": "changed mind"},
        headers={**_auth(user_tok), "Idempotency-Key": "e2e-c1"},
    )
    assert r.status_code == 200, r.text
    cancelled = r.json()
    assert cancelled == {
        "order_id": oid2, "state": "cancelled", "bill_total": 0,
        "deposit_reversed": 15000, "refund": None,  # unpaid COD: void, no refund row
    }
    me = http.get("/v1/auth/me", headers=_auth(user_tok)).json()["ledger_summary"]
    assert (me["deposit_paid"], me["deposit_refunded"]) == (30000, 15000)
    rec = http.get("/v1/admin/reconciliation", headers=_auth("tok-admin-1")).json()
    assert rec["deposit_liability"] == 15000  # order-1 liability survives

    # (10) abuse ------------------------------------------------------------------
    # cross-user read: not-yours == not-found (no oracle)
    r = http.post(
        "/v1/auth/otp/verify",
        json={"firebase_id_token": "good-user2", "device": {"id": "dev-e2e-2"}},
    )
    assert r.status_code == 200, r.text
    user2_tok = r.json()["access_token"]
    assert http.get(f"/v1/orders/{oid}", headers=_auth(user2_tok)).status_code == 404
    # tampered total: server recomputes the quote, client echo is rejected
    bad = _order_payload(quote, address_id)
    bad["quote_total"] = 1
    r = http.post(
        "/v1/orders", json=bad,
        headers={**_auth(user_tok), "Idempotency-Key": "e2e-tamper"},
    )
    assert r.status_code == 409, r.text
    assert r.json()["error"]["code"] == "STALE_QUOTE"
    # double-cancel: same key replays the single outcome, zero new writes
    again = http.post(
        f"/v1/orders/{oid2}/cancel", json={"reason": "changed mind"},
        headers={**_auth(user_tok), "Idempotency-Key": "e2e-c1"},
    )
    assert again.status_code == 200, again.text
    assert again.json() == cancelled  # identical outcome, zero new writes
    assert conn.execute(
        "SELECT COUNT(*) c FROM refunds WHERE order_id = ?", (oid2,)
    ).fetchone()["c"] == 0
    other_key = http.post(
        f"/v1/orders/{oid2}/cancel", json={"reason": "other reason"},
        headers={**_auth(user_tok), "Idempotency-Key": "e2e-c2"},
    )
    assert other_key.status_code == 409, other_key.text
    assert other_key.json()["error"]["code"] == "ALREADY_CANCELLED"
    assert other_key.json()["error"]["details"]["bill_total"] == 0
