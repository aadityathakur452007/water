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


def test_write_profile_requires_allow_writes() -> None:
    allowed, reason = bench_phase0.validate_profile("write", False, False)
    assert not allowed
    assert "allow-writes" in reason

    allowed, reason = bench_phase0.validate_profile("write", False, True)
    assert allowed, reason


def test_phase3_c_requires_allow_stress() -> None:
    allowed, reason = bench_phase0.validate_profile("phase3-c", False, False)
    assert not allowed
    assert "allow-stress" in reason

    allowed, reason = bench_phase0.validate_profile("phase3-c", True, False)
    assert allowed, reason


@pytest.mark.parametrize("profile", ["phase3-a", "phase3-b", "phase3-soak", "login"])
def test_phase3_profiles_are_allowed(profile: str) -> None:
    allowed, reason = bench_phase0.validate_profile(profile, False, False)
    assert allowed, reason


@pytest.mark.parametrize(
    "path",
    [
        "/v1/quotes",
        "/v1/orders",
        "/v1/orders/order-1/cancel",
        "/v1/orders/order-1/reschedule",
    ],
)
def test_write_path_whitelist(path: str) -> None:
    allowed, reason = bench_phase0.is_safe_write_path(path)
    assert allowed, reason


@pytest.mark.parametrize(
    "path",
    [
        "/v1/payments/upi-intent",
        "/v1/webhooks/upi",
        "/v1/orders/order-1/delivery-code/reissue",
        "/v1/addresses",
        "/v1/admin/metrics",
    ],
)
def test_write_path_refuses_non_probe_paths(path: str) -> None:
    allowed, reason = bench_phase0.is_safe_write_path(path)
    assert not allowed, f"{path} unexpectedly allowed: {reason}"


def test_write_target_is_loopback_or_staging_only() -> None:
    allowed, reason = bench_phase0.validate_write_target("http://127.0.0.1:8787")
    assert allowed, reason
    allowed, reason = bench_phase0.validate_write_target(
        "https://water-staging.adityathakur452007.workers.dev"
    )
    assert allowed, reason
    allowed, reason = bench_phase0.validate_write_target(
        "https://water.adityathakur452007.workers.dev"
    )
    assert not allowed
    assert "production" in reason.lower()


def test_credentials_parse_and_hide_secrets(tmp_path: Path) -> None:
    path = tmp_path / "credentials.json"
    path.write_text(
        json.dumps([{"phone": "+919999999999", "password": "not-a-real-password"}]),
        encoding="utf-8",
    )

    credentials = bench_phase0.load_credentials(path)
    assert len(credentials) == 1
    assert credentials[0].phone == "+919999999999"

    rendered = repr(credentials)
    assert "9999999999" not in rendered
    assert "not-a-real-password" not in rendered


def test_missing_credentials_fail_without_echoing_path_contents(tmp_path: Path) -> None:
    missing = tmp_path / "credentials.json"
    with pytest.raises(bench_phase0.CredentialsError) as excinfo:
        bench_phase0.load_credentials(missing)
    assert "not found" in str(excinfo.value).lower()


def test_empty_credentials_fail(tmp_path: Path) -> None:
    path = tmp_path / "credentials.json"
    path.write_text("[]", encoding="utf-8")
    with pytest.raises(bench_phase0.CredentialsError) as excinfo:
        bench_phase0.load_credentials(path)
    assert "no credentials" in str(excinfo.value)


def test_phase3_mix_matches_spec() -> None:
    total = sum(scenario.weight for scenario in bench_phase0.PHASE3_SCENARIOS)
    assert total == 100

    by_auth = Counter()
    for scenario in bench_phase0.PHASE3_SCENARIOS:
        by_auth[scenario.auth] += scenario.weight
    assert dict(by_auth) == {"none": 15, "user": 75, "vendor": 5, "admin": 5}

    session = next(
        scenario for scenario in bench_phase0.PHASE3_SCENARIOS if scenario.name == "me"
    )
    assert session.weight == 5
    assert session.auth == "user"
    assert by_auth["user"] - session.weight == 70


def test_phase3_admin_scenarios_need_admin_token() -> None:
    users = (
        bench_phase0.TokenEntry(id="u1", token="secret", order_id="order-1"),
    )
    scenarios, notes = bench_phase0.available_scenarios(
        bench_phase0.TokenData(users=users), bench_phase0.PHASE3_SCENARIOS
    )
    names = {scenario.name for scenario in scenarios}
    assert "admin_metrics" not in names
    assert "admin_overview" not in names
    assert any("admin_metrics skipped" in note for note in notes)

    tokens = bench_phase0.TokenData(
        users=users, admin=bench_phase0.TokenEntry(id="admin-1", token="secret")
    )
    scenarios, _ = bench_phase0.available_scenarios(
        tokens, bench_phase0.PHASE3_SCENARIOS
    )
    assert "admin_metrics" in {scenario.name for scenario in scenarios}


def test_build_timeline_scales_and_marks_counted_phases() -> None:
    slots = bench_phase0.build_timeline(bench_phase0.PHASE3_TIMELINE, 2.78, 0.02)
    assert slots
    assert slots[-1].at < 36.0
    assert any(slot.phase == "warmup" for slot in slots)
    assert any(slot.phase == "rampdown" for slot in slots)
    assert all(
        slot.counted == (slot.phase in {"steady", "burst", "recovery"})
        for slot in slots
    )


def test_build_timeline_rejects_invalid_inputs() -> None:
    with pytest.raises(ValueError):
        bench_phase0.build_timeline(bench_phase0.PHASE3_TIMELINE, 2.78, 0)
    with pytest.raises(ValueError):
        bench_phase0.build_timeline(bench_phase0.PHASE3_TIMELINE, 0, 1.0)


def test_build_timeline_phase_counts_at_full_scale() -> None:
    slots = bench_phase0.build_timeline(bench_phase0.PHASE3_TIMELINE, 2.78, 1.0)
    phases = Counter(slot.phase for slot in slots)
    assert phases["warmup"] == 83
    assert phases["steady"] == 1668
    assert phases["burst"] == 2085
    assert phases["recovery"] == 1668


def test_results_separate_expected_4xx_from_failures() -> None:
    stats = bench_phase0.Stats(["cancel_order"])
    stats.record("cancel_order", 409, 5.0, False, expected=True)
    outcome = bench_phase0.RunOutcome(
        stats=stats,
        elapsed_s=1.0,
        schedule_resets=0,
        aborted=False,
        abort_reason=None,
        failure_reason=None,
    )

    results = bench_phase0._build_results(
        profile="write",
        base_url="http://127.0.0.1:8787",
        label="test",
        outcome=outcome,
        started_at="2026-10-26T00:00:00Z",
        finished_at="2026-10-26T00:00:01Z",
        target_duration_s=1.0,
        rps=1.0,
        concurrency=1,
        warmup=0.0,
        max_5xx_pct=2.0,
        max_p99_ms=5000.0,
        notes=[],
    )

    assert results["expected_error_count"] == 1
    assert results["unexpected_error_count"] == 0
    assert results["result"] == "pass"
    assert results["scope"] == "all"
    assert results["schema_version"] == 2
