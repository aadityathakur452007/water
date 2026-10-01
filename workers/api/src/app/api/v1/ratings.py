"""Rating route: bare router (mounted under /v1 by the integrator).

Created because no rating endpoint exists elsewhere (orders.py has only
create/list/detail/cancel/reschedule — verified 2026-09-29). POST
/orders/{id}/rating {stars 1..5}, once per delivered order; stars <= 3
returns a complaint shortcut (Finder-A15: UR-19/FR-13).
"""

from __future__ import annotations

import datetime as _dt
import sqlite3

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.api.auth_deps import require_active_user
from app.api.deps import get_db_conn
from app.core.errors import AppError, ConflictError, NotFoundError
from app.db import WRITE_LOCK

router = APIRouter(tags=["ratings"])


class AlreadyRatedError(AppError):
    code = "ALREADY_RATED"
    status_code = 409


class RatingIn(BaseModel):
    stars: int = Field(ge=1, le=5)  # out-of-range -> 400 VALIDATION at the boundary


@router.post("/orders/{order_id}/rating", status_code=201)
async def rate_order(order_id: str, payload: RatingIn, user=Depends(require_active_user),
               conn=Depends(get_db_conn)):
    uid = str(user.get("id"))
    order = (await conn.execute("SELECT id, user_id, state FROM orders WHERE id = ?",
                         (order_id,))).fetchone()
    if order is None or str(order["user_id"]) != uid:
        raise NotFoundError(message="Order not found.", details={"id": order_id})
    if str(order["state"]) != "delivered":
        raise ConflictError(message="Only delivered orders can be rated.",
                            details={"state": order["state"]})
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    with WRITE_LOCK:
        try:
            await conn.execute(
                "INSERT INTO ratings(order_id, user_id, stars, created_at)"
                " VALUES (?, ?, ?, ?)",
                (order_id, uid, int(payload.stars), now),
            )
            conn.commit()
        except sqlite3.IntegrityError as e:
            conn.rollback()
            raise AlreadyRatedError(message="Order already rated.",
                                    details={"order_id": order_id}) from e
        except Exception:
            conn.rollback()
            raise
    return {"order_id": order_id, "stars": int(payload.stars),
            "complaint_shortcut": int(payload.stars) <= 3}
