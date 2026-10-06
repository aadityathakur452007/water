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
import hashlib
import json
import secrets
import sqlite3
import uuid

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field

from app.api.auth_deps import get_current_user, require_role  # noqa: F401 (re-export for test overrides)
from app.api.caching import cached
from app.api.deps import get_db_conn
from app.core.errors import AppError, ConflictError, NotFoundError, ValidationError
from app.db import WRITE_LOCK
from app.repositories.admin_read_repo import AdminReadRepo, ist_today
from app.repositories.access_code_repo import AccessCodeRepo
from app.repositories.ledger_repo import LedgerRepo
from app.repositories.order_repo import OrderRepo
from app.repositories.vendor_access_repo import VendorAccessRepo
from app.services.dispatch_service import (
    CustodyBlockedError,
    assign_order,
    auto_repool,
    ensure_profile,
    generate_routes,
    reassign_order,
    write_audit,
)
from app.services.vendor_service import VendorService

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


class RejectIn(BaseModel):
    reason: str = Field(min_length=1, max_length=500)


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
        f"SELECT id, user_id, n, e, water_bill, deposit_due, cap_charge, total, payment_status,"
        f" state, window_start, created_at,"  # noqa: S608
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
async def admin_reassign(order_id: str, payload: ReassignIn,
                  conn=Depends(get_db_conn), user=Admin):
    return await reassign_order(conn, order_id, payload.vendor_id,
                          {"id": _uid(user), "role": "admin"}, payload.reason)


@router.post("/admin/orders/{order_id}/accept")
async def admin_accept(order_id: str, conn=Depends(get_db_conn), user=Admin):
    out = await OrderRepo(conn).transition(
        order_id, "accepted", {"id": _uid(user), "role": "admin"}, "dispatcher accept")
    with WRITE_LOCK:
        await _audit(conn, user, "order.accept", "orders", order_id, "", "accepted")
        conn.commit()
    return out


@router.post("/admin/orders/{order_id}/reject")
async def admin_reject(order_id: str, payload: RejectIn,
                conn=Depends(get_db_conn), user=Admin):
    out = await OrderRepo(conn).transition(
        order_id, "rejected", {"id": _uid(user), "role": "admin"}, payload.reason)
    with WRITE_LOCK:
        await _audit(conn, user, "order.reject", "orders", order_id, "", payload.reason)
        conn.commit()
    return out


@router.post("/admin/orders/{order_id}/pack")
async def admin_pack(order_id: str, conn=Depends(get_db_conn), user=Admin):
    actor = {"id": _uid(user), "role": "admin"}
    await OrderRepo(conn).transition(order_id, "picked", actor, "dispatcher single-touch pack")
    out = await OrderRepo(conn).transition(order_id, "packed", actor, "dispatcher single-touch pack")
    with WRITE_LOCK:
        await _audit(conn, user, "order.pack", "orders", order_id, "", "packed")
        conn.commit()
    return out


@router.post("/admin/routes/{route_id}/dispatch")
async def admin_dispatch_route(route_id: str, conn=Depends(get_db_conn), user=Admin):
    actor = {"id": _uid(user), "role": "admin"}
    stops = (await conn.execute(
        "SELECT s.id, s.order_id FROM stops s WHERE s.route_id = ? AND s.status = 'pending'"
        " AND s.order_id IS NOT NULL",
        (route_id,),
    )).fetchall()
    dispatched, skipped = [], []
    for s in stops:
        order = (await conn.execute(
            "SELECT state FROM orders WHERE id = ?", (s["order_id"],))).fetchone()
        if order is None or str(order["state"]) != "assigned":
            skipped.append({"stop_id": s["id"], "state": str(order["state"]) if order else "missing"})
            continue
        await OrderRepo(conn).transition(s["order_id"], "dispatched", actor, f"route {route_id} dispatched")
        with WRITE_LOCK:
            await _audit(conn, user, "admin.dispatch", "stops", s["id"], "", "dispatched")
            conn.commit()
        dispatched.append(s["id"])
    return {"route_id": route_id, "dispatched": dispatched, "skipped": skipped}


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


# -- vendor access codes (027 RBAC: admin-issued, hash-stored, revocable) -----
# Repo methods self-lock per txn (otp_repo pattern); the audit insert takes
# WRITE_LOCK per the dispatch convention. Never nested — Lock is not reentrant.

class AccessCodeIssueIn(BaseModel):
    expires_at: str | None = Field(default=None, max_length=64)


class RoleRefusedError(AppError):
    code = "ROLE_REFUSED"
    status_code = 422


def _code_expiry(raw: str | None) -> str:
    if raw:
        try:
            dt = _dt.datetime.fromisoformat(raw.strip())
        except ValueError:
            raise ValidationError(message="expires_at must be ISO-8601.", details={})
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=_dt.timezone.utc)
        return dt.isoformat()
    return (_dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(days=90)).isoformat()


async def _require_vendor(conn, vendor_id: str) -> dict:
    """Target must exist and be a vendor. Role assignment stays on the verify
    flow — codes never upgrade roles (422, never auto-fix)."""
    row = (await conn.execute("SELECT * FROM users WHERE id = ?", (vendor_id,))).fetchone()
    if row is None:
        raise NotFoundError(message="Vendor not found.", details={"id": vendor_id})
    if row["role"] != "vendor":
        raise RoleRefusedError(message="Access codes are vendor-only.",
                               details={"id": vendor_id, "role": row["role"]})
    return dict(row)


@router.get("/admin/vendors/{vendor_id}/access-codes")
async def vendor_access_list(vendor_id: str, conn=Depends(get_db_conn), user=Admin):
    await _require_vendor(conn, vendor_id)
    return {"data": await VendorAccessRepo(conn).list_for_vendor(vendor_id)}


@router.post("/admin/vendors/{vendor_id}/access-codes", status_code=201)
async def vendor_access_issue(vendor_id: str, payload: AccessCodeIssueIn,
                              conn=Depends(get_db_conn), user=Admin):
    await _require_vendor(conn, vendor_id)
    code = secrets.token_urlsafe(12)
    code_id = uuid.uuid4().hex
    expires = _code_expiry(payload.expires_at)
    hint = f"••{code[-2:]}"
    await VendorAccessRepo(conn).issue(
        code_id=code_id, vendor_id=vendor_id,
        code_hash=hashlib.sha256(code.encode()).hexdigest(),
        masked_hint=hint, expires_at=expires, created_by=_uid(user))
    with WRITE_LOCK:
        await _audit(conn, user, "vendor.access.issue", "vendor_access_codes", code_id,
                     "", {"vendor_id": vendor_id, "expires_at": expires})
        conn.commit()
    return {"id": code_id, "vendor_id": vendor_id, "code": code,
            "masked_hint": hint, "expires_at": expires}


@router.post("/admin/vendors/{vendor_id}/access-codes/{code_id}/revoke")
async def vendor_access_revoke(vendor_id: str, code_id: str,
                               conn=Depends(get_db_conn), user=Admin):
    await _require_vendor(conn, vendor_id)
    if not await VendorAccessRepo(conn).revoke(code_id, vendor_id):
        raise NotFoundError(message="Access code not found.", details={"id": code_id})
    with WRITE_LOCK:
        await _audit(conn, user, "vendor.access.revoke", "vendor_access_codes", code_id,
                     "", {"vendor_id": vendor_id})
        conn.commit()
    return {"code_id": code_id, "vendor_id": vendor_id, "revoked": True}


# -- generalized access codes (028: ONE table for vendor+admin) ---------------
# Legacy /vendors/* endpoints above stay for 027-seeded DBs. New flows use
# ONLY access_codes via AccessCodeRepo: any user id, expected_role follows the
# target's own role (vendor AND admin allowed; role=user → 422, they onboard
# via POST /v1/auth/user/register). Plaintext is returned ONCE on issue.

def _general_code_expiry(raw: str | None) -> str:
    now = _dt.datetime.now(_dt.timezone.utc)
    if raw:
        try:
            dt = _dt.datetime.fromisoformat(raw.strip())
        except ValueError:
            raise ValidationError(message="expires_at must be ISO-8601.", details={})
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=_dt.timezone.utc)
    else:
        dt = now + _dt.timedelta(days=90)
    if dt < now + _dt.timedelta(hours=1) or dt > now + _dt.timedelta(days=180):
        raise ValidationError(
            message="expires_at must be between 1 hour and 180 days from now.",
            details={},
        )
    return dt.isoformat()


async def _require_code_target(conn, user_id: str) -> dict:
    """Generalized code target: must exist and be vendor or admin.

    Users (role=user) never get codes (422 — they use name+number register);
    role assignment stays on the verify flow, codes never upgrade roles."""
    row = (await conn.execute("SELECT * FROM users WHERE id = ?", (user_id,))).fetchone()
    if row is None:
        raise NotFoundError(message="User not found.", details={"id": user_id})
    if row["role"] not in ("vendor", "admin"):
        raise RoleRefusedError(message="Access codes are for staff accounts only.",
                               details={"id": user_id, "role": row["role"]})
    return dict(row)


@router.get("/admin/users/{user_id}/access-codes")
async def access_list(user_id: str, conn=Depends(get_db_conn), user=Admin):
    await _require_code_target(conn, user_id)
    return {"data": await AccessCodeRepo(conn).list_masked(user_id)}


@router.post("/admin/users/{user_id}/access-codes", status_code=201)
async def access_issue(user_id: str, payload: AccessCodeIssueIn,
                       conn=Depends(get_db_conn), user=Admin):
    target = await _require_code_target(conn, user_id)
    code = secrets.token_urlsafe(12)
    code_id = uuid.uuid4().hex
    expires = _general_code_expiry(payload.expires_at)
    hint = f"••{code[-2:]}"
    await AccessCodeRepo(conn).issue(
        code_id=code_id, user_id=user_id,
        code_hash=hashlib.sha256(code.encode()).hexdigest(),
        masked_hint=hint, expected_role=str(target["role"]),
        expires_at=expires, created_by=_uid(user))
    with WRITE_LOCK:
        await _audit(conn, user, "access.issue", "access_codes", code_id,
                     "", {"user_id": user_id, "expires_at": expires})
        conn.commit()
    return {"id": code_id, "user_id": user_id, "code": code,
            "masked_hint": hint, "expires_at": expires,
            "expected_role": str(target["role"])}


@router.post("/admin/users/{user_id}/access-codes/{code_id}/revoke")
async def access_revoke(user_id: str, code_id: str,
                        conn=Depends(get_db_conn), user=Admin):
    await _require_code_target(conn, user_id)
    if not await AccessCodeRepo(conn).revoke(code_id, user_id):
        raise NotFoundError(message="Access code not found.", details={"id": code_id})
    with WRITE_LOCK:
        await _audit(conn, user, "access.revoke", "access_codes", code_id,
                     "", {"user_id": user_id})
        conn.commit()
    return {"code_id": code_id, "user_id": user_id, "revoked": True}


@router.get("/admin/vendors/{vendor_id}/preview")
async def admin_vendor_preview(vendor_id: str, date: str | None = None,
                               conn=Depends(get_db_conn), user=Admin):
    """Read-only view-as-vendor: vendor_detail basics + existing VendorService
    reads composed with an explicit vendor_id param. No writes."""
    detail = await AdminReadRepo(conn).vendor_detail(vendor_id)
    if detail is None:
        raise NotFoundError(message="Vendor not found.", details={"id": vendor_id})
    svc = VendorService(conn)
    return {
        "vendor": detail["vendor"], "profile": detail["profile"],
        "route": await svc.today_route(vendor_id, date),
        "earnings": await svc.earnings(vendor_id, date),
        "customers": await svc.today_customers(vendor_id, date),
        "complaints": await svc.vendor_complaints(vendor_id),
    }


# -- zones attach/detach (custody-zero guard, §14.2) ----------------------------

@router.get("/admin/zones")
async def zone_list(request: Request, conn=Depends(get_db_conn), user=Admin):
    rows = (await conn.execute(
        "SELECT id, name, pincodes, active FROM zones ORDER BY name LIMIT 200")).fetchall()
    # Phase 8 §8.5: cached 5 min + ETag (auth still required; BFF opts in).
    return cached({"data": [dict(r) for r in rows]}, request)

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
async def reconciliation(date: str | None = Query(default=None),
                   conn=Depends(get_db_conn), user=Admin):
    day = (date or "").strip() or ist_today()
    led = (await conn.execute(
        "SELECT COALESCE(SUM(held),0) h, COALESCE(SUM(deposit_paid),0) p,"
        " COALESCE(SUM(deposit_refunded),0) r, COALESCE(SUM(dues),0) d FROM ledger"
    )).fetchone()
    states = (await conn.execute(
        "SELECT state, COUNT(*) c, COALESCE(SUM(total),0) t FROM orders GROUP BY state"
    )).fetchall()
    rows = (await conn.execute(
        "SELECT r.id AS route_id, r.vendor_id, COALESCE(u.name, '') AS vendor_name,"
        " COUNT(s.id) AS stops,"
        " SUM(CASE WHEN s.status = 'done' THEN 1 ELSE 0 END) AS delivered,"
        " SUM(CASE WHEN s.status = 'failed' THEN 1 ELSE 0 END) AS failed,"
        " COALESCE(SUM(s.fulls_exp), 0) AS jars_out,"
        " COALESCE(SUM(s.empties_exp), 0) AS empties_expected,"
        " COALESCE(SUM(p.cash), 0) AS cash, COALESCE(SUM(p.upi), 0) AS upi"
        " FROM routes r LEFT JOIN stops s ON s.route_id = r.id"
        " LEFT JOIN (SELECT order_id,"
        " SUM(CASE WHEN method = 'cod' AND status IN ('paid','partial') THEN amount ELSE 0 END) AS cash,"
        " SUM(CASE WHEN method = 'upi' AND status IN ('paid','partial') THEN amount ELSE 0 END) AS upi"
        " FROM payments GROUP BY order_id) p ON p.order_id = s.order_id"
        " LEFT JOIN users u ON u.id = r.vendor_id"
        " WHERE r.date = ? GROUP BY r.id ORDER BY r.id",
        (day,),
    )).fetchall()
    return {"date": day,
            "routes": [{**dict(r), "stops": int(r["stops"]), "delivered": int(r["delivered"] or 0),
                        "failed": int(r["failed"] or 0),
                        "jars_out": int(r["jars_out"]), "empties_expected": int(r["empties_expected"]),
                        "cash": int(r["cash"]), "upi": int(r["upi"])} for r in rows],
            "jars_out": int(led["h"]), "deposit_liability": int(led["p"]) - int(led["r"]),
            "dues_receivable": int(led["d"]),
            "orders_by_state": [{**dict(r)} for r in states]}


@router.get("/admin/custody")
async def custody(conn=Depends(get_db_conn), user=Admin):
    rows = (await conn.execute(
        "SELECT u.id AS vendor_id, COALESCE(u.name, '') AS name, COALESCE(u.phone, '') AS phone,"
        " COALESCE(p.on_duty, 0) AS on_duty, COALESCE(p.in_hand, 0) AS in_hand"
        " FROM users u LEFT JOIN vendor_profile p ON p.user_id = u.id"
        " WHERE u.role = 'vendor' ORDER BY u.id"
    )).fetchall()
    return {"data": [{**dict(r), "on_duty": bool(r["on_duty"]),
                      "zero": int(r["in_hand"]) == 0} for r in rows]}


@router.get("/admin/dunning")
async def dunning(conn=Depends(get_db_conn), user=Admin):
    rows = (await conn.execute(
        "SELECT customer_id, dues FROM ledger WHERE dues > 0 ORDER BY dues DESC LIMIT 200"
    )).fetchall()
    return {"data": [dict(r) for r in rows]}


class PayoutGenerateIn(BaseModel):
    vendor_id: str = Field(min_length=1)
    period: str = Field(pattern=r"^\d{4}-\d{2}$")  # YYYY-MM


# -- payouts + day-close + custody confirm (F6: admin writes close the loop) ---

@router.get("/admin/payouts")
async def payouts_list(vendor_id: str | None = None, status: str | None = None,
                 conn=Depends(get_db_conn), user=Admin):
    args: list[object] = []
    clauses = []
    if vendor_id:
        clauses.append("vendor_id = ?")
        args.append(vendor_id)
    if status:
        clauses.append("status = ?")
        args.append(status)
    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    rows = (await conn.execute(
        f"SELECT * FROM payouts {where} ORDER BY created_at DESC LIMIT 200", (*args,)))  # noqa: S608
    return {"data": [dict(r) for r in rows.fetchall()]}


@router.post("/admin/payouts/generate")
async def payout_generate(payload: PayoutGenerateIn, conn=Depends(get_db_conn), user=Admin):
    """Accrue a pending payout: done stops in period × per_stop_fee."""
    with WRITE_LOCK:
        prof = await ensure_profile(conn, payload.vendor_id)
        dup = (await conn.execute("SELECT id FROM payouts WHERE vendor_id = ? AND period = ?",
                           (payload.vendor_id, payload.period))).fetchone()
        if dup is not None:
            raise ConflictError(message="Payout already generated for this period.",
                                details={"vendor_id": payload.vendor_id, "period": payload.period})
        n = (await conn.execute(
            "SELECT COUNT(*) c FROM stops s JOIN routes r ON r.id = s.route_id"
            " WHERE r.vendor_id = ? AND r.date LIKE ? AND s.status = 'done'",
            (payload.vendor_id, f"{payload.period}%"))).fetchone()["c"]
        gross = int(n) * int(prof.get("per_stop_fee", 0))
        pid = uuid.uuid4().hex
        now = _now()
        await conn.execute(
            "INSERT INTO payouts(id, vendor_id, period, stops_done, gross_fee,"
            " deductions, net, status, created_at)"
            " VALUES (?, ?, ?, ?, ?, 0, ?, 'pending', ?)",
            (pid, payload.vendor_id, payload.period, int(n), gross, gross, now),
        )
        row = dict((await conn.execute("SELECT * FROM payouts WHERE id = ?", (pid,))).fetchone())
        await _audit(conn, user, "payout.generate", "payouts", pid, "", row)
        conn.commit()
    return row


@router.post("/admin/payouts/{payout_id}/approve")
async def payout_approve(payout_id: str, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        row = (await conn.execute("SELECT * FROM payouts WHERE id = ?", (payout_id,))).fetchone()
        if row is None:
            raise NotFoundError(message="Payout not found.", details={"id": payout_id})
        if row["status"] != "pending":
            raise ConflictError(message="Only pending payouts can be approved.",
                                details={"id": payout_id, "status": row["status"]})
        await conn.execute("UPDATE payouts SET status = 'approved', approved_by = ? WHERE id = ?",
                     (_uid(user), payout_id))
        after = dict((await conn.execute("SELECT * FROM payouts WHERE id = ?", (payout_id,))).fetchone())
        await _audit(conn, user, "payout.approve", "payouts", payout_id, dict(row), after)
        conn.commit()
    return after


class CustodyConfirmIn(BaseModel):
    vendor_id: str = Field(min_length=1)
    amount: int = Field(ge=1)


@router.post("/admin/custody/confirm")
async def custody_confirm(payload: CustodyConfirmIn, conn=Depends(get_db_conn), user=Admin):
    """Record cash handover received from a vendor (decrements in_hand)."""
    with WRITE_LOCK:
        prof = await ensure_profile(conn, payload.vendor_id)
        hand = int(prof.get("in_hand", 0))
        if hand < int(payload.amount):
            raise ValidationError(message="Handover exceeds cash in hand.",
                                  details={"in_hand": hand, "amount": payload.amount})
        await conn.execute("UPDATE vendor_profile SET in_hand = in_hand - ? WHERE user_id = ?",
                     (int(payload.amount), payload.vendor_id))
        after = int((await conn.execute("SELECT in_hand FROM vendor_profile WHERE user_id = ?",
                                  (payload.vendor_id,))).fetchone()["in_hand"])
        await _audit(conn, user, "custody.confirm", "users", payload.vendor_id,
               {"in_hand": hand}, {"in_hand": after, "confirmed": int(payload.amount)})
        conn.commit()
    return {"vendor_id": payload.vendor_id, "confirmed": int(payload.amount), "in_hand": after}


class RecoCloseIn(BaseModel):
    route: str = Field(default="")
    date: str = Field(default="")


@router.post("/admin/reconciliation/close")
async def reconciliation_close(payload: RecoCloseIn, conn=Depends(get_db_conn), user=Admin):
    """Day-close marker: money truth comes from `payments` rows (paid/partial
    by method for the day); the triple JSON sums stay as a non-blocking
    cross-check (declared vs posted diverge on offline timing)."""
    day = payload.date.strip() or ist_today()
    led = (await conn.execute(
        "SELECT COALESCE(SUM(held),0) h, COALESCE(SUM(deposit_paid),0) p,"
        " COALESCE(SUM(deposit_refunded),0) r, COALESCE(SUM(dues),0) d FROM ledger"
    )).fetchone()
    hand = (await conn.execute("SELECT COALESCE(SUM(in_hand),0) t FROM vendor_profile")).fetchone()["t"]
    triples = (await conn.execute(
        "SELECT s.triple FROM stops s JOIN routes r ON r.id = s.route_id"
        " WHERE r.date = ? AND s.status = 'done'", (day,))).fetchall()
    cash = upi = 0
    for t in triples:
        try:
            j = json.loads(t["triple"]) if t["triple"] else {}
        except (ValueError, TypeError):
            j = {}
        cash += int(j.get("cash", 0))
        upi += int(j.get("upi", 0))
    prows = (await conn.execute(
        "SELECT method, COALESCE(SUM(amount),0) s FROM payments"
        " WHERE status IN ('paid','partial') AND date(created_at) = ? GROUP BY method",
        (day,))).fetchall()
    by_method = {str(r["method"]): int(r["s"]) for r in prows}
    payments_cash, payments_upi = by_method.get("cod", 0), by_method.get("upi", 0)
    snapshot = {"date": day, "route": payload.route,
                "jars_out": int(led["h"]),
                "deposit_liability": int(led["p"]) - int(led["r"]),
                "dues_receivable": int(led["d"]),
                "collected_cash": cash, "collected_upi": upi,
                "payments_cash": payments_cash, "payments_upi": payments_upi,
                "cash_mismatch": payments_cash != cash, "upi_mismatch": payments_upi != upi,
                "custody_in_hand": int(hand)}
    with WRITE_LOCK:
        await _audit(conn, user, "reco.close", "reconciliation", f"{day}:{payload.route}", "", snapshot)
        conn.commit()
    return {**snapshot, "closed": True}


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
        if ret["status"] != "requested":
            raise ConflictError(message="Only requested returns can be assigned.",
                                details={"id": return_id, "status": ret["status"]})
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
        if ret["status"] != "picked":
            raise ConflictError(message="Only picked returns can be refunded.",
                                details={"id": return_id, "status": ret["status"]})
        if int(payload.qty) > int(ret["qty"]):
            raise ValidationError(message="Refund qty exceeds requested.",
                                  details={"qty": ret["qty"]})
        rate = int(get_settings().deposit_per_jar_paise)
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
async def config_read(request: Request, conn=Depends(get_db_conn), user=Admin):
    try:
        rows = (await conn.execute("SELECT key, value, effective_from, updated_by, updated_at"
                            " FROM config ORDER BY key")).fetchall()
    except sqlite3.OperationalError:
        rows = (await conn.execute("SELECT key, value FROM config ORDER BY key")).fetchall()
    # Phase 8 §8.5: cached 5 min + ETag (auth still required; BFF opts in).
    return cached({"data": [dict(r) for r in rows]}, request)


@router.get("/admin/audit")
async def audit_read(entity: str | None = Query(default=None),
               actor_id: str | None = Query(default=None, max_length=80),  # F-SA additive
               action: str | None = Query(default=None, max_length=80),  # F-SA additive
               limit: int = Query(default=50, ge=1, le=200),
               cursor: str = Query(default=""),
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
    cur = _cursor(cursor)
    if cur > 0:
        clauses.append("rowid < ?")
        args.append(cur)
    where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
    try:
        rows = (await conn.execute(
            f"SELECT *, rowid AS _rowid FROM audit_log {where} ORDER BY rowid DESC LIMIT ?", (*args, limit + 1)  # noqa: S608
        )).fetchall()
    except sqlite3.OperationalError:
        rows = []
    data = [dict(r) for r in rows[:limit]]
    next_cursor = str(rows[limit]["_rowid"]) if len(rows) > limit else ""
    return {"data": data, "next_cursor": next_cursor}


@router.get("/admin/audit/export")
async def audit_export(entity: str | None = Query(default=None),
                 actor_id: str | None = Query(default=None, max_length=80),
                 action: str | None = Query(default=None, max_length=80),
                 limit: int = Query(default=200, ge=1, le=1000),
                 conn=Depends(get_db_conn), user=Admin):
    """Filtered audit as CSV (same filters as the viewer; header follows the
    live table shape, whichever migration owns it)."""
    import csv
    import io

    from fastapi.responses import PlainTextResponse

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
    data = [dict(r) for r in rows]
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(list(data[0].keys()) if data else ["empty"])
    for r in data:
        writer.writerow([r.get(k, "") for k in (list(data[0].keys()) if data else [])])
    return PlainTextResponse(buf.getvalue(), media_type="text/csv")


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
    today = ist_today()
    since = (_dt.datetime.fromisoformat(today) - _dt.timedelta(days=days)).date().isoformat()
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
    # Phase 6 S6.3: directory totals for the analytics Customers card
    # (trust-style counts ride the list read — one GROUP BY, no new route).
    by_role = {str(r["role"]): int(r["c"]) for r in (await conn.execute(
        "SELECT role, COUNT(*) c FROM users GROUP BY role")).fetchall()}
    return {"data": data, "next_cursor": next_cursor,
            "counts": {"total": sum(by_role.values()), **by_role}}


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
                   query: str | None = Query(default=None, max_length=80),
                   limit: int = Query(default=50, ge=1, le=200),
                   cursor: str = Query(default=""),
                   conn=Depends(get_db_conn), user=Admin):
    data, next_cursor = await AdminReadRepo(conn).payments_page(
        status=status or "", method=method or "", query=query or "",
        limit=limit, cursor=_cursor(cursor))
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
