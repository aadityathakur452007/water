from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.api.auth_deps import require_role
from app.api.deps import get_db_conn
from app.services.rider_service import RiderService

router = APIRouter(tags=["rider"])

_rider = require_role("rider")


from app.core.http_utils import user_id as _uid


def _svc(conn=Depends(get_db_conn)) -> RiderService:
    return RiderService(conn)


class RiderPodIn(BaseModel):
    delivery_otp: str = Field(min_length=4, max_length=8, pattern=r"^\d{4,8}$")
    empties_count: int = Field(ge=0, le=100, default=0)
    cash: int = Field(ge=0, le=10000000, default=0)


class RiderFailIn(BaseModel):
    reason_code: str = Field(min_length=1, max_length=50, pattern=r"^[a-zA-Z0-9_\-]+$")
    note: str = Field(default="", max_length=500)


class RiderCancelIn(BaseModel):
    cancel_otp: str = Field(min_length=4, max_length=8, pattern=r"^\d{4,8}$")
    reason: str = Field(default="CUSTOMER_UNREACHABLE", max_length=200)


class RiderDutyIn(BaseModel):
    status: str = Field(pattern=r"^(on_duty|off_duty|shift_ended)$")


@router.get("/rider/me")
async def get_rider_me(user=Depends(_rider)):
    return {
        "id": user["id"],
        "name": user.get("name"),
        "phone": user.get("phone"),
        "role": user.get("role"),
    }


@router.get("/rider/duty")
async def get_rider_duty(conn=Depends(get_db_conn), user=Depends(_rider)):
    return await _svc(conn).get_duty(_uid(user))


@router.post("/rider/duty")
async def set_rider_duty(payload: RiderDutyIn, conn=Depends(get_db_conn), user=Depends(_rider)):
    return await _svc(conn).set_duty(_uid(user), payload.status)


@router.get("/rider/routes/today")
async def rider_today_route(
    date: str | None = Query(default=None),
    conn=Depends(get_db_conn),
    user=Depends(_rider),
):
    return await _svc(conn).routes_today(_uid(user), date)


@router.post("/rider/stops/{stop_id}/complete")
async def rider_complete_stop(
    stop_id: str,
    payload: RiderPodIn,
    conn=Depends(get_db_conn),
    user=Depends(_rider),
):
    return await _svc(conn).complete_stop(_uid(user), stop_id, payload.model_dump())


@router.post("/rider/stops/{stop_id}/fail")
async def rider_fail_stop(
    stop_id: str,
    payload: RiderFailIn,
    conn=Depends(get_db_conn),
    user=Depends(_rider),
):
    return await _svc(conn).fail_stop(_uid(user), stop_id, payload.reason_code, payload.note)


@router.post("/rider/stops/{stop_id}/cancel")
async def rider_cancel_stop(
    stop_id: str,
    payload: RiderCancelIn,
    conn=Depends(get_db_conn),
    user=Depends(_rider),
):
    return await _svc(conn).cancel_stop(_uid(user), stop_id, payload.cancel_otp, payload.reason)


