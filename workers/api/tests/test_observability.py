"""Phase 0 observability: redaction, sampling, trace ids, DB counters, health."""

import json
import logging
import re
import sqlite3
import sys
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.api.deps import get_db_conn  # noqa: E402
from app.api.health import reset_health_cache  # noqa: E402
from app.core import observability  # noqa: E402
from app.core.errors import TRACE_HEADER, safe_trace_id  # noqa: E402
from app.db_d1 import AsyncSqliteConn, D1Conn  # noqa: E402
from app.main import create_app  # noqa: E402

TRACE_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
LOG_NAME = "shodasha.request"


@pytest.fixture(autouse=True)
def _reset_health():
    reset_health_cache()
    yield
    reset_health_cache()


@pytest.fixture
def client():
    return TestClient(create_app())


def _payloads(caplog) -> list[dict]:
    out = []
    for rec in caplog.records:
        if rec.name != LOG_NAME:
            continue
        msg = rec.getMessage()
        if not msg.startswith("{"):
            continue
        try:
            out.append(json.loads(msg))
        except json.JSONDecodeError:
            continue
    return out


def test_trace_id_is_sanitized_and_echoed(client):
    raw = "bad id!<>|; DROP"
    r = client.get("/does-not-exist", headers={TRACE_HEADER: raw})
    assert r.status_code == 404
    echoed = r.headers[TRACE_HEADER]
    assert echoed != raw
    assert TRACE_RE.match(echoed)
    assert r.json()["error"]["trace_id"] == echoed


def test_safe_trace_id_accepts_only_log_safe_values():
    assert safe_trace_id("abc.DEF-123_") == "abc.DEF-123_"
    assert TRACE_RE.match(safe_trace_id("x" * 100))
    assert safe_trace_id("bad id") != "bad id"
    assert safe_trace_id(None) and TRACE_RE.match(safe_trace_id(None))


def test_request_log_redacts_query_headers_and_raw_path(client, caplog, monkeypatch):
    monkeypatch.setenv("OBS_LOG_SAMPLE_RATE", "1")
    monkeypatch.setenv("OBS_SLOW_MS", "999999")
    caplog.set_level(logging.INFO, logger=LOG_NAME)
    r = client.get(
        "/health?phone=%2B919999999999",
        headers={
            "Authorization": "Bearer supersecret-token",
            "Cookie": "sh_session=secret-cookie",
            TRACE_HEADER: "trace-redact-1",
        },
    )
    assert r.status_code == 200
    rows = _payloads(caplog)
    assert rows
    payload = rows[-1]
    assert payload["route"] == "/health"
    assert payload["trace_id"] == "trace-redact-1"
    assert set(payload) == {
        "event",
        "ts",
        "env",
        "trace_id",
        "method",
        "route",
        "status",
        "duration_ms",
        "db_queries",
        "db_roundtrips",
        "db_rows_read",
        "db_rows_written",
    }
    text = json.dumps(payload)
    for secret in ("9999999999", "supersecret-token", "secret-cookie", "phone"):
        assert secret not in text


def test_unmatched_path_logs_template_not_raw_path(client, caplog, monkeypatch):
    monkeypatch.setenv("OBS_LOG_SAMPLE_RATE", "0")
    caplog.set_level(logging.INFO, logger=LOG_NAME)
    r = client.get("/v1/secret-phone-9999999999")
    assert r.status_code == 404
    rows = _payloads(caplog)
    assert any(
        p["status"] == 404 and p["route"] == "<unmatched>" for p in rows
    )
    assert "9999999999" not in json.dumps(rows)


def test_errors_log_even_at_zero_sample(client, caplog, monkeypatch):
    monkeypatch.setenv("OBS_LOG_SAMPLE_RATE", "0")
    caplog.set_level(logging.INFO, logger=LOG_NAME)
    client.get("/does-not-exist", headers={TRACE_HEADER: "trace-404"})
    assert any(
        p["status"] == 404 and p["trace_id"] == "trace-404"
        for p in _payloads(caplog)
    )


def test_healthy_fast_path_silent_at_zero_sample(client, caplog, monkeypatch):
    monkeypatch.setenv("OBS_LOG_SAMPLE_RATE", "0")
    caplog.set_level(logging.INFO, logger=LOG_NAME)
    assert client.get("/health").status_code == 200
    assert not any(p["status"] == 200 for p in _payloads(caplog))


def test_slow_requests_always_log(monkeypatch):
    monkeypatch.setenv("OBS_LOG_SAMPLE_RATE", "0")
    monkeypatch.setenv("OBS_SLOW_MS", "100")
    assert observability.should_log(
        status_code=200, duration_ms=100, trace_id="trace-slow"
    )
    assert not observability.should_log(
        status_code=200, duration_ms=99, trace_id="trace-fast"
    )


def test_sampling_is_deterministic_and_bounded():
    assert observability.sampled("trace-a", 0) is False
    assert observability.sampled("trace-a", 1) is True
    assert observability.sampled("trace-a", 0.5) == observability.sampled(
        "trace-a", 0.5
    )


class _Meta:
    def __init__(self, rows_read=0, rows_written=0, changes=0):
        self.rows_read = rows_read
        self.rows_written = rows_written
        self.changes = changes


class _Res:
    def __init__(self, results, meta):
        self.results = results
        self.meta = meta


class _Stmt:
    def __init__(self, res):
        self.res = res

    def bind(self, *params):
        return self

    async def all(self):
        return self.res

    async def run(self):
        return self.res


class _FakeD1:
    def prepare(self, sql):
        if sql.strip().lower().startswith("select"):
            return _Stmt(_Res([{"a": 1}, {"a": 2}], _Meta(rows_read=2)))
        return _Stmt(_Res([], _Meta(rows_written=3, changes=3)))

    async def batch(self, stmts):
        return [s.res for s in stmts]


async def test_d1_counters_use_meta_and_count_batch_as_one_roundtrip():
    conn = D1Conn(_FakeD1())
    metrics, token = observability.start_metrics()
    try:
        await conn.execute("SELECT * FROM t")
        await conn.execute("UPDATE t SET a = 1")
        await conn.batch([("SELECT * FROM t", ()), ("UPDATE t SET a = 2", ())])
    finally:
        observability.reset_metrics(token)
    assert metrics.db_queries == 4
    assert metrics.db_roundtrips == 3
    assert metrics.db_rows_read == 4
    assert metrics.db_rows_written == 6


async def test_sqlite_counters_local_shape():
    raw = sqlite3.connect(":memory:")
    raw.row_factory = sqlite3.Row
    conn = AsyncSqliteConn(raw)
    metrics, token = observability.start_metrics()
    try:
        await conn.execute("CREATE TABLE t (a INTEGER)")
        await conn.execute("INSERT INTO t (a) VALUES (?)", (1,))
        await conn.execute("SELECT a FROM t")
        await conn.batch([("INSERT INTO t (a) VALUES (?)", (2,)), ("SELECT a FROM t", ())])
    finally:
        observability.reset_metrics(token)
    assert metrics.db_queries == 5
    assert metrics.db_roundtrips == 4
    assert metrics.db_rows_read == 3  # 1 row before batch, 2 rows after its insert
    assert metrics.db_rows_written == 2


def test_health_success_contract(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
    assert r.headers["Cache-Control"] == "no-store"
    assert r.headers[TRACE_HEADER]


def test_health_degraded_on_db_failure(client):
    class _FailConn:
        async def execute(self, sql, params=()):
            raise RuntimeError("secret dsn /internal/path")

    client.app.dependency_overrides[get_db_conn] = lambda: _FailConn()
    try:
        r = client.get("/health")
    finally:
        client.app.dependency_overrides.pop(get_db_conn, None)
    assert r.status_code == 503
    assert r.json() == {"status": "degraded", "checks": {"db": "error"}}
    assert r.headers["Cache-Control"] == "no-store"
    assert "secret" not in r.text
    assert "internal" not in r.text


def test_health_caches_probe_per_isolate(client):
    class _CountingConn:
        calls = 0

        async def execute(self, sql, params=()):
            self.calls += 1
            return None

    conn = _CountingConn()
    client.app.dependency_overrides[get_db_conn] = lambda: conn
    try:
        assert client.get("/health").status_code == 200
        assert client.get("/health").status_code == 200
    finally:
        client.app.dependency_overrides.pop(get_db_conn, None)
    assert conn.calls == 1
