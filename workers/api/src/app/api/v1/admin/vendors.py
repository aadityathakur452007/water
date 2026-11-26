from __future__ import annotations

import datetime as _dt
import hashlib
import secrets
import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.api.auth_deps import get_current_user, require_role  # noqa: F401
from app.api.deps import get_db_conn
from app.core.errors import AppError, ConflictError, NotFoundError, ValidationError
from app.core.http_utils import user_id as _uid
from app.core.time_utils import utc_now_iso as _now
from app.db import WRITE_LOCK
from app.repositories.access_code_repo import AccessCodeRepo
from app.repositories.admin_read_repo import AdminReadRepo
from app.repositories.vendor_access_repo import VendorAccessRepo
from app.services.auth_service import normalize_phone
from app.services.dispatch_service import (
    ensure_profile,
)
from app.services.vendor_service import VendorService
from app.api.v1.admin._common import *  # noqa: F401, F403

router = APIRouter(tags=["admin"])

@router.post("/admin/vendors", status_code=201)
async def vendor_create(payload: VendorCreateIn, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        phone_n = normalize_phone(payload.phone)
        if (await conn.execute("SELECT id FROM users WHERE phone = ? OR phone = ?", (phone_n, payload.phone.strip()))).fetchone():
            raise ConflictError(message="Phone already registered.", details={"phone": payload.phone})
        if (await conn.execute("SELECT id FROM zones WHERE id = ?", (payload.zone_id,))).fetchone() is None:
            raise NotFoundError(message="Zone not found.", details={"id": payload.zone_id})
        vid = uuid.uuid4().hex
        now_iso = _now()
        role = "vendor" if payload.auto_verify else "user"
        kyc = "verified" if payload.auto_verify else "pending"
        await conn.execute(
            "INSERT INTO users(id, phone, name, role, language, kyc_status, suspended, created_at)"
            " VALUES (?, ?, ?, ?, 'hi', ?, 0, ?)",
            (vid, phone_n, payload.name.strip(), role, kyc, now_iso),
        )
        max_stops = payload.max_stops if payload.max_stops is not None else 50
        max_jars = payload.max_jars if payload.max_jars is not None else 250
        await conn.execute(
            "INSERT INTO vendor_profile(user_id, kyc_note, max_stops_per_shift, max_jars_per_shift, updated_at)"
            " VALUES (?, ?, ?, ?, ?)",
            (vid, payload.kyc_note or "Verified by Admin", max_stops, max_jars, now_iso),
        )
        await conn.execute("INSERT OR IGNORE INTO vendor_zones(vendor_id, zone_id) VALUES (?, ?)",
                     (vid, payload.zone_id))

        code = None
        expires = None
        if payload.auto_verify:
            code = secrets.token_urlsafe(12)
            code_id = uuid.uuid4().hex
            expires = _code_expiry(None)
            hint = f"••{code[-2:]}"
            code_hash = hashlib.sha256(code.encode()).hexdigest()
            admin_uid = _uid(user)
            try:
                await VendorAccessRepo(conn).issue(
                    code_id=code_id, vendor_id=vid,
                    code_hash=code_hash,
                    masked_hint=hint, expires_at=expires, created_by=admin_uid
                )
            except Exception:
                pass
            try:
                await AccessCodeRepo(conn).issue(
                    code_id=code_id, user_id=vid,
                    code_hash=code_hash, masked_hint=hint,
                    expected_role="vendor", expires_at=expires, created_by=admin_uid
                )
            except Exception:
                pass
            await _audit(conn, user, "vendor.access.issue", "vendor_access_codes", code_id,
                         "", {"vendor_id": vid, "expires_at": expires})

        await _audit(conn, user, "vendor.create", "users", vid, "", {"phone": phone_n, "role": role})
        conn.commit()

    res = {
        "id": vid,
        "phone": phone_n,
        "name": payload.name,
        "role": role,
        "kyc_status": kyc,
        "zone_id": payload.zone_id,
    }
    if code:
        res["code"] = code
        res["expires_at"] = expires
    return res


@router.post("/admin/vendors/{vendor_id}/capacity")
async def vendor_capacity_post(vendor_id: str, payload: CapacityPatchIn, conn=Depends(get_db_conn), user=Admin):
    return await vendor_capacity(vendor_id, payload, conn, user)


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


def _parse_iso_or_days(raw: str | None, default_days: int = 90) -> _dt.datetime:
    now = _dt.datetime.now(_dt.timezone.utc)
    if not raw or not raw.strip() or raw.strip().lower() in ("null", "none", "undefined"):
        return now + _dt.timedelta(days=default_days)
    val = raw.strip()
    if val.isdigit():
        days = int(val)
        return now + _dt.timedelta(days=max(1, days))
    normalized = val.replace("Z", "+00:00")
    if len(normalized) == 10 and normalized.count("-") == 2:
        try:
            dt = _dt.datetime.strptime(normalized, "%Y-%m-%d").replace(tzinfo=_dt.timezone.utc)
            return dt + _dt.timedelta(hours=23, minutes=59, seconds=59)
        except ValueError:
            pass
    try:
        dt = _dt.datetime.fromisoformat(normalized)
    except (ValueError, TypeError):
        raise ValidationError(message="expires_at must be ISO-8601.", details={"received": val})
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=_dt.timezone.utc)
    return dt


def _code_expiry(raw: str | None) -> str:
    dt = _parse_iso_or_days(raw, default_days=90)
    return dt.isoformat()


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
    dt = _parse_iso_or_days(raw, default_days=90)
    if dt < now + _dt.timedelta(hours=1) or dt > now + _dt.timedelta(days=180):
        raise ValidationError(
            message="expires_at must be between 1 hour and 180 days from now.",
            details={"received": str(raw)},
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


@router.get("/admin/vendors/{vendor_id}/orphan-customers")
async def get_orphan_customers(vendor_id: str, conn=Depends(get_db_conn), user=Admin):
    """List all customers assigned to this vendor (especially if suspended)."""
    v = (await conn.execute("SELECT id, name, role, suspended FROM users WHERE id = ?", (vendor_id,))).fetchone()
    if v is None:
        raise NotFoundError(message="Vendor not found.", details={"vendor_id": vendor_id})
    customers = (await conn.execute(
        "SELECT id, name, phone, email, created_at FROM users WHERE assigned_vendor_id = ? AND role = 'user' ORDER BY created_at DESC",
        (vendor_id,)
    )).fetchall()
    return {
        "vendor_id": vendor_id,
        "vendor_name": v["name"],
        "vendor_suspended": bool(v["suspended"]),
        "count": len(customers),
        "customers": [dict(c) for c in customers],
    }


@router.post("/admin/vendors/{vendor_id}/reassign-customers")
async def reassign_vendor_customers(
    vendor_id: str, payload: ReassignCustomersIn,
    conn=Depends(get_db_conn), user=Admin,
):
    """1-click reassign all customers from vendor_id to new_vendor_id.
    Also auto-assigns any placed/accepted/picked/packed orders for these customers to the new vendor.
    """
    with WRITE_LOCK:
        new_vendor = (await conn.execute(
            "SELECT id, name, role, suspended FROM users WHERE id = ? AND role = 'vendor'",
            (payload.new_vendor_id,)
        )).fetchone()
        if new_vendor is None:
            raise NotFoundError(message="New vendor not found.", details={"new_vendor_id": payload.new_vendor_id})
        if bool(new_vendor["suspended"]):
            raise ValidationError(message="Cannot reassign to a suspended vendor.", details={"new_vendor_id": payload.new_vendor_id})

        cur = await conn.execute(
            "UPDATE users SET assigned_vendor_id = ? WHERE assigned_vendor_id = ? AND role = 'user'",
            (payload.new_vendor_id, vendor_id)
        )
        reassigned_count = cur.rowcount if cur.rowcount and cur.rowcount > 0 else 0

        # Auto-assign unfulfilled orders
        from app.services.dispatch_service import auto_assign_trusted_vendor  # noqa: PLC0415
        orders_to_route = (await conn.execute(
            "SELECT o.id, o.user_id FROM orders o JOIN users u ON o.user_id = u.id "
            "WHERE u.assigned_vendor_id = ? AND o.state IN ('placed', 'accepted', 'picked', 'packed')",
            (payload.new_vendor_id,)
        )).fetchall()

        routed_orders = 0
        for o in orders_to_route:
            try:
                res = await auto_assign_trusted_vendor(conn, o["id"], o["user_id"])
                if res:
                    routed_orders += 1
            except Exception:
                pass

        await _audit(
            conn,
            user,
            "vendor.reassign_customers",
            "users",
            vendor_id,
            {"old_vendor_id": vendor_id},
            {"new_vendor_id": payload.new_vendor_id, "reassigned_customers": reassigned_count, "routed_orders": routed_orders, "reason": payload.reason}
        )
        conn.commit()

    return {
        "old_vendor_id": vendor_id,
        "new_vendor_id": payload.new_vendor_id,
        "reassigned_count": reassigned_count,
        "routed_orders": routed_orders,
    }


