"""Real health probe: one D1 round-trip, cached per isolate for 5 s.

Success keeps the legacy contract exactly ``{"status":"ok"}``. Failure is
additive (503 + ``checks.db``) and never includes exception text, SQL, or
secrets. Failures are cached too, so a monitor cannot amplify a D1 outage.
"""

from __future__ import annotations

import asyncio
import logging
import time

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from app.api.deps import get_db_conn
from app.core.observability import elapsed_ms

log = logging.getLogger(__name__)

router = APIRouter(tags=["health"])

_PROBE_TIMEOUT_S = 2.0
_CACHE_TTL_S = 5.0
_cache: tuple[float, bool] | None = None


def reset_health_cache() -> None:
    """Test hook / manual reset (per-isolate cache is otherwise 5 s)."""
    global _cache
    _cache = None


async def _probe(conn) -> tuple[bool, float]:
    started = time.perf_counter()
    try:
        await asyncio.wait_for(conn.execute("SELECT 1"), timeout=_PROBE_TIMEOUT_S)
        return True, elapsed_ms(started)
    except Exception:  # noqa: BLE001 - degraded is the signal, not the error text
        return False, elapsed_ms(started)


@router.get("/health")
async def health(request: Request, conn=Depends(get_db_conn)) -> JSONResponse:
    global _cache
    now = time.monotonic()
    cached = _cache
    probed = False
    duration_ms = 0.0
    if cached is not None and now - cached[0] < _CACHE_TTL_S:
        ok = cached[1]
    else:
        ok, duration_ms = await _probe(conn)
        _cache = (time.monotonic(), ok)
        probed = True

    headers = {"Cache-Control": "no-store"}
    if ok:
        return JSONResponse({"status": "ok"}, headers=headers)

    if probed:
        trace_id = getattr(request.state, "trace_id", "unknown")
        log.warning(
            "health degraded trace_id=%s duration_ms=%.1f", trace_id, duration_ms
        )
    return JSONResponse(
        {"status": "degraded", "checks": {"db": "error"}},
        status_code=503,
        headers=headers,
    )
