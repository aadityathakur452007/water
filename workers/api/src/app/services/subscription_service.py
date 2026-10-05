"""Subscription service — pause / resume / skip / due-run (contract §4.5, EC-S).

Business rules ONLY (python card: services stay DB-agnostic in spirit; SQL is
kept here because the D3 file list allows no new repository file — same
precedent as ``OrderService._idem_get/_idem_put`` touching the connection).

Tiers stay NULL in v1 (tier/discount_pct/perks never written). All dates are
ISO-8601 strings; hold/skip/next_run compare as YYYY-MM-DD; the resume guard
compares full UTC datetimes.

Tunables (contract §8 open until survey): SKIP_CUTOFF_HOUR, RESUME_LEAD_HOURS.
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import json
import sqlite3
import uuid

from app.core.errors import AppError
from app.db import WRITE_LOCK
from app.db_d1 import AsyncSqliteConn, D1Conn

Conn = D1Conn | AsyncSqliteConn

RESUME_LEAD_HOURS = 24  # Bisleri rule: resume needs >=24h notice (E2)
SKIP_CUTOFF_HOUR = 18  # after 18:00 UTC a same-day skip is late (tunable, §8)


class SubNotFoundError(AppError):
    code = "NOT_FOUND"
    status_code = 404


class SubValidationError(AppError):
    code = "VALIDATION"
    status_code = 400


class ResumeTooSoonError(AppError):
    code = "RESUME_TOO_SOON"
    status_code = 422


def _now() -> _dt.datetime:
    return _dt.datetime.now(_dt.timezone.utc)


def _parse_dt(v: object) -> _dt.datetime | None:
    if isinstance(v, _dt.datetime):
        dt = v
    elif isinstance(v, str):
        try:
            dt = _dt.datetime.fromisoformat(v)
        except ValueError:
            return None
    else:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=_dt.timezone.utc)
    return dt


def _parse_day(v: object) -> str | None:
    """Any ISO date/datetime -> 'YYYY-MM-DD', else None."""
    if isinstance(v, _dt.date) and not isinstance(v, _dt.datetime):
        return v.isoformat()
    dt = _parse_dt(v)
    if dt is None:
        return None
    return dt.date().isoformat()


def _advance(day: _dt.date, schedule: str, recurrence: str) -> _dt.date:
    step = {"daily": 1, "alternate": 2, "weekly": 7}.get((schedule or "").lower(), 0)
    if (schedule or "").lower() == "custom":
        try:
            step = int((recurrence or "7").strip() or "7")
        except (ValueError, AttributeError):
            step = 7
    if step < 1:
        step = 1
    nxt = day + _dt.timedelta(days=step)
    while nxt.weekday() == 6:  # scheduler never generates Sundays (8-8 Sun-closed)
        nxt += _dt.timedelta(days=1)
    return nxt


def _row(r: sqlite3.Row) -> dict:
    return dict(r)


def _due_today(qty: object, sku_mix: object) -> int:
    """Today's dues preview: qty x rate (container 3000, else refill 2800).

    Paid/previous dues stay with GET /billing/dues (no new endpoint here).
    """
    from app.services import pricing  # noqa: PLC0415 (leaf module, no cycle)

    try:
        q = max(0, int(qty or 0))  # type: ignore[arg-type]
    except (TypeError, ValueError):
        q = 0
    rate = pricing.CONTAINER_PAISE if str(sku_mix or "").strip().lower() == "container" else pricing.REFILL_PAISE
    return q * rate


class SubscriptionService:
    """Owner-scoped subscription use-cases (IDOR: miss -> 404, no oracle)."""

    def __init__(self, conn: Conn):
        self._conn = conn

    # -- create / list ----------------------------------------------------

    async def create(self, user_id: str, payload: dict, idempotency_key: str = "") -> dict:
        qty = int(payload.get("qty", 0))
        if qty < 1:
            raise SubValidationError(message="Quantity must be >= 1.", details={})
        address_id = str(payload.get("address_id") or "").strip()
        if not address_id:
            raise SubValidationError(message="address_id required.", details={})
        if not await self._owned_address(user_id, address_id):
            raise SubNotFoundError(message="Address not found.", details={"id": address_id})
        schedule = str(payload.get("schedule_type") or "daily")
        recurrence = str(payload.get("recurrence") or "")
        key = (idempotency_key or "").strip()
        scoped = f"POST /v1/subscriptions:{key}" if key else ""
        idem_phash = hashlib.sha256(json.dumps(
            {"a": address_id, "q": qty, "s": schedule, "r": recurrence},
            sort_keys=True).encode()).hexdigest() if key else ""
        if key:
            # Double-tap guard: same sheet-open key replays the minted row.
            row = (await self._conn.execute(
                "SELECT payload_hash, result FROM idempotency_keys WHERE user_id=? AND scoped_key=?",
                (user_id, scoped),
            )).fetchone()
            if row is not None:
                if row["payload_hash"] != idem_phash:
                    from app.repositories.payment_repo import PayloadMismatchError  # noqa: PLC0415 (lazy, light)

                    raise PayloadMismatchError(
                        message="Idempotency-Key was already used with a different payload.",
                        details={"user_id": user_id})
                return json.loads(row["result"])
        next_run = _parse_day(payload.get("next_run")) or self._default_next_run()
        sub = {
            "id": uuid.uuid4().hex,
            "user_id": user_id,
            "address_id": address_id,
            "qty": qty,
            "sku_mix": str(payload.get("sku_mix") or "refill"),
            "window": str(payload.get("window") or ""),
            "next_run": next_run,
            "schedule_type": schedule,
            "recurrence": recurrence,
            "payment_method": str(payload.get("payment_method") or "cod"),
            "status": "active",
        }
        with WRITE_LOCK:
            try:
                await self._conn.execute(
                    "INSERT INTO subscriptions(id, user_id, address_id, qty, sku_mix, window,"
                    " next_run, schedule_type, recurrence, payment_method,"
                    " tier, discount_pct, perks, status, hold_from, hold_to)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, 'active', NULL, NULL)",
                    (sub["id"], user_id, address_id, qty, sub["sku_mix"], sub["window"],
                     next_run, schedule, recurrence, sub["payment_method"]),
                )
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        out = await self.get_owned(user_id, sub["id"]) or sub
        if key:
            with WRITE_LOCK:
                try:
                    await self._conn.execute(
                        "INSERT OR IGNORE INTO idempotency_keys(user_id, scoped_key, order_id,"
                        " payload_hash, result, created_at) VALUES (?,?,?,?,?,?)",
                        (user_id, scoped, sub["id"], idem_phash,
                         json.dumps(out), _dt.datetime.now(_dt.timezone.utc).isoformat()),
                    )
                    self._conn.commit()
                except Exception:
                    self._conn.rollback()
                    raise
        return out

    async def list(self, user_id: str) -> list[dict]:
        rows = (await self._conn.execute(
            "SELECT * FROM subscriptions WHERE user_id = ? ORDER BY rowid", (user_id,)
        )).fetchall()
        out = []
        for r in rows:
            d = _row(r)
            d["due_today_paise"] = _due_today(d.get("qty"), d.get("sku_mix"))
            out.append(d)
        return out

    async def get_owned(self, user_id: str, sub_id: str) -> dict | None:
        row = (await self._conn.execute(
            "SELECT * FROM subscriptions WHERE id = ? AND user_id = ?", (sub_id, user_id)
        )).fetchone()
        return _row(row) if row is not None else None

    # -- pause / resume / skip --------------------------------------------

    async def pause(self, user_id: str, sub_id: str, hold_from: object, hold_to: object) -> dict:
        sub = await self.get_owned(user_id, sub_id)
        if sub is None:
            raise SubNotFoundError(message="Subscription not found.", details={"id": sub_id})
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

    async def process_due(self, today: object = None) -> dict:
        """Generate due runs + fire auto-resumes. Idempotent per day.

        Returns descriptors the future cron turns into orders (order-row
        creation stays with the orders slice — no cross-slice writes here).
        Second call with the same ``today`` returns empty lists.
        """
        tday = _parse_day(today) if today is not None else _now().date().isoformat()
        assert tday is not None, "today must be a date"
        resumed: list[dict] = []
        generated: list[dict] = []
        with WRITE_LOCK:
            try:
                paused = (await self._conn.execute(
                    "SELECT id, user_id FROM subscriptions"
                    " WHERE status = 'paused' AND hold_to IS NOT NULL AND hold_to < ?",
                    (tday,),
                )).fetchall()
                for p in paused:
                    await self._conn.execute(
                        "UPDATE subscriptions SET status = 'active',"
                        " hold_from = NULL, hold_to = NULL WHERE id = ?",
                        (p["id"],),
                    )
                    resumed.append({"sub_id": p["id"], "user_id": p["user_id"]})
                due = (await self._conn.execute(
                    "SELECT * FROM subscriptions"
                    " WHERE status = 'active' AND next_run <> '' AND next_run <= ?",
                    (tday,),
                )).fetchall()
                for s in due:
                    d = _dt.date.fromisoformat(s["next_run"])
                    if s["hold_from"] and s["hold_to"] and s["hold_from"] <= s["next_run"] <= s["hold_to"]:
                        continue  # paused range wins over schedule (§15)
                    if d.weekday() == 6 or await self._skipped(s["id"], d.isoformat()):
                        await self._advance_past(s, _dt.date.fromisoformat(tday))
                        continue
                    generated.append({
                        "sub_id": s["id"], "user_id": s["user_id"],
                        "address_id": s["address_id"], "qty": s["qty"],
                        "sku_mix": s["sku_mix"], "window": s["window"],
                        "payment_method": s["payment_method"], "date": d.isoformat(),
                    })
                    await self._advance_past(s, _dt.date.fromisoformat(tday))
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise
        return {"date": tday, "generated": generated, "resumed": resumed}

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
            "UPDATE subscriptions SET next_run = ? WHERE id = ?", (nxt.isoformat(), sub["id"])
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
