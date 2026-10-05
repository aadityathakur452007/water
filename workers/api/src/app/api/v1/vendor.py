"""Vendor router: thin HTTP boundary (parse, validate DTO, map to service).

Bare paths — mounted under ``/v1`` by the integrator (this slice must NOT touch
app/main.py). Every route is behind ``require_role('vendor')`` (ssdlc: authz on
every endpoint, actor from the session, never the body).
"""

from fastapi import APIRouter, Depends, Header
from pydantic import BaseModel, Field
from typing import Any

from app.api.auth_deps import require_role
from app.api.deps import get_db_conn
from app.core.errors import ValidationError
from app.services.vendor_service import VendorService

router = APIRouter(tags=["vendor"])

_vendor = require_role("vendor")  # module-level so tests can override this exact dep


def _require_idem(idem: str | None) -> str:
    if not idem or not idem.strip():
        raise ValidationError(message="Idempotency-Key header required.", details={})
    return idem.strip()


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


class ProfileIn(BaseModel):
    name: str | None = Field(default=None, max_length=500)
    phone: str | None = Field(default=None, max_length=500)
    address: str | None = Field(default=None, max_length=500)
    hours: str | None = Field(default=None, max_length=500)


class SlotsIn(BaseModel):
    slots: dict[str, bool]


@router.post("/vendor/duty")
async def set_duty(payload: DutyIn, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).duty(_uid(user), payload.on)


@router.get("/vendor/routes/today")
async def routes_today(date: str | None = None, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).today_route(_uid(user), date)


# 015: placed pool for the Pull button (simple, no geo/auto-assign).
# 016: zone-scoped — vendor sees only their zones' placed orders.
@router.get("/vendor/placed")
async def placed_orders(limit: int = 20, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).placed_pool(_uid(user), limit)


# Phase 2: the Pull button made real — self-assign one zone-scoped placed
# order (placed→accepted→picked→packed→assigned, route+stop created, PoD
# code minted). Zone/capacity gates inside are the pool enforcement.
@router.post("/vendor/placed/{order_id}/accept")
async def accept_placed_order(order_id: str, conn=Depends(get_db_conn), user=Depends(_vendor)):
    from app.services.dispatch_service import vendor_accept_order  # noqa: PLC0415 (lazy, cycle-safe)

    return await vendor_accept_order(conn, order_id, _uid(user))


@router.get("/vendor/stops/{stop_id}")
async def get_stop(stop_id: str, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).get_stop(_uid(user), stop_id)


@router.post("/vendor/stops/{stop_id}/triple")
async def commit_triple(stop_id: str, payload: TripleIn,
                 conn=Depends(get_db_conn), user=Depends(_vendor),
                 idem: str | None = Header(default=None, alias="Idempotency-Key")):
    return await _svc(conn).triple_commit(
        _uid(user), stop_id, payload.model_dump(mode="json"), _require_idem(idem))


@router.post("/vendor/stops/{stop_id}/pod")
async def complete_pod(stop_id: str, payload: PodIn, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).pod_complete(_uid(user), stop_id, payload.model_dump(mode="json"))


class CashIn(BaseModel):
    amount: int = Field(ge=0)


# F2: doorstep cash → money truth (mark_paid_cash + dues reconcile).
# Dedupe is deterministic on (stop, amount) server-side — no client key.
@router.post("/vendor/stops/{stop_id}/cash")
async def post_cash(stop_id: str, payload: CashIn,
             conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).cash_post(_uid(user), stop_id, int(payload.amount))


@router.post("/vendor/sync")
async def sync_batch(payload: SyncIn, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).sync_batch(_uid(user), payload.items)


@router.get("/vendor/earnings")
async def earnings(shift: str | None = None, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).earnings(_uid(user), shift)


@router.get("/vendor/profile")
async def get_profile(conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).profile_get(_uid(user))


@router.patch("/vendor/profile")
async def save_profile(payload: ProfileIn, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).profile_save(
        _uid(user), payload.model_dump(exclude_unset=True, mode="json"))


@router.get("/vendor/slots")
async def get_slots(conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).slots_get(_uid(user))


@router.put("/vendor/slots")
async def set_slots(payload: SlotsIn, conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).slots_set(_uid(user), payload.slots)


@router.get("/vendor/customers")
async def vendor_customers(date: str | None = None,
                     conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).today_customers(_uid(user), date)


@router.get("/vendor/complaints")
async def vendor_complaints(conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).vendor_complaints(_uid(user))


@router.get("/vendor/quality")
async def vendor_quality(conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).vendor_quality(_uid(user))


@router.post("/complaints/{complaint_id}/verify")
async def verify_complaint(complaint_id: str, payload: VerifyIn,
                     conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).verify_complaint(_uid(user), complaint_id, payload.agree, payload.note)


@router.post("/quality/{incident_id}/vendor-check")
async def vendor_check_quality(incident_id: str, payload: QualityCheckIn,
                         conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).vendor_check_quality(
        _uid(user), incident_id, payload.agree, payload.check, payload.note)


# 027 RBAC: read-only own payouts + custody (approve stays admin-only).
@router.get("/vendor/payouts")
async def vendor_payouts(conn=Depends(get_db_conn), user=Depends(_vendor)):
    return await _svc(conn).payouts_for_vendor(_uid(user))
