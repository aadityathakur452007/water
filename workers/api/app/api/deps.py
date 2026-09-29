"""Shared FastAPI dependencies: settings, trace middleware, db session."""

import uuid
from collections.abc import Iterator
from functools import lru_cache

from fastapi import Request

from app.core.config import Settings
from app.core.errors import TRACE_HEADER


@lru_cache
def get_settings() -> Settings:
    return Settings()


async def trace_middleware(request: Request, call_next):
    trace_id = request.headers.get(TRACE_HEADER) or uuid.uuid4().hex[:16]
    request.state.trace_id = trace_id
    response = await call_next(request)
    response.headers[TRACE_HEADER] = trace_id
    return response


def get_db() -> Iterator:
    # B3 owns app.db. Lazy import so slice-1 health tests pass before db.py lands.
    from app.db import get_connection  # noqa: PLC0415

    yield get_connection()
