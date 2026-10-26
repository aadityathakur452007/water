"""Shared FastAPI dependencies: settings, trace middleware, db session."""

from collections.abc import Iterator
from functools import lru_cache
from time import perf_counter

from fastapi import Request

from app.core.config import Settings
from app.core.errors import TRACE_HEADER, safe_trace_id
from app.core.observability import (
    elapsed_ms,
    log_request,
    reset_metrics,
    start_metrics,
)


@lru_cache
def get_settings() -> Settings:
    return Settings()


async def trace_middleware(request: Request, call_next):
    """Outermost request middleware: sanitize trace id, time, and log.

    Registered last in ``create_app`` so throttle/body-cap rejections also get
    a trace id and a structured log line. Logging failures never escape.
    """
    trace_id = safe_trace_id(request.headers.get(TRACE_HEADER))
    request.state.trace_id = trace_id
    metrics, token = start_metrics()
    started = perf_counter()
    status_code = 500
    try:
        response = await call_next(request)
        status_code = response.status_code
        response.headers[TRACE_HEADER] = trace_id
        return response
    finally:
        try:
            log_request(
                request,
                status_code=status_code,
                duration_ms=elapsed_ms(started),
                metrics=metrics,
                trace_id=trace_id,
            )
        except Exception:  # noqa: BLE001 - never break the request path
            pass
        reset_metrics(token)


def get_db() -> Iterator:
    # B3 owns app.db. Lazy import so slice-1 health tests pass before db.py lands.
    from app.db import get_connection  # noqa: PLC0415

    if _TEST_CONNECTION is not None:
        yield _TEST_CONNECTION
        return
    yield get_connection()


_TEST_CONNECTION = None


def set_test_connection(conn) -> None:
    """Test hook (integrator-added for C1): route get_db to an in-memory DB."""
    global _TEST_CONNECTION
    _TEST_CONNECTION = conn


def get_db_conn(request: Request):
    """Phase-A T2 connection selector (plain sync dependency, no yield).

    Production (worker env pinned by entry.py) → D1Conn over the DB binding.
    Local/pytest → AsyncSqliteConn over sqlite (same await shape, so converted
    callers work identically in both). Non-converted routers keep get_db.
    """
    from app.core.worker_env import current_env  # noqa: PLC0415
    from app.db import get_connection  # noqa: PLC0415
    from app.db_d1 import AsyncSqliteConn, D1Conn  # noqa: PLC0415
    from app.db import get_d1  # noqa: PLC0415

    if isinstance(_TEST_CONNECTION, (D1Conn, AsyncSqliteConn)):
        return _TEST_CONNECTION
    if _TEST_CONNECTION is not None:
        return AsyncSqliteConn(_TEST_CONNECTION)
    env = request.scope.get("env") or current_env()
    binding = get_d1(env)
    if binding is not None:
        return D1Conn(binding)
    return AsyncSqliteConn(get_connection())
