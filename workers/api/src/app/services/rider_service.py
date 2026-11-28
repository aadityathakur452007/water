from __future__ import annotations

import datetime as _dt
import re
import sqlite3
from typing import Any

from app.adapters.firebase import UnauthError
from app.core.errors import NotFoundError, ValidationError
from app.services.vendor_service import VendorService


def mask_phone(phone: str | None) -> str:
    """Mask customer phone number to prevent poaching and direct off-platform circumvention."""
    if not phone:
        return ""
    digits = re.sub(r"\D", "", phone)
    if len(digits) >= 10:
        last10 = digits[-10:]
        prefix = f"+{digits[:-10]} " if len(digits) > 10 else "+91 "
        return f"{prefix}{last10[:2]}*** **{last10[-3:]}"
    if len(digits) >= 6:
        return f"{digits[:2]}***{digits[-2:]}"
    return "***"


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

    async def ensure_rider_profile(self, rider_id: str) -> dict:
        from app.db import WRITE_LOCK

        cols = {r["name"] for r in (await self._conn.execute(
            "SELECT name FROM pragma_table_info('rider_profile')")).fetchall()}
        if "user_id" not in cols:
            with WRITE_LOCK:
                await self._conn.execute(
                    "CREATE TABLE IF NOT EXISTS rider_profile ("
                    "user_id TEXT PRIMARY KEY REFERENCES users(id),"
                    " duty_status TEXT NOT NULL DEFAULT 'on_duty',"
                    " duty_on TEXT, duty_off TEXT, updated_at TEXT)"
                )
                self._conn.commit()
        row = (await self._conn.execute(
            "SELECT * FROM rider_profile WHERE user_id = ?", (rider_id,)
        )).fetchone()
        if row is None:
            now_iso = _dt.datetime.now(_dt.timezone.utc).isoformat()
            with WRITE_LOCK:
                await self._conn.execute(
                    "INSERT OR IGNORE INTO rider_profile(user_id, duty_status, duty_on, updated_at)"
                    " VALUES (?, 'on_duty', ?, ?)",
                    (rider_id, now_iso, now_iso),
                )
                self._conn.commit()
            row = (await self._conn.execute(
                "SELECT * FROM rider_profile WHERE user_id = ?", (rider_id,)
            )).fetchone()
        return dict(row)

    async def get_duty(self, rider_id: str) -> dict:
        rider = await self._get_rider(rider_id)
        prof = await self.ensure_rider_profile(rider_id)
        return {
            "rider_id": rider_id,
            "name": rider.get("name"),
            "duty_status": prof.get("duty_status", "on_duty"),
            "duty_on": prof.get("duty_on"),
            "duty_off": prof.get("duty_off"),
        }

    async def set_duty(self, rider_id: str, new_status: str) -> dict:
        from app.core.state_machines import validate_rider_duty_transition
        from app.db import WRITE_LOCK

        await self._get_rider(rider_id)
        prof = await self.ensure_rider_profile(rider_id)
        current = prof.get("duty_status", "on_duty")
        validate_rider_duty_transition(current, new_status)
        now_iso = _dt.datetime.now(_dt.timezone.utc).isoformat()
        with WRITE_LOCK:
            if new_status == "on_duty":
                await self._conn.execute(
                    "UPDATE rider_profile SET duty_status = ?, duty_on = ?, duty_off = NULL, updated_at = ? WHERE user_id = ?",
                    (new_status, now_iso, now_iso, rider_id),
                )
            else:
                await self._conn.execute(
                    "UPDATE rider_profile SET duty_status = ?, duty_off = ?, updated_at = ? WHERE user_id = ?",
                    (new_status, now_iso, now_iso, rider_id),
                )
            self._conn.commit()
        return await self.get_duty(rider_id)

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

        cols = {r["name"] for r in (
            await self._conn.execute("SELECT name FROM pragma_table_info('stops')")
        ).fetchall()}
        fr_col = ", s.failure_reason" if "failure_reason" in cols else ""

        # Fetch stops for this route assigned to this rider OR unassigned (NULL rider_id)
        # Only include today's deliveries (exclude previous-day orders that lingered on route)
        query = (
            f"SELECT s.id, s.route_id, s.order_id, s.return_id, s.customer_id, s.seq, s.fulls_exp, s.empties_exp, "
            f" s.status, s.triple, s.rider_id{fr_col}, "
            " o.payment_mode, o.payment_status, o.total, o.state AS order_state, o.instructions, o.idempotency_key, "
            " a.formatted AS address_text, a.landmark, a.lift_flag, "
            " u.name AS customer_name, u.phone AS customer_phone "
            " FROM stops s "
            " LEFT JOIN orders o ON o.id = s.order_id "
            " LEFT JOIN returns ret ON ret.id = s.return_id "
            " LEFT JOIN addresses a ON a.id = COALESCE(o.address_id, ret.address_id) "
            " LEFT JOIN users u ON u.id = s.customer_id "
            " WHERE s.route_id = ? AND (s.rider_id = ? OR s.rider_id IS NULL) "
            " AND (o.window_start IS NULL OR length(o.window_start) < 10 "
            "      OR substr(o.window_start, 5, 1) != '-' "
            "      OR substr(o.window_start, 1, 10) >= ?) "
            " ORDER BY s.seq ASC"
        )
        rows = (await self._conn.execute(query, (route_id, rider_id, day))).fetchall()

        # Batch-load subscriptions and ledger (held + dues) in 2 queries total (zero N+1)
        cust_ids = list({r["customer_id"] for r in rows if r["customer_id"]})
        subs_by_customer: dict[str, tuple[str, str]] = {}
        held_by_customer: dict[str, int] = {}
        dues_by_customer: dict[str, int] = {}
        if cust_ids:
            ph = ",".join("?" for _ in cust_ids)
            try:
                sub_cols = {
                    r["name"]
                    for r in (
                        await self._conn.execute("SELECT name FROM pragma_table_info('subscriptions')")
                    ).fetchall()
                }
                bm_sel = "billing_mode" if "billing_mode" in sub_cols else "'monthly_postpaid' AS billing_mode"
                sub_rows = (await self._conn.execute(
                    f"SELECT user_id, {bm_sel}, status FROM subscriptions"  # noqa: S608
                    f" WHERE user_id IN ({ph})",
                    tuple(cust_ids),
                )).fetchall()
                for sr in sub_rows:
                    uid = str(sr["user_id"])
                    st = str(sr["status"] or "")
                    bm = str(sr["billing_mode"] or "")
                    # Active subscription always takes precedence over cancelled/paused
                    if uid not in subs_by_customer or st == "active":
                        subs_by_customer[uid] = (st, bm)
            except Exception:
                pass
            try:
                led_rows = (await self._conn.execute(
                    f"SELECT customer_id, held, dues FROM ledger WHERE customer_id IN ({ph})",  # noqa: S608
                    tuple(cust_ids),
                )).fetchall()
                for lr in led_rows:
                    cid = str(lr["customer_id"])
                    held_by_customer[cid] = max(0, int(lr["held"] or 0))
                    dues_by_customer[cid] = max(0, int(lr["dues"] or 0))
            except Exception:
                pass

        seen_dues_customers: set[str] = set()
        stops: list[dict[str, Any]] = []
        for r in rows:
            d = dict(r)
            cust_id = d.get("customer_id")
            sub_info = subs_by_customer.get(cust_id) if cust_id else None
            is_sub = sub_info is not None and sub_info[0] == "active"
            sub_billing_mode = sub_info[1] if is_sub else None
            idem_key = str(d.get("idempotency_key") or "")
            is_sub_order = is_sub and (idem_key.startswith("sub:") or ":sub:" in idem_key)
            dues_paise = dues_by_customer.get(cust_id, 0) if cust_id else 0
            jars_held = held_by_customer.get(cust_id, 0) if cust_id else 0

            is_cod = (d.get("payment_mode") or "").lower() == "cod"
            is_paid = (d.get("payment_status") or "").lower() in ("paid", "paid_upi", "paid_cash")
            order_amt = int(d.get("total") or 0) if (is_cod and not is_paid) else 0

            stop_status = d["status"]
            order_state = d.get("order_state") or ""
            failure_reason = d.get("failure_reason") or ""
            if order_state == "cancelled" or failure_reason.startswith("CANCELLED"):
                stop_status = "cancelled"

            # 3-case payment resolution (order-scoped, not customer-wide):
            # 1. Active subscription scheduled refill (`sub:`): ₹0 daily cash
            # 2. Cancelled/inactive subscription with pending dues: collect dues once + this order's COD
            # 3. Extra jar or regular one-time order: collect order COD total (or ₹0 if prepaid)
            is_monthly_dues = False
            if is_sub_order and sub_billing_mode in ("monthly_postpaid", "monthly_prepaid", "weekly_postpaid"):
                amount_due = 0
            elif not is_sub and dues_paise > 0 and stop_status == "pending" and cust_id and cust_id not in seen_dues_customers:
                amount_due = max(order_amt, dues_paise)
                is_monthly_dues = True
                seen_dues_customers.add(cust_id)
            else:
                amount_due = order_amt

            qty = int(d["fulls_exp"] or 1)
            max_empties = jars_held
            cash_collected = 0
            try:
                triple_raw = d.get("triple")
                triple_obj = json.loads(triple_raw) if isinstance(triple_raw, str) and triple_raw else (
                    triple_raw if isinstance(triple_raw, dict) else {}
                )
                pod_obj = triple_obj.get("pod") if isinstance(triple_obj.get("pod"), dict) else {}
                cash_collected = int(pod_obj.get("cash") or triple_obj.get("cash") or 0)
            except Exception:
                cash_collected = 0

            stops.append({
                "id": d["id"],
                "seq": d["seq"],
                "status": stop_status,
                "order_state": order_state,
                "failure_reason": failure_reason,
                "order_id": d["order_id"],
                "customer_name": d["customer_name"] or "Customer",
                "customer_phone": (d["customer_phone"] or "").strip(),
                "quantity": qty,
                "jars_held": jars_held,
                "max_empties": max_empties,
                "empties_expected": max_empties,
                "payment_mode": "cod" if is_cod else "prepaid",
                "payment_status": (d.get("payment_status") or "unpaid").lower(),
                "is_paid": is_paid,
                "cash_collected": cash_collected,
                "amount_due": amount_due,
                "order_amount": order_amt,
                "is_subscription": is_sub_order,
                "is_monthly_dues": is_monthly_dues,
                "monthly_dues": dues_paise if is_monthly_dues else 0,
                "billing_mode": sub_billing_mode or ("monthly_postpaid" if is_sub_order else "per_delivery"),
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
        prof = await self.ensure_rider_profile(rider_id)

        return {
            "rider": rider,
            "route_id": route_id,
            "date": day,
            "duty_status": prof.get("duty_status", "on_duty"),
            "stops": stops,
            "summary": {
                "total": total,
                "delivered": delivered,
                "pending": pending,
            },
        }

    async def complete_stop(self, rider_id: str, stop_id: str, payload: dict) -> dict:
        rider = await self._get_rider(rider_id)
        prof = await self.ensure_rider_profile(rider_id)
        if prof.get("duty_status") != "on_duty":
            raise ValidationError("Rider must be on duty to deliver stops.",
                                  details={"duty_status": prof.get("duty_status")})
        vendor_id = rider.get("assigned_vendor_id")
        if not vendor_id:
            raise ValidationError("Rider is not assigned to a vendor.", {})

        from app.db import WRITE_LOCK
        from app.services.dispatch_service import write_audit

        # Verify stop belongs to a route owned by the rider's vendor
        stop = (await self._conn.execute(
            "SELECT s.id, r.vendor_id, s.rider_id, s.customer_id, s.fulls_exp FROM stops s JOIN routes r ON s.route_id = r.id WHERE s.id = ?",
            (stop_id,),
        )).fetchone()
        if stop is None or stop["vendor_id"] != vendor_id:
            raise NotFoundError("Stop not found.", {"stop_id": stop_id})

        # Security check: If stop is explicitly assigned to another rider, reject
        if stop["rider_id"] is not None and stop["rider_id"] != rider_id:
            raise NotFoundError("Stop not found.", {"stop_id": stop_id})

        # Enforce empty jar limit: cap at min(quantity, customer's held jars) when ledger exists
        sanitized_payload = dict(payload)
        cust_id = stop["customer_id"]
        if cust_id and "empties_count" in sanitized_payload:
            try:
                led = (await self._conn.execute(
                    "SELECT held, dues FROM ledger WHERE customer_id = ?",
                    (cust_id,),
                )).fetchone()
                if led is not None:
                    jars_held = max(0, int(led["held"] or 0))
                    req_empties = max(0, int(sanitized_payload.get("empties_count") or 0))
                    sanitized_payload["empties_count"] = min(req_empties, jars_held)
            except Exception:
                pass

        # Link rider_id before pod_complete so vendor route/stop reflects the rider
        if stop["rider_id"] is None:
            with WRITE_LOCK:
                await self._conn.execute(
                    "UPDATE stops SET rider_id = ? WHERE id = ?",
                    (rider_id, stop_id),
                )
                self._conn.commit()

        # Delegate to proven, hardened VendorService.pod_complete
        result = await self._vendor_svc.pod_complete(vendor_id, stop_id, sanitized_payload)

        try:
            await write_audit(
                self._conn,
                actor=rider_id,
                action="rider.complete_stop",
                entity="stops",
                entity_id=stop_id,
            )
        except Exception:
            pass

        # If cash was collected (> 0), ensure ledger dues are cleared and vendor in_hand reflects it
        cash_amt = int(sanitized_payload.get("cash") or 0)
        if cash_amt > 0 and cust_id and not result.get("replay"):
            try:
                from app.repositories.ledger_repo import LedgerRepo
                led = (await self._conn.execute(
                    "SELECT dues FROM ledger WHERE customer_id = ?",
                    (cust_id,),
                )).fetchone()
                dues_now = max(0, int(led["dues"] or 0)) if led else 0
                if dues_now > 0:
                    clear_amt = min(cash_amt, dues_now)
                    await LedgerRepo(self._conn).apply_event(
                        cust_id,
                        d_dues=-clear_amt,
                        ref=f"stop:{stop_id}",
                        actor=rider_id,
                        reason="rider cash dues collected",
                    )
            except Exception:
                pass
            # If pod_complete couldn't post cash (e.g. order total was 0 on dues stop), ensure vendor_profile.in_hand is credited
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
        from app.services.dispatch_service import write_audit

        rider = await self._get_rider(rider_id)
        prof = await self.ensure_rider_profile(rider_id)
        if prof.get("duty_status") != "on_duty":
            raise ValidationError("Rider must be on duty to update stops.",
                                  details={"duty_status": prof.get("duty_status")})
        vendor_id = rider.get("assigned_vendor_id")
        if not vendor_id:
            raise ValidationError("Rider is not assigned to a vendor.", {})

        stop = (await self._conn.execute(
            "SELECT s.id, r.vendor_id, s.rider_id FROM stops s JOIN routes r ON s.route_id = r.id WHERE s.id = ?",
            (stop_id,),
        )).fetchone()
        if stop is None or stop["vendor_id"] != vendor_id:
            raise NotFoundError("Stop not found.", {"stop_id": stop_id})

        if stop["rider_id"] is not None and stop["rider_id"] != rider_id:
            raise NotFoundError("Stop not found.", {"stop_id": stop_id})

        out = await self._vendor_svc.fail_stop(vendor_id, stop_id, reason_code, note)
        try:
            await write_audit(
                self._conn,
                actor=rider_id,
                action="rider.fail_stop",
                entity="stops",
                entity_id=stop_id,
            )
        except Exception:
            pass
        return out

    async def cancel_stop(
        self,
        rider_id: str,
        stop_id: str,
        cancel_otp: str,
        reason: str = "CUSTOMER_UNREACHABLE",
    ) -> dict:
        import hmac
        from app.db import WRITE_LOCK
        from app.core.errors import ConflictError, NotFoundError, ValidationError
        from app.repositories.order_repo import OrderRepo
        from app.services.dispatch_service import write_audit
        from app.services.vendor_service import _ensure_stop_cancel_cols

        rider = await self._get_rider(rider_id)
        vendor_id = rider.get("assigned_vendor_id")
        if not vendor_id:
            raise ValidationError("Rider is not assigned to a vendor.", {})

        await _ensure_stop_cancel_cols(self._conn)

        stop = (await self._conn.execute(
            "SELECT s.id, s.route_id, s.order_id, s.status, s.cancel_otp, s.rider_id, r.vendor_id "
            "FROM stops s JOIN routes r ON s.route_id = r.id WHERE s.id = ?",
            (stop_id,),
        )).fetchone()
        if stop is None or stop["vendor_id"] != vendor_id:
            raise NotFoundError("Stop not found.", {"stop_id": stop_id})
        if stop["rider_id"] is not None and stop["rider_id"] != rider_id:
            raise NotFoundError("Stop not found.", {"stop_id": stop_id})
        if stop["status"] in ("done", "failed"):
            raise ConflictError("Stop is already finalized.", {"status": stop["status"]})

        expected_otp = str(stop["cancel_otp"] or "").strip()
        provided_otp = str(cancel_otp or "").strip()
        if not expected_otp or not hmac.compare_digest(expected_otp, provided_otp):
            raise ValidationError("Invalid cancellation OTP. Ask vendor for OTP.", {"cancel_otp": cancel_otp})

        order_id = stop["order_id"]
        if order_id:
            try:
                await OrderRepo(self._conn).transition(
                    order_id, "cancelled", {"id": rider_id, "role": "rider"}, f"Rider cancelled: {reason}"
                )
            except Exception:
                try:
                    await OrderRepo(self._conn).transition(
                        order_id, "failed", {"id": rider_id, "role": "rider"}, f"Rider cancelled: {reason}"
                    )
                except Exception:
                    pass

        now = _dt.datetime.now(_dt.timezone.utc).isoformat()
        with WRITE_LOCK:
            await self._conn.execute(
                "UPDATE stops SET status = 'failed', failure_reason = ?, cancel_otp = NULL, synced_at = ? WHERE id = ?",
                (f"CANCELLED: {reason}", now, stop_id),
            )
            self._conn.commit()

        try:
            await write_audit(
                self._conn,
                actor=rider_id,
                action="rider.cancel_stop",
                entity="stops",
                entity_id=stop_id,
            )
        except Exception:
            pass

        return {"stop_id": stop_id, "status": "cancelled", "reason": reason}
