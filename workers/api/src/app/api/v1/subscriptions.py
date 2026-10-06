"""Subscription routes: bare router (mounted under /v1 by the integrator).

All endpoints owner-scoped behind session auth (ssdlc: never trust client
identity). Creation needs role=='user'; other writes need an active
(non-suspended) user; reads allow suspended users (contract §14.1 — history
preserved, never a dead end).
DTOs live here next to their only consumer (same pattern as auth.py).
"""

from fastapi import APIRouter, Depends, Header
from pydantic import BaseModel, Field

from app.api.auth_deps import get_current_user, require_active_user, require_role
from app.api.deps import get_db_conn
from app.services.subscription_service import SubscriptionService

router = APIRouter(tags=["subscriptions"])

# Module-level so tests can override this exact dep (same pattern as
# vendor.py `_vendor`): subscription creation is a user-role-only write.
_user = require_role("user")


class SubCreateIn(BaseModel):
    address_id: str = Field(min_length=1)
    qty: int = Field(ge=1, le=30)
    sku_mix: str = Field(default="refill", max_length=32)
    window: str = Field(default="", max_length=64)
    schedule_type: str = Field(default="daily", max_length=16)
    recurrence: str = Field(default="", max_length=64)
    payment_method: str = Field(default="cod", max_length=16)
    next_run: str | None = Field(default=None, max_length=32)


class PauseIn(BaseModel):
    hold_from: str = Field(min_length=1, max_length=32)
    hold_to: str = Field(min_length=1, max_length=32)


class ResumeIn(BaseModel):
    preferred_date: str = Field(min_length=1, max_length=64)


class SkipIn(BaseModel):
    date: str = Field(min_length=1, max_length=32)


def _uid(user: dict) -> str:
    return str(user.get("id"))


@router.post("/subscriptions", status_code=201)
async def create_subscription(payload: SubCreateIn, user=Depends(_user),
                        conn=Depends(get_db_conn),
                        idem: str | None = Header(default=None, alias="Idempotency-Key")):
    return await SubscriptionService(conn).create(
        _uid(user), payload.model_dump(mode="json"), (idem or "").strip())


class SubEstimateIn(BaseModel):
    qty: int = Field(ge=1, le=30)
    sku_mix: str = Field(default="refill", max_length=32)


@router.post("/subscriptions/estimate")
async def estimate_subscription(payload: SubEstimateIn, user=Depends(_user),
                          conn=Depends(get_db_conn)):
    """Phase 7 F5: pure first-cycle amount (water + once-only deposit) —
    no write. The sheet shows this on Pay instead of client math."""
    return await SubscriptionService(conn).estimate_first_cycle(
        _uid(user), payload.qty, payload.sku_mix)


@router.get("/subscriptions")
async def list_subscriptions(user=Depends(get_current_user), conn=Depends(get_db_conn)):
    return {"data": await SubscriptionService(conn).list(_uid(user))}


@router.post("/subscriptions/{sub_id}/pause")
async def pause_subscription(sub_id: str, payload: PauseIn, user=Depends(require_active_user),
                       conn=Depends(get_db_conn)):
    sub = await SubscriptionService(conn).pause(_uid(user), sub_id, payload.hold_from, payload.hold_to)
    return {**sub, "fcm": "pause_confirm queued"}


@router.post("/subscriptions/{sub_id}/resume")
async def resume_subscription(sub_id: str, payload: ResumeIn, user=Depends(require_active_user),
                        conn=Depends(get_db_conn)):
    return await SubscriptionService(conn).resume(_uid(user), sub_id, payload.preferred_date)


@router.post("/subscriptions/{sub_id}/skips", status_code=201)
async def skip_subscription(sub_id: str, payload: SkipIn, user=Depends(require_active_user),
                      conn=Depends(get_db_conn)):
    return await SubscriptionService(conn).skip(_uid(user), sub_id, payload.date)


class CancelSubIn(BaseModel):
    reason: str = Field(default="", max_length=500)
    upi_id: str | None = Field(default=None, max_length=100)


@router.post("/subscriptions/{sub_id}/cancel")
async def cancel_subscription(
    sub_id: str,
    payload: CancelSubIn,
    user=Depends(require_active_user),
    conn=Depends(get_db_conn),
):
    """Cancel subscription: prorates unused water days and schedules empty bottle pickup."""
    return await SubscriptionService(conn).cancel(
        _uid(user), sub_id, payload.reason, payload.upi_id or ""
    )

