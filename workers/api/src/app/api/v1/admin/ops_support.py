from __future__ import annotations

import datetime as _dt
import uuid

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.api.auth_deps import get_current_user, require_role  # noqa: F401
from app.api.deps import get_db_conn
from app.core.errors import ConflictError, NotFoundError, ValidationError
from app.core.http_utils import user_id as _uid
from app.core.state_machines import validate_return_transition
from app.core.time_utils import utc_now_iso as _now
from app.db import WRITE_LOCK
from app.repositories.ledger_repo import LedgerRepo
from app.api.v1.admin._common import *  # noqa: F401, F403

router = APIRouter(tags=["admin"])

@router.get("/admin/returns")
async def returns_queue(status: str | None = Query(default=None), conn=Depends(get_db_conn), user=Admin):
    args: list[object] = []
    where = ""
    if status:
        where = "WHERE status = ?"
        args.append(status)
    rows = await conn.execute(
        f"SELECT * FROM returns {where} ORDER BY created_at DESC LIMIT 200", (*args,))  # noqa: S608
    counts = (await conn.execute(
        "SELECT status, COUNT(*) c FROM returns GROUP BY status")).fetchall()
    return {"data": [dict(r) for r in rows.fetchall()],
            "counts": {str(r["status"]): int(r["c"]) for r in counts}}


class ReturnAssignIn(BaseModel):
    vendor_id: str = Field(min_length=1)
    date: str = Field(default="")


@router.post("/admin/returns/{return_id}/assign")
async def return_assign(return_id: str, payload: ReturnAssignIn,
                  conn=Depends(get_db_conn), user=Admin):
    """F8: queue a pickup stop for a requested return on a vendor's route."""
    import uuid as _uuid

    from app.services.dispatch_service import route_for_vendor

    with WRITE_LOCK:
        ret = (await conn.execute("SELECT * FROM returns WHERE id = ?", (return_id,))).fetchone()
        if ret is None:
            raise NotFoundError(message="Return not found.", details={"id": return_id})
        validate_return_transition(ret["status"], "assigned")
        dup = (await conn.execute("SELECT id FROM stops WHERE return_id = ?",
                            (return_id,))).fetchone()
        if dup is not None:
            raise ConflictError(message="Return is already assigned to a route.",
                                details={"id": return_id, "stop_id": dup["id"]})
        day = payload.date.strip() or _dt.datetime.now(_dt.timezone.utc).date().isoformat()
        route_id = await route_for_vendor(conn, payload.vendor_id, day)
        seq = (await conn.execute("SELECT COALESCE(MAX(seq), -1) m FROM stops WHERE route_id = ?",
                            (route_id,))).fetchone()["m"] + 1
        sid = _uuid.uuid4().hex
        await conn.execute(
            "INSERT INTO stops(id, route_id, return_id, customer_id, seq,"
            " fulls_exp, empties_exp, version, status)"
            " VALUES (?, ?, ?, ?, ?, 0, ?, 1, 'pending')",
            (sid, route_id, return_id, ret["user_id"], int(seq), int(ret["qty"])),
        )
        await _audit(conn, user, "return.assign", "returns", return_id, "",
               {"route_id": route_id, "vendor_id": payload.vendor_id})
        conn.commit()
    return {"id": return_id, "stop_id": sid, "route_id": route_id, "vendor_id": payload.vendor_id}


class ReturnRefundIn(BaseModel):
    method: str = Field(pattern=r"^(upi|manual)$")
    qty: int = Field(ge=1)


@router.post("/admin/returns/{return_id}/refund")
async def return_refund(return_id: str, payload: ReturnRefundIn,
                  conn=Depends(get_db_conn), user=Admin):
    """F8: refund deposit for collected empties (picked only, audited)."""
    from app.api.deps import get_settings

    with WRITE_LOCK:
        ret = (await conn.execute("SELECT * FROM returns WHERE id = ?", (return_id,))).fetchone()
        if ret is None:
            raise NotFoundError(message="Return not found.", details={"id": return_id})
        validate_return_transition(ret["status"], "refunded")
        if int(payload.qty) > int(ret["qty"]):
            raise ValidationError(message="Refund qty exceeds requested.",
                                  details={"qty": ret["qty"]})
        rate = int(get_settings().deposit_per_jar_paise) or 15000
        after = await LedgerRepo(conn).apply_event(
            ret["user_id"], d_deposit=-(int(payload.qty) * rate),
            ref=f"return-refund:{return_id}", actor=_uid(user),
            reason=f"deposit refund via {payload.method}", commit=False)
        await conn.execute("UPDATE returns SET status = 'refunded' WHERE id = ?", (return_id,))
        await _audit(conn, user, "return.refund", "returns", return_id, dict(ret),
               {"qty": int(payload.qty), "method": payload.method})
        conn.commit()
    return {"id": return_id, "status": "refunded",
            "refunded": int(payload.qty) * rate, "ledger": after}


@router.get("/admin/complaints")
async def complaints_queue(conn=Depends(get_db_conn), user=Admin):
    rows = (await conn.execute("SELECT * FROM complaints ORDER BY created_at DESC LIMIT 200")).fetchall()
    counts = (await conn.execute(
        "SELECT status, COUNT(*) c FROM complaints GROUP BY status")).fetchall()
    return {"data": [dict(r) for r in rows],
            "counts": {str(r["status"]): int(r["c"]) for r in counts}}


@router.post("/admin/complaints/{complaint_id}/resolve")
async def complaint_resolve(complaint_id: str, payload: ComplaintResolveIn,
                      conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        row = (await conn.execute("SELECT * FROM complaints WHERE id = ?", (complaint_id,))).fetchone()
        if row is None:
            raise NotFoundError(message="Complaint not found.", details={"id": complaint_id})
        before = dict(row)
        await conn.execute("UPDATE complaints SET status = 'resolved', resolved_at = ? WHERE id = ?",
                     (_now(), complaint_id))
        await _audit(conn, user, f"complaint.resolve:{payload.action}", "complaints",
               complaint_id, before, {"action": payload.action, "note": payload.note})
        conn.commit()
    return {"complaint_id": complaint_id, "status": "resolved", "action": payload.action}


@router.get("/admin/quality")
async def quality_queue(status: str | None = Query(default=None), conn=Depends(get_db_conn), user=Admin):
    args: list[object] = []
    where = ""
    if status:
        where = "WHERE status = ?"
        args.append(status)
    rows = await conn.execute(
        f"SELECT * FROM quality_incidents {where} ORDER BY created_at DESC LIMIT 200",  # noqa: S608
        (*args,))
    counts = (await conn.execute(
        "SELECT status, COUNT(*) c FROM quality_incidents GROUP BY status")).fetchall()
    return {"data": [dict(r) for r in rows.fetchall()],
            "counts": {str(r["status"]): int(r["c"]) for r in counts}}


@router.post("/admin/quality/{incident_id}/confirm")
async def quality_confirm(incident_id: str, payload: QualityDecisionIn,
                    conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        row = (await conn.execute("SELECT * FROM quality_incidents WHERE id = ?", (incident_id,))).fetchone()
        if row is None:
            raise NotFoundError(message="Quality incident not found.", details={"id": incident_id})
        inc = dict(row)
        await conn.execute("UPDATE quality_incidents SET status = 'confirmed', resolution = ? WHERE id = ?",
                     (payload.resolution, incident_id))
        strike_id = uuid.uuid4().hex
        await conn.execute(
            "INSERT INTO strikes(id, subject_id, kind, severity, ref_type, ref_id, note,"
            " created_by, created_at) VALUES (?, ?, 'quality', 1, 'quality_incidents', ?, ?, ?, ?)",
            (strike_id, inc["vendor_id"], incident_id, payload.resolution, _uid(user), _now()),
        )
        await _audit(conn, user, "quality.confirm", "quality_incidents", incident_id, inc,
               {"status": "confirmed", "strike_id": strike_id})
        conn.commit()
    return {"incident_id": incident_id, "status": "confirmed", "strike_id": strike_id}


@router.post("/admin/quality/{incident_id}/reject")
async def quality_reject(incident_id: str, payload: QualityDecisionIn,
                   conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        row = (await conn.execute("SELECT * FROM quality_incidents WHERE id = ?", (incident_id,))).fetchone()
        if row is None:
            raise NotFoundError(message="Quality incident not found.", details={"id": incident_id})
        await conn.execute("UPDATE quality_incidents SET status = 'rejected', resolution = ? WHERE id = ?",
                     (payload.resolution, incident_id))
        await _audit(conn, user, "quality.reject", "quality_incidents", incident_id,
               dict(row), {"status": "rejected"})
        conn.commit()
    return {"incident_id": incident_id, "status": "rejected"}


# -- strikes -------------------------------------------------------------------

@router.get("/admin/strikes")
async def strikes_list(conn=Depends(get_db_conn), user=Admin):
    rows = (await conn.execute("SELECT * FROM strikes ORDER BY created_at DESC LIMIT 200")).fetchall()
    counts = (await conn.execute(
        "SELECT CASE WHEN cleared_at IS NULL THEN 'open' ELSE 'cleared' END AS status,"
        " COUNT(*) c FROM strikes GROUP BY status")).fetchall()
    return {"data": [dict(r) for r in rows],
            "counts": {str(r["status"]): int(r["c"]) for r in counts}}


@router.post("/admin/strikes/{strike_id}/clear")
async def strike_clear(strike_id: str, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        row = (await conn.execute("SELECT * FROM strikes WHERE id = ?", (strike_id,))).fetchone()
        if row is None:
            raise NotFoundError(message="Strike not found.", details={"id": strike_id})
        await conn.execute("UPDATE strikes SET cleared_by = ?, cleared_at = ? WHERE id = ?",
                     (_uid(user), _now(), strike_id))
        await _audit(conn, user, "strike.clear", "strikes", strike_id, dict(row), {"cleared": True})
        conn.commit()
    return {"strike_id": strike_id, "cleared": True}


# -- config / audit / metrics ---------------------------------------------------


class LeaveReviewIn(BaseModel):
    action: str = Field(pattern=r"^(approved|rejected)$")
    cover_vendor_id: str | None = Field(default=None)
    note: str = Field(default="", max_length=500)


@router.get("/admin/vendor-leaves")
async def list_all_vendor_leaves(
    status: str | None = Query(default=None),
    conn=Depends(get_db_conn),
    user=Admin,
):
    where = "WHERE vl.status = ?" if status else ""
    args = (status,) if status else ()
    rows = (await conn.execute(
        f"SELECT vl.*, u.name AS vendor_name, u.phone AS vendor_phone,"
        f" cu.name AS cover_name, cu.phone AS cover_phone"
        f" FROM vendor_leaves vl"
        f" JOIN users u ON u.id = vl.vendor_id"
        f" LEFT JOIN users cu ON cu.id = vl.cover_vendor_id"
        f" {where} ORDER BY vl.created_at DESC LIMIT 200",
        args,
    )).fetchall()
    return {"data": [dict(r) for r in rows]}


@router.post("/admin/vendor-leaves/{leave_id}/review")
async def review_vendor_leave(
    leave_id: str,
    payload: LeaveReviewIn,
    conn=Depends(get_db_conn),
    user=Admin,
):
    with WRITE_LOCK:
        leave = (await conn.execute("SELECT * FROM vendor_leaves WHERE id = ?", (leave_id,))).fetchone()
        if leave is None:
            raise NotFoundError(message="Leave request not found.", details={"id": leave_id})
        now = _now()
        cover_id = (payload.cover_vendor_id or "").strip() or None
        if payload.action == "approved" and cover_id:
            cov = (await conn.execute("SELECT id FROM users WHERE id = ?", (cover_id,))).fetchone()
            if cov is None:
                raise NotFoundError(message="Cover vendor not found.", details={"cover_vendor_id": cover_id})
        await conn.execute(
            "UPDATE vendor_leaves SET status = ?, cover_vendor_id = ?, reviewed_at = ?, reviewed_by = ?"
            " WHERE id = ?",
            (payload.action, cover_id, now, _uid(user), leave_id),
        )
        await _audit(conn, user, f"vendor_leave.{payload.action}", "vendor_leaves", leave_id,
                     dict(leave), {"action": payload.action, "cover_vendor_id": cover_id, "note": payload.note})
        conn.commit()
    row = (await conn.execute("SELECT * FROM vendor_leaves WHERE id = ?", (leave_id,))).fetchone()
    return dict(row)

