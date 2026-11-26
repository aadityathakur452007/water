from __future__ import annotations

import json

from fastapi import Depends
from pydantic import BaseModel, Field

from app.api.auth_deps import get_current_user, require_role  # noqa: F401
from app.core.db_utils import write_audit
from app.core.http_utils import user_id as _uid
from app.core.time_utils import utc_now_iso as _now

Admin = Depends(require_role("admin"))

__all__ = [
    "Admin",
    "_audit",
    "_cursor",
    "_now",
    "_uid",
    "AssignIn",
    "ReassignIn",
    "CancelOverrideIn",
    "RejectIn",
    "VendorCreateIn",
    "CapacityPatchIn",
    "ZoneCreateIn",
    "ZonePatchIn",
    "LedgerAdjustIn",
    "ConfigPatchIn",
    "ComplaintResolveIn",
    "QualityDecisionIn",
    "WriteOffIn",
    "AttachIn",
    "DetachIn",
    "HoldIn",
    "SuspendIn",
    "PasswordResetIn",
    "AssignUserVendorIn",
    "ReassignCustomersIn",
]


async def _audit(conn, user, action: str, entity: str, entity_id: str,
           before: object = "", after: object = "") -> None:
    await write_audit(conn, actor=_uid(user), action=action, entity=entity, entity_id=entity_id,
                before=before if isinstance(before, str) else json.dumps(before, default=str),
                after=after if isinstance(after, str) else json.dumps(after, default=str))


# -- DTOs (wire contracts, co-located like auth.py) ---------------------------

class AssignIn(BaseModel):
    vendor_id: str = Field(min_length=1)


class ReassignIn(BaseModel):
    vendor_id: str = Field(min_length=1)
    reason: str = Field(default="", max_length=500)


class CancelOverrideIn(BaseModel):
    reason: str = Field(default="admin override", max_length=500)


class RejectIn(BaseModel):
    reason: str = Field(min_length=1, max_length=500)


class VendorCreateIn(BaseModel):
    phone: str = Field(min_length=10, max_length=16)
    name: str = Field(min_length=1, max_length=80)
    zone_id: str = Field(min_length=1)
    kyc_note: str = Field(default="", max_length=500)
    max_stops: int | None = Field(default=None, ge=1, le=500)
    max_jars: int | None = Field(default=None, ge=1, le=5000)
    auto_verify: bool = False


class CapacityPatchIn(BaseModel):
    max_stops: int | None = Field(default=None, ge=1, le=500)
    max_jars: int | None = Field(default=None, ge=1, le=5000)
    per_stop_fee: int | None = Field(default=None, ge=0)


class ZoneCreateIn(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    pincodes: str = Field(default="", max_length=500)
    polygon: str | None = Field(default=None, max_length=5000)
    id: str | None = Field(default=None, max_length=50)


class ZonePatchIn(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=100)
    pincodes: str | None = Field(default=None, max_length=500)
    active: int | None = Field(default=None, ge=0, le=1)


class LedgerAdjustIn(BaseModel):
    d_held: int = 0
    d_deposit: int = 0
    d_dues: int = 0
    reason: str = Field(min_length=1, max_length=500)


class ConfigPatchIn(BaseModel):
    key: str = Field(min_length=1, max_length=128)
    value: str = Field(max_length=4096)


class ComplaintResolveIn(BaseModel):
    action: str = Field(pattern=r"^(refund|redelivery|note)$")
    note: str = Field(default="", max_length=500)


class QualityDecisionIn(BaseModel):
    resolution: str = Field(default="", max_length=500)


class WriteOffIn(BaseModel):
    reason: str = Field(min_length=1, max_length=500)


class AttachIn(BaseModel):
    vendor_id: str = Field(min_length=1)
    priority: int = Field(default=0, ge=0, le=100)


class DetachIn(BaseModel):
    reason: str = Field(default="", max_length=500)


class HoldIn(BaseModel):
    reason: str = Field(default="", max_length=500)


class SuspendIn(BaseModel):
    reason: str = Field(min_length=3, max_length=500)
    level: str = Field(default="suspend", pattern=r"^(restrict|suspend)$")


class PasswordResetIn(BaseModel):
    new_password: str = Field(min_length=8, max_length=128)


class AssignUserVendorIn(BaseModel):
    vendor_id: str | None = None


class ReassignCustomersIn(BaseModel):
    new_vendor_id: str = Field(min_length=1)
    reason: str = Field(default="Vendor reassignment", max_length=500)



def _cursor(value: str) -> int:
    try:
        n = int(value)
    except (TypeError, ValueError):
        return 0
    return n if n > 0 else 0

