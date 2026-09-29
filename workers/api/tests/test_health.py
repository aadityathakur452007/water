"""Slice-1 tests: /health 200 + error envelope shape (contract §0)."""

import sys
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))


def _ensure_router_module(name: str) -> None:
    """B2 owns app.api.v1.catalog / app.api.v1.quotes.

    Stub an empty router in-process only while those modules don't exist yet,
    so the slice-1 foundation is testable standalone. Real modules take
    precedence once B2 merges (stub applies on ImportError only; no files).
    """
    try:
        __import__(name)
    except ImportError:
        import types

        from fastapi import APIRouter

        mod = types.ModuleType(name)
        mod.router = APIRouter()
        sys.modules[name] = mod


_ensure_router_module("app.api.v1.catalog")
_ensure_router_module("app.api.v1.quotes")

from fastapi.testclient import TestClient  # noqa: E402

from app.main import create_app  # noqa: E402

client = TestClient(create_app())


def test_health_ok():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
    assert r.headers["X-Trace-Id"]


def test_404_envelope_shape():
    r = client.get("/does-not-exist")
    assert r.status_code == 404
    err = r.json()["error"]
    assert err["code"] == "NOT_FOUND"
    assert isinstance(err["message"], str) and err["message"]
    assert isinstance(err["details"], dict)
    assert isinstance(err["trace_id"], str) and err["trace_id"]
