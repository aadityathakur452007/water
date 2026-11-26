from __future__ import annotations

import datetime as _dt
import hashlib
import json
import secrets
import uuid

from app.core.errors import ConflictError, NotFoundError, ValidationError
from app.db import WRITE_LOCK
from app.services.vendor._common import (
    RIDER_CODE_TTL_DAYS,
    _decode_cursor,
    _encode_cursor,
    _ensure_stop_cancel_cols,
    _now,
    _today,
)

class VendorFleetMixin:
    async def earnings(self, vendor_id: str, shift: str | None = None) -> dict:
        day = shift or _today()
        rows = (await self._conn.execute(
            "SELECT s.triple FROM stops s JOIN routes r ON r.id = s.route_id"
            " WHERE r.vendor_id = ? AND r.date = ? AND s.status = 'done'",
            (vendor_id, day),
        )).fetchall()
        cash = upi = held_cash = held_upi = flagged = done = 0
        for r in rows:
            try:
                t = json.loads(r["triple"]) if r["triple"] else {}
            except (ValueError, TypeError):
                t = {}
            done += 1
            c, u = int(t.get("cash", 0)), int(t.get("upi", 0))
            cash += c
            upi += u
            if (t.get("pod") or {}).get("gps", {}).get("flagged"):
                flagged += 1
                held_cash += c
                held_upi += u
        prof_row = (await self._conn.execute(
            "SELECT in_hand, per_stop_fee FROM vendor_profile WHERE user_id = ?",
            (vendor_id,),
        )).fetchone()
        in_hand = int(prof_row["in_hand"]) if prof_row and prof_row["in_hand"] is not None else 0
        per_stop_fee = int(prof_row["per_stop_fee"]) if prof_row and prof_row["per_stop_fee"] is not None else 0
        earned_payout = done * per_stop_fee

        return {
            "shift": day,
            "stops_done": done,
            "cash_total": cash,
            "upi_total": upi,
            "in_hand": in_hand,
            "per_stop_fee": per_stop_fee,
            "earned_payout": earned_payout,
            "flagged_stops": flagged,
            "flagged_hold": held_cash + held_upi,  # §11: accrues, held out of payouts till cleared
            "note": "GPS-flagged stops accrue but are held out of payouts until admin clears the flag.",
        }

    # -- payouts (027 RBAC: READ-ONLY own payouts + custody) --------------------

    async def payouts_for_vendor(self, vendor_id: str, limit: int = 200,
                               cursor: str | None = None) -> dict:
        """Own payouts + in_hand custody. Owner-scoped by construction
        (``payouts WHERE vendor_id=?``); approve stays admin-only.
        Phase 8 §8.2: 200-cap + created_at|id cursor (same shape as orders)."""
        limit = max(1, min(int(limit), 200))
        args: list[object] = [vendor_id]
        cursor_sql = ""
        decoded = _decode_cursor(cursor or "")
        if decoded is not None:
            cursor_sql = " AND (created_at < ? OR (created_at = ? AND id < ?))"
            args += [decoded[0], decoded[0], decoded[1]]
        rows = (await self._conn.execute(
            "SELECT id, period, stops_done, gross_fee, deductions, net, status,"
            f" approved_by, created_at FROM payouts WHERE vendor_id = ?{cursor_sql}"  # noqa: S608
            " ORDER BY created_at DESC, id DESC LIMIT ?",
            (*args, limit + 1),
        )).fetchall()
        page = rows[:limit]
        next_cursor = _encode_cursor(page[-1]["created_at"], page[-1]["id"]) if len(rows) > limit else None
        try:
            prof = (await self._conn.execute(
                "SELECT in_hand FROM vendor_profile WHERE user_id = ?", (vendor_id,))).fetchone()
            in_hand = int(prof["in_hand"]) if prof is not None else 0
        except Exception:
            in_hand = 0  # pre-007 DBs: honest 0, never 500
        return {
            "payouts": [dict(r) for r in page],
            "in_hand": in_hand,
            "next_cursor": next_cursor,
            "note": "Payouts are approved by the agency; this view is read-only.",
        }

    # -- profile + slots (011_port: server vendor profile, Slice 1) --------------

    async def profile_get(self, vendor_id: str) -> dict:
        # Phase 5 §5.3: duty truth rides the profile read. Fully shape-
        # tolerant like _stop_field_cols — any applied migration subset
        # (pre-007 no table, 007-only duty shape, 011 port shape) reads
        # without writes (unlike ensure_profile, a read stays a read).
        blank = {"user_id": vendor_id, "name": "", "phone": "",
                 "address": "", "hours": "", "updated_at": None,
                 "on_duty": False}
        cols = {r["name"] for r in (await self._conn.execute(
            "SELECT name FROM pragma_table_info('vendor_profile')")).fetchall()}
        if "user_id" not in cols:
            return dict(blank)
        want = ("user_id", "name", "phone", "address", "hours",
                "updated_at", "on_duty")
        sel = ", ".join(k for k in want if k in cols)
        row = (await self._conn.execute(
            f"SELECT {sel} FROM vendor_profile WHERE user_id = ?",  # noqa: S608 (allowlisted cols)
            (vendor_id,),
        )).fetchone()
        if row is None:
            return dict(blank)
        out = dict(blank)
        out.update({k: v for k, v in dict(row).items() if v is not None})
        # Phase 5 §5.3: duty truth for the vendor switch (NULL → off).
        out["on_duty"] = bool(out.get("on_duty"))
        return out

    async def profile_save(self, vendor_id: str, patch: dict) -> dict:
        allow = ("name", "phone", "address", "hours")
        fields = {k: str(patch.get(k) or "")[:500] for k in allow if k in patch}
        current = await self.profile_get(vendor_id)
        merged = {**current, **fields, "updated_at": _now()}
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "INSERT INTO vendor_profile(user_id, name, phone, address, hours, updated_at)"
                    " VALUES (?, ?, ?, ?, ?, ?)"
                    " ON CONFLICT(user_id) DO UPDATE SET"
                    " name=excluded.name, phone=excluded.phone,"
                    " address=excluded.address, hours=excluded.hours, updated_at=excluded.updated_at",
                    (vendor_id, merged["name"], merged["phone"],
                     merged["address"], merged["hours"], merged["updated_at"]),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return await self.profile_get(vendor_id)

    async def slots_get(self, vendor_id: str) -> dict:
        rows = (await self._conn.execute(
            "SELECT slot_key, enabled FROM vendor_slots WHERE user_id = ?",
            (vendor_id,),
        )).fetchall()
        return {"user_id": vendor_id,
                "slots": {r["slot_key"]: bool(r["enabled"]) for r in rows}}

    async def slots_set(self, vendor_id: str, slots: dict) -> dict:
        items = {str(k)[:80]: (1 if v else 0) for k, v in dict(slots).items()}
        if len(items) > 50:
            raise ValidationError(message="Too many slots (max 50).", details={})
        with WRITE_LOCK:
            try:
                for key, enabled in items.items():
                    await self._conn.execute(
                        "INSERT INTO vendor_slots(user_id, slot_key, enabled) VALUES (?, ?, ?)"
                        " ON CONFLICT(user_id, slot_key) DO UPDATE SET enabled=excluded.enabled",
                        (vendor_id, key, enabled),
                    )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return await self.slots_get(vendor_id)

    # -- customers (011_port: derived from today_route stops — Water-native) -----

    async def today_customers(self, vendor_id: str, date: str | None = None) -> dict:
        day = date or _today()
        rows = (await self._conn.execute(
            "SELECT s.id AS stop_id, s.customer_id, s.seq, s.fulls_exp, s.empties_exp,"
            " s.status, s.order_id, u.name AS customer_name, u.phone AS customer_phone"
            " FROM stops s JOIN routes r ON r.id = s.route_id"
            " LEFT JOIN users u ON u.id = s.customer_id"
            " WHERE r.vendor_id = ? AND r.date = ? ORDER BY s.seq",
            (vendor_id, day),
        )).fetchall()
        grouped: dict[str, dict] = {}
        for r in rows:
            cid = r["customer_id"] or ""
            g = grouped.setdefault(cid, {
                "customer_id": cid,
                "customer_name": r["customer_name"] or cid,
                "customer_phone": r["customer_phone"],
                "stops": [], "fulls_exp": 0, "empties_exp": 0, "done": 0,
            })
            g["stops"].append({"stop_id": r["stop_id"], "seq": r["seq"],
                               "status": r["status"], "order_id": r["order_id"]})
            g["fulls_exp"] += int(r["fulls_exp"] or 0)
            g["empties_exp"] += int(r["empties_exp"] or 0)
            g["done"] += 1 if r["status"] == "done" else 0
        customers = list(grouped.values())
        # 016: additive can-ledger fields (server truth, display-only).
        # Owner-scoped by construction: customers derive from this vendor's
        # own stops. Keys mirror ledger_repo.get (`held` = jars, `dues` =
        # paise); missing ledger row → honest 0s, never nulls.
        for g in customers:
            if g["customer_id"]:
                led = await self.ledger.get(g["customer_id"])
                g["held"] = int(led.get("held", 0))
                g["dues"] = int(led.get("dues", 0))
            else:
                g["held"] = 0
                g["dues"] = 0
        return {"date": day, "customers": customers}

    # -- vendor complaint queue (011_port: ticket thread reads, verify writes) ---

    async def vendor_complaints(self, vendor_id: str, limit: int = 100,
                                cursor: str | None = None) -> dict:
        """Phase 8 §8.2: 200-cap + created_at|id cursor (was fixed LIMIT 100)."""
        limit = max(1, min(int(limit), 200))
        args: list[object] = [vendor_id]
        cursor_sql = ""
        decoded = _decode_cursor(cursor or "")
        if decoded is not None:
            cursor_sql = " AND (c.created_at < ? OR (c.created_at = ? AND c.id < ?))"
            args += [decoded[0], decoded[0], decoded[1]]
        rows = (await self._conn.execute(
            "SELECT c.id, c.order_id, c.reason_code, c.text, c.status,"
            " c.vendor_agree, c.created_at FROM complaints c"
            " JOIN stops s ON s.order_id = c.order_id"
            f" JOIN routes r ON r.id = s.route_id AND r.vendor_id = ?{cursor_sql}"  # noqa: S608
            " ORDER BY c.created_at DESC, c.id DESC LIMIT ?",
            (*args, limit + 1),
        )).fetchall()
        page = rows[:limit]
        next_cursor = _encode_cursor(page[-1]["created_at"], page[-1]["id"]) if len(rows) > limit else None
        return {"data": [dict(r) for r in page], "next_cursor": next_cursor}

    async def vendor_quality(self, vendor_id: str, limit: int = 100,
                             cursor: str | None = None) -> dict:
        """Quality incidents on this vendor's route orders (replaces the
        manual-id crutch): owned by the same stop join as complaints.
        Phase 8 §8.2: 200-cap + created_at|id cursor (was fixed LIMIT 100)."""
        limit = max(1, min(int(limit), 200))
        args: list[object] = [vendor_id]
        cursor_sql = ""
        decoded = _decode_cursor(cursor or "")
        if decoded is not None:
            cursor_sql = " AND (q.created_at < ? OR (q.created_at = ? AND q.id < ?))"
            args += [decoded[0], decoded[0], decoded[1]]
        rows = (await self._conn.execute(
            "SELECT q.id, q.order_id, q.reason_code, q.status,"
            " q.vendor_agree, q.created_at FROM quality_incidents q"
            " JOIN stops s ON s.order_id = q.order_id"
            f" JOIN routes r ON r.id = s.route_id AND r.vendor_id = ?{cursor_sql}"  # noqa: S608
            " ORDER BY q.created_at DESC, q.id DESC LIMIT ?",
            (*args, limit + 1),
        )).fetchall()
        page = rows[:limit]
        next_cursor = _encode_cursor(page[-1]["created_at"], page[-1]["id"]) if len(rows) > limit else None
        return {"data": [dict(r) for r in page], "next_cursor": next_cursor}

    # -- complaint + quality verification (§14.3) ---------------------------------------

    async def verify_complaint(self, vendor_id: str, complaint_id: str, agree: bool, note: str = "") -> dict:
        """Vendor countersigns a complaint it may be party to — but never
        closes it: agree → ``vendor_confirmed`` (mandatory ≥10-char note) and
        only an admin release writes ``resolved``; disagree → ``under_review``.
        """
        from app.services.dispatch_service import write_audit  # noqa: PLC0415 (lazy, lock-safe)

        with WRITE_LOCK:
            row = (await self._conn.execute(
                "SELECT c.id, c.order_id, c.status FROM complaints c"
                " JOIN stops s ON s.order_id = c.order_id"
                " JOIN routes r ON r.id = s.route_id AND r.vendor_id = ?"
                " WHERE c.id = ?",
                (vendor_id, complaint_id),
            )).fetchone()
            if row is None:
                raise NotFoundError(message="Complaint not found.", details={"id": complaint_id})
            # Ownership first (no oracle), then the countersign rule: agree
            # needs a real explanation — the vendor never writes `resolved`.
            if agree and len(note.strip()) < 10:
                raise ValidationError(
                    message="Vendor note must explain the confirmation (at least 10 characters).",
                    details={"id": complaint_id})
            # agree → vendor_confirmed (admin releases to resolved);
            # disagree → frozen, 48h admin triage.
            status = "vendor_confirmed" if agree else "under_review"
            try:
                await self._conn.execute(
                    "UPDATE complaints SET vendor_agree = ?, vendor_note = ?, status = ?,"
                    " resolved_at = ? WHERE id = ?",
                    (1 if agree else 0, note[:500], status, None, complaint_id),
                )
                await write_audit(self._conn, actor=vendor_id, action="vendor.complaint_verify",
                                  entity="complaints", entity_id=complaint_id)
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return {**dict(row), "vendor_agree": 1 if agree else 0, "vendor_note": note[:500], "status": status}

    async def vendor_check_quality(self, vendor_id: str, incident_id: str, agree: bool,
                                 check: str = "", note: str = "") -> dict:
        """F4: door/pickup verification on the quality_incidents table (single
        truth with admin). Ownership via the incident's order on this vendor's
        route — else 404, no oracle. Agree → confirmed; disagree stays open
        with vendor_agree=0,         frozen for 48h admin triage (CHECK allows only
        open/confirmed/rejected)."""
        from app.services.dispatch_service import write_audit  # noqa: PLC0415 (lazy, lock-safe)

        with WRITE_LOCK:
            row = (await self._conn.execute(
                "SELECT * FROM quality_incidents WHERE id = ?", (incident_id,))).fetchone()
            if row is None:
                raise NotFoundError(message="Quality incident not found.", details={"id": incident_id})
            link = (await self._conn.execute(
                "SELECT 1 FROM stops s JOIN routes r ON r.id = s.route_id"
                " WHERE s.order_id = ? AND r.vendor_id = ?",
                (row["order_id"], vendor_id),
            )).fetchone()
            if link is None:
                raise NotFoundError(message="Quality incident not found.", details={"id": incident_id})
            try:
                await self._conn.execute(
                    "UPDATE quality_incidents SET vendor_agree = ?, vendor_check = ?,"
                    " vendor_note = ?, status = ? WHERE id = ?",
                    (1 if agree else 0, check[:80], note[:500],
                     "confirmed" if agree else "open", incident_id),
                )
                await write_audit(self._conn, actor=vendor_id, action="vendor.quality_check",
                                  entity="quality_incidents", entity_id=incident_id)
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
            fresh = (await self._conn.execute(
                "SELECT * FROM quality_incidents WHERE id = ?", (incident_id,))).fetchone()
            return dict(fresh)

    async def create_rider(self, vendor_id: str, name: str, phone: str) -> dict:
        from app.services.auth_service import normalize_phone  # noqa: PLC0415

        phone_n = normalize_phone(phone)
        now_iso = _dt.datetime.now(_dt.timezone.utc).isoformat()
        with WRITE_LOCK:
            existing = (await self._conn.execute(
                "SELECT id, phone, name, role, assigned_vendor_id FROM users WHERE phone = ?",
                (phone_n,),
            )).fetchone()
            if existing is not None:
                # Onboarding must never rewrite an existing account's role or
                # owner: that let a vendor turn any customer/admin phone into
                # their rider and then sign in as it (phone-only rider login).
                if str(existing["role"]) != "rider":
                    raise ConflictError(
                        "This number already belongs to another account.",
                        {"phone": phone_n},
                    )
                if str(existing["assigned_vendor_id"] or "") != str(vendor_id):
                    raise ConflictError(
                        "This rider belongs to another vendor.",
                        {"phone": phone_n},
                    )
                rider_id = existing["id"]
                await self._conn.execute(
                    "UPDATE users SET name = ?, suspended = 0 WHERE id = ?",
                    (name.strip(), rider_id),
                )
            else:
                rider_id = str(uuid.uuid4())
                await self._conn.execute(
                    "INSERT INTO users (id, phone, name, role, assigned_vendor_id, suspended, created_at) "
                    "VALUES (?, ?, ?, 'rider', ?, 0, ?)",
                    (rider_id, phone_n, name.strip(), vendor_id, now_iso),
                )
            self._conn.commit()
        rider = {"id": rider_id, "name": name.strip(), "phone": phone_n,
                 "vendor_id": vendor_id}
        return {**rider, **await self._issue_rider_code(vendor_id, rider_id)}

    async def _issue_rider_code(self, vendor_id: str, rider_id: str) -> dict:
        """Mint the rider's sign-in code, replacing any live one.

        Keeping exactly one live code per rider makes rotation honest: the old
        code dies the moment a new one is issued. Open sessions are untouched —
        the code is a door key, not the session itself.
        """
        from app.repositories.access_code_repo import AccessCodeRepo  # noqa: PLC0415

        code = f"{secrets.randbelow(900000) + 100000}"
        expires_at = (
            _dt.datetime.now(_dt.timezone.utc)
            + _dt.timedelta(days=RIDER_CODE_TTL_DAYS)
        ).isoformat()
        repo = AccessCodeRepo(self._conn)
        await repo.revoke_all(rider_id, "rider")
        await repo.issue(
            code_id=uuid.uuid4().hex,
            user_id=rider_id,
            code_hash=hashlib.sha256(code.encode()).hexdigest(),
            masked_hint=f"\u2022\u2022{code[-2:]}",
            expected_role="rider",
            expires_at=expires_at,
            created_by=vendor_id,
        )
        return {"access_code": code, "access_code_expires_at": expires_at}

    async def reissue_rider_code(self, vendor_id: str, rider_id: str) -> dict:
        """Rotate a rider's sign-in code; the previous code stops working."""
        owned = (await self._conn.execute(
            "SELECT id FROM users WHERE id = ? AND role = 'rider' AND assigned_vendor_id = ?",
            (rider_id, vendor_id),
        )).fetchone()
        if owned is None:
            raise NotFoundError("Rider not found.", {"id": rider_id})
        return {"id": rider_id, **await self._issue_rider_code(vendor_id, rider_id)}

    async def list_riders(self, vendor_id: str) -> list[dict]:
        rows = (await self._conn.execute(
            "SELECT id, phone, name, role, assigned_vendor_id, suspended FROM users "
            "WHERE assigned_vendor_id = ? AND role = 'rider' ORDER BY created_at DESC",
            (vendor_id,),
        )).fetchall()
        return [dict(r) for r in rows]

    async def assign_rider_to_stop(self, vendor_id: str, stop_id: str, rider_id: str | None) -> dict:
        from app.db import WRITE_LOCK
        from app.core.errors import NotFoundError

        stop = (await self._conn.execute(
            "SELECT s.id, r.vendor_id FROM stops s JOIN routes r ON s.route_id = r.id WHERE s.id = ?",
            (stop_id,),
        )).fetchone()
        if stop is None or stop["vendor_id"] != vendor_id:
            raise NotFoundError("Stop not found.", {"stop_id": stop_id})

        with WRITE_LOCK:
            await self._conn.execute(
                "UPDATE stops SET rider_id = ? WHERE id = ?",
                (rider_id, stop_id),
            )
            self._conn.commit()
        return {"stop_id": stop_id, "rider_id": rider_id}

    async def delete_rider(self, vendor_id: str, rider_id: str) -> dict:
        owned = (await self._conn.execute(
            "SELECT id FROM users WHERE id = ? AND role = 'rider' AND assigned_vendor_id = ?",
            (rider_id, vendor_id),
        )).fetchone()
        if owned is None:
            raise NotFoundError("Rider not found.", {"id": rider_id})
        now = _now()
        with WRITE_LOCK:
            await self._conn.execute(
                "UPDATE users SET assigned_vendor_id = NULL WHERE id = ?",
                (rider_id,),
            )
            await self._conn.execute(
                "UPDATE access_codes SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL",
                (now, rider_id),
            )
            await self._conn.execute(
                "UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL",
                (now, rider_id),
            )
            await self._conn.execute(
                "UPDATE stops SET rider_id = NULL WHERE rider_id = ? AND status = 'pending'",
                (rider_id,),
            )
            self._conn.commit()
        return {"status": "removed", "rider_id": rider_id}

    async def issue_stop_cancel_otp(self, vendor_id: str, stop_id: str) -> dict:
        stop = await self._owned_stop(vendor_id, stop_id)
        if stop["status"] == "done":
            raise ConflictError(message="Completed stop cannot be cancelled.", details={"stop_id": stop_id})
        await _ensure_stop_cancel_cols(self._conn)
        otp = f"{secrets.randbelow(9000) + 1000}"
        now = _now()
        with WRITE_LOCK:
            await self._conn.execute(
                "UPDATE stops SET cancel_otp = ?, cancel_otp_created_at = ? WHERE id = ?",
                (otp, now, stop_id),
            )
            self._conn.commit()
        return {"stop_id": stop_id, "cancel_otp": otp}
