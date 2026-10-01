"""Admin router: dispatch + vendors + money + trust board (contract §4.11/§9/§11/§14).

Bare ``router`` (mounted under /v1 by the integrator — same pattern as
orders.py). EVERY route is behind ``require_role('admin')`` (ssdlc: wrong role
or suspended -> 403, no oracle). Actor id always := session user (H1); money in
paise; writes are single-transaction + audit_log on money/role/config changes.
Maker-checker refunds stay D1's job (slices own refunds); this file only queues
returns/complaints/quality decisions that create strikes/refund inputs.
"""

from __future__ import annotations

import datetime as _dt
import json
import sqlite3
import uuid

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.api.auth_deps import get_current_user, require_role  # noqa: F401 (re-export for test overrides)
from app.api.deps import get_db_conn
from app.core.errors import ConflictError, NotFoundError, ValidationError
from app.db import WRITE_LOCK
from app.repositories.admin_read_repo import AdminReadRepo
from app.repositories.ledger_repo import LedgerRepo
from app.repositories.order_repo import OrderRepo
from app.services.dispatch_service import (
    CustodyBlockedError,
    assign_order,
    auto_repool,
    ensure_profile,
    generate_routes,
    reassign_order,
    write_audit,
)

router = APIRouter(tags=["admin"])
Admin = Depends(require_role("admin"))


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat()


def _uid(user: object) -> str:
    return str(user.get("id") if isinstance(user, dict) else getattr(user, "id"))  # type: ignore[union-attr]


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


class VendorCreateIn(BaseModel):
    phone: str = Field(min_length=10, max_length=16)
    name: str = Field(min_length=1, max_length=80)
    zone_id: str = Field(min_length=1)
    kyc_note: str = Field(default="", max_length=500)


class CapacityPatchIn(BaseModel):
    max_stops: int | None = Field(default=None, ge=1, le=500)
    max_jars: int | None = Field(default=None, ge=1, le=5000)
    per_stop_fee: int | None = Field(default=None, ge=0)


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


# -- orders queue + dispatch --------------------------------------------------

@router.get("/admin/orders")
async def orders_queue(state: str | None = Query(default=None),
                 payment_status: str | None = Query(default=None),  # F-SA additive filter
                 query: str | None = Query(default=None, max_length=80),  # F-SA: user_id/phone search
                 limit: int = Query(default=50, ge=1, le=200),
                 cursor: str = Query(default=""),  # F-SA: rowid cursor (backward compatible)
                 conn=Depends(get_db_conn), user=Admin):
    args: list[object] = []
    clauses = []
    if state:
        clauses.append("state = ?")
        args.append(state)
    if payment_status:
        clauses.append("payment_status = ?")
        args.append(payment_status)
    if query:
        clauses.append("(user_id IN (SELECT id FROM users WHERE phone LIKE ?) OR user_id = ? OR id = ?)")
        like = f"%{query}%"
        args.extend([like, query, query])
    if cursor:
        try:
            clauses.append("rowid < ?")
            args.append(int(cursor))
        except ValueError:
            pass
    where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
    rows = (await conn.execute(
        f"SELECT id, user_id, n, e, total, payment_status, state, window_start, created_at,"  # noqa: S608
        f" rowid AS _rowid FROM orders {where} ORDER BY rowid DESC LIMIT ?",
        (*args, limit + 1),
    )).fetchall()
    data = [dict(r) for r in rows[:limit]]
    next_cursor = str(rows[limit]["_rowid"]) if len(rows) > limit else ""
    return {"data": data, "next_cursor": next_cursor}


@router.post("/admin/orders/{order_id}/assign")
async def admin_assign(order_id: str, payload: AssignIn, conn=Depends(get_db_conn), user=Admin):
    return await assign_order(conn, order_id, payload.vendor_id, {"id": _uid(user), "role": "admin"})


@router.post("/admin/orders/{order_id}/reassign")
async def admin_reassign(order_id: str, payload: ReassignIn, conn=Depends(get_db_conn), user=Admin):
    return await reassign_order(conn, order_id, payload.vendor_id,
                          {"id": _uid(user), "role": "admin"}, payload.reason)


@router.post("/admin/orders/{order_id}/cancel-override")
async def admin_cancel_override(order_id: str, payload: CancelOverrideIn,
                          conn=Depends(get_db_conn), user=Admin):
    outcome = await OrderRepo(conn).cancel_settle(order_id, {"id": _uid(user), "role": "admin"})
    with WRITE_LOCK:
        await _audit(conn, user, "order.cancel_override", "orders", order_id, "", payload.reason)
        conn.commit()
    return outcome


@router.post("/admin/routes/generate")
async def admin_generate_routes(payload: dict, conn=Depends(get_db_conn), user=Admin):
    try:
        date, zone_id = str(payload.get("date", "")), str(payload.get("zone", payload.get("zone_id", "")))
    except AttributeError:
        raise ValidationError(message="Body must be {date, zone}.", details={})
    return await generate_routes(conn, date, zone_id, {"id": _uid(user), "role": "admin"})


@router.post("/admin/vendors/{vendor_id}/repool")
async def admin_repool(vendor_id: str, conn=Depends(get_db_conn), user=Admin):
    return await auto_repool(conn, vendor_id, {"id": _uid(user), "role": "admin"})


# -- vendors ------------------------------------------------------------------

@router.post("/admin/vendors", status_code=201)
async def vendor_create(payload: VendorCreateIn, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        if (await conn.execute("SELECT id FROM users WHERE phone = ?", (payload.phone,))).fetchone():
            raise ConflictError(message="Phone already registered.", details={"phone": payload.phone})
        if (await conn.execute("SELECT id FROM zones WHERE id = ?", (payload.zone_id,))).fetchone() is None:
            raise NotFoundError(message="Zone not found.", details={"id": payload.zone_id})
        vid = uuid.uuid4().hex
        await conn.execute(
            "INSERT INTO users(id, phone, name, role, language, kyc_status, suspended, created_at)"
            " VALUES (?, ?, ?, 'user', 'hi', 'pending', 0, ?)",
            (vid, payload.phone.strip(), payload.name.strip(), _now()),
        )
        await conn.execute(
            "INSERT INTO vendor_profile(user_id, kyc_note, updated_at) VALUES (?, ?, ?)",
            (vid, payload.kyc_note, _now()),
        )
        await conn.execute("INSERT OR IGNORE INTO vendor_zones(vendor_id, zone_id) VALUES (?, ?)",
                     (vid, payload.zone_id))
        await _audit(conn, user, "vendor.create", "users", vid, "", {"phone": payload.phone})
        conn.commit()
    return {"id": vid, "phone": payload.phone, "name": payload.name,
            "kyc_status": "pending", "zone_id": payload.zone_id}


@router.patch("/admin/vendors/{vendor_id}/capacity")
async def vendor_capacity(vendor_id: str, payload: CapacityPatchIn, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        before = await ensure_profile(conn, vendor_id)
        sets, args = [], []
        if payload.max_stops is not None:
            sets.append("max_stops_per_shift = ?")
            args.append(int(payload.max_stops))
        if payload.max_jars is not None:
            sets.append("max_jars_per_shift = ?")
            args.append(int(payload.max_jars))
        if payload.per_stop_fee is not None:
            sets.append("per_stop_fee = ?")
            args.append(int(payload.per_stop_fee))
        if not sets:
            raise ValidationError(message="Nothing to update.", details={})
        sets.append("updated_at = ?")
        args.append(_now())
        await conn.execute(f"UPDATE vendor_profile SET {', '.join(sets)} WHERE user_id = ?", (*args, vendor_id))  # noqa: S608
        after = dict((await conn.execute("SELECT * FROM vendor_profile WHERE user_id = ?",
                                  (vendor_id,))).fetchone())
        await _audit(conn, user, "vendor.capacity", "users", vendor_id, before, after)
        conn.commit()
    return {"vendor_id": vendor_id, "max_stops": after["max_stops_per_shift"],
            "max_jars": after["max_jars_per_shift"], "per_stop_fee": after["per_stop_fee"]}


@router.get("/admin/vendors")
async def vendor_list(conn=Depends(get_db_conn), user=Admin):
    rows = (await conn.execute(
        "SELECT u.id, u.phone, u.name, u.role, u.kyc_status,"
        " p.max_stops_per_shift, p.max_jars_per_shift, p.per_stop_fee,"
        " p.active, p.on_duty, p.in_hand, p.review_hold"
        " FROM users u LEFT JOIN vendor_profile p ON p.user_id = u.id"
        " WHERE u.role = 'vendor' OR p.user_id IS NOT NULL ORDER BY u.created_at DESC"
    )).fetchall()
    return {"data": [dict(r) for r in rows]}


@router.get("/admin/vendors/{vendor_id}/duty")
async def vendor_duty(vendor_id: str, conn=Depends(get_db_conn), user=Admin):
    prof = await ensure_profile(conn, vendor_id)
    today = _dt.datetime.now(_dt.timezone.utc).date().isoformat()
    n = (await conn.execute(
        "SELECT COUNT(*) c FROM stops s JOIN routes r ON s.route_id = r.id"
        " WHERE r.vendor_id = ? AND r.date = ? AND s.status = 'pending'", (vendor_id, today)
    )).fetchone()["c"]
    return {"vendor_id": vendor_id, "on_duty": bool(prof.get("on_duty")),
            "active": bool(prof.get("active")), "in_hand": int(prof.get("in_hand", 0)),
            "pending_stops": int(n), "review_hold": bool(prof.get("review_hold", 0))}


@router.post("/admin/vendors/{vendor_id}/verify")
async def vendor_verify(vendor_id: str, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        row = (await conn.execute("SELECT id, role, kyc_status FROM users WHERE id = ?", (vendor_id,))).fetchone()
        if row is None:
            raise NotFoundError(message="Vendor not found.", details={"id": vendor_id})
        before = dict(row)
        await conn.execute("UPDATE users SET role = 'vendor', kyc_status = 'verified' WHERE id = ?",
                     (vendor_id,))
        await _audit(conn, user, "vendor.verify", "users", vendor_id, before,
               {"role": "vendor", "kyc_status": "verified"})
        conn.commit()
    return {"vendor_id": vendor_id, "role": "vendor", "kyc_status": "verified"}


@router.post("/admin/vendors/{vendor_id}/review-hold")
async def vendor_hold(vendor_id: str, payload: HoldIn, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        await ensure_profile(conn, vendor_id)
        await conn.execute("UPDATE vendor_profile SET review_hold = 1, updated_at = ? WHERE user_id = ?",
                     (_now(), vendor_id))
        await _audit(conn, user, "vendor.review_hold", "users", vendor_id, "", payload.reason)
        conn.commit()
    return {"vendor_id": vendor_id, "review_hold": True}


@router.post("/admin/vendors/{vendor_id}/release")
async def vendor_release(vendor_id: str, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        await ensure_profile(conn, vendor_id)
        await conn.execute(
            "UPDATE vendor_profile SET review_hold = 0, active = 1, updated_at = ? WHERE user_id = ?",
            (_now(), vendor_id))
        await _audit(conn, user, "vendor.release", "users", vendor_id, "", "")
        conn.commit()
    return {"vendor_id": vendor_id, "review_hold": False}


# -- zones attach/detach (custody-zero guard, §14.2) ----------------------------

@router.post("/admin/zones/{zone_id}/vendors/attach")
async def zone_attach(zone_id: str, payload: AttachIn, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        if (await conn.execute("SELECT id FROM zones WHERE id = ?", (zone_id,))).fetchone() is None:
            raise NotFoundError(message="Zone not found.", details={"id": zone_id})
        await conn.execute("INSERT OR IGNORE INTO vendor_zones(vendor_id, zone_id, priority)"
                     " VALUES (?, ?, ?)", (payload.vendor_id, zone_id, int(payload.priority)))
        await _audit(conn, user, "zone.attach", "zones", zone_id, "", {"vendor_id": payload.vendor_id})
        conn.commit()
    return {"zone_id": zone_id, "vendor_id": payload.vendor_id}


@router.post("/admin/zones/{zone_id}/vendors/{vendor_id}/detach")
async def zone_detach(zone_id: str, vendor_id: str, payload: DetachIn,
                conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        prof = await ensure_profile(conn, vendor_id)
        if int(prof.get("in_hand", 0)) != 0:
            raise CustodyBlockedError(
                message="Vendor still holds agency cash. Complete handover before detach.",
                details={"vendor_id": vendor_id, "in_hand": int(prof["in_hand"])})
        cur = await conn.execute("DELETE FROM vendor_zones WHERE vendor_id = ? AND zone_id = ?",
                           (vendor_id, zone_id))
        if cur.rowcount == 0:
            raise NotFoundError(message="Vendor is not attached to this zone.",
                                details={"zone_id": zone_id, "vendor_id": vendor_id})
        await _audit(conn, user, "zone.detach", "zones", zone_id,
               {"vendor_id": vendor_id}, payload.reason)
        conn.commit()
    return {"zone_id": zone_id, "vendor_id": vendor_id, "detached": True}


# -- money: ledger adjust, write-off, invoices stub, reconciliation -------------

@router.post("/admin/ledger/{customer_id}/adjust")
async def ledger_adjust(customer_id: str, payload: LedgerAdjustIn, conn=Depends(get_db_conn), user=Admin):
    repo = LedgerRepo(conn)
    before = await repo.get(customer_id)
    with WRITE_LOCK:
        after = await repo.apply_event(customer_id, d_held=int(payload.d_held),
                                 d_deposit=int(payload.d_deposit), d_dues=int(payload.d_dues),
                                 ref=f"admin-adjust:{_uid(user)}", actor=_uid(user),
                                 reason=payload.reason, commit=False)
        await _audit(conn, user, "ledger.adjust", "ledger", customer_id, before, after)
        conn.commit()
    return {"customer_id": customer_id, "before": before, "after": after}


@router.post("/admin/dues/{customer_id}/write-off")
async def dues_writeoff(customer_id: str, payload: WriteOffIn, conn=Depends(get_db_conn), user=Admin):
    repo = LedgerRepo(conn)
    before = await repo.get(customer_id)
    if int(before.get("dues", 0)) <= 0:
        raise ValidationError(message="No dues to write off.", details={"customer_id": customer_id})
    with WRITE_LOCK:
        after = await repo.apply_event(customer_id, d_dues=-int(before["dues"]),
                                 ref=f"write-off:{_uid(user)}", actor=_uid(user),
                                 reason=payload.reason, commit=False)
        await _audit(conn, user, "dues.write_off", "ledger", customer_id, before, after)
        conn.commit()
    return {"customer_id": customer_id, "written_off": int(before["dues"]), "after": after}


@router.post("/admin/invoices/{invoice_id}/send-whatsapp")
async def invoice_whatsapp(invoice_id: str, conn=Depends(get_db_conn), user=Admin):
    # TODO: wire the configured WhatsApp provider adapter (templates + opt-out + DLT).
    with WRITE_LOCK:
        await _audit(conn, user, "invoice.send_whatsapp", "invoices", invoice_id, "", "queued:stub")
        conn.commit()
    return {"invoice_id": invoice_id, "status": "queued", "provider": "stub"}


@router.get("/admin/reconciliation")
async def reconciliation(conn=Depends(get_db_conn), user=Admin):
    led = (await conn.execute(
        "SELECT COALESCE(SUM(held),0) h, COALESCE(SUM(deposit_paid),0) p,"
        " COALESCE(SUM(deposit_refunded),0) r, COALESCE(SUM(dues),0) d FROM ledger"
    )).fetchone()
    states = (await conn.execute(
        "SELECT state, COUNT(*) c, COALESCE(SUM(total),0) t FROM orders GROUP BY state"
    )).fetchall()
    return {"jars_out": int(led["h"]), "deposit_liability": int(led["p"]) - int(led["r"]),
            "dues_receivable": int(led["d"]),
            "orders_by_state": [{**dict(r)} for r in states]}


@router.get("/admin/custody")
async def custody(conn=Depends(get_db_conn), user=Admin):
    rows = (await conn.execute(
        "SELECT user_id AS vendor_id, in_hand FROM vendor_profile WHERE in_hand != 0"
    )).fetchall()
    return {"data": [dict(r) for r in rows]}


@router.get("/admin/dunning")
async def dunning(conn=Depends(get_db_conn), user=Admin):
    rows = (await conn.execute(
        "SELECT customer_id, dues FROM ledger WHERE dues > 0 ORDER BY dues DESC LIMIT 200"
    )).fetchall()
    return {"data": [dict(r) for r in rows]}


# -- returns / complaints / quality --------------------------------------------

@router.get("/admin/returns")
async def returns_queue(status: str | None = Query(default=None), conn=Depends(get_db_conn), user=Admin):
    args: list[object] = []
    where = ""
    if status:
        where = "WHERE status = ?"
        args.append(status)
    rows = await conn.execute(
        f"SELECT * FROM returns {where} ORDER BY created_at DESC LIMIT 200", (*args,))  # noqa: S608
    return {"data": [dict(r) for r in rows.fetchall()]}


@router.get("/admin/complaints")
async def complaints_queue(conn=Depends(get_db_conn), user=Admin):
    rows = (await conn.execute("SELECT * FROM complaints ORDER BY created_at DESC LIMIT 200")).fetchall()
    return {"data": [dict(r) for r in rows]}


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
    return {"data": [dict(r) for r in rows.fetchall()]}


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
    return {"data": [dict(r) for r in rows]}


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

@router.patch("/admin/config")
async def config_patch(payload: ConfigPatchIn, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        before = (await conn.execute("SELECT * FROM config WHERE key = ?", (payload.key,))).fetchone()
        now = _now()
        await conn.execute(
            "INSERT INTO config(key, value, effective_from, updated_by, updated_at)"
            " VALUES (?, ?, ?, ?, ?)"
            " ON CONFLICT(key) DO UPDATE SET value = excluded.value,"
            " effective_from = excluded.effective_from, updated_by = excluded.updated_by,"
            " updated_at = excluded.updated_at",
            (payload.key.strip(), payload.value, now, _uid(user), now),
        )
        await _audit(conn, user, "config.set", "config", payload.key,
               dict(before) if before else {}, {"value": payload.value, "effective_from": now})
        conn.commit()
    return {"key": payload.key, "value": payload.value, "effective_from": now}


@router.get("/admin/config")
async def config_read(conn=Depends(get_db_conn), user=Admin):
    try:
        rows = (await conn.execute("SELECT key, value, effective_from, updated_by, updated_at"
                            " FROM config ORDER BY key")).fetchall()
    except sqlite3.OperationalError:
        rows = (await conn.execute("SELECT key, value FROM config ORDER BY key")).fetchall()
    return {"data": [dict(r) for r in rows]}


@router.get("/admin/audit")
async def audit_read(entity: str | None = Query(default=None),
               actor_id: str | None = Query(default=None, max_length=80),  # F-SA additive
               action: str | None = Query(default=None, max_length=80),  # F-SA additive
               limit: int = Query(default=50, ge=1, le=200),
               conn=Depends(get_db_conn), user=Admin):
    args: list[object] = []
    clauses = []
    if entity:
        clauses.append("entity = ?")
        args.append(entity)
    if actor_id:
        clauses.append("actor_id = ?")
        args.append(actor_id)
    if action:
        clauses.append("action = ?")
        args.append(action)
    where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
    try:
        rows = (await conn.execute(
            f"SELECT * FROM audit_log {where} ORDER BY rowid DESC LIMIT ?", (*args, limit)  # noqa: S608
        )).fetchall()
    except sqlite3.OperationalError:
        rows = []
    return {"data": [dict(r) for r in rows]}


@router.get("/admin/metrics")
async def metrics(conn=Depends(get_db_conn), user=Admin):
    orders = {r["state"]: int(r["c"])
              for r in (await conn.execute("SELECT state, COUNT(*) c FROM orders GROUP BY state")).fetchall()}
    users = {r["role"]: int(r["c"])
             for r in (await conn.execute("SELECT role, COUNT(*) c FROM users GROUP BY role")).fetchall()}
    dues = (await conn.execute("SELECT COALESCE(SUM(dues),0) d FROM ledger")).fetchone()["d"]
    open_q = 0
    try:
        open_q = int((await conn.execute(
            "SELECT COUNT(*) c FROM quality_incidents WHERE status = 'open'")).fetchone()["c"])
    except sqlite3.OperationalError:
        pass
    return {"orders_by_state": orders, "users_by_role": users,
            "dues_paise": int(dues), "quality_open": open_q}


# -- F-SA super-admin panel (additive, contract §4.11 + §14.5) ----------------
# Reads power the Next.js admin web panel; suspend/unsuspend implement §14.5
# (block = human-confirmed, sessions revoked instantly, always audited).


def _cursor(value: str) -> int:
    try:
        n = int(value)
    except (TypeError, ValueError):
        return 0
    return n if n > 0 else 0


@router.get("/admin/metrics/overview")
async def metrics_overview(days: int = Query(default=14, ge=1, le=90),
                     conn=Depends(get_db_conn), user=Admin):
    repo = AdminReadRepo(conn)
    since = (_dt.datetime.now(_dt.timezone.utc) - _dt.timedelta(days=days)).isoformat()[:10]
    today = _dt.datetime.now(_dt.timezone.utc).isoformat()[:10]
    daily = await repo.daily_series(since)
    on_time = {r["day"]: r for r in await repo.on_time_series(since)}
    series = []
    for row in daily:
        ot = on_time.get(row["day"], {})
        delivered = ot.get("delivered") or 0
        series.append({
            "day": row["day"],
            "orders": int(row["orders"] or 0),
            "gmv_paise": int(row["gmv_paise"] or 0),
            "delivered": int(row["delivered"] or 0),
            "cancelled": int(row["cancelled"] or 0),
            "failed": int(row["failed"] or 0),
            "upi_orders": int(row["upi_orders"] or 0),
            "cod_orders": int(row["cod_orders"] or 0),
            "on_time_pct": round(100.0 * (ot.get("on_time") or 0) / delivered, 1) if delivered else None,
        })
    today_row = next((r for r in series if r["day"] == today), None)
    return {
        "today": today_row or {
            "day": today, "orders": 0, "gmv_paise": 0, "delivered": 0,
            "cancelled": 0, "failed": 0, "upi_orders": 0, "cod_orders": 0,
            "on_time_pct": None,
        },
        "series": series,
        "money": await repo.money_totals(),
    }


@router.get("/admin/users")
async def admin_users(query: str | None = Query(default=None, max_length=80),
                role: str | None = Query(default=None, pattern=r"^(user|vendor|admin)$"),
                suspended: int | None = Query(default=None, ge=0, le=1),
                limit: int = Query(default=50, ge=1, le=200),
                cursor: str = Query(default=""),
                conn=Depends(get_db_conn), user=Admin):
    data, next_cursor = await AdminReadRepo(conn).users_page(
        query=(query or "").strip(), role=role or "", suspended=suspended,
        limit=limit, cursor=_cursor(cursor))
    return {"data": data, "next_cursor": next_cursor}


@router.get("/admin/users/{user_id}/detail")
async def admin_user_detail(user_id: str, conn=Depends(get_db_conn), user=Admin):
    detail = await AdminReadRepo(conn).user_detail(user_id)
    if detail is None:
        raise NotFoundError(message="User not found.", details={"id": user_id})
    return detail


@router.get("/admin/vendors/{vendor_id}/detail")
async def admin_vendor_detail(vendor_id: str, conn=Depends(get_db_conn), user=Admin):
    detail = await AdminReadRepo(conn).vendor_detail(vendor_id)
    if detail is None:
        raise NotFoundError(message="Vendor not found.", details={"id": vendor_id})
    return detail


@router.post("/admin/users/{user_id}/suspend")
async def admin_suspend_user(user_id: str, payload: SuspendIn,
                       conn=Depends(get_db_conn), user=Admin):
    """§14.5 block: restrict (flag only) or suspend (flag + revoke all sessions).
    Never deletes the account; never touches admins (no lockout path)."""
    with WRITE_LOCK:
        row = (await conn.execute("SELECT * FROM users WHERE id = ?", (user_id,))).fetchone()
        if row is None:
            raise NotFoundError(message="User not found.", details={"id": user_id})
        if row["role"] == "admin":
            raise ValidationError(message="Admin accounts cannot be suspended from the panel.")
        now = _now()
        await conn.execute(
            "UPDATE users SET suspended = 1, suspended_reason = ?, suspended_by = ?,"
            " suspended_at = ? WHERE id = ?",
            (f"[{payload.level}] {payload.reason}", _uid(user), now, user_id),
        )
        revoked = 0
        if payload.level == "suspend":
            cur = await conn.execute(
                "UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL",
                (now, user_id),
            )
            revoked = cur.rowcount if cur.rowcount and cur.rowcount > 0 else 0
        await _audit(conn, user, f"user.{payload.level}", "users", user_id,
               {"suspended": bool(row["suspended"]), "reason": row["suspended_reason"]},
               {"level": payload.level, "reason": payload.reason, "revoked_sessions": revoked})
        conn.commit()
    return {"user_id": user_id, "level": payload.level,
            "suspended": True, "revoked_sessions": revoked}


@router.post("/admin/users/{user_id}/unsuspend")
async def admin_unsuspend_user(user_id: str, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        row = (await conn.execute("SELECT * FROM users WHERE id = ?", (user_id,))).fetchone()
        if row is None:
            raise NotFoundError(message="User not found.", details={"id": user_id})
        await conn.execute(
            "UPDATE users SET suspended = 0, suspended_reason = NULL, suspended_by = NULL,"
            " suspended_at = NULL WHERE id = ?",
            (user_id,),
        )
        await _audit(conn, user, "user.unsuspend", "users", user_id,
               {"suspended": bool(row["suspended"]), "reason": row["suspended_reason"]},
               {"suspended": False})
        conn.commit()
    return {"user_id": user_id, "suspended": False}


@router.get("/admin/payments")
async def admin_payments(status: str | None = Query(default=None),
                   method: str | None = Query(default=None, pattern=r"^(upi|cod)$"),
                   limit: int = Query(default=50, ge=1, le=200),
                   cursor: str = Query(default=""),
                   conn=Depends(get_db_conn), user=Admin):
    data, next_cursor = await AdminReadRepo(conn).payments_page(
        status=status or "", method=method or "", limit=limit, cursor=_cursor(cursor))
    return {"data": data, "next_cursor": next_cursor}


@router.get("/admin/refunds")
async def admin_refunds(status: str | None = Query(default=None),
                  limit: int = Query(default=50, ge=1, le=200),
                  cursor: str = Query(default=""),
                  conn=Depends(get_db_conn), user=Admin):
    data, next_cursor = await AdminReadRepo(conn).refunds_page(
        status=status or "", limit=limit, cursor=_cursor(cursor))
    return {"data": data, "next_cursor": next_cursor}


@router.get("/admin/ledger")
async def admin_ledger(limit: int = Query(default=50, ge=1, le=200),
                 cursor: str = Query(default=""),
                 conn=Depends(get_db_conn), user=Admin):
    data, next_cursor = await AdminReadRepo(conn).ledger_page(limit=limit, cursor=_cursor(cursor))
    return {"data": data, "next_cursor": next_cursor}
