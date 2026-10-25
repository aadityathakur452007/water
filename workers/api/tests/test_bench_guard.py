"""Guard tests for scripts/bench_phase0.py. No network, no server, no load."""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

import pytest

API_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = API_ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import bench_phase0  # noqa: E402


@pytest.mark.parametrize(
    "url",
    [
        "http://127.0.0.1:8787",
        "http://localhost:8787",
        "http://localhost:8787/",
        "http://[::1]:8787",
        "https://water-staging.adityathakur452007.workers.dev",
        "https://water-staging.adityathakur452007.workers.dev/",
    ],
)
def test_safe_targets(url: str) -> None:
    allowed, reason = bench_phase0.is_safe_target(url)
    assert allowed, reason


@pytest.mark.parametrize(
    "url",
    [
        "https://water.adityathakur452007.workers.dev",
        "https://shodasha.adityathakur452007.workers.dev",
        "https://adityathakur452007.workers.dev",
        "https://example.com",
        "ftp://localhost",
        "http://localhost:8787/v1/orders",
        "http://localhost:8787/?debug=1",
        "http://user:pass@localhost:8787",
    ],
)
def test_unsafe_targets(url: str) -> None:
    allowed, reason = bench_phase0.is_safe_target(url)
    assert not allowed, f"{url} unexpectedly allowed: {reason}"


def test_production_host_is_named_in_reason() -> None:
    allowed, reason = bench_phase0.is_safe_target(
        "https://water.adityathakur452007.workers.dev"
    )
    assert not allowed
    assert "production" in reason.lower()


def test_trailing_v1_is_normalized_to_root() -> None:
    assert (
        bench_phase0.normalize_base_url("http://localhost:8787/v1")
        == "http://localhost:8787"
    )
    assert (
        bench_phase0.normalize_base_url("http://localhost:8787/v1/")
        == "http://localhost:8787"
    )
    assert (
        bench_phase0.normalize_base_url(
            "https://water-staging.adityathakur452007.workers.dev/v1"
        )
        == "https://water-staging.adityathakur452007.workers.dev"
    )
    allowed, reason = bench_phase0.is_safe_target("http://localhost:8787/v1")
    assert allowed, reason


def test_profile_c_requires_allow_stress() -> None:
    allowed, reason = bench_phase0.validate_profile("c", False)
    assert not allowed
    assert "allow-stress" in reason

    allowed, reason = bench_phase0.validate_profile("c", True)
    assert allowed, reason


@pytest.mark.parametrize("profile", ["smoke", "a", "b"])
def test_non_stress_profiles_are_allowed(profile: str) -> None:
    allowed, reason = bench_phase0.validate_profile(profile, False)
    assert allowed, reason


def test_missing_token_file_fails_for_auth_profile(tmp_path: Path) -> None:
    missing = tmp_path / "phase0_tokens.json"
    with pytest.raises(bench_phase0.TokenFileError) as excinfo:
        bench_phase0.load_tokens(missing, require_users=True)

    message = str(excinfo.value).lower()
    assert "token file" in message
    assert "not found" in message
    assert "seed_phase0" in message


def test_missing_token_file_is_allowed_for_public_smoke(tmp_path: Path) -> None:
    missing = tmp_path / "phase0_tokens.json"
    tokens = bench_phase0.load_tokens(missing, require_users=False)
    assert tokens.users == ()
    assert tokens.vendors == ()
    assert tokens.admin is None


def test_empty_token_file_fails_for_auth_profile(tmp_path: Path) -> None:
    empty = tmp_path / "empty.json"
    empty.write_text("{}", encoding="utf-8")
    with pytest.raises(bench_phase0.TokenFileError) as excinfo:
        bench_phase0.load_tokens(empty, require_users=True)
    assert "no usable user tokens" in str(excinfo.value)


def test_token_file_parses_contract_and_hides_tokens(tmp_path: Path) -> None:
    path = tmp_path / "tokens.json"
    path.write_text(
        json.dumps(
            {
                "users": [
                    {"id": "u1", "token": "user-token", "order_id": "order-1"},
                    {"id": "u2", "token": "user-token-2"},
                ],
                "vendors": [
                    {
                        "id": "v1",
                        "token": "vendor-token",
                        "stop_id": "stop-1",
                        "route_id": "route-1",
                    }
                ],
                "admin": {"id": "admin-1", "token": "admin-token"},
            }
        ),
        encoding="utf-8",
    )

    tokens = bench_phase0.load_tokens(path, require_users=True)
    assert [user.id for user in tokens.users] == ["u1", "u2"]
    assert tokens.users[0].order_id == "order-1"
    assert tokens.users[1].order_id is None
    assert tokens.vendors[0].stop_id == "stop-1"
    assert tokens.vendors[0].route_id == "route-1"
    assert tokens.admin is not None
    assert tokens.admin.id == "admin-1"

    rendered = repr(tokens)
    assert "user-token" not in rendered
    assert "vendor-token" not in rendered
    assert "admin-token" not in rendered


def test_public_only_scenarios_skip_auth_and_vendor() -> None:
    scenarios, notes = bench_phase0.available_scenarios(bench_phase0.TokenData())
    assert [scenario.name for scenario in scenarios] == ["health", "catalog"]
    assert any("vendor_route skipped" in note for note in notes)
    assert any("me skipped" in note for note in notes)


def test_weighted_cycle_renormalizes_without_vendor() -> None:
    users = (
        bench_phase0.TokenEntry(id="u1", token="secret", order_id="order-1"),
    )
    scenarios, notes = bench_phase0.available_scenarios(
        bench_phase0.TokenData(users=users)
    )
    cycle = bench_phase0.weighted_cycle(scenarios)
    counts = Counter(scenario.name for scenario in cycle)

    assert dict(counts) == {
        "health": 5,
        "catalog": 15,
        "me": 15,
        "orders": 20,
        "order_detail": 20,
        "dues": 15,
    }
    assert len(cycle) == 90
    assert any("vendor_route skipped" in note for note in notes)
