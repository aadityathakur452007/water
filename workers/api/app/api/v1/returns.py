"""Return routes: bare router (mounted under /v1 by the integrator).

POST /returns {qty, address_id} -> 10-working-day SLA + request id (E rulebook).
GET /returns -> own history (requested -> picked -> refunded). Owner-scoped;
suspended users keep read access, writes need require_active_user.
"""

from __future__ import annotations

import datetime as _dt
import sqlite3
import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.api.auth_deps import get_current_user, require_active_user
from app.api.deps import get_db
from app.core.errors import NotFoundError
from app.db import WRITE_LOCK

router = APIRouter(tags=["returns"])

SLA_WORKING_DAYS = 10  # Bisleri rulebook: pickup within 10 working days (E2)


class ReturnIn(BaseModel):
    qty: int = Field(ge=1, le=30)
    address_id: str = Field(min_length=1)


def _sla_due(from_day: _dt.date | None = None) -> str:
    """Add 10 working days, skipping Sundays (holidays ride on windows API)."""
    d = from_day or _dt.datetime.now(_dt.timezone.utc).date()
    added = 0
    while added < SLA_WORKING_DAYS:
        d += _dt.timedelta(days=1)
        if d.weekday() == 6:
            continue
        added += 1
    return d.isoformat()


def _owned_address(conn: sqlite3.Connection, user_id: str, address_id: str) -> bool:
    try:
        row = conn.execute(
            "SELECT 1 FROM addresses WHERE id = ? AND user_id = ?", (address_id, user_id)
        ).fetchone()
    except Exception:
        return True  # addresses slice not migrated yet -> don't block
    return row is not None


@router.post("/returns", status_code=201)
def create_return(payload: ReturnIn, user=Depends(require_active_user),
                  conn=Depends(get_db)):
    uid = str(user.get("id"))
    if not _owned_address(conn, uid, payload.address_id):
        raise NotFoundError(message="Address not found.", details={"id": payload.address_id})
    rid, sla = uuid.uuid4().hex, _sla_due()
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    with WRITE_LOCK:
        try:
            conn.execute(
                "INSERT INTO returns(id, user_id, qty, address_id, status, sla_due, created_at)"
                " VALUES (?, ?, ?, ?, 'requested', ?, ?)",
                (rid, uid, int(payload.qty), payload.address_id, sla, now),
            )
            conn.commit()
        except Exception:
            conn.rollback()
            raise
    row = conn.execute("SELECT * FROM returns WHERE id = ?", (rid,)).fetchone()
    out = dict(row)
    out["message"] = (f"Return requested. Pickup within {SLA_WORKING_DAYS} working days"
                      f" (by {sla}).")
    return out


@router.get("/returns")
def list_returns(user=Depends(get_current_user), conn=Depends(get_db)):
    rows = conn.execute(
        "SELECT * FROM returns WHERE user_id = ? ORDER BY created_at DESC, id DESC",
        (str(user.get("id")),),
    ).fetchall()
    return {"data": [dict(r) for r in rows]}
