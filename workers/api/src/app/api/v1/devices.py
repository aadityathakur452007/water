"""Device routes: bare router (mounted under /v1 by the integrator).

POST /devices {device_id, fcm_token, platform} — upsert per user+device.
DELETE /devices {device_id} — own device only (logout/deletes never touch
another device, C8). Owner scoping makes cross-user deletes 404, no oracle.
"""

from __future__ import annotations

import datetime as _dt

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.api.auth_deps import get_current_user, require_active_user
from app.api.deps import get_db_conn
from app.core.errors import NotFoundError
from app.db import WRITE_LOCK

router = APIRouter(tags=["devices"])


class DeviceIn(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)
    fcm_token: str = Field(min_length=1, max_length=512)
    platform: str = Field(default="", max_length=16)


class DeviceDelIn(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)


@router.post("/devices", status_code=201)
async def upsert_device(payload: DeviceIn, user=Depends(require_active_user),
                  conn=Depends(get_db_conn)):
    uid = str(user.get("id"))
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    with WRITE_LOCK:
        try:
            await conn.execute(
                "INSERT INTO device_tokens(user_id, device_id, token, platform, updated_at)"
                " VALUES (?, ?, ?, ?, ?)"
                " ON CONFLICT(user_id, device_id) DO UPDATE SET token = excluded.token,"
                " platform = excluded.platform, updated_at = excluded.updated_at",
                (uid, payload.device_id, payload.fcm_token, payload.platform, now),
            )
            conn.commit()
        except Exception:
            conn.rollback()
            raise
    return {"device_id": payload.device_id, "updated": True}


@router.delete("/devices")
async def delete_device(payload: DeviceDelIn, user=Depends(get_current_user),
                  conn=Depends(get_db_conn)):
    uid = str(user.get("id"))
    with WRITE_LOCK:
        try:
            cur = await conn.execute(
                "DELETE FROM device_tokens WHERE user_id = ? AND device_id = ?",
                (uid, payload.device_id),
            )
            conn.commit()
        except Exception:
            conn.rollback()
            raise
    if cur.rowcount == 0:
        raise NotFoundError(message="Device not found.", details={"device_id": payload.device_id})
    return {"device_id": payload.device_id, "deleted": True}
