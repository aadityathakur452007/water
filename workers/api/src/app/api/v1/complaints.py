"""Complaint routes: bare router (mounted under /v1 by the integrator).

POST /complaints {order_id, reason_code (11-code enum), text <=500}:
24h window for water_quality, 3 days general (E2); photos rejected in v1
(400 PHOTOS_V2 — no object storage, ADR-017). GET shows disagreements as
"under-review" (vendor verification protocol, §14.3). Owner-scoped.
"""

from __future__ import annotations

import datetime as _dt
import sqlite3
import uuid
from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.api.auth_deps import get_current_user, require_active_user
from app.api.deps import get_db
from app.core.errors import AppError, ConflictError, NotFoundError
from app.db import WRITE_LOCK

router = APIRouter(tags=["complaints"])

# §14.3 reason-code catalog (v1: words + vendor eyes, NO photos).
ReasonCode = Literal[
    "water_quality", "damaged_jar", "wrong_item", "short_delivery",
    "late_delivery", "deposit_dispute", "cap_dispute", "duplicate_app_order",
    "not_needed_today", "vendor_behavior", "other",
]

QUALITY_WINDOW_H = 24  # water_quality: 24h from delivery
GENERAL_WINDOW_H = 72  # everything else: 3 days (E2)


class PhotosV2Error(AppError):
    code = "PHOTOS_V2"
    status_code = 400


class DisputeExpiredError(AppError):
    code = "DISPUTE_EXPIRED"
    status_code = 422


class ComplaintIn(BaseModel):
    order_id: str = Field(min_length=1)
    reason_code: ReasonCode
    text: str = Field(default="", max_length=500)
    photos: list[str] | None = None  # accepted only to reject with PHOTOS_V2


def _now() -> _dt.datetime:
    return _dt.datetime.now(_dt.timezone.utc)


def _delivered_at(conn: sqlite3.Connection, order_id: str) -> _dt.datetime | None:
    """Delivery instant from the order event chain (server truth, not client)."""
    try:
        row = conn.execute(
            "SELECT created_at FROM order_events WHERE order_id = ? AND to_state = 'delivered'"
            " ORDER BY created_at DESC LIMIT 1",
            (order_id,),
        ).fetchone()
    except Exception:
        return None
    if row is None:
        return None
    try:
        dt = _dt.datetime.fromisoformat(row["created_at"])
    except (ValueError, TypeError):
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=_dt.timezone.utc)
    return dt


def _display(row: dict) -> dict:
    out = dict(row)
    if out.get("vendor_agree") == 0 and out.get("status") != "resolved":
        out["status"] = "under_review"  # frozen statements, 48h admin triage (§14.3)
    return out


@router.post("/complaints", status_code=201)
def create_complaint(payload: ComplaintIn, user=Depends(require_active_user),
                     conn=Depends(get_db)):
    if payload.photos:  # v1 has no object storage — reject loudly, don't swallow
        raise PhotosV2Error(
            message="Photo upload arrives in v2. Describe the issue in words.",
            details={"reason_code": payload.reason_code},
        )
    uid = str(user.get("id"))
    order = conn.execute("SELECT id, user_id FROM orders WHERE id = ?",
                         (payload.order_id,)).fetchone()
    if order is None or str(order["user_id"]) != uid:
        raise NotFoundError(message="Order not found.", details={"id": payload.order_id})
    delivered = _delivered_at(conn, payload.order_id)
    if delivered is None:
        raise ConflictError(message="Only delivered orders can be complained about.",
                            details={"order_id": payload.order_id})
    window_h = QUALITY_WINDOW_H if payload.reason_code == "water_quality" else GENERAL_WINDOW_H
    if _now() - delivered > _dt.timedelta(hours=window_h):
        raise DisputeExpiredError(
            message="Complaint window closed. Call support — we will still help.",
            details={"order_id": payload.order_id, "window_h": window_h},
        )
    cid = uuid.uuid4().hex
    now = _now().isoformat()
    with WRITE_LOCK:
        try:
            conn.execute(
                "INSERT INTO complaints(id, order_id, user_id, reason_code, text, photos,"
                " vendor_agree, vendor_note, status, created_at, resolved_at)"
                " VALUES (?, ?, ?, ?, ?, NULL, NULL, NULL, 'open', ?, NULL)",
                (cid, payload.order_id, uid, payload.reason_code,
                 payload.text.strip(), now),
            )
            conn.commit()
        except Exception:
            conn.rollback()
            raise
    row = conn.execute("SELECT * FROM complaints WHERE id = ?", (cid,)).fetchone()
    return _display(dict(row))


@router.get("/complaints")
def list_complaints(user=Depends(get_current_user), conn=Depends(get_db)):
    rows = conn.execute(
        "SELECT * FROM complaints WHERE user_id = ? ORDER BY created_at DESC, id DESC",
        (str(user.get("id")),),
    ).fetchall()
    return {"data": [_display(dict(r)) for r in rows]}
