"""Phase 8 §8.5: tiny Cache-Control + ETag helper for slow-moving GETs.

Only the five spec-listed reads use this (catalog/windows/serviceability +
admin config/zones); everything else stays no-store (admin correctness
first). Admin paths stay auth-gated — `public` lets the edge/CDN reuse the
bytes, but clients must still present the session (responses vary by auth;
the BFF keeps its own no-store except where it opts into these paths).
"""

from __future__ import annotations

import hashlib
import json

from fastapi import Request
from fastapi.responses import JSONResponse

CACHE_MAX_AGE_S = 300


def cached(body: dict, request: Request | None = None,
         max_age_s: int = CACHE_MAX_AGE_S) -> JSONResponse:
    """Wrap a JSON-serializable body with Cache-Control + ETag.

    If-None-Match matches → 304 empty (bandwidth saved on the 15-min cron
    pollers and repeat admin loads). No new deps, no middleware — call it
    at the return site so uncached routes provably stay uncached.
    """
    raw = json.dumps(body, sort_keys=True, default=str).encode()
    etag = f'"{hashlib.sha256(raw).hexdigest()[:32]}"'
    if request is not None and request.headers.get("if-none-match") == etag:
        return JSONResponse(status_code=304, content=None, headers={"ETag": etag})
    return JSONResponse(
        content=json.loads(raw.decode()),
        headers={"Cache-Control": f"public, max-age={max_age_s}", "ETag": etag},
    )
