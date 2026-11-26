from __future__ import annotations

import datetime as _dt
import uuid

from app.db import WRITE_LOCK
from app.services.subscription._common import (  # noqa: F401
    BILLING_MODES,
    Conn,
    InsufficientCreditError,
    MAX_PLAN_JARS,
    PAYMENT_METHODS,
    RESUME_LEAD_HOURS,
    ResumeTooSoonError,
    SCHEDULE_TYPES,
    SKIP_CUTOFF_HOUR,
    SubNotFoundError,
    SubValidationError,
    _advance,
    _due_today,
    _ensure_billing_mode,
    _monthly_estimate,
    _now,
    _parse_day,
    _parse_dt,
    _row,
)

class SubScheduleMixin:
    async def pause(self, user_id: str, sub_id: str, hold_from: object, hold_to: object) -> dict:
        sub = await self.get_owned(user_id, sub_id)
        if sub is None:
            raise SubNotFoundError(message="Subscription not found.", details={"id": sub_id})
        if sub.get("canceled_at"):
            raise SubValidationError(message="Cannot modify a canceled subscription.", details={"id": sub_id})
        dfrom, dto = _parse_day(hold_from), _parse_day(hold_to)
        if dfrom is None or dto is None or dfrom > dto:
            raise SubValidationError(
                message="hold_from must be <= hold_to (YYYY-MM-DD).",
                details={"hold_from": hold_from, "hold_to": hold_to},
            )
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "UPDATE subscriptions SET status = 'paused', hold_from = ?, hold_to = ?"
                    " WHERE id = ?",
                    (dfrom, dto, sub_id),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return await self.get_owned(user_id, sub_id)  # type: ignore[return-value]

    async def resume(
        self, user_id: str, sub_id: str, preferred_date: object,
        now: _dt.datetime | None = None,
    ) -> dict:
        sub = await self.get_owned(user_id, sub_id)
        if sub is None:
            raise SubNotFoundError(message="Subscription not found.", details={"id": sub_id})
        if sub.get("canceled_at"):
            raise SubValidationError(message="Cannot modify a canceled subscription.", details={"id": sub_id})
        now = now or _now()
        pref = _parse_dt(preferred_date)
        if pref is None:
            raise SubValidationError(message="preferred_date must be ISO-8601.", details={})
        earliest = now + _dt.timedelta(hours=RESUME_LEAD_HOURS)
        if pref < earliest:  # >=24h guard (Bisleri ≥24h resume)
            raise ResumeTooSoonError(
                message="Resume needs 24h notice. Pick a later date.",
                details={"preferred_date": str(preferred_date),
                         "next_valid_date": earliest.isoformat()},
            )
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "UPDATE subscriptions SET status = 'active', hold_from = NULL,"
                    " hold_to = NULL, next_run = ? WHERE id = ?",
                    (pref.date().isoformat(), sub_id),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return await self.get_owned(user_id, sub_id)  # type: ignore[return-value]

    async def skip(
        self, user_id: str, sub_id: str, date: object,
        now: _dt.datetime | None = None,
    ) -> dict:
        sub = await self.get_owned(user_id, sub_id)
        if sub is None:
            raise SubNotFoundError(message="Subscription not found.", details={"id": sub_id})
        if sub.get("canceled_at"):
            raise SubValidationError(message="Cannot modify a canceled subscription.", details={"id": sub_id})
        day = _parse_day(date)
        now = now or _now()
        if day is None:
            raise SubValidationError(message="date must be YYYY-MM-DD.", details={})
        if day < now.date().isoformat():
            raise SubValidationError(message="Cannot skip a past date.", details={"date": day})
        late = 1 if (day == now.date().isoformat() and now.hour >= SKIP_CUTOFF_HOUR) else 0
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "INSERT OR IGNORE INTO skips(id, sub_id, date, late) VALUES (?, ?, ?, ?)",
                    (uuid.uuid4().hex, sub_id, day, late),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        row = (await self._conn.execute(
            "SELECT id, sub_id, date, late FROM skips WHERE sub_id = ? AND date = ?",
            (sub_id, day),
        )).fetchone()
        out = _row(row)
        out["late_skip"] = bool(out["late"])
        if out["late_skip"]:
            out["cta"] = "Late skip — please call support so the vendor is informed."
        return out

    # -- due runner (job-callable; future cron calls this, never HTTP) -----

    async def process_due(self, today: object = None, limit: int = 60) -> dict:
        """Generate due-run descriptors + fire auto-resumes.

        Generated descriptors are NOT advanced here: the caller creates the
        order (and settles prepaid credit) first, then calls ``advance_due``.
        A failed creation leaves ``next_run`` due and records a backoff, so a
        cron failure can never skip a delivery. Skipped Sundays and resumes
        still advance in this pass. Bounded to ``limit`` rows per tick.
        """
        tday = _parse_day(today) if today is not None else _now().date().isoformat()
        assert tday is not None, "today must be a date"
        now = _now().isoformat()
        await _ensure_billing_mode(self._conn)
        resumed: list[dict] = []
        generated: list[dict] = []
        low_balance: list[dict] = []
        with WRITE_LOCK:
            try:
                paused = (await self._conn.execute(
                    "SELECT id, user_id FROM subscriptions"
                    " WHERE status = 'paused' AND canceled_at IS NULL"
                    " AND billing_status != 'pending_payment'"
                    " AND hold_to IS NOT NULL AND hold_to < ?"
                    " ORDER BY id LIMIT ?",
                    (tday, int(limit)),
                )).fetchall()
                for p in paused:
                    cur = await self._conn.execute(
                        "UPDATE subscriptions SET status = 'active',"
                        " hold_from = NULL, hold_to = NULL"
                        " WHERE id = ? AND status = 'paused'",
                        (p["id"],),
                    )
                    if cur.rowcount:
                        resumed.append({"sub_id": p["id"], "user_id": p["user_id"]})
                due = (await self._conn.execute(
                    "SELECT * FROM subscriptions"
                    " WHERE status = 'active' AND canceled_at IS NULL AND next_run <> ''"
                    " AND next_run <= ?"
                    " AND (due_retry_at IS NULL OR due_retry_at <= ?)"
                    " AND NOT (hold_from IS NOT NULL AND hold_to IS NOT NULL"
                    "          AND hold_from <= next_run AND next_run <= hold_to)"
                    " ORDER BY next_run, id LIMIT ?",
                    (tday, now, int(limit)),
                )).fetchall()
                for s in due:
                    d = _dt.date.fromisoformat(s["next_run"])
                    if d.weekday() == 6 or await self._skipped(s["id"], d.isoformat()):
                        await self._advance_past(s, _dt.date.fromisoformat(tday))
                        continue
                    billing = str(s.get("billing_mode") or "per_delivery")
                    if str(s.get("billing_status") or "active") == "pending_payment":
                        low_balance.append({
                            "sub_id": s["id"], "user_id": s["user_id"],
                            "reason": "payment_pending",
                        })
                        continue
                    if billing == "monthly_prepaid":
                        need = _due_today(s["qty"], s["sku_mix"])
                        if int(s.get("credit_balance_paise") or 0) < need:
                            low_balance.append({
                                "sub_id": s["id"], "user_id": s["user_id"],
                                "reason": "low_balance", "needed_paise": need,
                                "balance_paise": int(s.get("credit_balance_paise") or 0),
                            })
                            continue
                    generated.append({
                        "sub_id": s["id"], "user_id": s["user_id"],
                        "address_id": s["address_id"], "qty": s["qty"],
                        "sku_mix": s["sku_mix"], "window": s["window"],
                        "payment_method": s.get("payment_method", "cod"),
                        "billing_mode": billing,
                        "date": d.isoformat(),
                    })
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return {"date": tday, "generated": generated, "resumed": resumed,
                "low_balance": low_balance}

    async def due_backlog(self, today: object = None) -> int:
        """Count due subs with the same filters as ``process_due``."""
        tday = _parse_day(today) if today is not None else _now().date().isoformat()
        assert tday is not None, "today must be a date"
        row = (await self._conn.execute(
            "SELECT COUNT(*) c FROM subscriptions"
            " WHERE status = 'active' AND canceled_at IS NULL AND next_run <> ''"
            " AND next_run <= ?"
            " AND (due_retry_at IS NULL OR due_retry_at <= ?)"
            " AND NOT (hold_from IS NOT NULL AND hold_to IS NOT NULL"
            "          AND hold_from <= next_run AND next_run <= hold_to)",
            (tday, _now().isoformat()),
        )).fetchone()
        return int(row["c"]) if row is not None else 0

    async def advance_due(self, sub_id: str, expected_next_run: str,
                          today: object = None) -> bool:
        """Advance ``next_run`` only if it still equals the processed date.

        Called after the order exists and prepaid credit is settled. A lost
        CAS means another tick already advanced it; harmless. Resets retry
        state so the plan is eligible on its next schedule.
        """
        sub = (await self._conn.execute(
            "SELECT next_run, schedule_type, recurrence FROM subscriptions WHERE id = ?",
            (sub_id,),
        )).fetchone()
        if sub is None or str(sub["next_run"]) != str(expected_next_run):
            return False
        tday = _parse_day(today) if today is not None else _now().date().isoformat()
        assert tday is not None, "today must be a date"
        nxt = _advance(_dt.date.fromisoformat(str(expected_next_run)),
                       sub["schedule_type"], sub["recurrence"])
        guard = 0
        while (nxt <= _dt.date.fromisoformat(tday) or nxt.weekday() == 6) and guard < 370:
            guard += 1
            if nxt.weekday() == 6:
                nxt += _dt.timedelta(days=1)
            else:
                nxt = _advance(nxt, sub["schedule_type"], sub["recurrence"])
        with WRITE_LOCK:
            cur = await self._conn.execute(
                "UPDATE subscriptions SET next_run = ?, due_attempts = 0,"
                " due_last_error = NULL, due_retry_at = NULL"
                " WHERE id = ? AND next_run = ?",
                (nxt.isoformat(), sub_id, str(expected_next_run)),
            )
            self._conn.commit()
            return cur.rowcount > 0

    async def record_due_failure(self, sub_id: str, code: str,
                                 message: str = "") -> dict:
        """Record a failed due run and back off 15m → 24h (no dead-letter)."""
        row = (await self._conn.execute(
            "SELECT due_attempts FROM subscriptions WHERE id = ?", (sub_id,)
        )).fetchone()
        attempts = int(row["due_attempts"] or 0) + 1 if row is not None else 1
        delay = min(15 * 60 * (2 ** (attempts - 1)), 24 * 3600)
        retry_at = (_now() + _dt.timedelta(seconds=delay)).isoformat()
        with WRITE_LOCK:
            await self._conn.execute(
                "UPDATE subscriptions SET due_attempts = due_attempts + 1,"
                " due_last_error = ?, due_retry_at = ? WHERE id = ?",
                (str(message or code)[:200], retry_at, sub_id),
            )
            self._conn.commit()
        return {"sub_id": sub_id, "attempts": attempts, "code": code,
                "retry_at": retry_at, "retry_after_s": delay}

    # -- internals --------------------------------------------------------

    async def _advance_past(self, sub: dict, today: _dt.date) -> None:
        nxt = _advance(_dt.date.fromisoformat(sub["next_run"]),
                       sub["schedule_type"], sub["recurrence"])
        guard = 0
        while (nxt <= today or nxt.weekday() == 6) and guard < 370:
            guard += 1
            if nxt.weekday() == 6:
                nxt += _dt.timedelta(days=1)
            else:
                nxt = _advance(nxt, sub["schedule_type"], sub["recurrence"])
        await self._conn.execute(
            "UPDATE subscriptions SET next_run = ? WHERE id = ? AND next_run = ?",
            (nxt.isoformat(), sub["id"], sub["next_run"]),
        )

    async def _skipped(self, sub_id: str, day: str) -> bool:
        return (await self._conn.execute(
            "SELECT 1 FROM skips WHERE sub_id = ? AND date = ?", (sub_id, day)
        )).fetchone() is not None

    async def _owned_address(self, user_id: str, address_id: str) -> bool:
        try:
            row = (await self._conn.execute(
                "SELECT 1 FROM addresses WHERE id = ? AND user_id = ?", (address_id, user_id)
            )).fetchone()
        except Exception:
            return True  # addresses slice not migrated yet -> don't block
        return row is not None

    def _default_next_run(self) -> str:
        nxt = _now().date() + _dt.timedelta(days=1)
        while nxt.weekday() == 6:
            nxt += _dt.timedelta(days=1)
        return nxt.isoformat()
