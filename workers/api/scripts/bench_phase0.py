"""Shodasha benchmark harness (Python 3.13, stdlib only).

Read-only by default. ``--allow-writes`` enables the COD create/cancel/reschedule
probe and is refused unless the target is loopback or staging. The harness
refuses production and any target that is not loopback or does not contain
``staging``. Results are written as JSON + Markdown; bearer tokens, passwords,
and credential files are never printed or serialized.
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
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlsplit, urlunsplit

API_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_TOKENS = API_ROOT / "data" / "phase0_tokens.json"
DEFAULT_RESULTS_DIR = REPO_ROOT / "Feature_docs" / "performance" / "results"

USER_AGENT = "shodasha-phase0-bench/2.0"
PRODUCTION_HOST_MARKER = "adityathakur452007.workers.dev"
LOOPBACK_HOSTS = frozenset({"localhost", "127.0.0.1", "::1"})
MAX_BODY_BYTES = 1_048_576
HTTP_TIMEOUT_S = 10.0
MIN_ABORT_REQUESTS = 20
ABORT_CHECK_INTERVAL_S = 0.5
MAX_UNEXPECTED_ERROR_PCT = 2.0
PHASE3_READ_PROFILES = frozenset({"phase3-a", "phase3-b", "phase3-soak", "phase3-c"})
WRITE_PROFILE = "write"
LOGIN_PROFILE = "login"
WRITE_PROBE_PREFIX = "load3-w"
QUOTE_RATE_VERSION = "v1"  # pricing.RATE_VERSION; order create re-checks it
PROVIDER_PATH_MARKERS = (
    "/payments",
    "/webhooks",
    "/provider",
    "/dues-intent",
    "/subscription-intent",
    "/upi",
)


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
    "phase3-a": ProfileDefaults(duration=1800.0, rps=2.78, concurrency=50, warmup=0.0),
    "phase3-b": ProfileDefaults(duration=1800.0, rps=5.56, concurrency=100, warmup=0.0),
    "phase3-soak": ProfileDefaults(duration=1800.0, rps=5.56, concurrency=100, warmup=0.0),
    "phase3-c": ProfileDefaults(duration=3600.0, rps=55.6, concurrency=1000, warmup=0.0),
    WRITE_PROFILE: ProfileDefaults(duration=600.0, rps=1.11, concurrency=1, warmup=0.0),
    LOGIN_PROFILE: ProfileDefaults(duration=600.0, rps=0.15, concurrency=1, warmup=0.0),
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


def validate_profile(
    profile: str, allow_stress: bool, allow_writes: bool = False
) -> tuple[bool, str]:
    """Return ``(allowed, reason)``; stress and write profiles need explicit flags."""
    if profile not in PROFILE_DEFAULTS:
        return False, f"unknown profile {profile!r}; choose from {', '.join(PROFILE_DEFAULTS)}"
    if profile in {"c", "phase3-c"} and not allow_stress:
        return False, f"profile {profile} is a stress profile; pass --allow-stress to run it"
    if profile == WRITE_PROFILE and not allow_writes:
        return False, "profile write is a write probe; pass --allow-writes to run it"
    return True, f"profile {profile} allowed"


def is_safe_write_path(path: str) -> tuple[bool, str]:
    """Return ``(allowed, reason)`` for a write-probe path. No network I/O."""
    normalized = urlsplit(path).path.rstrip("/")
    if any(marker in normalized for marker in PROVIDER_PATH_MARKERS):
        return False, f"refusing provider/payment path {normalized!r}"
    if normalized in {"/v1/quotes", "/v1/orders"}:
        return True, "allowed write path"
    parts = normalized.split("/")
    if (
        len(parts) == 5
        and parts[1:3] == ["v1", "orders"]
        and parts[3]
        and parts[4] in {"cancel", "reschedule"}
    ):
        return True, "allowed write path"
    return False, f"write path {normalized!r} is not in the approved probe set"


def validate_write_target(base_url: str) -> tuple[bool, str]:
    """Writes are allowed only on loopback or a staging host."""
    allowed, reason = is_safe_target(base_url)
    if not allowed:
        return False, reason
    host = (urlsplit(base_url.strip()).hostname or "").lower()
    if host in LOOPBACK_HOSTS:
        return True, "loopback write target"
    if "staging" in host:
        return True, "staging write target"
    return False, "writes require a loopback or staging target"


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
            f"{token_path}: no usable user tokens; profiles a/b/c/phase3/write need "
            "at least one seeded user (or use --profile smoke)."
        )
    return TokenData(users=users, vendors=vendors, admin=admin)


class CredentialsError(RuntimeError):
    """Login credential file missing, unreadable, or invalid."""


@dataclass(frozen=True)
class Credential:
    phone: str = field(repr=False)
    password: str = field(repr=False)


def load_credentials(path: str | Path) -> tuple[Credential, ...]:
    """Load login credentials. Errors never include phone numbers or passwords."""
    cred_path = Path(path)
    if not cred_path.is_file():
        raise CredentialsError(f"credential file not found: {cred_path}")
    try:
        raw = json.loads(cred_path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise CredentialsError(f"cannot read credential file {cred_path}: {exc}") from exc
    if not isinstance(raw, list):
        raise CredentialsError(f"{cred_path}: top-level JSON must be a list")

    credentials: list[Credential] = []
    for index, item in enumerate(raw):
        if not isinstance(item, dict):
            raise CredentialsError(f"{cred_path}: credential[{index}] must be an object")
        phone = item.get("phone")
        password = item.get("password")
        if not isinstance(phone, str) or not phone.strip():
            raise CredentialsError(f"{cred_path}: credential[{index}].phone must be a string")
        if not isinstance(password, str) or not password:
            raise CredentialsError(f"{cred_path}: credential[{index}].password must be a string")
        credentials.append(Credential(phone=phone.strip(), password=password))
    if not credentials:
        raise CredentialsError(f"{cred_path}: no credentials")
    return tuple(credentials)


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

# Phase 3 read mix: 15% public, 70% authed, 5% session, 5% vendor, 5% admin.
# Health is smoke-only; the public share is catalog + windows.
PHASE3_SCENARIOS: tuple[Scenario, ...] = (
    Scenario("catalog", "/v1/catalog", "none", 8),
    Scenario("windows", "/v1/windows", "none", 7),
    Scenario("orders", "/v1/orders?limit=50", "user", 20),
    Scenario("order_detail", "/v1/orders", "user", 20),
    Scenario("subscriptions", "/v1/subscriptions", "user", 15),
    Scenario("ledger", "/v1/ledger/me", "user", 10),
    Scenario("dues", "/v1/billing/dues", "user", 5),
    Scenario("me", "/v1/auth/me", "user", 5),
    Scenario("vendor_route", "/v1/vendor/routes/today", "vendor", 5),
    Scenario("admin_metrics", "/v1/admin/metrics", "admin", 3),
    Scenario("admin_overview", "/v1/admin/metrics/overview", "admin", 2),
)


def available_scenarios(
    tokens: TokenData, scenarios: Sequence[Scenario] = SCENARIOS
) -> tuple[list[Scenario], list[str]]:
    """Return runnable scenarios in canonical order plus human-readable skip notes."""
    has_users = bool(tokens.users)
    has_orders = any(user.order_id for user in tokens.users)
    has_vendors = bool(tokens.vendors)
    has_admin = tokens.admin is not None
    available: list[Scenario] = []
    notes: list[str] = []

    for scenario in scenarios:
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
        elif scenario.auth == "admin":
            if has_admin:
                available.append(scenario)
            else:
                notes.append(f"{scenario.name} skipped: no admin token")
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
        self._admin = tokens.admin
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
            elif scenario.auth == "admin":
                token = self._admin
            else:
                token = None
        return scenario, token


# ---------------------------------------------------------------------------
# HTTP: thread-local keep-alive connections, one retry on transport failure
# ---------------------------------------------------------------------------


class HttpClient:
    """Thread-local keep-alive client; 10s timeout, one retry."""

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

    def _read_body(self, response: http.client.HTTPResponse) -> bytes:
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = response.read(65_536)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_BODY_BYTES:
                self._close()
                break
            chunks.append(chunk)
        return b"".join(chunks)

    def request(
        self,
        method: str,
        path: str,
        token: str | None = None,
        body: bytes | None = None,
        extra_headers: dict[str, str] | None = None,
    ) -> tuple[int, float, bool, bytes]:
        """Send one request. Returns ``(status, latency_ms, retried, body)``."""
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
            if body is not None:
                headers["Content-Type"] = "application/json"
                headers["Content-Length"] = str(len(body))
            if extra_headers:
                headers.update(extra_headers)
            try:
                conn = self._connection()
                conn.request(method, path, body=body, headers=headers)
                response = conn.getresponse()
                status = response.status
                payload = self._read_body(response)
                return status, (time.perf_counter() - started) * 1000.0, retried, payload
            except (OSError, http.client.HTTPException):
                self._close()
                if attempt == 0:
                    retried = True
                    continue
                return 0, (time.perf_counter() - started) * 1000.0, retried, b""

        return 0, (time.perf_counter() - started) * 1000.0, retried, b""

    def get(self, path: str, token: str | None) -> tuple[int, float, bool]:
        """Send one GET. Returns ``(status, latency_ms, retried)``; status 0 on failure."""
        status, latency_ms, retried, _ = self.request("GET", path, token)
        return status, latency_ms, retried


# ---------------------------------------------------------------------------
# Results, scheduling, and abort monitor
# ---------------------------------------------------------------------------


@dataclass
class RouteStats:
    count: int = 0
    status_counts: Counter[int] = field(default_factory=Counter)
    latencies_ms: list[float] = field(default_factory=list)
    error_count: int = 0
    expected_error_count: int = 0
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

    def record(
        self,
        route: str,
        status: int,
        latency_ms: float,
        retried: bool,
        expected: bool = False,
    ) -> None:
        with self._lock:
            route_stats = self._routes[route]
            route_stats.count += 1
            route_stats.status_counts[status] += 1
            route_stats.latencies_ms.append(latency_ms)
            if status < 200 or status >= 300:
                route_stats.error_count += 1
                if expected:
                    route_stats.expected_error_count += 1
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
                    route.expected_error_count,
                    route.retry_count,
                )
                for name, route in self._routes.items()
            }

        routes: dict[str, dict[str, Any]] = {}
        all_latencies: list[float] = []
        total_count = 0
        total_errors = 0
        total_expected_errors = 0
        total_retries = 0
        total_status: Counter[int] = Counter()

        for name, (
            count,
            statuses,
            latencies,
            errors,
            expected_errors,
            retries,
        ) in raw.items():
            latencies.sort()
            all_latencies.extend(latencies)
            total_count += count
            total_errors += errors
            total_expected_errors += expected_errors
            total_retries += retries
            total_status.update(statuses)
            routes[name] = {
                "count": count,
                "status_counts": {str(code): value for code, value in sorted(statuses.items())},
                "5xx_count": sum(value for code, value in statuses.items() if code >= 500),
                "error_count": errors,
                "expected_error_count": expected_errors,
                "unexpected_error_count": errors - expected_errors,
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
            "expected_error_count": total_expected_errors,
            "unexpected_error_count": total_errors - total_expected_errors,
            "error_rate_pct": _pct(total_errors, total_count),
            "5xx_count": five_xx,
            "5xx_pct": _pct(five_xx, total_count),
            "network_error_count": total_status.get(0, 0),
            "retry_count": total_retries,
            "latency": _latency_summary(all_latencies),
        }


class PhaseStats:
    """Per-phase stats plus counted/all aggregates for a timeline run."""

    def __init__(self, phase_names: Sequence[str], route_names: Sequence[str]) -> None:
        self._phases = {name: Stats(route_names) for name in phase_names}
        self.counted = Stats(route_names)
        self.all = Stats(route_names)

    def record(
        self,
        phase: str,
        route: str,
        status: int,
        latency_ms: float,
        retried: bool,
        counted: bool,
        expected: bool = False,
    ) -> None:
        self._phases[phase].record(route, status, latency_ms, retried, expected)
        self.all.record(route, status, latency_ms, retried, expected)
        if counted:
            self.counted.record(route, status, latency_ms, retried, expected)

    def phase_snapshots(self) -> dict[str, Any]:
        return {name: stats.snapshot() for name, stats in self._phases.items()}


@dataclass(frozen=True)
class TimelinePhase:
    name: str
    duration: float
    rate_factor: float
    counted: bool


PHASE3_TIMELINE: tuple[TimelinePhase, ...] = (
    TimelinePhase("warmup", 120.0, 0.25, False),
    TimelinePhase("steady", 600.0, 1.0, True),
    TimelinePhase("burst", 300.0, 2.5, True),
    TimelinePhase("recovery", 600.0, 1.0, True),
    TimelinePhase("rampdown", 180.0, 1.0, False),
)
SOAK_TIMELINE: tuple[TimelinePhase, ...] = (
    TimelinePhase("soak", 1800.0, 1.0, True),
)


@dataclass(frozen=True)
class TimelineSlot:
    at: float
    phase: str
    counted: bool


def build_timeline(
    phases: Sequence[TimelinePhase], avg_rps: float, scale: float = 1.0
) -> list[TimelineSlot]:
    """Precompute arrival slots; ramp-down uses a linear rate to zero."""
    if not math.isfinite(scale) or scale <= 0:
        raise ValueError("timeline scale must be a finite number > 0")
    if not math.isfinite(avg_rps) or avg_rps <= 0:
        raise ValueError("average rps must be a finite number > 0")

    slots: list[TimelineSlot] = []
    cursor = 0.0
    for phase in phases:
        duration = phase.duration * scale
        rate = avg_rps * phase.rate_factor
        if phase.name == "rampdown":
            count = max(0, int(duration * rate / 2.0 + 0.5))
            for index in range(count):
                fraction = 1.0 - math.sqrt(1.0 - (index + 0.5) / count)
                slots.append(
                    TimelineSlot(cursor + fraction * duration, phase.name, phase.counted)
                )
        else:
            count = max(0, int(duration * rate + 0.5))
            for index in range(count):
                slots.append(
                    TimelineSlot(cursor + (index + 0.5) / rate, phase.name, phase.counted)
                )
        cursor += duration

    slots.sort(key=lambda slot: slot.at)
    return slots


class SlotSchedule:
    """Thread-safe cursor over a precomputed timeline."""

    def __init__(self, slots: Sequence[TimelineSlot]) -> None:
        self._slots = tuple(slots)
        self._index = 0
        self._start = time.monotonic()
        self._lock = threading.Lock()
        self._resets = 0

    @property
    def duration(self) -> float:
        return self._slots[-1].at if self._slots else 0.0

    @property
    def resets(self) -> int:
        with self._lock:
            return self._resets

    def next(self, stop_event: threading.Event) -> TimelineSlot | None:
        with self._lock:
            if self._index >= len(self._slots):
                return None
            slot = self._slots[self._index]
            self._index += 1

        target = self._start + slot.at
        delay = target - time.monotonic()
        if delay > 0 and stop_event.wait(delay):
            return None
        if delay < -2.0:
            with self._lock:
                self._resets += 1
        return slot


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


def _abort_reason(
    snapshot: dict[str, Any], max_5xx_pct: float, max_p99_ms: float
) -> str | None:
    """Return the first abort reason for a stats snapshot, or ``None``."""
    if snapshot["requests"] < MIN_ABORT_REQUESTS:
        return None
    reasons: list[str] = []
    if snapshot["5xx_pct"] > max_5xx_pct:
        reasons.append(f"5xx rate {snapshot['5xx_pct']:.2f}% > {max_5xx_pct:.2f}%")
    p99 = snapshot["latency"]["p99_ms"]
    if p99 is not None and p99 > max_p99_ms:
        reasons.append(f"p99 {p99:.0f} ms > {max_p99_ms:.0f} ms")
    return "; ".join(reasons) or None


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

            reason = _abort_reason(snapshot, self._max_5xx_pct, self._max_p99_ms)
            if reason:
                self._abort.set(reason)
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
    phases: dict[str, Any] | None = None
    all_stats: dict[str, Any] | None = None
    counted_duration_s: float | None = None
    details: dict[str, Any] | None = None


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
    if scenario.auth == "admin":
        return tokens.admin
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


def _unexpected_failure(snapshot: dict[str, Any]) -> str | None:
    """Fail a run when unexpected non-2xx responses exceed the 2% gate."""
    if snapshot["requests"] == 0:
        return "no requests were sent during the measurement window"
    pct = _pct(snapshot["unexpected_error_count"], snapshot["requests"])
    if pct > MAX_UNEXPECTED_ERROR_PCT:
        return (
            f"unexpected errors {pct:.2f}% > {MAX_UNEXPECTED_ERROR_PCT:.2f}% "
            f"({snapshot['unexpected_error_count']} of {snapshot['requests']})"
        )
    return None


def _run_timeline(
    base_url: str,
    tokens: TokenData,
    scenarios: Sequence[Scenario],
    *,
    rps: float,
    concurrency: int,
    scale: float,
    max_5xx_pct: float,
    max_p99_ms: float,
    timeline: Sequence[TimelinePhase] = PHASE3_TIMELINE,
) -> RunOutcome:
    """Run a Phase 3 timeline; SLOs use the counted phases only."""
    slots = build_timeline(timeline, rps, scale)
    if not slots:
        raise ValueError("timeline produced no request slots")
    timeline_duration = sum(phase.duration for phase in timeline) * scale
    counted_duration = sum(phase.duration for phase in timeline if phase.counted) * scale
    phase_stats = PhaseStats(
        [phase.name for phase in timeline], [scenario.name for scenario in scenarios]
    )
    picker = ScenarioPicker(scenarios, tokens)
    schedule = SlotSchedule(slots)
    client = HttpClient(base_url)
    stop_event = threading.Event()
    abort = AbortFlag()
    started = time.monotonic()

    def worker() -> None:
        try:
            while not stop_event.is_set():
                slot = schedule.next(stop_event)
                if slot is None or abort.reason is not None:
                    return
                scenario, token = picker.next()
                status, latency_ms, retried = client.get(
                    _request_path(scenario, token),
                    token.token if token else None,
                )
                phase_stats.record(
                    slot.phase, scenario.name, status, latency_ms, retried, slot.counted
                )
        except Exception as exc:  # pragma: no cover - defensive
            abort.set(f"worker error: {type(exc).__name__}")
            stop_event.set()

    threads = [
        threading.Thread(target=worker, name=f"phase3-worker-{index}", daemon=True)
        for index in range(concurrency)
    ]
    for thread in threads:
        thread.start()

    monitor = AbortMonitor(phase_stats.counted, stop_event, abort, max_5xx_pct, max_p99_ms)
    monitor.start()

    while True:
        remaining = timeline_duration - (time.monotonic() - started)
        if remaining <= 0:
            break
        if stop_event.wait(min(remaining, 0.25)):
            break

    stop_event.set()
    for thread in threads:
        thread.join(timeout=15.0)
    monitor.join(timeout=2.0)

    elapsed = min(timeline_duration, max(0.0, time.monotonic() - started))
    alive = any(thread.is_alive() for thread in threads)
    counted = phase_stats.counted.snapshot()
    failure = abort.reason or _unexpected_failure(counted)
    if failure is None and alive:
        failure = "worker threads did not finish within 15s"

    phases = phase_stats.phase_snapshots()
    for phase in timeline:
        phases[phase.name]["counted"] = phase.counted

    return RunOutcome(
        stats=phase_stats.counted,
        elapsed_s=elapsed,
        schedule_resets=schedule.resets,
        aborted=abort.reason is not None,
        abort_reason=abort.reason,
        failure_reason=failure,
        phases=phases,
        all_stats=phase_stats.all.snapshot(),
        counted_duration_s=counted_duration,
    )


# ---------------------------------------------------------------------------
# Write probe (COD create/cancel/reschedule only; probe-owned orders)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ProbeOrder:
    order_id: str
    window_start: str


def _json_bytes(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, separators=(",", ":")).encode("utf-8")


def _json_value(payload: bytes) -> Any:
    try:
        return json.loads(payload)
    except (ValueError, UnicodeDecodeError):
        return None


def _probe_quote(
    client: HttpClient,
    token: TokenEntry,
    address_id: str,
    window_start: str,
    stats: Stats,
) -> dict[str, Any] | None:
    payload = {
        "items": [{"sku": "refill", "qty": 1}],
        "e": 0,
        "address_id": address_id,
        "window_start": window_start,
    }
    status, latency_ms, retried, body = client.request(
        "POST", "/v1/quotes", token.token, _json_bytes(payload)
    )
    stats.record("quote", status, latency_ms, retried)
    if status != 200:
        return None
    quote = _json_value(body)
    return quote if isinstance(quote, dict) else None


def _write_create(
    client: HttpClient,
    token: TokenEntry,
    address_id: str,
    window_start: str,
    idem_key: str,
    stats: Stats,
) -> str | None:
    quote = _probe_quote(client, token, address_id, window_start, stats)
    if quote is None:
        return None
    required = ("quote_hash", "total", "expires_at")
    if any(quote.get(key) is None for key in required):
        return None
    payload = {
        "items": [{"sku": "refill", "qty": 1}],
        "e": 0,
        "address_id": address_id,
        "window_start": window_start,
        "quote_hash": quote["quote_hash"],
        "quote_total": quote["total"],
        "quote_rate_version": QUOTE_RATE_VERSION,
        "quote_expires_at": quote["expires_at"],
        "payment_mode": "cod",
    }
    status, latency_ms, retried, body = client.request(
        "POST",
        "/v1/orders",
        token.token,
        _json_bytes(payload),
        extra_headers={"Idempotency-Key": idem_key},
    )
    stats.record("create_order", status, latency_ms, retried)
    if status != 201:
        return None
    created = _json_value(body)
    if isinstance(created, dict) and created.get("id"):
        return str(created["id"])
    return None


def _write_cancel(
    client: HttpClient,
    token: TokenEntry,
    order_id: str,
    idem_key: str,
    stats: Stats,
) -> int:
    status, latency_ms, retried, _ = client.request(
        "POST",
        f"/v1/orders/{quote(order_id, safe='')}/cancel",
        token.token,
        _json_bytes({"reason": "phase3 write probe"}),
        extra_headers={"Idempotency-Key": idem_key},
    )
    stats.record("cancel_order", status, latency_ms, retried, expected=status == 409)
    return status


def _write_reschedule(
    client: HttpClient,
    token: TokenEntry,
    order_id: str,
    window_start: str,
    idem_key: str,
    stats: Stats,
) -> int:
    status, latency_ms, retried, _ = client.request(
        "POST",
        f"/v1/orders/{quote(order_id, safe='')}/reschedule",
        token.token,
        _json_bytes({"window_start": window_start}),
        extra_headers={"Idempotency-Key": idem_key},
    )
    stats.record("reschedule_order", status, latency_ms, retried, expected=status == 409)
    return status


def _setup_write_pool(
    client: HttpClient,
    token: TokenEntry,
    run_id: str,
    pool_size: int,
    window_start: str,
) -> tuple[str, list[ProbeOrder]]:
    status, _, _, body = client.request("GET", "/v1/addresses", token.token)
    if status != 200:
        raise RuntimeError("write probe setup: cannot list addresses")
    addresses = _json_value(body)
    address_id = None
    if isinstance(addresses, list):
        address_id = next(
            (
                str(item["id"])
                for item in addresses
                if isinstance(item, dict) and item.get("id")
            ),
            None,
        )
    if address_id is None:
        raise RuntimeError("write probe setup: the probe user has no address")

    setup_stats = Stats(["quote", "create_order"])
    orders: list[ProbeOrder] = []
    for index in range(pool_size):
        order_id = _write_create(
            client,
            token,
            address_id,
            window_start,
            f"{WRITE_PROBE_PREFIX}-{run_id}-setup-{index}",
            setup_stats,
        )
        if order_id:
            orders.append(ProbeOrder(order_id, window_start))
    if not orders:
        raise RuntimeError("write probe setup: no pool orders were created")
    return address_id, orders


def _run_write(
    base_url: str,
    tokens: TokenData,
    *,
    rps: float,
    duration: float,
    pool_size: int,
    max_5xx_pct: float,
    max_p99_ms: float,
) -> RunOutcome:
    """COD create/cancel/reschedule probe against probe-owned orders only."""
    client = HttpClient(base_url)
    token = tokens.users[0]
    run_id = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    window_start = (datetime.now(UTC) + timedelta(hours=2)).isoformat(timespec="seconds")
    address_id, pool = _setup_write_pool(client, token, run_id, pool_size, window_start)
    stats = Stats(["quote", "create_order", "cancel_order", "reschedule_order"])
    available = list(pool)
    created = cancelled = rescheduled = 0
    resets = 0
    aborted = False
    abort_reason = None
    interval = 1.0 / rps
    started = time.monotonic()
    next_at = started
    index = 0

    while time.monotonic() - started < duration:
        delay = next_at - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        if time.monotonic() - started >= duration:
            break

        action = ("create", "cancel", "reschedule")[index % 3]
        key = f"{WRITE_PROBE_PREFIX}-{run_id}-{index}"
        index += 1
        if action == "create" or not available:
            order_id = _write_create(
                client, token, address_id, window_start, key, stats
            )
            if order_id:
                created += 1
                available.append(ProbeOrder(order_id, window_start))
        elif action == "cancel":
            order = available.pop(0)
            status = _write_cancel(client, token, order.order_id, key, stats)
            cancelled += int(status == 200)
        else:
            order = available.pop(0)
            status = _write_reschedule(
                client, token, order.order_id, window_start, key, stats
            )
            if status == 200:
                rescheduled += 1
                available.append(order)

        snapshot = stats.snapshot()
        abort_reason = _abort_reason(snapshot, max_5xx_pct, max_p99_ms)
        if abort_reason:
            aborted = True
            break
        next_at += interval
        if next_at < time.monotonic() - 2.0:
            next_at = time.monotonic()
            resets += 1

    elapsed = min(duration, max(0.0, time.monotonic() - started))
    snapshot = stats.snapshot()
    failure = abort_reason or _unexpected_failure(snapshot)
    return RunOutcome(
        stats=stats,
        elapsed_s=elapsed,
        schedule_resets=resets,
        aborted=aborted,
        abort_reason=abort_reason,
        failure_reason=failure,
        details={
            "run_id": run_id,
            "prefix": f"{WRITE_PROBE_PREFIX}-{run_id}-",
            "pool_initial": len(pool),
            "pool_final": len(available),
            "created": created,
            "cancelled": cancelled,
            "rescheduled": rescheduled,
            "quotes": snapshot["routes"]["quote"]["count"],
            "quote_rate_version": QUOTE_RATE_VERSION,
        },
    )


# ---------------------------------------------------------------------------
# Login probe (credentials live outside the repo; never serialized)
# ---------------------------------------------------------------------------


def _login_device_id(run_tag: str, credential_index: int) -> str:
    """One stable device per credential; sharing one device trips DEVICE_CAP."""
    return f"phase3-login-{run_tag}-{credential_index:03d}"


def _run_login(
    base_url: str,
    credentials: Sequence[Credential],
    *,
    rps: float,
    duration: float,
    max_5xx_pct: float,
    max_p99_ms: float,
) -> RunOutcome:
    """One phone/password login per slot; never prints or serializes credentials."""
    client = HttpClient(base_url)
    stats = Stats(["login"])
    run_tag = uuid.uuid4().hex[:8]
    interval = 1.0 / rps
    started = time.monotonic()
    next_at = started
    index = 0
    resets = 0
    aborted = False
    abort_reason = None

    while time.monotonic() - started < duration:
        delay = next_at - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        if time.monotonic() - started >= duration:
            break

        credential_index = index % len(credentials)
        credential = credentials[credential_index]
        index += 1
        payload = {
            "phone": credential.phone,
            "password": credential.password,
            "device": {
                "id": _login_device_id(run_tag, credential_index),
                "integrity": None,
            },
        }
        status, latency_ms, retried, _ = client.request(
            "POST", "/v1/auth/user/login", body=_json_bytes(payload)
        )
        stats.record("login", status, latency_ms, retried)

        snapshot = stats.snapshot()
        abort_reason = _abort_reason(snapshot, max_5xx_pct, max_p99_ms)
        if abort_reason:
            aborted = True
            break
        next_at += interval
        if next_at < time.monotonic() - 2.0:
            next_at = time.monotonic()
            resets += 1

    elapsed = min(duration, max(0.0, time.monotonic() - started))
    snapshot = stats.snapshot()
    failure = abort_reason
    if failure is None and snapshot["unexpected_error_count"]:
        failure = (
            f"login probe: {snapshot['unexpected_error_count']} of "
            f"{snapshot['requests']} logins failed"
        )
    return RunOutcome(
        stats=stats,
        elapsed_s=elapsed,
        schedule_resets=resets,
        aborted=aborted,
        abort_reason=abort_reason,
        failure_reason=failure,
        details={"credentials": len(credentials), "device_mode": "per-credential"},
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
    denominator = outcome.counted_duration_s or outcome.elapsed_s
    scope = "counted" if outcome.phases is not None else "all"
    return {
        "schema_version": 2,
        "label": label,
        "profile": profile,
        "scope": scope,
        "base_url": base_url,
        "started_at": started_at,
        "finished_at": finished_at,
        "duration_s": round(outcome.elapsed_s, 3),
        "counted_duration_s": (
            round(outcome.counted_duration_s, 3)
            if outcome.counted_duration_s is not None
            else None
        ),
        "target_duration_s": target_duration_s,
        "warmup_s": round(warmup, 3),
        "target_rps": rps,
        "concurrency": concurrency,
        "requests": snapshot["requests"],
        "achieved_rps": (
            round(snapshot["requests"] / denominator, 3) if denominator > 0 else 0.0
        ),
        "status_counts": snapshot["status_counts"],
        "error_count": snapshot["error_count"],
        "error_rate_pct": snapshot["error_rate_pct"],
        "expected_error_count": snapshot["expected_error_count"],
        "unexpected_error_count": snapshot["unexpected_error_count"],
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
        "thresholds": {
            "max_5xx_pct": max_5xx_pct,
            "max_p99_ms": max_p99_ms,
            "max_unexpected_error_pct": MAX_UNEXPECTED_ERROR_PCT,
        },
        "routes": snapshot["routes"],
        "phases": outcome.phases,
        "all": outcome.all_stats,
        "details": outcome.details,
        "notes": list(notes),
    }


def render_markdown(results: dict[str, Any]) -> str:
    phase3 = results["profile"].startswith("phase3") or results["profile"] in {
        WRITE_PROFILE,
        LOGIN_PROFILE,
    }
    lines = [
        f"# {'Phase 3' if phase3 else 'Phase 0'} benchmark - profile {results['profile']}",
        "",
    ]
    if results["label"]:
        lines.append(f"- **Label:** {results['label']}")
    lines.extend(
        [
            f"- **Result:** {results['result']}",
            f"- **Scope:** {results['scope']}",
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
                f"({results['error_rate_pct']:.2f}%), "
                f"expected {results['expected_error_count']}, "
                f"unexpected {results['unexpected_error_count']}"
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

    if results.get("phases"):
        lines.extend(
            [
                "",
                "## Timeline phases",
                "",
                "| Phase | Counted | Requests | 5xx | p50 (ms) | p95 (ms) | p99 (ms) |",
                "|---|---:|---:|---:|---:|---:|---:|",
            ]
        )
        for name, phase in results["phases"].items():
            lines.append(
                f"| {name} | {'yes' if phase.get('counted') else 'no'} | "
                f"{phase['requests']} | {phase['5xx_count']} | "
                f"{_fmt_ms(phase['latency']['p50_ms'])} | "
                f"{_fmt_ms(phase['latency']['p95_ms'])} | "
                f"{_fmt_ms(phase['latency']['p99_ms'])} |"
            )
        lines.extend(
            ["", "SLOs use the counted phases only; warm-up and ramp-down are excluded."]
        )

    if results.get("details"):
        lines.extend(["", "## Probe details", ""])
        lines.extend(
            f"- **{key}:** {value}" for key, value in results["details"].items()
        )

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
        description=(
            "Shodasha benchmark (read-only by default; loopback or staging only)."
        ),
        epilog=(
            "Guard: only loopback hosts or hosts containing 'staging' are allowed; "
            "production is refused. Profile c/phase3-c requires --allow-stress; "
            "profile write requires --allow-writes; profile login requires "
            "--credentials. Tokens and credentials are read from files and never printed."
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
        help=(
            "measurement seconds; for phase3 profiles it scales the timeline "
            "(default: profile default)"
        ),
    )
    parser.add_argument(
        "--rps",
        "--rate",
        dest="rps",
        type=float,
        default=None,
        help="target requests/sec (default: profile default)",
    )
    parser.add_argument(
        "--concurrency",
        type=int,
        default=None,
        help="worker threads (default: profile default; write/login force 1)",
    )
    parser.add_argument(
        "--timeline-scale",
        type=float,
        default=None,
        help="phase3 timeline multiplier, e.g. 0.02 for a local compressed run",
    )
    parser.add_argument(
        "--pool-size",
        type=int,
        default=5,
        help="write probe setup pool size (default: %(default)s)",
    )
    parser.add_argument(
        "--tokens",
        default=str(DEFAULT_TOKENS),
        help="seed token JSON (default: %(default)s)",
    )
    parser.add_argument(
        "--credentials",
        default=None,
        help="login credential JSON for profile login (never printed or serialized)",
    )
    parser.add_argument(
        "--output",
        default=None,
        help=(
            "JSON output path (default: "
            "Feature_docs/performance/results/<phase>-<profile>-<UTC>.json)"
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
        help="required for profile c and phase3-c",
    )
    parser.add_argument(
        "--allow-writes",
        action="store_true",
        help="required for profile write; refused on a non-loopback/non-staging target",
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

    allowed, reason = validate_profile(
        args.profile, args.allow_stress, args.allow_writes
    )
    if not allowed:
        print(f"error: {reason}", file=sys.stderr)
        return 1

    if args.profile == WRITE_PROFILE:
        allowed, reason = validate_write_target(args.base_url)
        if not allowed:
            print(f"error: unsafe write target: {reason}", file=sys.stderr)
            return 1

    if args.timeline_scale is not None and args.profile not in PHASE3_READ_PROFILES:
        print(
            "error: --timeline-scale is only valid for phase3 profiles",
            file=sys.stderr,
        )
        return 1
    if args.credentials is not None and args.profile != LOGIN_PROFILE:
        print("error: --credentials is only valid for profile login", file=sys.stderr)
        return 1
    if args.profile == LOGIN_PROFILE and not args.credentials:
        print("error: profile login requires --credentials", file=sys.stderr)
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
    if args.pool_size < 1:
        print("error: --pool-size must be >= 1", file=sys.stderr)
        return 1
    if args.profile in {WRITE_PROFILE, LOGIN_PROFILE} and concurrency != 1:
        print(
            f"error: profile {args.profile} is sequential; --concurrency must be 1",
            file=sys.stderr,
        )
        return 1

    timeline = SOAK_TIMELINE if args.profile == "phase3-soak" else PHASE3_TIMELINE
    timeline_total = sum(phase.duration for phase in timeline)
    if args.profile in PHASE3_READ_PROFILES:
        if args.timeline_scale is not None:
            scale = args.timeline_scale
        elif args.duration is not None:
            scale = duration / timeline_total
        else:
            scale = 1.0
        if not math.isfinite(scale) or scale <= 0:
            print("error: --timeline-scale must be a finite number > 0", file=sys.stderr)
            return 1
        duration = timeline_total * scale
        warmup = 0.0
    else:
        scale = 1.0

    base_url = normalize_base_url(args.base_url)
    tokens_path = _as_path(args.tokens)
    require_users = args.profile not in {"smoke", LOGIN_PROFILE}
    try:
        tokens = load_tokens(tokens_path, require_users=require_users)
    except TokenFileError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    credentials: tuple[Credential, ...] = ()
    if args.profile == LOGIN_PROFILE:
        try:
            credentials = load_credentials(_as_path(args.credentials))
        except CredentialsError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1

    notes: list[str] = []
    if args.profile == "smoke" and not tokens_path.is_file():
        notes.append(f"token file not found ({tokens_path}); public scenarios only")
    if args.profile in {"c", "phase3-c"}:
        notes.append(
            f"profile {args.profile} is a stress profile; results find the knee, "
            "not a launch gate"
        )
    if args.profile in PHASE3_READ_PROFILES:
        notes.append(
            "Phase 3F run; does not certify Workers CPU or 1,000-user capacity"
        )
        if args.warmup is not None:
            notes.append("phase3 profiles use timeline phases; --warmup is ignored")
    if args.profile == WRITE_PROFILE:
        notes.append(
            "write probe: COD create/cancel/reschedule only; provider paths refused"
        )
    if args.profile == LOGIN_PROFILE:
        notes.append("login probe: credentials are never serialized")
    if args.profile == "smoke" and any(
        value is not None
        for value in (args.duration, args.rps, args.concurrency, args.warmup)
    ):
        notes.append("smoke ignores --duration/--rps/--concurrency/--warmup; one pass per scenario")

    scenarios: list[Scenario] = []
    if args.profile not in {WRITE_PROFILE, LOGIN_PROFILE}:
        scenario_set = (
            PHASE3_SCENARIOS if args.profile in PHASE3_READ_PROFILES else SCENARIOS
        )
        scenarios, skipped = available_scenarios(tokens, scenario_set)
        notes.extend(skipped)
    for note in notes:
        print(f"note: {note}", file=sys.stderr)

    if args.profile not in {WRITE_PROFILE, LOGIN_PROFILE} and not scenarios:
        print("error: no runnable scenarios", file=sys.stderr)
        return 1

    started = datetime.now(UTC)
    started_at = _iso_utc(started)
    if args.output:
        output_path = _as_path(args.output)
    else:
        stamp = started.strftime("%Y%m%dT%H%M%SZ")
        prefix = (
            "phase3"
            if args.profile in PHASE3_READ_PROFILES
            or args.profile in {WRITE_PROFILE, LOGIN_PROFILE}
            else "phase0"
        )
        output_path = DEFAULT_RESULTS_DIR / f"{prefix}-{args.profile}-{stamp}.json"
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
        elif args.profile in PHASE3_READ_PROFILES:
            outcome = _run_timeline(
                base_url,
                tokens,
                scenarios,
                rps=rps,
                concurrency=concurrency,
                scale=scale,
                max_5xx_pct=args.max_5xx_pct,
                max_p99_ms=args.max_p99_ms,
                timeline=timeline,
            )
            run_rps = rps
            run_concurrency = concurrency
            run_warmup = 0.0
            run_duration = duration
        elif args.profile == WRITE_PROFILE:
            outcome = _run_write(
                base_url,
                tokens,
                rps=rps,
                duration=duration,
                pool_size=args.pool_size,
                max_5xx_pct=args.max_5xx_pct,
                max_p99_ms=args.max_p99_ms,
            )
            run_rps = rps
            run_concurrency = 1
            run_warmup = 0.0
            run_duration = duration
        elif args.profile == LOGIN_PROFILE:
            outcome = _run_login(
                base_url,
                credentials,
                rps=rps,
                duration=duration,
                max_5xx_pct=args.max_5xx_pct,
                max_p99_ms=args.max_p99_ms,
            )
            run_rps = rps
            run_concurrency = 1
            run_warmup = 0.0
            run_duration = duration
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
