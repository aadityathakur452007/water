"""Structured request logs + request-scoped DB counters (Phase 0).

One JSON object per sampled request. The payload is deliberately closed: it
contains only the route *template*, method, status, duration, trace id and
D1 counters. Headers, bodies, query strings, client IPs and raw paths are
never read into the payload, so tokens/phones/UPI ids cannot leak here.

Sampling is deterministic from the trace id (stable across isolates), so the
same request is either logged everywhere or nowhere. Errors (4xx/5xx) and
slow requests always log; ``OBS_LOG_SAMPLE_RATE=0`` only silences the
healthy fast path.

Runtime flags come from :func:`app.core.worker_env.env_get` because Worker
vars are not visible to pydantic-settings.
"""

from __future__ import annotations

import contextvars
import datetime as _dt
import hashlib
import json
import logging
import time
from dataclasses import dataclass

from app.core.worker_env import env_get

log = logging.getLogger("shodasha.request")
if not log.handlers:  # Workers has no root handler; INFO would be dropped.
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter("%(message)s"))
    log.addHandler(_handler)
log.setLevel(logging.INFO)
log.propagate = True

DEFAULT_SAMPLE_RATE = 0.05
DEFAULT_SLOW_MS = 750.0
_METHODS = frozenset({"GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"})


@dataclass
class RequestMetrics:
    """Counters accumulated while one request is in flight."""

    db_queries: int = 0
    db_roundtrips: int = 0
    db_rows_read: int = 0
    db_rows_written: int = 0

    def add(
        self,
        *,
        queries: int = 0,
        roundtrips: int = 0,
        rows_read: int = 0,
        rows_written: int = 0,
    ) -> None:
        self.db_queries += queries
        self.db_roundtrips += roundtrips
        self.db_rows_read += rows_read
        self.db_rows_written += rows_written


_current_metrics: contextvars.ContextVar[RequestMetrics | None] = contextvars.ContextVar(
    "shodasha_request_metrics", default=None
)


def start_metrics() -> tuple[RequestMetrics, object]:
    """Attach a fresh metrics object to the current request context."""
    metrics = RequestMetrics()
    return metrics, _current_metrics.set(metrics)


def reset_metrics(token: object) -> None:
    try:
        _current_metrics.reset(token)  # type: ignore[arg-type]
    except (ValueError, RuntimeError):
        # Token used in another context (defensive; never break a request).
        _current_metrics.set(None)


def current_metrics() -> RequestMetrics | None:
    return _current_metrics.get()


def record_db(
    *,
    queries: int = 0,
    roundtrips: int = 0,
    rows_read: int = 0,
    rows_written: int = 0,
) -> None:
    """Add DB work to the active request, or no-op outside a request."""
    metrics = _current_metrics.get()
    if metrics is not None:
        metrics.add(
            queries=queries,
            roundtrips=roundtrips,
            rows_read=rows_read,
            rows_written=rows_written,
        )


def _float_env(name: str, default: float) -> float:
    raw = env_get(name)
    if raw is None or raw == "":
        return default
    try:
        return float(raw)
    except (TypeError, ValueError):
        return default


def sample_rate() -> float:
    return min(1.0, max(0.0, _float_env("OBS_LOG_SAMPLE_RATE", DEFAULT_SAMPLE_RATE)))


def slow_ms() -> float:
    return max(0.0, _float_env("OBS_SLOW_MS", DEFAULT_SLOW_MS))


def sampled(trace_id: str, rate: float) -> bool:
    """Deterministic per-request sampling (stable across isolates)."""
    if rate <= 0:
        return False
    if rate >= 1:
        return True
    digest = hashlib.sha256(trace_id.encode("utf-8", "replace")).digest()
    return int.from_bytes(digest[:8], "big") / 2**64 < rate


def should_log(
    *,
    status_code: int,
    duration_ms: float,
    trace_id: str,
    rate: float | None = None,
    threshold_ms: float | None = None,
) -> bool:
    """Errors and slow requests always log; the rest is sampled."""
    if status_code >= 400:
        return True
    if duration_ms >= (slow_ms() if threshold_ms is None else threshold_ms):
        return True
    return sampled(trace_id, sample_rate() if rate is None else rate)


def _route_template(request) -> str:
    route = request.scope.get("route")
    path = getattr(route, "path", None)
    if isinstance(path, str) and path.startswith("/"):
        return path
    return "<unmatched>"


def _env_name() -> str:
    value = env_get("APP_ENV") or "local"
    # Keep the field small and log-safe even if the var is misconfigured.
    return "".join(ch for ch in value if ch.isalnum() or ch in "._-")[:32] or "local"


def log_request(
    request,
    *,
    status_code: int,
    duration_ms: float,
    metrics: RequestMetrics | None = None,
    trace_id: str | None = None,
) -> None:
    """Emit one JSON line. Never raises into the request path."""
    try:
        trace = trace_id or getattr(request.state, "trace_id", None) or "unknown"
        if not should_log(
            status_code=status_code,
            duration_ms=duration_ms,
            trace_id=trace,
        ):
            return
        metrics = metrics or RequestMetrics()
        method = request.method.upper()
        payload = {
            "event": "http_request",
            "ts": _dt.datetime.now(_dt.timezone.utc)
            .isoformat(timespec="milliseconds")
            .replace("+00:00", "Z"),
            "env": _env_name(),
            "trace_id": trace,
            "method": method if method in _METHODS else "OTHER",
            "route": _route_template(request),
            "status": int(status_code),
            "duration_ms": round(float(duration_ms), 1),
            "db_queries": int(metrics.db_queries),
            "db_roundtrips": int(metrics.db_roundtrips),
            "db_rows_read": int(metrics.db_rows_read),
            "db_rows_written": int(metrics.db_rows_written),
        }
        line = json.dumps(payload, separators=(",", ":"), ensure_ascii=True)
        if status_code >= 500:
            log.warning(line)
        else:
            log.info(line)
    except Exception:  # noqa: BLE001 - observability must never break a request
        try:
            log.debug("request log failed")
        except Exception:
            pass


def elapsed_ms(started: float) -> float:
    return (time.perf_counter() - started) * 1000.0
