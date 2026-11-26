from __future__ import annotations


from app.core.errors import ValidationError
from app.db import WRITE_LOCK
from app.services.vendor._common import (
    _now,
)

class VendorDutyMixin:
    async def duty(self, vendor_id: str, on: bool) -> dict:
        from app.services.dispatch_service import ensure_profile

        await ensure_profile(self._conn, vendor_id)
        since = _now()
        with WRITE_LOCK:
            try:
                if on:
                    await self._conn.execute(
                        "UPDATE vendor_profile SET on_duty = 1, duty_on = ?,"
                        " duty_off = NULL WHERE user_id = ?",
                        (since, vendor_id),
                    )
                else:
                    await self._conn.execute(
                        "UPDATE vendor_profile SET on_duty = 0, duty_off = ?"
                        " WHERE user_id = ?",
                        (since, vendor_id),
                    )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        repooled = 0
        if not on:
            # Duty-off keeps the promise on the confirm copy ("baki stops ruk
            # jayenge"): pending stops return to the zone pool in the same
            # flow, audited with the count. Separate txn — auto_repool owns
            # its lock (WRITE_LOCK is not reentrant).
            from app.services.dispatch_service import auto_repool, write_audit  # noqa: PLC0415 (lazy, lock-safe)

            repooled = int((await auto_repool(self._conn, vendor_id,
                                              {"id": vendor_id, "role": "vendor"}))["repooled"])
            with WRITE_LOCK:
                try:
                    await write_audit(self._conn, actor=vendor_id, action="vendor.duty_off",
                                      entity="vendors", entity_id=vendor_id)
                    self._conn.commit()
                except Exception:
                    self._conn.rollback()
                    raise
        return {"vendor_id": vendor_id, "duty_on": bool(on), "since": since, "repooled": repooled}

    async def is_on_duty(self, vendor_id: str) -> bool:
        from app.services.dispatch_service import ensure_profile

        prof = await ensure_profile(self._conn, vendor_id)
        return bool(prof.get("on_duty"))

    async def stockout(self, vendor_id: str, reason: str = "") -> dict:
        """Vendor emergency SOS: vehicle is out of stock mid-route.
        Pending stops return to zone pool so backup vendors can fulfill them.
        """
        from app.services.dispatch_service import auto_repool, write_audit
        repooled = int((await auto_repool(self._conn, vendor_id,
                                          {"id": vendor_id, "role": "vendor"}))["repooled"])
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "UPDATE vendor_profile SET on_duty = 0, duty_off = ? WHERE user_id = ?",
                    (_now(), vendor_id),
                )
                await write_audit(self._conn, actor=vendor_id, action="vendor.stockout",
                                  entity="vendors", entity_id=vendor_id,
                                  after=reason or "Emergency stockout reported")
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return {
            "vendor_id": vendor_id,
            "status": "stockout_recorded",
            "repooled_stops": repooled,
            "message": f"Emergency recorded. {repooled} remaining stops sent for repooling.",
        }

    async def request_leave(self, vendor_id: str, start_date: str, end_date: str, reason: str = "") -> dict:
        import uuid
        s_date, e_date = str(start_date).strip(), str(end_date).strip()
        if not s_date or not e_date or s_date > e_date:
            raise ValidationError(message="start_date must be <= end_date (YYYY-MM-DD).", details={})
        lid = uuid.uuid4().hex
        now = _now()
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "INSERT INTO vendor_leaves(id, vendor_id, start_date, end_date, reason, status, created_at)"
                    " VALUES (?, ?, ?, ?, ?, 'pending', ?)",
                    (lid, vendor_id, s_date, e_date, reason or "", now),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        row = (await self._conn.execute("SELECT * FROM vendor_leaves WHERE id = ?", (lid,))).fetchone()
        return dict(row)

    async def list_leaves(self, vendor_id: str) -> list[dict]:
        rows = (await self._conn.execute(
            "SELECT * FROM vendor_leaves WHERE vendor_id = ? ORDER BY created_at DESC",
            (vendor_id,),
        )).fetchall()
        return [dict(r) for r in rows]
