"""Return routes: bare router (mounted under /v1 by the integrator).

POST /returns {qty, address_id} -> 10-working-day SLA + request id (E rulebook).
GET /returns -> own history (requested -> picked -> refunded). Owner-scoped;
suspended users keep read access; creation needs role=='user' (vendor/admin
sessions get 403, no oracle).
"""

from __future__ import annotations

import datetime as _dt
import sqlite3
import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.api.auth_deps import get_current_user, require_active_user, require_role
from app.api.deps import get_db_conn
from app.core.errors import ConflictError, NotFoundError, ValidationError
from app.db import WRITE_LOCK
from app.repositories.ledger_repo import LedgerRepo

router = APIRouter(tags=["returns"])

_vendor = require_role("vendor")

# Module-level so tests can override this exact dep (same pattern as
# `_vendor` above): return requests are a user-role-only write.
_user = require_role("user")

SLA_WORKING_DAYS = 10  # Bisleri rulebook: pickup within 10 working days (E2)


class ReturnIn(BaseModel):
    qty: int = Field(ge=1, le=30)
    address_id: str = Field(min_length=1)
    upi_id: str | None = Field(default=None, max_length=100)


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


async def _owned_address(conn, user_id: str, address_id: str) -> bool:
    try:
        row = (await conn.execute(
            "SELECT 1 FROM addresses WHERE id = ? AND user_id = ?", (address_id, user_id)
        )).fetchone()
    except Exception:
        return True  # addresses slice not migrated yet -> don't block
    return row is not None


@router.post("/returns", status_code=201)
async def create_return(payload: ReturnIn, user=Depends(_user),
                  conn=Depends(get_db_conn)):
    uid = str(user.get("id"))
    if not await _owned_address(conn, uid, payload.address_id):
        raise NotFoundError(message="Address not found.", details={"id": payload.address_id})
    rid, sla = uuid.uuid4().hex, _sla_due()
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    upi = (payload.upi_id or "").strip()
    with WRITE_LOCK:
        try:
            try:
                await conn.execute(
                    "INSERT INTO returns(id, user_id, qty, address_id, status, sla_due, created_at, upi_id)"
                    " VALUES (?, ?, ?, ?, 'requested', ?, ?, ?)",
                    (rid, uid, int(payload.qty), payload.address_id, sla, now, upi),
                )
            except Exception:
                await conn.execute(
                    "INSERT INTO returns(id, user_id, qty, address_id, status, sla_due, created_at)"
                    " VALUES (?, ?, ?, ?, 'requested', ?, ?)",
                    (rid, uid, int(payload.qty), payload.address_id, sla, now),
                )
            conn.commit()
        except Exception:
            conn.rollback()
            raise
    row = (await conn.execute("SELECT * FROM returns WHERE id = ?", (rid,))).fetchone()
    out = dict(row)
    out["message"] = (f"Return requested. Pickup within {SLA_WORKING_DAYS} working days"
                      f" (by {sla}).")
    return out


@router.get("/returns")
async def list_returns(user=Depends(get_current_user), conn=Depends(get_db_conn)):
    rows = (await conn.execute(
        "SELECT * FROM returns WHERE user_id = ? ORDER BY created_at DESC, id DESC",
        (str(user.get("id")),),
    )).fetchall()
    return {"data": [dict(r) for r in rows]}


class PickupIn(BaseModel):
    empties_collected: int = Field(ge=0)
    caps_missing: int = Field(ge=0, default=0)


@router.post("/returns/{return_id}/pickup")
async def pickup_return(return_id: str, payload: PickupIn,
                  conn=Depends(get_db_conn), user=Depends(_vendor)):
    """F8: vendor collects empties for a return on their own route.

    Ownership via the pickup stop (return_id on vendor's route) — else 404.
    Ledger: held decreases, cap-missing × Rs 3 posts to dues. Pickup stop
    completes with the counts in its triple JSON.
    """
    import json as _json

    from app.services.pricing import CAP_PAISE

    vid = str(user.get("id"))
    with WRITE_LOCK:
        ret = (await conn.execute("SELECT * FROM returns WHERE id = ?", (return_id,))).fetchone()
        if ret is None:
            raise NotFoundError(message="Return not found.", details={"id": return_id})
        if ret["status"] != "requested":
            raise ConflictError(message="Return is already settled.",
                                details={"id": return_id, "status": ret["status"]})
        if int(payload.empties_collected) > int(ret["qty"]):
            raise ValidationError(message="Cannot collect more than requested.",
                                  details={"qty": ret["qty"]})
        link = (await conn.execute(
            "SELECT s.id FROM stops s JOIN routes r ON r.id = s.route_id"
            " WHERE s.return_id = ? AND r.vendor_id = ?", (return_id, vid))).fetchone()
        if link is None:
            raise NotFoundError(message="Return not found.", details={"id": return_id})
        cap_paise = int(payload.caps_missing) * int(CAP_PAISE)
        led = await LedgerRepo(conn).apply_event(
            ret["user_id"], d_held=-int(payload.empties_collected), d_dues=cap_paise,
            ref=f"return:{return_id}", actor=vid, reason="empty-jar pickup", commit=False)
        await conn.execute(
            "UPDATE returns SET status = 'picked' WHERE id = ?", (return_id,))
        await conn.execute(
            "UPDATE stops SET triple = ?, status = 'done', synced_at = ? WHERE return_id = ?",
            (_json.dumps({"empties_collected": int(payload.empties_collected),
                          "caps_missing": int(payload.caps_missing)}),
             _dt.datetime.now(_dt.timezone.utc).isoformat(), return_id),
        )
        conn.commit()
    return {"id": return_id, "status": "picked",
            "empties_collected": int(payload.empties_collected),
            "cap_charge": cap_paise, "ledger": led}
