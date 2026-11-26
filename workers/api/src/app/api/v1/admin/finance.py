from __future__ import annotations

import json
import uuid

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.api.auth_deps import get_current_user, require_role  # noqa: F401
from app.api.deps import get_db_conn
from app.core.errors import ConflictError, NotFoundError, ValidationError
from app.core.http_utils import user_id as _uid
from app.core.time_utils import utc_now_iso as _now
from app.db import WRITE_LOCK
from app.repositories.admin_read_repo import AdminReadRepo, ist_today
from app.repositories.ledger_repo import LedgerRepo
from app.services.dispatch_service import (
    ensure_profile,
)
from app.api.v1.admin._common import *  # noqa: F401, F403

router = APIRouter(tags=["admin"])

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
        row["in_hand_custody"] = int(prof.get("in_hand", 0))
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
        prof = await ensure_profile(conn, row["vendor_id"])
        in_hand = int(prof.get("in_hand", 0))
        await conn.execute("UPDATE payouts SET status = 'approved', approved_by = ? WHERE id = ?",
                     (_uid(user), payout_id))
        after = dict((await conn.execute("SELECT * FROM payouts WHERE id = ?", (payout_id,))).fetchone())
        after["in_hand_custody"] = in_hand
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


class LeaveReviewIn(BaseModel):
    action: str = Field(pattern=r"^(approved|rejected)$")
    cover_vendor_id: str | None = Field(default=None)
    note: str = Field(default="", max_length=500)


