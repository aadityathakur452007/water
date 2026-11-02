from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.api.auth_deps import require_role
from app.api.deps import get_db_conn
from app.services.rider_service import RiderService

router = APIRouter(tags=["rider"])

_rider = require_role("rider")


def _uid(user: dict) -> str:
    return str(user["id"])


def _svc(conn=Depends(get_db_conn)) -> RiderService:
    return RiderService(conn)


class RiderPodIn(BaseModel):
    delivery_otp: str = Field(min_length=1, max_length=10)
    empties_count: int = Field(ge=0, default=0)
    cash: int = Field(ge=0, default=0)


class RiderFailIn(BaseModel):
    reason_code: str = Field(min_length=1, max_length=50)
    note: str = Field(default="", max_length=500)


@router.get("/rider/me")
async def get_rider_me(user=Depends(_rider)):
    return {
        "id": user["id"],
        "name": user.get("name"),
        "phone": user.get("phone"),
        "role": user.get("role"),
    }


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
