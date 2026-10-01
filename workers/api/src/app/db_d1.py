"""Async DB facade: one call shape for D1 (prod) and sqlite (local/tests).

Repositories/services call ``await conn.execute(sql, params)`` and read the
returned :class:`Rows` exactly like a DB-API cursor (``fetchone`` /
``fetchall`` / ``rowcount``); ``commit()`` / ``rollback()`` stay
synchronous (D1 auto-commits per statement; sqlite commits for real).

- :class:`D1Conn` — wraps a Cloudflare D1 binding (async-only API).
  Reads use ``all()``; writes use ``run()`` (rowcount comes from meta).
- :class:`AsyncSqliteConn` — wraps a stdlib ``sqlite3`` connection for
  local dev and pytest (same await shape, real transactions).

Phase-A note: only the auth slice (users/sessions + auth service/router)
uses this; every other caller keeps raw ``sqlite3`` until its own phase.
"""

from __future__ import annotations

import sqlite3


def _row_to_dict(row) -> dict:
    if isinstance(row, dict):
        return dict(row)
    to_py = getattr(row, "to_py", None)
    if callable(to_py):
        try:
            value = to_py()
            return dict(value) if isinstance(value, dict) else {"value": value}
        except Exception:
            pass
    try:
        return dict(row)
    except Exception:
        return {"value": row}


class Rows:
    """Cursor-compatible result (fetchone/fetchall/rowcount)."""

    def __init__(self, rows: list[dict], rowcount: int = 0):
        self._rows = rows
        self.rowcount = rowcount

    def fetchone(self) -> dict | None:
        return self._rows[0] if self._rows else None

    def fetchall(self) -> list[dict]:
        return list(self._rows)

    def __iter__(self):
        return iter(self._rows)

    def __len__(self) -> int:
        return len(self._rows)


_READ_PREFIXES = ("select", "with", "pragma", "explain")


class D1Conn:
    """Async connection over a D1 database binding."""

    def __init__(self, binding):
        self._db = binding

    async def execute(self, sql: str, params: tuple = ()) -> Rows:
        stmt = self._db.prepare(sql)
        if params:
            stmt = stmt.bind(*params)
        first = sql.strip().split(None, 1)
        if first and first[0].lower() in _READ_PREFIXES:
            res = await stmt.all()
            results = list(getattr(res, "results", None) or [])
            return Rows([_row_to_dict(r) for r in results], rowcount=len(results))
        res = await stmt.run()
        meta = getattr(res, "meta", None)
        changes = getattr(meta, "changes", None) if meta is not None else None
        return Rows([], rowcount=int(changes) if isinstance(changes, int) else 0)

    def commit(self) -> None:
        """No-op: D1 auto-commits every statement (see ADR T2 caveat)."""

    def rollback(self) -> None:
        """No-op: nothing to roll back on D1 (same caveat)."""


class AsyncSqliteConn:
    """Async-shaped wrapper over a stdlib sqlite3 connection (local/tests)."""

    def __init__(self, conn: sqlite3.Connection):
        self._conn = conn

    async def execute(self, sql: str, params: tuple = ()) -> Rows:
        cur = self._conn.execute(sql, params)
        rows = [dict(r) for r in cur.fetchall()]
        count = cur.rowcount if cur.rowcount and cur.rowcount >= 0 else len(rows)
        return Rows(rows, rowcount=count)

    def executescript(self, sql: str) -> None:
        """Setup escape hatch (migrations in tests); never used by repos."""
        self._conn.executescript(sql)
        self._conn.commit()

    def commit(self) -> None:
        self._conn.commit()

    def rollback(self) -> None:
        self._conn.rollback()
