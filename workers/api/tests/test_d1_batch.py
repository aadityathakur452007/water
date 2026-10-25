"""D1 batch/execute hardening (Phase 1A prerequisite).

The local suite mostly runs on sqlite, so the real D1 failure path needs a
fake binding: a failed statement must raise, never return partial results, and
a batch must count as one network roundtrip.
"""
import sys
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.core.observability import (  # noqa: E402
    current_metrics,
    reset_metrics,
    start_metrics,
)
from app.db import get_connection  # noqa: E402
from app.db_d1 import AsyncSqliteConn, D1BatchError, D1Conn  # noqa: E402


class FakeResult:
    def __init__(self, results=None, changes=0, success=True, error=None, meta=None):
        self.results = list(results or [])
        self.success = success
        self.error = error
        self.meta = meta if meta is not None else {
            "changes": changes,
            "rows_read": len(self.results),
            "rows_written": changes,
        }


class FakeStmt:
    def __init__(self, db, sql, params=()):
        self._db = db
        self.sql = sql
        self.params = tuple(params)

    def bind(self, *params):
        self.params = tuple(params)
        return self

    async def all(self):
        return self._db.next_result()

    async def run(self):
        return self._db.next_result()


class FakeDB:
    """Minimal D1 binding: queue one result per execute/batch call."""

    def __init__(self):
        self.batch_calls = 0
        self.results: list = []
        self.batch_results: list | None = None
        self.executed: list[tuple[str, tuple]] = []

    def prepare(self, sql):
        return FakeStmt(self, sql)

    def next_result(self):
        return self.results.pop(0) if self.results else FakeResult()

    async def batch(self, statements):
        self.batch_calls += 1
        self.executed.extend((s.sql, s.params) for s in statements)
        if self.batch_results is not None:
            return self.batch_results
        return [FakeResult(changes=1) for _ in statements]


async def test_batch_preserves_rowcounts_and_counts_one_roundtrip():
    db = FakeDB()
    db.batch_results = [FakeResult(changes=2), FakeResult(changes=1)]
    metrics, token = start_metrics()
    try:
        out = await D1Conn(db).batch([
            ("UPDATE orders SET state='x' WHERE id=?", ("o1",)),
            ("INSERT INTO order_events(id) VALUES (?)", ("e1",)),
        ])
        assert [r.rowcount for r in out] == [2, 1]
        assert db.batch_calls == 1
        m = current_metrics()
        assert m is not None
        assert (m.db_queries, m.db_roundtrips) == (2, 1)
    finally:
        reset_metrics(token)


async def test_batch_failure_raises_with_statement_index():
    db = FakeDB()
    db.batch_results = [
        FakeResult(changes=1),
        FakeResult(success=False, error="UNIQUE constraint failed"),
    ]
    with pytest.raises(D1BatchError) as e:
        await D1Conn(db).batch([
            ("INSERT INTO a(id) VALUES (?)", ("1",)),
            ("INSERT INTO a(id) VALUES (?)", ("1",)),
        ])
    assert "statement 1" in str(e.value)
    assert "UNIQUE" in str(e.value)


async def test_batch_short_result_list_is_an_error():
    db = FakeDB()
    db.batch_results = [FakeResult(changes=1)]
    with pytest.raises(D1BatchError, match="returned 1 results for 2"):
        await D1Conn(db).batch([
            ("INSERT INTO a(id) VALUES (?)", ("1",)),
            ("INSERT INTO a(id) VALUES (?)", ("2",)),
        ])


async def test_batch_read_uses_dict_results_and_meta():
    db = FakeDB()
    db.batch_results = [{
        "success": True,
        "results": [{"id": "o1"}, {"id": "o2"}],
        "meta": {"rows_read": 2},
    }]
    out = await D1Conn(db).batch([
        ("SELECT id FROM orders WHERE state=?", ("placed",)),
    ])
    assert out[0].rowcount == 2
    assert [r["id"] for r in out[0].fetchall()] == ["o1", "o2"]


async def test_execute_write_failure_raises():
    db = FakeDB()
    db.results = [FakeResult(success=False, error="no such table")]
    with pytest.raises(D1BatchError, match="no such table"):
        await D1Conn(db).execute("INSERT INTO missing(id) VALUES (?)", ("1",))


async def test_execute_read_failure_raises():
    db = FakeDB()
    db.results = [FakeResult(success=False, error="malformed SQL")]
    with pytest.raises(D1BatchError, match="malformed SQL"):
        await D1Conn(db).execute("SELECT * FROM missing")


async def test_sqlite_batch_rolls_back_every_statement():
    raw = get_connection(":memory:")
    raw.execute("CREATE TABLE t(id TEXT PRIMARY KEY, n INTEGER)")
    raw.commit()
    conn = AsyncSqliteConn(raw)
    with pytest.raises(Exception):
        await conn.batch([
            ("INSERT INTO t(id, n) VALUES (?, ?)", ("a", 1)),
            ("INSERT INTO missing(id) VALUES (?)", ("b",)),
        ])
    assert raw.execute("SELECT COUNT(*) c FROM t").fetchone()["c"] == 0


async def test_sqlite_batch_leaves_outer_transaction_open():
    raw = get_connection(":memory:")
    raw.execute("CREATE TABLE t(id TEXT PRIMARY KEY)")
    raw.commit()
    conn = AsyncSqliteConn(raw)
    raw.execute("BEGIN")
    await conn.batch([("INSERT INTO t(id) VALUES (?)", ("a",))])
    assert raw.in_transaction is True
    raw.rollback()
    assert raw.execute("SELECT COUNT(*) c FROM t").fetchone()["c"] == 0


def test_purge_chunk_respects_d1_parameter_limit():
    from app.jobs.scheduler import _PURGE_CHUNK

    assert _PURGE_CHUNK <= 90
