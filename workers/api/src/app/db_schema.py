"""Per-isolate schema probes.

Migrations are static at runtime: a column set cannot change inside an
isolate's lifetime, so probing once removes a PRAGMA from every hot read.
Only schema metadata is cached here — never request or user data.
"""

from __future__ import annotations

from app.db_d1 import AsyncSqliteConn, D1Conn

Conn = D1Conn | AsyncSqliteConn

_stop_cols: frozenset[str] | None = None
_order_cols: frozenset[str] | None = None


async def _table_cols(conn: Conn, table: str) -> frozenset[str] | None:
    """Column names, or None when the probe itself fails (retry next call)."""
    try:
        rows = (await conn.execute(
            f"SELECT name FROM pragma_table_info('{table}')"  # noqa: S608 (literal table)
        )).fetchall()
    except Exception:
        return None
    return frozenset(str(r["name"]) for r in rows)


async def stop_columns(conn: Conn) -> frozenset[str]:
    global _stop_cols
    if _stop_cols is None:
        cols = await _table_cols(conn, "stops")
        if cols is not None:
            _stop_cols = cols
        return cols or frozenset()
    return _stop_cols


async def order_columns(conn: Conn) -> frozenset[str]:
    global _order_cols
    if _order_cols is None:
        cols = await _table_cols(conn, "orders")
        if cols is not None:
            _order_cols = cols
        return cols or frozenset()
    return _order_cols


def reset_schema_cache() -> None:  # tests only
    global _stop_cols, _order_cols
    _stop_cols = None
    _order_cols = None
