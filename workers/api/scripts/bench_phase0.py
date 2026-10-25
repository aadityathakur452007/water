"""Phase 0 constant-arrival benchmark harness (Python 3.13, stdlib only).

Read-only: every scenario is a GET. The harness refuses production and any
target that is not loopback or does not contain ``staging``. Results are
written as JSON + Markdown; bearer tokens are never printed or serialized.
"""

from __future__ import annotations

import argparse
import http.client
import json
import math
import sys
import threading
import time
import uuid
from collections import Counter
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlsplit, urlunsplit

API_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_TOKENS = API_ROOT / "data" / "phase0_tokens.json"
DEFAULT_RESULTS_DIR = REPO_ROOT / "Feature_docs" / "performance" / "results"

USER_AGENT = "shodasha-phase0-bench/1.0"
PRODUCTION_HOST_MARKER = "adityathakur452007.workers.dev"
LOOPBACK_HOSTS = frozenset({"localhost", "127.0.0.1", "::1"})
MAX_BODY_BYTES = 1_048_576
HTTP_TIMEOUT_S = 10.0
MIN_ABORT_REQUESTS = 20
ABORT_CHECK_INTERVAL_S = 0.5


@dataclass(frozen=True)
class ProfileDefaults:
    duration: float
    rps: float
    concurrency: int
    warmup: float


PROFILE_DEFAULTS: dict[str, ProfileDefaults] = {
    "smoke": ProfileDefaults(duration=0.0, rps=1.0, concurrency=1, warmup=0.0),
    "a": ProfileDefaults(duration=600.0, rps=2.78, concurrency=20, warmup=5.0),
    "b": ProfileDefaults(duration=600.0, rps=5.56, concurrency=40, warmup=5.0),
    "c": ProfileDefaults(duration=300.0, rps=55.6, concurrency=200, warmup=5.0),
}


# ---------------------------------------------------------------------------
# Guards (pure; safe to import and unit-test without a network)
# ---------------------------------------------------------------------------


def normalize_base_url(base_url: str) -> str:
    """Return ``scheme://host[:port]`` with a trailing ``/v1`` removed."""
    parts = urlsplit(base_url.strip())
    path = parts.path
    if path.rstrip("/") == "/v1" or path == "/":
        path = ""
    return urlunsplit((parts.scheme.lower(), parts.netloc, path, parts.query, parts.fragment))


def is_safe_target(base_url: str) -> tuple[bool, str]:
    """Return ``(allowed, reason)`` for a benchmark target. No network I/O."""
    if not isinstance(base_url, str) or not base_url.strip():
        return False, "base URL is empty"
    try:
        parts = urlsplit(base_url.strip())
        host = parts.hostname
        _ = parts.port
        username = parts.username
        password = parts.password
    except ValueError as exc:
        return False, f"invalid URL: {exc}"

    if parts.scheme.lower() not in {"http", "https"}:
        return False, "scheme must be http or https"
    if not host:
        return False, "URL has no host"
    if username or password:
        return False, "credentials in the base URL are not allowed"

    host_l = host.lower()
    if PRODUCTION_HOST_MARKER in host_l and "staging" not in host_l:
        return False, "refusing the production Worker host"
    if parts.query or parts.fragment:
        return False, "base URL must not include a query or fragment"

    normalized_path = urlsplit(normalize_base_url(base_url)).path
    if normalized_path not in ("", "/"):
        return False, "base URL path must be empty or / (only a trailing /v1 is normalized)"
    if host_l in LOOPBACK_HOSTS:
        return True, "loopback target"
    if "staging" in host_l:
        return True, "staging target"
    return False, "host must be loopback or contain 'staging'"


def validate_profile(profile: str, allow_stress: bool) -> tuple[bool, str]:
    """Return ``(allowed, reason)``; profile c is stress-only."""
    if profile not in PROFILE_DEFAULTS:
        return False, f"unknown profile {profile!r}; choose from {', '.join(PROFILE_DEFAULTS)}"
    if profile == "c" and not allow_stress:
        return False, "profile c is a stress profile; pass --allow-stress to run it"
    return True, f"profile {profile} allowed"


# ---------------------------------------------------------------------------
# Token file (read-only; tokens are hidden from repr and error messages)
# ---------------------------------------------------------------------------


class TokenFileError(RuntimeError):
    """Token file missing, unreadable, or missing required entries."""


@dataclass(frozen=True)
class TokenEntry:
    id: str
    token: str = field(repr=False)
    order_id: str | None = None
    stop_id: str | None = None
    route_id: str | None = None


@dataclass(frozen=True)
class TokenData:
    users: tuple[TokenEntry, ...] = ()
    vendors: tuple[TokenEntry, ...] = ()
    admin: TokenEntry | None = None


def _optional_str(item: dict[Any, Any], key: str, where: str) -> str | None:
    value = item.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        raise TokenFileError(f"{where}.{key} must be a string or null")
    return value


def _parse_entry(item: object, where: str, optional: tuple[str, ...]) -> TokenEntry:
    if not isinstance(item, dict):
        raise TokenFileError(f"{where} must be an object")
    ident = item.get("id")
    token = item.get("token")
    if not isinstance(ident, str) or not ident:
        raise TokenFileError(f"{where}.id must be a non-empty string")
    if not isinstance(token, str) or not token:
        raise TokenFileError(f"{where}.token must be a non-empty string")
    extras = {name: _optional_str(item, name, where) for name in optional}
    return TokenEntry(id=ident, token=token, **extras)


def _parse_entries(
    raw: object, key: str, path: Path, optional: tuple[str, ...]
) -> tuple[TokenEntry, ...]:
    if raw is None:
        return ()
    if not isinstance(raw, list):
        raise TokenFileError(f"{path}: '{key}' must be a list")
    return tuple(
        _parse_entry(item, f"{path}: {key}[{index}]", optional)
        for index, item in enumerate(raw)
    )


def _parse_admin(raw: object, path: Path) -> TokenEntry | None:
    if raw is None:
        return None
    return _parse_entry(raw, f"{path}: admin", ())


def load_tokens(path: str | Path, *, require_users: bool) -> TokenData:
    """Load the seed token file. Errors never include token values."""
    token_path = Path(path)
    if not token_path.is_file():
        if require_users:
            raise TokenFileError(
                f"token file not found: {token_path}. Run scripts/seed_phase0.py first, "
                "or use --profile smoke for a public-only check."
            )
        return TokenData()

    try:
        raw = json.loads(token_path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise TokenFileError(f"cannot read token file {token_path}: {exc}") from exc
    if not isinstance(raw, dict):
        raise TokenFileError(f"{token_path}: top-level JSON must be an object")

    users = _parse_entries(raw.get("users"), "users", token_path, ("order_id",))
    vendors = _parse_entries(raw.get("vendors"), "vendors", token_path, ("stop_id", "route_id"))
    admin = _parse_admin(raw.get("admin"), token_path)

    if require_users and not users:
        raise TokenFileError(
            f"{token_path}: no usable user tokens; profiles a/b/c need at least one "
            "seeded user (or use --profile smoke)."
        )
    return TokenData(users=users, vendors=vendors, admin=admin)


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Scenario:
    name: str
    path: str
    auth: str
    weight: int


SCENARIOS: tuple[Scenario, ...] = (
    Scenario("health", "/health", "none", 5),
    Scenario("catalog", "/v1/catalog", "none", 15),
    Scenario("me", "/v1/auth/me", "user", 15),
    Scenario("orders", "/v1/orders?limit=20", "user", 20),
    Scenario("order_detail", "/v1/orders", "user", 20),
    Scenario("dues", "/v1/billing/dues", "user", 15),
    Scenario("vendor_route", "/v1/vendor/routes/today", "vendor", 10),
)


def available_scenarios(tokens: TokenData) -> tuple[list[Scenario], list[str]]:
    """Return runnable scenarios in canonical order plus human-readable skip notes."""
    has_users = bool(tokens.users)
    has_orders = any(user.order_id for user in tokens.users)
    has_vendors = bool(tokens.vendors)
    available: list[Scenario] = []
    notes: list[str] = []

    for scenario in SCENARIOS:
        if scenario.auth == "none":
            available.append(scenario)
        elif scenario.name == "order_detail":
            if has_orders:
                available.append(scenario)
            else:
                notes.append(
                    "order_detail skipped: no user token has order_id"
                    if has_users
                    else "order_detail skipped: no user tokens"
                )
        elif scenario.auth == "vendor":
            if has_vendors:
                available.append(scenario)
            else:
                notes.append("vendor_route skipped: no vendor tokens")
        else:
            if has_users:
                available.append(scenario)
            else:
                notes.append(f"{scenario.name} skipped: no user tokens")

    return available, notes


def weighted_cycle(scenarios: Sequence[Scenario]) -> list[Scenario]:
    """Return a deterministic smooth weighted cycle with exact integer weights."""
    if not scenarios:
        raise ValueError("no scenarios available")
    weights = {scenario.name: scenario.weight for scenario in scenarios}
    total = sum(weights.values())
    if total <= 0:
        raise ValueError("scenario weights must sum to a positive value")
    by_name = {scenario.name: scenario for scenario in scenarios}
    current = {name: 0 for name in weights}
    cycle: list[Scenario] = []

    for _ in range(total):
        for name, weight in weights.items():
            current[name] += weight
        name = max(weights, key=lambda item: current[item])
        current[name] -= total
        cycle.append(by_name[name])

    return cycle


class ScenarioPicker:
    """Thread-safe deterministic scenario and token rotation."""

    def __init__(self, scenarios: Sequence[Scenario], tokens: TokenData) -> None:
        self._cycle = weighted_cycle(scenarios)
        self._users = tokens.users
        self._vendors = tokens.vendors
        self._orders = tuple(user for user in tokens.users if user.order_id)
        self._lock = threading.Lock()
        self._index = 0
        self._user_index = 0
        self._detail_index = 0
        self._vendor_index = 0

    def next(self) -> tuple[Scenario, TokenEntry | None]:
        with self._lock:
            scenario = self._cycle[self._index % len(self._cycle)]
            self._index += 1
            if scenario.name == "order_detail":
                token = self._orders[self._detail_index % len(self._orders)]
                self._detail_index += 1
            elif scenario.auth == "user":
                token = self._users[self._user_index % len(self._users)]
                self._user_index += 1
            elif scenario.auth == "vendor":
                token = self._vendors[self._vendor_index % len(self._vendors)]
                self._vendor_index += 1
            else:
                token = None
        return scenario, token


# ---------------------------------------------------------------------------
# HTTP: thread-local keep-alive connections, one retry on transport failure
# ---------------------------------------------------------------------------


class HttpClient:
    """GET-only client. Thread-local connection, 10s timeout, one retry."""

    def __init__(self, base_url: str, timeout: float = HTTP_TIMEOUT_S) -> None:
        parts = urlsplit(base_url)
        self._scheme = parts.scheme.lower()
        self._host = parts.hostname or ""
        self._port = parts.port
        self._timeout = timeout
        self._local = threading.local()

    def _new_connection(self) -> http.client.HTTPConnection:
        cls = (
            http.client.HTTPSConnection
            if self._scheme == "https"
            else http.client.HTTPConnection
        )
        return cls(self._host, self._port, timeout=self._timeout)

    def _connection(self) -> http.client.HTTPConnection:
        conn = getattr(self._local, "conn", None)
        if conn is None:
            conn = self._new_connection()
            self._local.conn = conn
        return conn

    def _close(self) -> None:
        conn = getattr(self._local, "conn", None)
        if conn is not None:
            try:
                conn.close()
            except OSError:
                pass
            self._local.conn = None

    def _drain(self, response: http.client.HTTPResponse) -> None:
        total = 0
        while True:
            chunk = response.read(65_536)
            if not chunk:
                return
            total += len(chunk)
            if total > MAX_BODY_BYTES:
                self._close()
                return

    def get(self, path: str, token: str | None) -> tuple[int, float, bool]:
        """Send one GET. Returns ``(status, latency_ms, retried)``; status 0 on failure."""
        started = time.perf_counter()
        retried = False

        for attempt in range(2):
            headers = {
                "User-Agent": USER_AGENT,
                "Accept": "application/json",
                "Connection": "keep-alive",
                "X-Trace-Id": uuid.uuid4().hex[:16],
            }
            if token:
                headers["Authorization"] = f"Bearer {token}"
            try:
                conn = self._connection()
                conn.request("GET", path, headers=headers)
                response = conn.getresponse()
                status = response.status
                self._drain(response)
                return status, (time.perf_counter() - started) * 1000.0, retried
            except (OSError, http.client.HTTPException):
                self._close()
                if attempt == 0:
                    retried = True
                    continue
                return 0, (time.perf_counter() - started) * 1000.0, retried

        return 0, (time.perf_counter() - started) * 1000.0, retried


# ---------------------------------------------------------------------------
# Results, scheduling, and abort monitor
# ---------------------------------------------------------------------------


@dataclass
class RouteStats:
    count: int = 0
    status_counts: Counter[int] = field(default_factory=Counter)
    latencies_ms: list[float] = field(default_factory=list)
    error_count: int = 0
    retry_count: int = 0


def _pct(part: int, total: int) -> float:
    return round(part / total * 100.0, 3) if total else 0.0


def _percentile(sorted_values: Sequence[float], percentile: float) -> float | None:
    if not sorted_values:
        return None
    index = max(0, math.ceil(percentile / 100.0 * len(sorted_values)) - 1)
    return round(sorted_values[index], 2)


def _latency_summary(sorted_values: Sequence[float]) -> dict[str, float | None]:
    return {
        "p50_ms": _percentile(sorted_values, 50),
        "p90_ms": _percentile(sorted_values, 90),
        "p95_ms": _percentile(sorted_values, 95),
        "p99_ms": _percentile(sorted_values, 99),
        "max_ms": round(sorted_values[-1], 2) if sorted_values else None,
    }


class Stats:
    """Thread-safe per-route counters and latency samples."""

    def __init__(self, route_names: Sequence[str]) -> None:
        self._lock = threading.Lock()
        self._routes = {name: RouteStats() for name in route_names}

    def record(self, route: str, status: int, latency_ms: float, retried: bool) -> None:
        with self._lock:
            route_stats = self._routes[route]
            route_stats.count += 1
            route_stats.status_counts[status] += 1
            route_stats.latencies_ms.append(latency_ms)
            if status < 200 or status >= 300:
                route_stats.error_count += 1
            if retried:
                route_stats.retry_count += 1

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            raw = {
                name: (
                    route.count,
                    dict(route.status_counts),
                    list(route.latencies_ms),
                    route.error_count,
                    route.retry_count,
                )
                for name, route in self._routes.items()
            }

        routes: dict[str, dict[str, Any]] = {}
        all_latencies: list[float] = []
        total_count = 0
        total_errors = 0
        total_retries = 0
        total_status: Counter[int] = Counter()

        for name, (count, statuses, latencies, errors, retries) in raw.items():
            latencies.sort()
            all_latencies.extend(latencies)
            total_count += count
            total_errors += errors
            total_retries += retries
            total_status.update(statuses)
            routes[name] = {
                "count": count,
                "status_counts": {str(code): value for code, value in sorted(statuses.items())},
                "5xx_count": sum(value for code, value in statuses.items() if code >= 500),
                "error_count": errors,
                "retry_count": retries,
                **_latency_summary(latencies),
            }

        all_latencies.sort()
        five_xx = sum(value for code, value in total_status.items() if code >= 500)
        return {
            "requests": total_count,
            "routes": routes,
            "status_counts": {str(code): value for code, value in sorted(total_status.items())},
            "error_count": total_errors,
            "error_rate_pct": _pct(total_errors, total_count),
            "5xx_count": five_xx,
            "5xx_pct": _pct(five_xx, total_count),
            "network_error_count": total_status.get(0, 0),
            "retry_count": total_retries,
            "latency": _latency_summary(all_latencies),
        }


class AbortFlag:
    """First abort reason wins; safe to read from any thread."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._reason: str | None = None

    def set(self, reason: str) -> None:
        with self._lock:
            if self._reason is None:
                self._reason = reason

    @property
    def reason(self) -> str | None:
        with self._lock:
            return self._reason


class ArrivalScheduler:
    """Shared constant-arrival schedule; resets if it falls more than 2s behind."""

    def __init__(self, rps: float) -> None:
        self._interval = 1.0 / rps
        self._lock = threading.Lock()
        self._next_slot = time.monotonic()
        self._resets = 0

    def wait_for_slot(self, stop_event: threading.Event) -> float | None:
        with self._lock:
            now = time.monotonic()
            if self._next_slot < now - 2.0:
                self._next_slot = now
                self._resets += 1
            slot = max(now, self._next_slot)
            self._next_slot = slot + self._interval

        delay = slot - time.monotonic()
        if delay > 0 and stop_event.wait(delay):
            return None
        return slot

    @property
    def resets(self) -> int:
        with self._lock:
            return self._resets


class AbortMonitor(threading.Thread):
    """Stops the run when 5xx or overall p99 exceeds the configured limits."""

    def __init__(
        self,
        stats: Stats,
        stop_event: threading.Event,
        abort: AbortFlag,
        max_5xx_pct: float,
        max_p99_ms: float,
    ) -> None:
        super().__init__(name="phase0-abort-monitor", daemon=True)
        self._stats = stats
        self._stop_event = stop_event
        self._abort = abort
        self._max_5xx_pct = max_5xx_pct
        self._max_p99_ms = max_p99_ms

    def run(self) -> None:
        while not self._stop_event.wait(ABORT_CHECK_INTERVAL_S):
            try:
                snapshot = self._stats.snapshot()
            except Exception as exc:  # pragma: no cover - defensive
                self._abort.set(f"monitor error: {type(exc).__name__}")
                self._stop_event.set()
                return

            if snapshot["requests"] < MIN_ABORT_REQUESTS:
                continue

            reasons: list[str] = []
            if snapshot["5xx_pct"] > self._max_5xx_pct:
                reasons.append(
                    f"5xx rate {snapshot['5xx_pct']:.2f}% > {self._max_5xx_pct:.2f}%"
                )
            p99 = snapshot["latency"]["p99_ms"]
            if p99 is not None and p99 > self._max_p99_ms:
                reasons.append(f"p99 {p99:.0f} ms > {self._max_p99_ms:.0f} ms")
            if reasons:
                self._abort.set("; ".join(reasons))
                self._stop_event.set()
                return


@dataclass
class RunOutcome:
    stats: Stats
    elapsed_s: float
    schedule_resets: int
    aborted: bool
    abort_reason: str | None
    failure_reason: str | None


# ---------------------------------------------------------------------------
# Runners
# ---------------------------------------------------------------------------


def _smoke_token(scenario: Scenario, tokens: TokenData) -> TokenEntry | None:
    if scenario.auth == "none":
        return None
    if scenario.name == "order_detail":
        return next((user for user in tokens.users if user.order_id), None)
    if scenario.auth == "vendor":
        return tokens.vendors[0] if tokens.vendors else None
    return tokens.users[0] if tokens.users else None


def _request_path(scenario: Scenario, token: TokenEntry | None) -> str:
    if scenario.name == "order_detail":
        if token is None or not token.order_id:
            raise RuntimeError("order_detail requires a token with order_id")
        return f"/v1/orders/{quote(token.order_id, safe='')}"
    return scenario.path


def _run_smoke(base_url: str, tokens: TokenData, scenarios: Sequence[Scenario]) -> RunOutcome:
    """One sequential GET per available scenario, in canonical order."""
    stats = Stats([scenario.name for scenario in scenarios])
    client = HttpClient(base_url)
    started = time.monotonic()

    for scenario in scenarios:
        token = _smoke_token(scenario, tokens)
        if scenario.auth != "none" and token is None:
            raise RuntimeError(f"no token for {scenario.name}")
        status, latency_ms, retried = client.get(
            _request_path(scenario, token),
            token.token if token else None,
        )
        stats.record(scenario.name, status, latency_ms, retried)

    elapsed = time.monotonic() - started
    snapshot = stats.snapshot()
    failure = None
    if snapshot["error_count"]:
        failure = (
            f"smoke: {snapshot['error_count']} of {snapshot['requests']} requests failed "
            "(non-2xx or transport error)"
        )
    return RunOutcome(stats, elapsed, 0, False, None, failure)


def _run_load(
    base_url: str,
    tokens: TokenData,
    scenarios: Sequence[Scenario],
    *,
    rps: float,
    concurrency: int,
    duration: float,
    warmup: float,
    max_5xx_pct: float,
    max_p99_ms: float,
) -> RunOutcome:
    """Run constant-arrival workers; warmup requests are sent but not recorded."""
    stats = Stats([scenario.name for scenario in scenarios])
    picker = ScenarioPicker(scenarios, tokens)
    scheduler = ArrivalScheduler(rps)
    client = HttpClient(base_url)
    stop_event = threading.Event()
    abort = AbortFlag()
    measure_start = time.monotonic() + warmup
    measure_end = measure_start + duration

    def worker() -> None:
        try:
            while not stop_event.is_set():
                slot = scheduler.wait_for_slot(stop_event)
                if slot is None:
                    return
                if time.monotonic() >= measure_end or abort.reason is not None:
                    return

                scenario, token = picker.next()
                status, latency_ms, retried = client.get(
                    _request_path(scenario, token),
                    token.token if token else None,
                )
                if slot >= measure_start:
                    stats.record(scenario.name, status, latency_ms, retried)
        except Exception as exc:  # pragma: no cover - defensive
            abort.set(f"worker error: {type(exc).__name__}")
            stop_event.set()

    threads = [
        threading.Thread(target=worker, name=f"phase0-worker-{index}", daemon=True)
        for index in range(concurrency)
    ]
    for thread in threads:
        thread.start()

    monitor = AbortMonitor(stats, stop_event, abort, max_5xx_pct, max_p99_ms)
    monitor.start()

    while True:
        remaining = measure_end - time.monotonic()
        if remaining <= 0:
            break
        if stop_event.wait(min(remaining, 0.25)):
            break

    stop_event.set()
    for thread in threads:
        thread.join(timeout=15.0)
    monitor.join(timeout=2.0)

    elapsed = max(0.0, time.monotonic() - measure_start)
    alive = any(thread.is_alive() for thread in threads)
    failure = abort.reason
    if alive and failure is None:
        failure = "worker threads did not finish within 15s"

    snapshot = stats.snapshot()
    if failure is None:
        if snapshot["requests"] == 0:
            failure = "no requests were sent during the measurement window"
        elif snapshot["error_count"] == snapshot["requests"]:
            failure = "all requests failed (non-2xx or transport error)"

    return RunOutcome(
        stats,
        elapsed,
        scheduler.resets,
        abort.reason is not None,
        abort.reason,
        failure,
    )


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------


def _iso_utc(moment: datetime) -> str:
    return moment.isoformat(timespec="seconds").replace("+00:00", "Z")


def _fmt_ms(value: float | None) -> str:
    return "-" if value is None else f"{value:.1f}"


def _build_results(
    *,
    profile: str,
    base_url: str,
    label: str | None,
    outcome: RunOutcome,
    started_at: str,
    finished_at: str,
    target_duration_s: float,
    rps: float,
    concurrency: int,
    warmup: float,
    max_5xx_pct: float,
    max_p99_ms: float,
    notes: Sequence[str],
) -> dict[str, Any]:
    snapshot = outcome.stats.snapshot()
    latency = snapshot["latency"]
    return {
        "schema_version": 1,
        "label": label,
        "profile": profile,
        "base_url": base_url,
        "started_at": started_at,
        "finished_at": finished_at,
        "duration_s": round(outcome.elapsed_s, 3),
        "target_duration_s": target_duration_s,
        "warmup_s": round(warmup, 3),
        "target_rps": rps,
        "concurrency": concurrency,
        "requests": snapshot["requests"],
        "achieved_rps": (
            round(snapshot["requests"] / outcome.elapsed_s, 3)
            if outcome.elapsed_s > 0
            else 0.0
        ),
        "status_counts": snapshot["status_counts"],
        "error_count": snapshot["error_count"],
        "error_rate_pct": snapshot["error_rate_pct"],
        "5xx_count": snapshot["5xx_count"],
        "5xx_pct": snapshot["5xx_pct"],
        "network_error_count": snapshot["network_error_count"],
        "retry_count": snapshot["retry_count"],
        "p50_ms": latency["p50_ms"],
        "p90_ms": latency["p90_ms"],
        "p95_ms": latency["p95_ms"],
        "p99_ms": latency["p99_ms"],
        "max_ms": latency["max_ms"],
        "schedule_resets": outcome.schedule_resets,
        "result": "fail" if outcome.failure_reason else "pass",
        "result_reason": outcome.failure_reason,
        "aborted": outcome.aborted,
        "abort_reason": outcome.abort_reason,
        "thresholds": {"max_5xx_pct": max_5xx_pct, "max_p99_ms": max_p99_ms},
        "routes": snapshot["routes"],
        "notes": list(notes),
    }


def render_markdown(results: dict[str, Any]) -> str:
    lines = [
        f"# Phase 0 benchmark - profile {results['profile']}",
        "",
    ]
    if results["label"]:
        lines.append(f"- **Label:** {results['label']}")
    lines.extend(
        [
            f"- **Result:** {results['result']}",
            f"- **Started (UTC):** {results['started_at']}",
            f"- **Finished (UTC):** {results['finished_at']}",
            f"- **Base URL:** `{results['base_url']}`",
            (
                f"- **Duration:** {results['duration_s']:.3f} s "
                f"(target {results['target_duration_s']:.1f} s, "
                f"warmup {results['warmup_s']:.1f} s)"
            ),
            (
                f"- **Target rate:** {results['target_rps']} rps, "
                f"concurrency {results['concurrency']}"
            ),
            (
                f"- **Requests:** {results['requests']} "
                f"({results['achieved_rps']} rps achieved)"
            ),
            (
                f"- **Errors:** {results['error_count']} "
                f"({results['error_rate_pct']:.2f}%)"
            ),
            f"- **5xx:** {results['5xx_count']} ({results['5xx_pct']:.2f}%)",
            f"- **Network errors:** {results['network_error_count']}",
            f"- **Retries:** {results['retry_count']}",
            f"- **Schedule resets:** {results['schedule_resets']}",
        ]
    )

    if results["aborted"]:
        lines.extend(["", f"> **ABORTED:** {results['abort_reason']}"])
    elif results["result"] == "fail":
        lines.extend(["", f"> **FAILED:** {results['result_reason']}"])

    lines.extend(
        [
            "",
            "| Route | Count | 5xx | p50 (ms) | p95 (ms) | p99 (ms) |",
            "|---|---:|---:|---:|---:|---:|",
        ]
    )
    for name, route in results["routes"].items():
        lines.append(
            f"| {name} | {route['count']} | {route['5xx_count']} | "
            f"{_fmt_ms(route['p50_ms'])} | {_fmt_ms(route['p95_ms'])} | "
            f"{_fmt_ms(route['p99_ms'])} |"
        )
    lines.append(
        f"| **Total** | {results['requests']} | {results['5xx_count']} | "
        f"{_fmt_ms(results['p50_ms'])} | {_fmt_ms(results['p95_ms'])} | "
        f"{_fmt_ms(results['p99_ms'])} |"
    )

    if results["notes"]:
        lines.extend(["", "## Notes", ""])
        lines.extend(f"- {note}" for note in results["notes"])

    return "\n".join(lines) + "\n"


def _write_outputs(results: dict[str, Any], output_path: Path, markdown_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(results, indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    markdown_path.write_text(render_markdown(results), encoding="utf-8")


def _as_path(value: str | Path) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else Path.cwd() / path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="bench_phase0.py",
        description="Phase 0 constant-arrival benchmark (GET-only; local/staging only).",
        epilog=(
            "Guard: only loopback hosts or hosts containing 'staging' are allowed; "
            "production is refused. Profile c requires --allow-stress. "
            "Tokens are read from --tokens and never printed."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--base-url",
        required=True,
        help="root URL, e.g. http://127.0.0.1:8787",
    )
    parser.add_argument(
        "--profile",
        choices=tuple(PROFILE_DEFAULTS),
        default="smoke",
        help="load profile (default: smoke)",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=None,
        help="measurement seconds (default: 0 smoke, 600 a/b, 300 c)",
    )
    parser.add_argument(
        "--rps",
        type=float,
        default=None,
        help="target requests/sec (default: 1 smoke, 2.78 a, 5.56 b, 55.6 c)",
    )
    parser.add_argument(
        "--concurrency",
        type=int,
        default=None,
        help="worker threads (default: 1 smoke, 20 a, 40 b, 200 c)",
    )
    parser.add_argument(
        "--tokens",
        default=str(DEFAULT_TOKENS),
        help="seed token JSON (default: %(default)s)",
    )
    parser.add_argument(
        "--output",
        default=None,
        help=(
            "JSON output path (default: "
            "Feature_docs/performance/results/phase0-<profile>-<UTC>.json)"
        ),
    )
    parser.add_argument(
        "--markdown",
        default=None,
        help="Markdown output path (default: sibling .md of --output)",
    )
    parser.add_argument(
        "--warmup",
        type=float,
        default=None,
        help="warmup seconds before measurement (default: 0 smoke, 5 a/b/c)",
    )
    parser.add_argument(
        "--max-5xx-pct",
        type=float,
        default=2.0,
        help="abort above this 5xx percentage after >=20 requests (default: %(default)s)",
    )
    parser.add_argument(
        "--max-p99-ms",
        type=float,
        default=5000.0,
        help="abort above this overall p99 in ms after >=20 requests (default: %(default)s)",
    )
    parser.add_argument(
        "--allow-stress",
        action="store_true",
        help="required for profile c",
    )
    parser.add_argument(
        "--label",
        default=None,
        help="optional label stored in results",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    allowed, reason = is_safe_target(args.base_url)
    if not allowed:
        print(f"error: unsafe base URL: {reason}", file=sys.stderr)
        return 1

    allowed, reason = validate_profile(args.profile, args.allow_stress)
    if not allowed:
        print(f"error: {reason}", file=sys.stderr)
        return 1

    defaults = PROFILE_DEFAULTS[args.profile]
    duration = defaults.duration if args.duration is None else args.duration
    rps = defaults.rps if args.rps is None else args.rps
    concurrency = defaults.concurrency if args.concurrency is None else args.concurrency
    warmup = defaults.warmup if args.warmup is None else args.warmup

    if not math.isfinite(duration) or duration < 0:
        print("error: --duration must be a finite number >= 0", file=sys.stderr)
        return 1
    if args.profile != "smoke" and duration <= 0:
        print(f"error: --duration must be > 0 for profile {args.profile}", file=sys.stderr)
        return 1
    if not math.isfinite(rps) or rps <= 0:
        print("error: --rps must be a finite number > 0", file=sys.stderr)
        return 1
    if concurrency < 1:
        print("error: --concurrency must be >= 1", file=sys.stderr)
        return 1
    if not math.isfinite(warmup) or warmup < 0:
        print("error: --warmup must be a finite number >= 0", file=sys.stderr)
        return 1
    if not math.isfinite(args.max_5xx_pct) or not 0 <= args.max_5xx_pct <= 100:
        print("error: --max-5xx-pct must be between 0 and 100", file=sys.stderr)
        return 1
    if not math.isfinite(args.max_p99_ms) or args.max_p99_ms <= 0:
        print("error: --max-p99-ms must be a finite number > 0", file=sys.stderr)
        return 1

    base_url = normalize_base_url(args.base_url)
    tokens_path = _as_path(args.tokens)
    require_users = args.profile != "smoke"
    try:
        tokens = load_tokens(tokens_path, require_users=require_users)
    except TokenFileError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    notes: list[str] = []
    if args.profile == "smoke" and not tokens_path.is_file():
        notes.append(f"token file not found ({tokens_path}); public scenarios only")
    if args.profile == "c":
        notes.append("profile c is a stress profile; results find the knee, not a launch gate")
    if args.profile == "smoke" and any(
        value is not None
        for value in (args.duration, args.rps, args.concurrency, args.warmup)
    ):
        notes.append("smoke ignores --duration/--rps/--concurrency/--warmup; one pass per scenario")

    scenarios, skipped = available_scenarios(tokens)
    notes.extend(skipped)
    for note in notes:
        print(f"note: {note}", file=sys.stderr)

    if not scenarios:
        print("error: no runnable scenarios", file=sys.stderr)
        return 1

    started = datetime.now(UTC)
    started_at = _iso_utc(started)
    if args.output:
        output_path = _as_path(args.output)
    else:
        stamp = started.strftime("%Y%m%dT%H%M%SZ")
        output_path = DEFAULT_RESULTS_DIR / f"phase0-{args.profile}-{stamp}.json"
    markdown_path = _as_path(args.markdown) if args.markdown else output_path.with_suffix(".md")
    if output_path.resolve() == markdown_path.resolve():
        print("error: --output and --markdown must be different paths", file=sys.stderr)
        return 1

    try:
        if args.profile == "smoke":
            outcome = _run_smoke(base_url, tokens, scenarios)
            run_rps = 1.0
            run_concurrency = 1
            run_warmup = 0.0
            run_duration = 0.0
        else:
            outcome = _run_load(
                base_url,
                tokens,
                scenarios,
                rps=rps,
                concurrency=concurrency,
                duration=duration,
                warmup=warmup,
                max_5xx_pct=args.max_5xx_pct,
                max_p99_ms=args.max_p99_ms,
            )
            run_rps = rps
            run_concurrency = concurrency
            run_warmup = warmup
            run_duration = duration
    except Exception as exc:  # never echo exception text: it may contain a header
        print(f"error: benchmark failed: {type(exc).__name__}", file=sys.stderr)
        return 1

    results = _build_results(
        profile=args.profile,
        base_url=base_url,
        label=args.label,
        outcome=outcome,
        started_at=started_at,
        finished_at=_iso_utc(datetime.now(UTC)),
        target_duration_s=run_duration,
        rps=run_rps,
        concurrency=run_concurrency,
        warmup=run_warmup,
        max_5xx_pct=args.max_5xx_pct,
        max_p99_ms=args.max_p99_ms,
        notes=notes,
    )

    try:
        _write_outputs(results, output_path, markdown_path)
    except (OSError, UnicodeError, TypeError, ValueError) as exc:
        print(f"error: cannot write results: {exc}", file=sys.stderr)
        return 1

    print(
        f"profile={results['profile']} result={results['result']} "
        f"requests={results['requests']} rps={results['achieved_rps']:.3f} "
        f"errors={results['error_rate_pct']:.2f}% 5xx={results['5xx_pct']:.2f}% "
        f"p99={_fmt_ms(results['p99_ms'])}ms resets={results['schedule_resets']}"
    )
    if results["aborted"]:
        print(f"ABORTED: {results['abort_reason']}", file=sys.stderr)
    elif results["result"] == "fail":
        print(f"FAILED: {results['result_reason']}", file=sys.stderr)
    print(f"json: {output_path}")
    print(f"markdown: {markdown_path}")
    return 0 if results["result"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
