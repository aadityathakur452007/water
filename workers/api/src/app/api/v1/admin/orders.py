from __future__ import annotations


from fastapi import APIRouter, Depends, Query

from app.api.auth_deps import get_current_user, require_role  # noqa: F401
from app.api.deps import get_db_conn
from app.core.errors import ValidationError
from app.core.http_utils import user_id as _uid
from app.db import WRITE_LOCK
from app.repositories.order_repo import OrderRepo
from app.services.dispatch_service import (
    assign_order,
    auto_repool,
    generate_routes,
    reassign_order,
    set_delivery_window,
)
from app.api.v1.admin._common import *  # noqa: F401, F403

router = APIRouter(tags=["admin"])

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
        await set_delivery_window(conn, s["id"])
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

