"""Payments router: thin HTTP boundary (parse, validate DTO, map to service).

Bare paths — mounted under ``/v1`` by the integrator. Webhook has NO session
auth (HMAC only, ssdlc); everything else uses ``get_current_user`` /
``require_active_user`` / ``require_role('admin')``. Actor id/role always come
from the session, never the body (H1).
"""

from fastapi import APIRouter, Depends, Header, Request
from pydantic import BaseModel, Field

from app.adapters.upi import get_provider
from app.api.auth_deps import get_current_user, require_active_user, require_role
from app.api.deps import get_db_conn
from app.repositories.ledger_repo import LedgerRepo
from app.repositories.order_repo import OrderRepo
from app.repositories.payment_repo import PaymentRepo
from app.services.payment_service import PaymentService

router = APIRouter(tags=["payments"])


class UpiIntentIn(BaseModel):
    order_id: str = Field(min_length=1)


def _service(conn) -> PaymentService:
    return PaymentService(PaymentRepo(conn), OrderRepo(conn), LedgerRepo(conn), get_provider())


def _uid(user: object) -> str:
    return str(user["id"] if isinstance(user, dict) else getattr(user, "id"))


def _require_idem(idem: str | None) -> str:
    from app.core.errors import ValidationError

    if not idem or not idem.strip():
        raise ValidationError(message="Idempotency-Key header required.", details={})
    return idem.strip()


@router.post("/payments/upi-intent", status_code=201)
async def upi_intent(payload: UpiIntentIn, conn=Depends(get_db_conn),
               user=Depends(require_active_user),
               idem: str | None = Header(default=None, alias="Idempotency-Key")):
    return await _service(conn).intent(_uid(user), payload.order_id.strip(), _require_idem(idem))


@router.post("/webhooks/upi")
async def upi_webhook(request: Request, conn=Depends(get_db_conn)):
    raw = await request.body()
    sig = request.headers.get("X-UPI-Signature", request.headers.get("X-Signature"))
    return await _service(conn).webhook_ingest(raw, sig)


@router.post("/orders/{order_id}/cod-confirm")
async def cod_confirm(order_id: str, conn=Depends(get_db_conn), user=Depends(require_active_user)):
    return await _service(conn).cod_confirm(_uid(user), order_id)


@router.get("/billing/dues")
async def billing_dues(conn=Depends(get_db_conn), user=Depends(get_current_user)):
    return await _service(conn).get_dues(_uid(user))


# 014: wallet truth for the app (held + deposit wallet + dues in one call).
# The Flutter ledgerMe() already calls GET /ledger/me — it 404'd before.
@router.get("/ledger/me")
async def ledger_me(conn=Depends(get_db_conn), user=Depends(get_current_user)):
    led = await LedgerRepo(conn).get(_uid(user))
    paid = int(led.get("deposit_paid", 0))
    refunded = int(led.get("deposit_refunded", 0))
    return {
        "held": int(led.get("held", 0)),
        "deposit_paid": paid,
        "deposit_refunded": refunded,
        "wallet_held": max(0, paid - refunded),
        "dues": int(led.get("dues", 0)),
    }


@router.get("/invoices/{order_id}")
async def invoice(order_id: str, conn=Depends(get_db_conn), user=Depends(get_current_user)):
    return await _service(conn).get_invoice(_uid(user), order_id)


@router.post("/refunds/{refund_id}/claim")
async def refund_claim(refund_id: str, conn=Depends(get_db_conn), user=Depends(require_role("admin"))):
    return await _service(conn).claim_refund(_uid(user), refund_id)


@router.post("/refunds/{refund_id}/done")
async def refund_done(refund_id: str, conn=Depends(get_db_conn), user=Depends(require_role("admin"))):
    return await _service(conn).complete_refund(_uid(user), refund_id, "done")


@router.post("/refunds/{refund_id}/failed")
async def refund_failed(refund_id: str, conn=Depends(get_db_conn), user=Depends(require_role("admin"))):
    return await _service(conn).complete_refund(_uid(user), refund_id, "failed")
