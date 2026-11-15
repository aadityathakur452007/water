"""Pytest bootstrap: expose src/ (the app package) on sys.path.

Layout is src-first for Cloudflare (entry.py lives beside the app package).
Local runs use the same rule: prefix commands with PYTHONPATH=src, e.g.
PYTHONPATH=src python -m uvicorn app.main:app / PYTHONPATH=src python -m app.migrate
"""

import sys
from pathlib import Path

import pytest

SRC = Path(__file__).resolve().parent / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))


@pytest.fixture(autouse=True)
def _reset_schema_caches(monkeypatch):
    """Schema probes and TTL memos are per-isolate caches; each test builds its own DB."""
    from app.api.auth_deps import reset_session_cache
    from app.core import memo
    from app.db_schema import reset_schema_cache
    from app.services.subscription_service import reset_billing_mode_cache

    # Tests keep the pre-045 zero-staleness behavior by default; the session
    # cache test opts back in with its own TTL.
    monkeypatch.setenv("AUTH_SESSION_CACHE_TTL_S", "0")
    reset_schema_cache()
    reset_billing_mode_cache()
    reset_session_cache()
    memo.clear()
    yield
