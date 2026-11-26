from __future__ import annotations


from fastapi import APIRouter, Depends, Query

from app.api.auth_deps import get_current_user, require_role  # noqa: F401
from app.api.deps import get_db_conn
from app.core.errors import NotFoundError, ValidationError
from app.core.http_utils import user_id as _uid
from app.core.time_utils import utc_now_iso as _now
from app.db import WRITE_LOCK
from app.repositories.admin_read_repo import AdminReadRepo
from app.services.auth_service import AuthService
from app.api.v1.admin._common import *  # noqa: F401, F403

router = APIRouter(tags=["admin"])

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
    Never deletes the account; never touches admins (no lockout path).
    If user is a vendor:
    - deactivates vendor_profile and sets review_hold
    - auto-repools active/pending stops back to zone pool
    - disassociates attached riders and revokes their sessions
    """
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

        repooled_stops = 0
        detached_riders = 0
        if row["role"] == "vendor":
            # 1. Deactivate vendor profile
            await conn.execute(
                "UPDATE vendor_profile SET active = 0, review_hold = 1, updated_at = ? WHERE user_id = ?",
                (now, user_id),
            )
            # 2. Auto-repool active/pending stops
            from app.services.dispatch_service import auto_repool  # noqa: PLC0415
            try:
                res = await auto_repool(conn, user_id, actor=user)
                repooled_stops = int(res.get("repooled", 0))
            except Exception:
                pass
            # 3. Disassociate attached riders and revoke rider sessions
            riders = (await conn.execute(
                "SELECT id FROM users WHERE assigned_vendor_id = ? AND role = 'rider'",
                (user_id,),
            )).fetchall()
            if riders:
                detached_riders = len(riders)
                r_ids = [str(r["id"]) for r in riders]
                await conn.execute(
                    "UPDATE users SET assigned_vendor_id = NULL WHERE assigned_vendor_id = ? AND role = 'rider'",
                    (user_id,),
                )
                placeholders = ",".join("?" for _ in r_ids)
                cur_riders = await conn.execute(
                    f"UPDATE sessions SET revoked_at = ? WHERE user_id IN ({placeholders}) AND revoked_at IS NULL",
                    (now, *r_ids),
                )
                revoked += cur_riders.rowcount if cur_riders.rowcount and cur_riders.rowcount > 0 else 0

        await _audit(conn, user, f"user.{payload.level}", "users", user_id,
               {"suspended": bool(row["suspended"]), "reason": row["suspended_reason"]},
               {"level": payload.level, "reason": payload.reason, "revoked_sessions": revoked,
                "repooled_stops": repooled_stops, "detached_riders": detached_riders})
        conn.commit()
    return {"user_id": user_id, "level": payload.level,
            "suspended": True, "revoked_sessions": revoked,
            "repooled_stops": repooled_stops, "detached_riders": detached_riders}


@router.post("/admin/users/{user_id}/unsuspend")
async def admin_unsuspend_user(user_id: str, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        row = (await conn.execute("SELECT * FROM users WHERE id = ?", (user_id,))).fetchone()
        if row is None:
            raise NotFoundError(message="User not found.", details={"id": user_id})
        now = _now()
        await conn.execute(
            "UPDATE users SET suspended = 0, suspended_reason = NULL, suspended_by = NULL,"
            " suspended_at = NULL WHERE id = ?",
            (user_id,),
        )
        if row["role"] == "vendor":
            await conn.execute(
                "UPDATE vendor_profile SET active = 1, review_hold = 0, updated_at = ? WHERE user_id = ?",
                (now, user_id),
            )
        await _audit(conn, user, "user.unsuspend", "users", user_id,
               {"suspended": bool(row["suspended"]), "reason": row["suspended_reason"]},
               {"suspended": False})
        conn.commit()
    return {"user_id": user_id, "suspended": False}


@router.post("/admin/users/{user_id}/password-reset")
async def admin_password_reset(
    user_id: str, payload: PasswordResetIn,
    conn=Depends(get_db_conn), user=Admin,
):
    """Support-only reset: new hash, all sessions revoked, admin audit row.

    There is no customer self-service reset in 034; a forgotten password is
    handled through this door.
    """
    return await AuthService(conn, None).reset_user_password(
        user_id, payload.new_password, actor_id=_uid(user)
    )


@router.post("/admin/users/{user_id}/assign-vendor")
async def admin_assign_user_vendor(
    user_id: str,
    payload: AssignUserVendorIn,
    conn=Depends(get_db_conn),
    user=Admin,
):
    """Directly assign or unassign a customer to a vendor.

    Enables admin to bind customer upon registration to a trusted vendor
    so all subsequent orders route to that vendor without repetitive manual clicks.
    """
    with WRITE_LOCK:
        target = (await conn.execute("SELECT id, name, role, assigned_vendor_id FROM users WHERE id = ?", (user_id,))).fetchone()
        if target is None:
            raise NotFoundError(message="User not found.", details={"id": user_id})

        vendor_id = (payload.vendor_id or "").strip() or None
        vendor_name = None
        if vendor_id:
            vendor = (await conn.execute("SELECT id, name, role, suspended FROM users WHERE id = ? AND role = 'vendor'", (vendor_id,))).fetchone()
            if vendor is None:
                raise NotFoundError(message="Vendor not found or not an active vendor.", details={"vendor_id": vendor_id})
            if bool(vendor["suspended"]):
                raise ValidationError(message="Cannot assign a suspended vendor.", details={"vendor_id": vendor_id})
            vendor_name = vendor["name"]

        before_vendor = target["assigned_vendor_id"]
        await conn.execute(
            "UPDATE users SET assigned_vendor_id = ? WHERE id = ?",
            (vendor_id, user_id),
        )
        await _audit(
            conn,
            user,
            "user.assign_vendor",
            "users",
            user_id,
            {"assigned_vendor_id": before_vendor},
            {"assigned_vendor_id": vendor_id},
        )
        if vendor_id:
            try:
                from app.services.dispatch_service import auto_assign_trusted_vendor
                placed_orders = (await conn.execute(
                    "SELECT id FROM orders WHERE user_id = ? AND state IN ('placed', 'accepted', 'picked', 'packed')",
                    (user_id,),
                )).fetchall()
                for p_order in placed_orders:
                    try:
                        await auto_assign_trusted_vendor(conn, p_order["id"], user_id)
                    except Exception:
                        pass
            except Exception:
                pass
        conn.commit()

    return {
        "user_id": user_id,
        "assigned_vendor_id": vendor_id,
        "assigned_vendor_name": vendor_name,
        "success": True,
    }


