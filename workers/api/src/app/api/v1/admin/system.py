from __future__ import annotations

import datetime as _dt
import sqlite3
import time

from fastapi import APIRouter, Depends, Query, Request, Response

from app.api.auth_deps import get_current_user, require_role  # noqa: F401
from app.api.caching import cached
from app.api.deps import get_db_conn
from app.core.http_utils import user_id as _uid
from app.core.time_utils import utc_now_iso as _now
from app.db import WRITE_LOCK
from app.repositories.admin_read_repo import AdminReadRepo, ist_today
from app.api.v1.admin._common import *  # noqa: F401, F403

router = APIRouter(tags=["admin"])

@router.patch("/admin/config")
async def config_patch(payload: ConfigPatchIn, conn=Depends(get_db_conn), user=Admin):
    with WRITE_LOCK:
        before = (await conn.execute("SELECT * FROM config WHERE key = ?", (payload.key,))).fetchone()
        now = _now()
        await conn.execute(
            "INSERT INTO config(key, value, effective_from, updated_by, updated_at)"
            " VALUES (?, ?, ?, ?, ?)"
            " ON CONFLICT(key) DO UPDATE SET value = excluded.value,"
            " effective_from = excluded.effective_from, updated_by = excluded.updated_by,"
            " updated_at = excluded.updated_at",
            (payload.key.strip(), payload.value, now, _uid(user), now),
        )
        await _audit(conn, user, "config.set", "config", payload.key,
               dict(before) if before else {}, {"value": payload.value, "effective_from": now})
        conn.commit()
    return {"key": payload.key, "value": payload.value, "effective_from": now}


@router.get("/admin/config")
async def config_read(request: Request, conn=Depends(get_db_conn), user=Admin):
    try:
        rows = (await conn.execute("SELECT key, value, effective_from, updated_by, updated_at"
                            " FROM config ORDER BY key")).fetchall()
    except sqlite3.OperationalError:
        rows = (await conn.execute("SELECT key, value FROM config ORDER BY key")).fetchall()
    # Phase 8 §8.5: auth still required; admin bytes must never enter a
    # shared cache, so private=True emits `private, no-store`.
    return cached({"data": [dict(r) for r in rows]}, request, private=True)


@router.get("/admin/audit")
async def audit_read(entity: str | None = Query(default=None),
               actor_id: str | None = Query(default=None, max_length=80),  # F-SA additive
               action: str | None = Query(default=None, max_length=80),  # F-SA additive
               limit: int = Query(default=50, ge=1, le=200),
               cursor: str = Query(default=""),
               conn=Depends(get_db_conn), user=Admin):
    args: list[object] = []
    clauses = []
    if entity:
        clauses.append("entity = ?")
        args.append(entity)
    if actor_id:
        clauses.append("actor_id = ?")
        args.append(actor_id)
    if action:
        clauses.append("action = ?")
        args.append(action)
    cur = _cursor(cursor)
    if cur > 0:
        clauses.append("rowid < ?")
        args.append(cur)
    where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
    try:
        rows = (await conn.execute(
            f"SELECT *, rowid AS _rowid FROM audit_log {where} ORDER BY rowid DESC LIMIT ?", (*args, limit + 1)  # noqa: S608
        )).fetchall()
    except sqlite3.OperationalError:
        rows = []
    data = [dict(r) for r in rows[:limit]]
    next_cursor = str(rows[limit]["_rowid"]) if len(rows) > limit else ""
    return {"data": data, "next_cursor": next_cursor}


@router.get("/admin/audit/export")
async def audit_export(entity: str | None = Query(default=None),
                 actor_id: str | None = Query(default=None, max_length=80),
                 action: str | None = Query(default=None, max_length=80),
                 limit: int = Query(default=200, ge=1, le=1000),
                 conn=Depends(get_db_conn), user=Admin):
    """Filtered audit as CSV (same filters as the viewer; header follows the
    live table shape, whichever migration owns it)."""
    import csv
    import io

    from fastapi.responses import PlainTextResponse

    args: list[object] = []
    clauses = []
    if entity:
        clauses.append("entity = ?")
        args.append(entity)
    if actor_id:
        clauses.append("actor_id = ?")
        args.append(actor_id)
    if action:
        clauses.append("action = ?")
        args.append(action)
    where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
    try:
        rows = (await conn.execute(
            f"SELECT * FROM audit_log {where} ORDER BY rowid DESC LIMIT ?", (*args, limit)  # noqa: S608
        )).fetchall()
    except sqlite3.OperationalError:
        rows = []
    data = [dict(r) for r in rows]
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(list(data[0].keys()) if data else ["empty"])
    for r in data:
        writer.writerow([r.get(k, "") for k in (list(data[0].keys()) if data else [])])
    return PlainTextResponse(buf.getvalue(), media_type="text/csv")


_METRICS_TTL_S = 60
_metrics_cache: dict[str, tuple[float, dict]] = {}


async def _metrics_cached(key: str, build):
    """Single-tenant dashboard aggregates; 60 s per-isolate cache.

    Only global counts live here (never per-user data), and the key set is
    bounded by `days` (1-90), so the map cannot grow without limit.
    """
    hit = _metrics_cache.get(key)
    now = time.monotonic()
    if hit is not None and now - hit[0] < _METRICS_TTL_S:
        return hit[1]
    value = await build()
    for stale in [k for k, v in _metrics_cache.items() if now - v[0] >= _METRICS_TTL_S]:
        _metrics_cache.pop(stale, None)
    _metrics_cache[key] = (now, value)
    return value


def reset_metrics_cache() -> None:  # tests only
    _metrics_cache.clear()


@router.get("/admin/metrics")
async def metrics(response: Response, conn=Depends(get_db_conn), user=Admin):
    async def build():
        orders = {r["state"]: int(r["c"])
                  for r in (await conn.execute("SELECT state, COUNT(*) c FROM orders GROUP BY state")).fetchall()}
        users = {r["role"]: int(r["c"])
                 for r in (await conn.execute("SELECT role, COUNT(*) c FROM users GROUP BY role")).fetchall()}
        dues = (await conn.execute("SELECT COALESCE(SUM(dues),0) d FROM ledger")).fetchone()["d"]
        open_q = 0
        try:
            open_q = int((await conn.execute(
                "SELECT COUNT(*) c FROM quality_incidents WHERE status = 'open'")).fetchone()["c"])
        except sqlite3.OperationalError:
            pass
        return {"orders_by_state": orders, "users_by_role": users,
                "dues_paise": int(dues), "quality_open": open_q}

    body = await _metrics_cached("metrics", build)
    response.headers["Cache-Control"] = "private, no-store"
    return body


# -- F-SA super-admin panel (additive, contract §4.11 + §14.5) ----------------
# Reads power the Next.js admin web panel; suspend/unsuspend implement §14.5
# (block = human-confirmed, sessions revoked instantly, always audited).




@router.get("/admin/metrics/overview")
async def metrics_overview(response: Response, days: int = Query(default=14, ge=1, le=90),
                     conn=Depends(get_db_conn), user=Admin):
    async def build():
        repo = AdminReadRepo(conn)
        today = ist_today()
        since = (_dt.datetime.fromisoformat(today) - _dt.timedelta(days=days)).date().isoformat()
        daily = await repo.daily_series(since)
        on_time = {r["day"]: r for r in await repo.on_time_series(since)}
        series = []
        for row in daily:
            ot = on_time.get(row["day"], {})
            delivered = ot.get("delivered") or 0
            series.append({
                "day": row["day"],
                "orders": int(row["orders"] or 0),
                "gmv_paise": int(row["gmv_paise"] or 0),
                "delivered": int(row["delivered"] or 0),
                "cancelled": int(row["cancelled"] or 0),
                "failed": int(row["failed"] or 0),
                "upi_orders": int(row["upi_orders"] or 0),
                "cod_orders": int(row["cod_orders"] or 0),
                "on_time_pct": round(100.0 * (ot.get("on_time") or 0) / delivered, 1) if delivered else None,
            })
        today_row = next((r for r in series if r["day"] == today), None)
        return {
            "today": today_row or {
                "day": today, "orders": 0, "gmv_paise": 0, "delivered": 0,
                "cancelled": 0, "failed": 0, "upi_orders": 0, "cod_orders": 0,
                "on_time_pct": None,
            },
            "series": series,
            "money": await repo.money_totals(),
        }

    body = await _metrics_cached(f"overview:{days}", build)
    response.headers["Cache-Control"] = "private, no-store"
    return body


