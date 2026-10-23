"""Delivery-handoff code rules (034).

The code is a short-lived secret the customer reads to the rider. It is
minted at assignment, armed for 24h at dispatch, and cleared on use, terminal
failure/cancel, expiry, or lockout. No deterministic order-id/date fallback is
accepted for an active stop.
"""

from __future__ import annotations

import datetime as _dt
import secrets

TTL_HOURS = 24
MAX_ATTEMPTS = 5
REISSUE_LIMIT = 3
REISSUE_WINDOW_HOURS = 24

STATES = frozenset({"none", "active", "expired", "locked", "unavailable", "used"})


def now() -> _dt.datetime:
    return _dt.datetime.now(_dt.timezone.utc)


def iso(value: _dt.datetime | None = None) -> str:
    return (value or now()).isoformat()


def expires_at(value: _dt.datetime | None = None) -> str:
    return ((value or now()) + _dt.timedelta(hours=TTL_HOURS)).isoformat()


def parse(value: str | None) -> _dt.datetime | None:
    if not value:
        return None
    try:
        parsed = _dt.datetime.fromisoformat(str(value))
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=_dt.timezone.utc)
    return parsed


def expired(value: str | None, at: _dt.datetime | None = None) -> bool:
    """True when a timestamp is present and at/past its expiry.

    A malformed timestamp is treated as expired: never keep a code whose
    lifetime cannot be proven.
    """
    if not value:
        return False
    parsed = parse(value)
    if parsed is None:
        return True
    return parsed <= (at or now())


def mint() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def state(
    *,
    order_state: str,
    stop_status: str | None,
    code: str | None,
    code_expires_at: str | None,
    attempts: int | None,
    at: _dt.datetime | None = None,
) -> str:
    """Resolve the customer-visible delivery-code state.

    ``assigned`` with no code is ``none`` (the code is normally minted at
    assignment); ``dispatched`` with no code is ``unavailable`` so the UI can
    offer a reissue. A delivered order is ``used`` even though the stop row is
    already done.
    """
    if order_state == "delivered":
        return "used"
    if order_state not in ("assigned", "dispatched"):
        return "none"
    if stop_status not in (None, "pending"):
        return "none"
    if int(attempts or 0) >= MAX_ATTEMPTS:
        return "locked"
    if expired(code_expires_at, at):
        return "expired"
    if not code:
        return "unavailable" if order_state == "dispatched" else "none"
    return "active"


def reissue_available(
    *, order_state: str, stop_status: str | None, code_state: str
) -> bool:
    return (
        order_state == "dispatched"
        and stop_status == "pending"
        and code_state in {"expired", "locked", "unavailable"}
    )
