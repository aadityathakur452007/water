"""Thin address business rules (Service layer — no DB, no HTTP).

- serviceability(): SERVICEABLE_PREFIXES env allowlist, empty = open (mirrors
  catalog.py slice-1 pattern; B1 owns Settings so env is read here, not added
  to config.py which is another agent's file).
- needs_pin_confirm(): GPS accuracy rule (contract §4.3 EC-G, C10):
  accuracy_m > 100m → force map-pin confirm, delivery still allowed.
- lookup_zone(): STUB — returns None. Zone router (pincode → zone, GPS polygon
  fallback) ships with slice-3 dispatch; callers must handle None as
  "unassigned → placed + needs_dispatch" per contract §9.1.
- verify_place_id_stub(): STUB — server-side Google re-verify lands when the
  Maps key exists; currently echoes place_id (mismatch → 422 comes later).
"""

from app.core.worker_env import env_get

PIN_CONFIRM_THRESHOLD_M = 100.0


def _prefixes() -> list[str]:
    raw = env_get("SERVICEABLE_PREFIXES", "") or ""
    return [p.strip() for p in raw.split(",") if p.strip()]


def serviceability(pincode: str) -> bool:
    """True if pincode is serviceable. Empty allowlist = open."""
    prefixes = _prefixes()
    return not prefixes or any(pincode.startswith(p) for p in prefixes)


# Alias matching catalog.py naming for grease.
is_serviceable = serviceability


def needs_pin_confirm(accuracy_m: float | None) -> bool:
    """True when the GPS fix is too coarse and the user must confirm a map pin."""
    return accuracy_m is not None and accuracy_m > PIN_CONFIRM_THRESHOLD_M


def lookup_zone(pincode: str, lat: float, lng: float) -> None:  # noqa: ARG001
    """STUB: zone lookup ships with slice-3 dispatch. Always None for now."""
    return None


def verify_place_id_stub(place_id: str | None) -> str | None:
    """STUB: echo place_id until server-side Google verification is wired."""
    return place_id
