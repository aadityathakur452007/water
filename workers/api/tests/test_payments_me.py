import pytest
import uuid
import datetime as _dt
from fastapi.testclient import TestClient
from app.db_d1 import AsyncSqliteConn
from app.services.payment_service import PaymentService
from app.repositories.payment_repo import PaymentRepo
from app.repositories.order_repo import OrderRepo
from app.repositories.ledger_repo import LedgerRepo
from tests.test_payments import _conn, _order, _svc, _client
from tests._rzp import real_provider, stub_orders_api

@pytest.mark.asyncio
async def test_payments_me_endpoint_returns_user_payments():
    c = _conn()
    uid = "u-test-me"
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    # Insert dummy order and payment
    oid = uuid.uuid4().hex
    pid = uuid.uuid4().hex
    c.execute(
        "INSERT INTO orders(id, user_id, address_id, items, n, e, m, water_bill, deposit_due, cap_charge, total, payment_mode, payment_status, state, window_start, created_at, idempotency_key)"
        " VALUES (?, ?, 'a1', '[]', 2, 0, 0, 5600, 0, 0, 5600, 'upi', 'paid_upi', 'delivered', '2026-10-06T09:00:00Z', ?, 'idem-test')",
        (oid, uid, now),
    )
    c.execute(
        "INSERT INTO payments(id, order_id, user_id, amount, method, provider_ref, status, created_at, verified_at)"
        " VALUES (?, ?, ?, 5600, 'upi', 'pay_test_me', 'paid', ?, ?)",
        (pid, oid, uid, now, now),
    )
    c.commit()

    ac = AsyncSqliteConn(c)
    repo = PaymentRepo(ac)
    history = await repo.list_user_payments(uid)
    assert len(history) == 1
    assert history[0]["id"] == pid
    assert history[0]["amount"] == 5600
    assert history[0]["jars_count"] == 2
    assert history[0]["method"] == "upi"
    assert history[0]["status"] == "paid"
