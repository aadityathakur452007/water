"""Tiny per-isolate TTL memo for slow-moving reads (045 worker split).

Workers have no shared memory across isolates, so this is deliberately a
process-local dict: each isolate pays at most one upstream lookup per key per
TTL window. Values must be plain JSON-ready objects (never ORM rows or
request-scoped connection handles). Tests clear it between cases.
"""

from __future__ import annotations

import time

_MAX_ENTRIES = 512
_store: dict[str, tuple[float, object]] = {}


def get(key: str) -> object | None:
    hit = _store.get(key)
    if hit is None:
        return None
    expires_at, value = hit
    if time.monotonic() >= expires_at:
        _store.pop(key, None)
        return None
    return value


def set(key: str, value: object, ttl_s: float) -> None:  # noqa: A001 - module API
    if ttl_s <= 0:
        return
    if len(_store) >= _MAX_ENTRIES:
        _store.clear()
    _store[key] = (time.monotonic() + ttl_s, value)


def clear() -> None:
    """Test hook / manual reset."""
    _store.clear()
