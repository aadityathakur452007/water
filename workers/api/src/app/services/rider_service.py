from __future__ import annotations

import datetime as _dt
import json
import sqlite3
from typing import Any

from app.adapters.firebase import UnauthError
from app.core.errors import NotFoundError, ValidationError
from app.services.vendor_service import VendorService


def _today() -> str:
    # IST day bucket (UTC + 5:30)
    utc = _dt.datetime.now(_dt.timezone.utc)
    ist = utc + _dt.timedelta(hours=5, minutes=30)
    return ist.date().isoformat()


class RiderService:
    def __init__(self, conn: sqlite3.Connection):
        self._conn = conn
        self._vendor_svc = VendorService(conn)

    async def _get_rider(self, rider_id: str) -> dict:
        row = (await self._conn.execute(
            "SELECT id, name, phone, role, assigned_vendor_id, suspended FROM users WHERE id = ?",
            (rider_id,),
        )).fetchone()
        if row is None or row["role"] != "rider":
            raise UnauthError("Rider not found or unauthorized.", {})
        if bool(row["suspended"]):
            raise UnauthError("Rider account is suspended.", {})
        return dict(row)

    async def routes_today(self, rider_id: str, date: str | None = None) -> dict:
        rider = await self._get_rider(rider_id)
        vendor_id = rider.get("assigned_vendor_id")
        if not vendor_id:
            return {"rider": rider, "stops": [], "summary": {"total": 0, "delivered": 0, "pending": 0}}

        day = date or _today()
        # Find route for the vendor on the given day
        route_row = (await self._conn.execute(
            "SELECT id, date, vendor_id, zone, status FROM routes WHERE vendor_id = ? AND date = ?",
            (vendor_id, day),
        )).fetchone()
        if route_row is None:
            return {"rider": rider, "stops": [], "summary": {"total": 0, "delivered": 0, "pending": 0}}

        route_id = route_row["id"]

        # Fetch stops for this route assigned to this rider OR unassigned (NULL rider_id)
        query = (
            "SELECT s.id, s.route_id, s.order_id, s.customer_id, s.seq, s.fulls_exp, s.empties_exp, "
            " s.status, s.triple, s.rider_id, "
            " o.payment_mode, o.payment_status, o.total, o.state AS order_state, o.instructions, "
            " a.formatted AS address_text, a.landmark, a.lift_flag, "
            " u.name AS customer_name, u.phone AS customer_phone "
            " FROM stops s "
            " LEFT JOIN orders o ON o.id = s.order_id "
            " LEFT JOIN addresses a ON a.id = o.address_id "
            " LEFT JOIN users u ON u.id = s.customer_id "
            " WHERE s.route_id = ? AND (s.rider_id = ? OR s.rider_id IS NULL) "
            " ORDER BY s.seq ASC"
        )
        rows = (await self._conn.execute(query, (route_id, rider_id))).fetchall()

        stops: list[dict[str, Any]] = []
        for r in rows:
            d = dict(r)
            # Payment calculation: if COD and not paid, amount due is order total
            is_cod = (d.get("payment_mode") or "").lower() == "cod"
            is_paid = (d.get("payment_status") or "").lower() == "paid"
            amount_due = int(d.get("total") or 0) if (is_cod and not is_paid) else 0

            stops.append({
                "id": d["id"],
                "seq": d["seq"],
                "status": d["status"],
                "order_id": d["order_id"],
                "customer_name": d["customer_name"] or "Customer",
                "customer_phone": d["customer_phone"] or "",
                "quantity": int(d["fulls_exp"] or 1),
                "empties_expected": int(d["empties_exp"] or 0),
                "payment_mode": "cod" if is_cod else "prepaid",
                "is_paid": is_paid,
                "amount_due": amount_due,
                "address": {
                    "formatted": d["address_text"] or "Delivery address",
                    "landmark": d["landmark"] or "",
                    "has_lift": bool(d.get("lift_flag")),
                },
                "instructions": d.get("instructions") or "",
            })

        total = len(stops)
        delivered = sum(1 for s in stops if s["status"] == "done")
        pending = sum(1 for s in stops if s["status"] == "pending")

        return {
            "rider": rider,
            "route_id": route_id,
            "date": day,
            "stops": stops,
            "summary": {
                "total": total,
                "delivered": delivered,
                "pending": pending,
            },
        }

    async def complete_stop(self, rider_id: str, stop_id: str, payload: dict) -> dict:
        rider = await self._get_rider(rider_id)
        vendor_id = rider.get("assigned_vendor_id")
        if not vendor_id:
            raise ValidationError("Rider is not assigned to a vendor.", {})

        # Verify stop belongs to a route owned by the rider's vendor
        stop = (await self._conn.execute(
            "SELECT s.id, r.vendor_id FROM stops s JOIN routes r ON s.route_id = r.id WHERE s.id = ?",
            (stop_id,),
        )).fetchone()
        if stop is None or stop["vendor_id"] != vendor_id:
            raise NotFoundError("Stop not found.", {"stop_id": stop_id})

        # Delegate to proven, hardened VendorService.pod_complete
        result = await self._vendor_svc.pod_complete(vendor_id, stop_id, payload)

        # If cash was collected and amount > 0, post cash automatically
        cash_amt = int(payload.get("cash") or 0)
        if cash_amt > 0:
            try:
                await self._vendor_svc.cash_post(vendor_id, stop_id, cash_amt)
            except Exception:
                pass

        return {
            "status": "delivered",
            "stop_id": stop_id,
            "replay": result.get("replay", False),
        }

    async def fail_stop(self, rider_id: str, stop_id: str, reason_code: str, note: str = "") -> dict:
        rider = await self._get_rider(rider_id)
        vendor_id = rider.get("assigned_vendor_id")
        if not vendor_id:
            raise ValidationError("Rider is not assigned to a vendor.", {})
        return await self._vendor_svc.fail_stop(vendor_id, stop_id, reason_code, note)
