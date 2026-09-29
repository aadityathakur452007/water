"""Orders router: thin HTTP boundary (parse, validate DTO, map to service).

Bare paths — mounted under ``/v1`` by the app factory/integrator. Every route is
behind ``get_current_user``: C1's ``app.api.auth_deps`` when it lands, else the
test-local stub below (header-bound identity, never trusted in production).
Actor id/role always come from the session, never the body (H1).
"""
from fastapi import APIRouter, Depends, Header, Query, Request

from app.api.deps import get_db, get_settings
from app.repositories.ledger_repo import LedgerRepo
from app.repositories.order_repo import OrderRepo
from app.schemas.orders import (
    CancelIn,
    CancelOut,
    OrderDetailOut,
    OrderIn,
    OrderListOut,
    OrderOut,
    RescheduleIn,
)
from app.services import pricing
from app.services.order_service import OrderService

try:  # C1 owns app.api.auth_deps; real session auth takes precedence.
    from app.api.auth_deps import get_current_user  # type: ignore[import-not-found]
except ImportError:  # test-local stub: identity from headers only.

    def get_current_user(request: Request) -> dict:
        return {
            "id": request.headers.get("X-User-Id", "test-user"),
            "role": request.headers.get("X-User-Role", "user"),
        }


router = APIRouter(tags=["orders"])


def _uid(user: object) -> str:
    if isinstance(user, dict):
        return str(user.get("id"))
    return str(getattr(user, "id"))


def _service(conn) -> OrderService:
    s = get_settings()
    rates = {
        "refill": s.rate_refill_paise,
        "container": s.rate_container_paise,
        "deposit": s.deposit_per_jar_paise,
    }
    return OrderService(OrderRepo(conn), LedgerRepo(conn), pricing, rates)


def _require_idem(idem: str | None) -> str:
    from app.core.errors import ValidationError

    if not idem or not idem.strip():
        raise ValidationError(message="Idempotency-Key header required.", details={})
    return idem.strip()


@router.post("/orders", response_model=OrderOut, status_code=201)
def create_order(
    payload: OrderIn,
    conn=Depends(get_db),
    user=Depends(get_current_user),
    idem: str | None = Header(default=None, alias="Idempotency-Key"),
):
    return _service(conn).create(_uid(user), payload.model_dump(mode="json"), _require_idem(idem))


@router.get("/orders", response_model=OrderListOut)
def list_orders(
    conn=Depends(get_db),
    user=Depends(get_current_user),
    limit: int = Query(default=20, ge=1, le=50),
    cursor: str | None = Query(default=None),
):
    return _service(conn).list(_uid(user), limit, cursor)


@router.get("/orders/{order_id}", response_model=OrderDetailOut)
def get_order(order_id: str, conn=Depends(get_db), user=Depends(get_current_user)):
    return _service(conn).detail(_uid(user), order_id)


@router.post("/orders/{order_id}/cancel", response_model=CancelOut)
def cancel_order(
    order_id: str,
    payload: CancelIn,
    conn=Depends(get_db),
    user=Depends(get_current_user),
    idem: str | None = Header(default=None, alias="Idempotency-Key"),
):
    return _service(conn).cancel(_uid(user), order_id, payload.reason, _require_idem(idem))


@router.post("/orders/{order_id}/reschedule", response_model=OrderOut)
def reschedule_order(
    order_id: str,
    payload: RescheduleIn,
    conn=Depends(get_db),
    user=Depends(get_current_user),
):
    return _service(conn).reschedule(_uid(user), order_id, payload.window_start)
