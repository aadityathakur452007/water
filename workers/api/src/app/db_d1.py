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

from app.core.observability import record_db


class D1BatchError(RuntimeError):
    """A D1 statement/batch reported failure; never return partial results."""


def _result_error(res) -> str:
    err = getattr(res, "error", None)
    if err is None and isinstance(res, dict):
        err = res.get("error")
    return str(err or "statement failed")[:200]


def _result_ok(res) -> bool:
    success = getattr(res, "success", None)
    if success is None and isinstance(res, dict):
        success = res.get("success")
    return success is not False


def _result_results(res) -> list:
    results = getattr(res, "results", None)
    if results is None and isinstance(res, dict):
        results = res.get("results")
    return list(results or [])


def _result_meta(res):
    meta = getattr(res, "meta", None)
    if meta is None and isinstance(res, dict):
        meta = res.get("meta")
    return meta


def _row_to_dict(row) -> dict:
    if isinstance(row, dict):
        return row
    to_py = getattr(row, "to_py", None)
    if callable(to_py):
        try:
            # depth=1 performs a fast shallow conversion rather than recursive deep traversal
            value = to_py(depth=1)
            return dict(value) if isinstance(value, dict) else {"value": value}
        except TypeError:
            try:
                value = to_py()
                return dict(value) if isinstance(value, dict) else {"value": value}
            except Exception:
                pass
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


def _is_read(sql: str) -> bool:
    first = sql.strip().split(None, 1)
    return bool(first) and first[0].lower() in _READ_PREFIXES


def _meta_int(meta, name: str) -> int | None:
    value = getattr(meta, name, None)
    if value is None and isinstance(meta, dict):
        value = meta.get(name)
    return int(value) if isinstance(value, (int, float)) else None


class D1Conn:
    """Async connection over a D1 database binding."""

    def __init__(self, binding):
        self._db = binding

    async def execute(self, sql: str, params: tuple = ()) -> Rows:
        stmt = self._db.prepare(sql)
        if params:
            stmt = stmt.bind(*params)
        if _is_read(sql):
            res = await stmt.all()
            if not _result_ok(res):
                raise D1BatchError(f"D1 read failed: {_result_error(res)}")
            results = _result_results(res)
            meta = _result_meta(res)
            rows_read = _meta_int(meta, "rows_read")
            record_db(
                queries=1,
                roundtrips=1,
                rows_read=len(results) if rows_read is None else rows_read,
            )
            return Rows([_row_to_dict(r) for r in results], rowcount=len(results))
        res = await stmt.run()
        if not _result_ok(res):
            raise D1BatchError(f"D1 write failed: {_result_error(res)}")
        meta = _result_meta(res)
        changes = _meta_int(meta, "changes")
        rows_written = _meta_int(meta, "rows_written")
        record_db(
            queries=1,
            roundtrips=1,
            rows_read=_meta_int(meta, "rows_read") or 0,
            rows_written=(changes or 0) if rows_written is None else rows_written,
        )
        return Rows([], rowcount=changes or 0)

    async def batch(self, statements: list[tuple[str, tuple]]) -> list[Rows]:
        """Execute multiple SQL statements in a single network round trip via D1 batch."""
        if not statements:
            return []
        stmts = []
        for sql, params in statements:
            stmt = self._db.prepare(sql)
            if params:
                stmt = stmt.bind(*params)
            stmts.append(stmt)
        res_list = list(await self._db.batch(stmts) or [])
        if len(res_list) != len(statements):
            raise D1BatchError(
                f"D1 batch returned {len(res_list)} results for {len(statements)} statements"
            )
        for index, res in enumerate(res_list):
            if not _result_ok(res):
                raise D1BatchError(
                    f"D1 batch statement {index} failed: {_result_error(res)}"
                )
        out = []
        rows_read = 0
        rows_written = 0
        for (sql, _), res in zip(statements, res_list):
            meta = _result_meta(res)
            if _is_read(sql):
                results = _result_results(res)
                meta_read = _meta_int(meta, "rows_read")
                rows_read += len(results) if meta_read is None else meta_read
                out.append(Rows([_row_to_dict(r) for r in results], rowcount=len(results)))
            else:
                changes = _meta_int(meta, "changes")
                meta_written = _meta_int(meta, "rows_written")
                rows_written += (
                    (changes or 0) if meta_written is None else meta_written
                )
                out.append(Rows([], rowcount=changes or 0))
        record_db(
            queries=len(statements),
            roundtrips=1,
            rows_read=rows_read,
            rows_written=rows_written,
        )
        return out

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
        if _is_read(sql):
            record_db(queries=1, roundtrips=1, rows_read=len(rows))
        else:
            record_db(
                queries=1,
                roundtrips=1,
                rows_written=count if cur.rowcount and cur.rowcount >= 0 else 0,
            )
        return Rows(rows, rowcount=count)

    async def batch(self, statements: list[tuple[str, tuple]]) -> list[Rows]:
        """All-or-nothing sqlite batch (matches D1's transaction contract)."""
        if not statements:
            return []
        started = not self._conn.in_transaction
        if started:
            self._conn.execute("BEGIN IMMEDIATE")
        out = []
        rows_read = 0
        rows_written = 0
        try:
            for sql, params in statements:
                cur = self._conn.execute(sql, params)
                rows = [dict(r) for r in cur.fetchall()]
                count = cur.rowcount if cur.rowcount and cur.rowcount >= 0 else len(rows)
                if _is_read(sql):
                    rows_read += len(rows)
                elif cur.rowcount and cur.rowcount >= 0:
                    rows_written += cur.rowcount
                out.append(Rows(rows, rowcount=count))
        except Exception:
            self._conn.rollback()
            raise
        record_db(
            queries=len(statements),
            roundtrips=1,
            rows_read=rows_read,
            rows_written=rows_written,
        )
        return out

    def executescript(self, sql: str) -> None:
        """Setup escape hatch (migrations in tests); never used by repos."""
        self._conn.executescript(sql)
        self._conn.commit()

    def commit(self) -> None:
        self._conn.commit()

    def rollback(self) -> None:
        self._conn.rollback()
