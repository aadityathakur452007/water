"""Vendor router: thin HTTP boundary (parse, validate DTO, map to service).

Bare paths — mounted under ``/v1`` by the integrator (this slice must NOT touch
app/main.py). Every route is behind ``require_role('vendor')`` (ssdlc: authz on
every endpoint, actor from the session, never the body).
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from typing import Any

from app.api.auth_deps import require_role
from app.api.deps import get_db_conn
from app.services.vendor_service import VendorService

router = APIRouter(tags=["vendor"])

_vendor = require_role("vendor")  # module-level so tests can override this exact dep


def _uid(user: object) -> str:
    if isinstance(user, dict):
        return str(user.get("id"))
    return str(getattr(user, "id"))


def _svc(conn) -> VendorService:
    return VendorService(conn)


class DutyIn(BaseModel):
    on: bool


class TripleIn(BaseModel):
    fulls_given: int = Field(ge=0)
    empties_back: int = Field(ge=0)
    cash: int = Field(ge=0, default=0)
    upi: int = Field(ge=0, default=0)
    caps_missing: int = Field(ge=0, default=0)
    tendered: int | None = Field(ge=0, default=None)
    change_given: int | None = Field(ge=0, default=None)
    seal_ok: bool | None = None
    version: int


class PodIn(BaseModel):
    delivery_otp: str = ""
    empties_count: int = Field(ge=0, default=0)
    cash: int = Field(ge=0, default=0)
    seal_ok: bool | None = None
    lat: float | None = None
    lng: float | None = None


class SyncItem(BaseModel):
    model_config = {"extra": "allow"}  # triple fields + stop_id/version/key pass through

    stop_id: str
    version: int


class SyncIn(BaseModel):
    items: list[dict[str, Any]]


class VerifyIn(BaseModel):
    agree: bool
    note: str = ""


class QualityCheckIn(BaseModel):
    agree: bool
    check: str = ""
    note: str = ""


@router.post("/vendor/duty")
async def set_duty(payload: DutyIn, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return _svc(conn).duty(_uid(user), payload.on)


@router.get("/vendor/routes/today")
async def routes_today(date: str | None = None, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).today_route(_uid(user), date)


@router.get("/vendor/stops/{stop_id}")
async def get_stop(stop_id: str, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).get_stop(_uid(user), stop_id)


@router.post("/vendor/stops/{stop_id}/triple")
async def commit_triple(stop_id: str, payload: TripleIn, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).triple_commit(_uid(user), stop_id, payload.model_dump(mode="json"))


@router.post("/vendor/stops/{stop_id}/pod")
async def complete_pod(stop_id: str, payload: PodIn, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).pod_complete(_uid(user), stop_id, payload.model_dump(mode="json"))


@router.post("/vendor/sync")
async def sync_batch(payload: SyncIn, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).sync_batch(_uid(user), payload.items)


@router.get("/vendor/earnings")
async def earnings(shift: str | None = None, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).earnings(_uid(user), shift)


@router.post("/complaints/{complaint_id}/verify")
async def verify_complaint(complaint_id: str, payload: VerifyIn,
                     conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).verify_complaint(_uid(user), complaint_id, payload.agree, payload.note)


@router.post("/quality/{incident_id}/vendor-check")
async def vendor_check_quality(incident_id: str, payload: QualityCheckIn,
                         conn=Depends(get_db_conn), user=Depends(_vendor)):
    return _svc(conn).vendor_check_quality(
        _uid(user), incident_id, payload.agree, payload.check, payload.note)
