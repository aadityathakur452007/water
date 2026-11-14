"""045: each Worker mounts only its own surface (no admin/vendor bleed)."""

import pytest
from fastapi.testclient import TestClient

from app.factory import create_app

_OPS_PREFIXES = ("/v1/vendor", "/v1/rider")
_ADMIN_PREFIX = "/v1/admin"


def _paths(surface: str) -> set[str]:
    return set(create_app(surface).openapi()["paths"])


def test_customer_surface_is_isolated():
    paths = _paths("customer")
    assert "/v1/catalog" in paths
    assert "/v1/auth/user/login" in paths
    assert "/v1/auth/refresh" in paths
    assert "/v1/auth/me" in paths
    assert "/health" in paths
    assert not [p for p in paths if p.startswith(_OPS_PREFIXES)]
    assert not [p for p in paths if p.startswith(_ADMIN_PREFIX)]
    assert "/v1/auth/admin/login" not in paths
    assert "/v1/returns/{return_id}/pickup" not in paths
    assert not [p for p in paths if p.startswith("/v1/refunds")]


def test_ops_surface_is_isolated():
    paths = _paths("ops")
    assert "/v1/vendor/duty" in paths
    assert "/v1/rider/me" in paths
    assert "/v1/auth/vendor/login" in paths
    assert "/v1/auth/rider/login" in paths
    assert "/v1/returns/{return_id}/pickup" in paths
    assert "/v1/auth/refresh" in paths
    assert "/health" in paths
    assert "/v1/catalog" not in paths
    assert not [p for p in paths if p.startswith(_ADMIN_PREFIX)]


def test_admin_surface_is_isolated():
    paths = _paths("admin")
    assert "/v1/admin/orders" in paths
    assert "/v1/auth/admin/login" in paths
    assert "/v1/refunds/{refund_id}/claim" in paths
    assert "/v1/auth/refresh" in paths
    assert "/health" in paths
    assert "/v1/catalog" not in paths
    assert not [p for p in paths if p.startswith(_OPS_PREFIXES)]


def test_all_surface_is_the_union():
    all_paths = _paths("all")
    assert _paths("customer") <= all_paths
    assert _paths("ops") <= all_paths
    assert _paths("admin") <= all_paths


def test_unknown_surface_rejected():
    with pytest.raises(ValueError):
        create_app("nope")


@pytest.mark.parametrize(
    ("surface", "wrong_path"),
    [
        ("customer", "/v1/admin/orders"),
        ("customer", "/v1/vendor/duty"),
        ("ops", "/v1/catalog"),
        ("ops", "/v1/admin/orders"),
        ("admin", "/v1/catalog"),
        ("admin", "/v1/vendor/duty"),
    ],
)
def test_wrong_surface_returns_404(surface: str, wrong_path: str):
    client = TestClient(create_app(surface))
    assert client.get(wrong_path).status_code == 404
