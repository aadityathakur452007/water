"""Admin-panel read repository (F-SA super-admin panel, contract §3/§4.11).

Read-only SQL aggregates that power the super-admin web panel. Deliberately
separate from ``user_repo``/``order_repo`` — those are shared with the Flutter
apps and must not gain admin-only queries (zero regression surface). Money is
integer paise; clocks ISO-8601 UTC TEXT (substr(x,1,10) = calendar day).
Every query is parameterized (ssdlc); cursor paging uses ``rowid`` (stable in
SQLite/D1, single-writer semantics keep it monotonic for reads).

Async (Phase-B T2): methods await the shared facade (D1 in prod, sqlite
locally) — call shapes are otherwise unchanged.
"""

from __future__ import annotations

import sqlite3

from app.db_d1 import AsyncSqliteConn, D1Conn

Conn = D1Conn | AsyncSqliteConn


def _page(rows: list[sqlite3.Row], limit: int) -> tuple[list[dict], str]:
    """Cursor page: fetch limit+1, next_cursor = rowid of the extra row."""
    has_more = len(rows) > limit
    rows = rows[:limit]
    data = [dict(r) for r in rows]
    next_cursor = str(rows[-1]["_rowid"]) if has_more and rows else ""
    return data, next_cursor


class AdminReadRepo:
    """Data access for the super-admin panel (reads only — writes stay in services)."""

    def __init__(self, conn: Conn):
        self._conn = conn

    # -- overview metrics (GET /admin/metrics/overview) -----------------------

    async def daily_series(self, since_day: str) -> list[dict]:
        rows = (
            await self._conn.execute(
                "SELECT substr(created_at, 1, 10) AS day,"
                " COUNT(*) AS orders,"
                " COALESCE(SUM(total), 0) AS gmv_paise,"
                " SUM(CASE WHEN state = 'delivered' THEN 1 ELSE 0 END) AS delivered,"
                " SUM(CASE WHEN state = 'cancelled' THEN 1 ELSE 0 END) AS cancelled,"
                " SUM(CASE WHEN state = 'failed' THEN 1 ELSE 0 END) AS failed,"
                " SUM(CASE WHEN payment_mode = 'upi' THEN 1 ELSE 0 END) AS upi_orders,"
                " SUM(CASE WHEN payment_mode = 'cod' THEN 1 ELSE 0 END) AS cod_orders"
                " FROM orders WHERE substr(created_at, 1, 10) >= ?"
                " GROUP BY day ORDER BY day",
                (since_day,),
            )
        ).fetchall()
        return [dict(r) for r in rows]

    async def on_time_series(self, since_day: str) -> list[dict]:
        """Delivered orders vs on-time (delivered event <= window_end) per day."""
        rows = (
            await self._conn.execute(
                "SELECT substr(o.created_at, 1, 10) AS day,"
                " COUNT(*) AS delivered,"
                " SUM(CASE WHEN e.created_at <= CASE WHEN o.window_end > ''"
                "     THEN o.window_end ELSE o.window_start END THEN 1 ELSE 0 END) AS on_time"
                " FROM order_events e JOIN orders o ON o.id = e.order_id"
                " WHERE e.to_state = 'delivered' AND substr(o.created_at, 1, 10) >= ?"
                " GROUP BY day ORDER BY day",
                (since_day,),
            )
        ).fetchall()
        return [dict(r) for r in rows]

    async def money_totals(self) -> dict:
        ledger = (
            await self._conn.execute(
                "SELECT COALESCE(SUM(held), 0) AS jars_held,"
                " COALESCE(SUM(deposit_paid - deposit_refunded), 0) AS deposit_liability_paise,"
                " COALESCE(SUM(dues), 0) AS dues_paise"
                " FROM ledger"
            )
        ).fetchone()
        payouts = (
            await self._conn.execute(
                "SELECT COALESCE(SUM(CASE WHEN status = 'paid' THEN net ELSE 0 END), 0) AS paid_paise,"
                " COALESCE(SUM(CASE WHEN status != 'paid' THEN net ELSE 0 END), 0) AS pending_paise"
                " FROM payouts"
            )
        ).fetchone()
        collected = (
            await self._conn.execute(
                "SELECT COALESCE(SUM(CASE WHEN method = 'upi' THEN amount ELSE 0 END), 0) AS upi_paise,"
                " COALESCE(SUM(CASE WHEN method = 'cod' THEN amount ELSE 0 END), 0) AS cod_paise"
                " FROM payments WHERE status = 'paid'"
            )
        ).fetchone()
        return {
            "jars_held": int(ledger["jars_held"]),
            "deposit_liability_paise": int(ledger["deposit_liability_paise"]),
            "dues_paise": int(ledger["dues_paise"]),
            "payouts_paid_paise": int(payouts["paid_paise"]),
            "payouts_pending_paise": int(payouts["pending_paise"]),
            "collected_upi_paise": int(collected["upi_paise"]),
            "collected_cod_paise": int(collected["cod_paise"]),
        }

    # -- directories -----------------------------------------------------------

    async def users_page(
        self,
        *,
        query: str,
        role: str,
        suspended: int | None,
        limit: int,
        cursor: int,
    ) -> tuple[list[dict], str]:
        where, args = [], []
        if query:
            where.append("(u.phone LIKE ? OR u.name LIKE ? OR u.id = ?)")
            like = f"%{query}%"
            args.extend([like, like, query])
        if role:
            where.append("u.role = ?")
            args.append(role)
        if suspended is not None:
            where.append("u.suspended = ?")
            args.append(suspended)
        if cursor > 0:
            where.append("u.rowid < ?")
            args.append(cursor)
        clause = ("WHERE " + " AND ".join(where)) if where else ""
        rows = (
            await self._conn.execute(
                "SELECT u.id, u.phone, u.name, u.role, u.kyc_status, u.suspended,"
                " u.suspended_reason, u.suspended_at, u.created_at, u.rowid AS _rowid"
                f" FROM users u {clause} ORDER BY u.rowid DESC LIMIT ?",
                (*args, limit + 1),
            )
        ).fetchall()
        return _page(rows, limit)

    async def user_detail(self, user_id: str) -> dict | None:
        user = (
            await self._conn.execute(
                "SELECT id, phone, firebase_uid, name, role, language, kyc_status, suspended,"
                " suspended_reason, suspended_by, suspended_at, created_at FROM users WHERE id = ?",
                (user_id,),
            )
        ).fetchone()
        if user is None:
            return None
        orders_agg = (
            await self._conn.execute(
                "SELECT COUNT(*) AS orders_count, COALESCE(SUM(total), 0) AS spend_paise,"
                " MAX(created_at) AS last_order_at FROM orders WHERE user_id = ?",
                (user_id,),
            )
        ).fetchone()
        ledger = (
            await self._conn.execute(
                "SELECT held, deposit_paid, deposit_refunded, dues FROM ledger WHERE customer_id = ?",
                (user_id,),
            )
        ).fetchone()
        sessions = (
            await self._conn.execute(
                "SELECT COUNT(*) AS c FROM sessions WHERE user_id = ? AND revoked_at IS NULL",
                (user_id,),
            )
        ).fetchone()
        devices = (
            await self._conn.execute(
                "SELECT COUNT(*) AS c FROM device_tokens WHERE user_id = ?",
                (user_id,),
            )
        ).fetchone()
        strikes = (
            await self._conn.execute(
                "SELECT COUNT(*) AS c FROM strikes WHERE subject_id = ? AND cleared_at IS NULL",
                (user_id,),
            )
        ).fetchone()
        recent = (
            await self._conn.execute(
                "SELECT id, total, state, payment_status, created_at FROM orders"
                " WHERE user_id = ? ORDER BY created_at DESC LIMIT 10",
                (user_id,),
            )
        ).fetchall()
        return {
            "user": dict(user),
            "orders_count": int(orders_agg["orders_count"]),
            "spend_paise": int(orders_agg["spend_paise"]),
            "last_order_at": orders_agg["last_order_at"],
            "ledger": dict(ledger) if ledger
            else {"held": 0, "deposit_paid": 0, "deposit_refunded": 0, "dues": 0},
            "active_sessions": int(sessions["c"]),
            "devices": int(devices["c"]),
            "open_strikes": int(strikes["c"]),
            "recent_orders": [dict(r) for r in recent],
        }

    async def vendor_detail(self, vendor_id: str) -> dict | None:
        user = (
            await self._conn.execute(
                "SELECT id, phone, name, role, kyc_status, suspended, suspended_reason,"
                " suspended_at, created_at FROM users WHERE id = ?",
                (vendor_id,),
            )
        ).fetchone()
        if user is None:
            return None
        profile = (
            await self._conn.execute(
                "SELECT * FROM vendor_profile WHERE user_id = ?", (vendor_id,)
            )
        ).fetchone()
        zones = (
            await self._conn.execute(
                "SELECT z.id, z.name, vz.priority FROM vendor_zones vz"
                " JOIN zones z ON z.id = vz.zone_id WHERE vz.vendor_id = ?",
                (vendor_id,),
            )
        ).fetchall()
        stops = (
            await self._conn.execute(
                "SELECT COUNT(*) AS stops_done,"
                " COALESCE(SUM(fulls_exp), 0) AS jars_out"
                " FROM stops s JOIN routes r ON r.id = s.route_id"
                " WHERE r.vendor_id = ? AND s.status = 'done'",
                (vendor_id,),
            )
        ).fetchone()
        payouts = (
            await self._conn.execute(
                "SELECT id, period, stops_done, gross_fee, deductions, net, status, created_at"
                " FROM payouts WHERE vendor_id = ? ORDER BY created_at DESC LIMIT 10",
                (vendor_id,),
            )
        ).fetchall()
        strikes = (
            await self._conn.execute(
                "SELECT id, kind, severity, note, created_at FROM strikes"
                " WHERE subject_id = ? ORDER BY created_at DESC LIMIT 10",
                (vendor_id,),
            )
        ).fetchall()
        return {
            "vendor": dict(user),
            "profile": dict(profile) if profile else None,
            "zones": [dict(z) for z in zones],
            "stops_done": int(stops["stops_done"]),
            "jars_delivered": int(stops["jars_out"]),
            "payouts": [dict(p) for p in payouts],
            "strikes": [dict(s) for s in strikes],
        }

    # -- money surfaces ----------------------------------------------------------

    async def payments_page(
        self, *, status: str, method: str, limit: int, cursor: int
    ) -> tuple[list[dict], str]:
        where, args = [], []
        if status:
            where.append("p.status = ?")
            args.append(status)
        if method:
            where.append("p.method = ?")
            args.append(method)
        if cursor > 0:
            where.append("p.rowid < ?")
            args.append(cursor)
        clause = ("WHERE " + " AND ".join(where)) if where else ""
        rows = (
            await self._conn.execute(
                "SELECT p.id, p.order_id, p.user_id, p.amount, p.method, p.provider_ref,"
                " p.status, p.created_at, p.verified_at, p.rowid AS _rowid,"
                " o.state AS order_state, o.payment_status AS order_payment_status,"
                " u.name AS user_name, u.phone AS user_phone"
                " FROM payments p"
                " LEFT JOIN orders o ON o.id = p.order_id"
                " LEFT JOIN users u ON u.id = p.user_id"
                f" {clause} ORDER BY p.rowid DESC LIMIT ?",
                (*args, limit + 1),
            )
        ).fetchall()
        return _page(rows, limit)

    async def refunds_page(self, *, status: str, limit: int, cursor: int) -> tuple[list[dict], str]:
        where, args = [], []
        if status:
            where.append("rf.status = ?")
            args.append(status)
        if cursor > 0:
            where.append("rf.rowid < ?")
            args.append(cursor)
        clause = ("WHERE " + " AND ".join(where)) if where else ""
        rows = (
            await self._conn.execute(
                "SELECT rf.id, rf.order_id, rf.payment_id, rf.amount, rf.method, rf.status,"
                " rf.claimed_by, rf.created_at, rf.done_at, rf.rowid AS _rowid,"
                " u.name AS user_name, u.phone AS user_phone"
                " FROM refunds rf"
                " LEFT JOIN payments pay ON pay.id = rf.payment_id"
                " LEFT JOIN orders o ON o.id = rf.order_id"
                " LEFT JOIN users u ON u.id = o.user_id"
                f" {clause} ORDER BY rf.rowid DESC LIMIT ?",
                (*args, limit + 1),
            )
        ).fetchall()
        return _page(rows, limit)

    async def ledger_page(self, *, limit: int, cursor: int) -> tuple[list[dict], str]:
        where, args = [], []
        if cursor > 0:
            where.append("l.rowid < ?")
            args.append(cursor)
        clause = ("WHERE " + " AND ".join(where)) if where else ""
        rows = (
            await self._conn.execute(
                "SELECT l.customer_id, l.held, l.deposit_paid, l.deposit_refunded, l.dues,"
                " l.rowid AS _rowid, u.name AS customer_name, u.phone AS customer_phone"
                " FROM ledger l LEFT JOIN users u ON u.id = l.customer_id"
                f" {clause} ORDER BY l.rowid DESC LIMIT ?",
                (*args, limit + 1),
            )
        ).fetchall()
        return _page(rows, limit)
