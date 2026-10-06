"""Edge hardening (ssdlc Phase 6): security headers, CORS allowlist, body cap, anon throttle.

Contract §0 rate table: catalog/windows/serviceability 120/IP/min → 429 + Retry-After.
All rejections use the §0 error envelope {error: {code, message, details, trace_id}}.
"""

import threading
import time

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

import logging

from app.api.deps import get_settings
from app.core.errors import error_envelope, get_trace_id

log = logging.getLogger(__name__)

_THROTTLED_PATHS = frozenset({"/v1/catalog", "/v1/windows", "/v1/serviceability"})
_THROTTLE_WINDOW_S = 60

_throttle_hits: dict[str, list[float]] = {}
_throttle_lock = threading.Lock()
# TODO(D1): D1-backed counters (multi-isolate). This dict is per-process:
# each Worker isolate counts on its own, so global limits are approximate
# for the anon throttle (same caveat as services.auth_service.RateLimiter).
# Phase 8 §8.4 narrowed the gap for AUTH paths (D1 truth in rate_counters);
# this anon edge throttle keeps the L1 shape — public catalog reads stay
# cheap and never pay a D1 read per request.


def _secure(response: JSONResponse) -> JSONResponse:
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Content-Security-Policy"] = "default-src 'self'"
    return response


async def security_headers_middleware(request: Request, call_next):
    return _secure(await call_next(request))


def _too_large(request: Request, maximum: int) -> JSONResponse:
    trace_id = get_trace_id(request)
    return _secure(
        JSONResponse(
            status_code=413,
            content=error_envelope(
                "PAYLOAD_TOO_LARGE",
                "Request body too large.",
                {"max_bytes": maximum},
                trace_id,
            ),
        )
    )


async def body_cap_middleware(request: Request, call_next):
    maximum = get_settings().body_max_bytes
    claimed = (request.headers.get("content-length") or "").strip()
    if claimed.isdigit() and int(claimed) > maximum:
        return _too_large(request, maximum)
    if len(await request.body()) > maximum:
        return _too_large(request, maximum)
    return await call_next(request)


def _throttled(request: Request, retry_after_s: int) -> JSONResponse:
    trace_id = get_trace_id(request)
    response = JSONResponse(
        status_code=429,
        content=error_envelope(
            "RATE_LIMITED",
            "Too many requests.",
            {"retry_after_s": retry_after_s},
            trace_id,
        ),
    )
    response.headers["Retry-After"] = str(retry_after_s)
    return _secure(response)


async def throttle_middleware(request: Request, call_next):
    path = request.url.path.rstrip("/") or "/"
    if request.method == "OPTIONS" or path not in _THROTTLED_PATHS:
        return await call_next(request)
    limit = get_settings().throttle_anon_per_min
    host = request.client.host if request.client and request.client.host else "unknown"
    key = f"throttle:{host}:{path}"
    now = time.monotonic()
    with _throttle_lock:
        hits = [t for t in _throttle_hits.get(key, []) if t > now - _THROTTLE_WINDOW_S]
        if len(hits) >= limit:
            retry = int(max(1, _THROTTLE_WINDOW_S - (now - hits[0])))
            # Phase 8 §8.4: observability on limit hits (pairs with Phase 10 alerting).
            log.warning("rate_limit edge_hit path=%s host=%s retry_after_s=%d", path, host, retry)
            return _throttled(request, retry)
        hits.append(now)
        _throttle_hits[key] = hits
    return await call_next(request)


def reset_throttle() -> None:  # tests only
    with _throttle_lock:
        _throttle_hits.clear()


def configure_cors(app: FastAPI) -> None:
    """Allowlist-only CORS (never * with credentials); empty allowlist denies cross-origin."""
    origins = get_settings().allowed_origins
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=bool(origins),
        allow_methods=["*"],
        allow_headers=["*"],
    )
