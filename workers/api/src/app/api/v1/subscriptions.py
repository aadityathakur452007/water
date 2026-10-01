"""Subscription routes: bare router (mounted under /v1 by the integrator).

All endpoints owner-scoped behind session auth (ssdlc: never trust client
identity). Writes require an active (non-suspended) user; reads allow
suspended users (contract §14.1 — history preserved, never a dead end).
DTOs live here next to their only consumer (same pattern as auth.py).
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.api.auth_deps import get_current_user, require_active_user
from app.api.deps import get_db
from app.services.subscription_service import SubscriptionService

router = APIRouter(tags=["subscriptions"])


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
def create_subscription(payload: SubCreateIn, user=Depends(require_active_user),
                        conn=Depends(get_db)):
    return SubscriptionService(conn).create(_uid(user), payload.model_dump(mode="json"))


@router.get("/subscriptions")
def list_subscriptions(user=Depends(get_current_user), conn=Depends(get_db)):
    return {"data": SubscriptionService(conn).list(_uid(user))}


@router.post("/subscriptions/{sub_id}/pause")
def pause_subscription(sub_id: str, payload: PauseIn, user=Depends(require_active_user),
                       conn=Depends(get_db)):
    sub = SubscriptionService(conn).pause(_uid(user), sub_id, payload.hold_from, payload.hold_to)
    return {**sub, "fcm": "pause_confirm queued"}


@router.post("/subscriptions/{sub_id}/resume")
def resume_subscription(sub_id: str, payload: ResumeIn, user=Depends(require_active_user),
                        conn=Depends(get_db)):
    return SubscriptionService(conn).resume(_uid(user), sub_id, payload.preferred_date)


@router.post("/subscriptions/{sub_id}/skips", status_code=201)
def skip_subscription(sub_id: str, payload: SkipIn, user=Depends(require_active_user),
                      conn=Depends(get_db)):
    return SubscriptionService(conn).skip(_uid(user), sub_id, payload.date)
