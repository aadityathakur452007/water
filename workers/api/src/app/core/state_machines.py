"""Central State Machines & Lifecycle Invariant Rules (034 / ADR-201 / Phase 1 Hardening).

Defines canonical transition tables and domain invariant validators for:
1. Orders & Order-Payment cross-state invariants
2. Delivery-Code (PoD OTP) states
3. Late-capture refund actions

Zero external dependencies; pure Python.
"""

from __future__ import annotations

from typing import Final, Literal

from app.core.errors import AppError, ConflictError


class NeedDispatchOverrideError(AppError):
    code = "NEED_DISPATCH_OVERRIDE"
    status_code = 409


class InvalidStateTransitionError(ConflictError):
    code = "STATE_CONFLICT"


# -- Order State Machine --------------------------------------------------------

# Legal transitions per contract §2 + ADR-201 (autonomous assigned -> delivered)
LEGAL_ORDER_TRANSITIONS: Final[dict[str, set[str]]] = {
    "placed": {"accepted", "rejected", "cancelled"},
    "accepted": {"picked", "cancelled"},
    "picked": {"packed", "cancelled"},
    "packed": {"assigned", "cancelled"},
    "assigned": {"dispatched", "delivered", "cancelled"},
    "dispatched": {"delivered", "failed", "cancelled"},
    "failed": {"dispatched", "cancelled"},
    "delivered": set(),
    "rejected": set(),
    "cancelled": set(),
}

OVERRIDE_FROM: Final[set[str]] = {"assigned", "dispatched"}
OVERRIDE_ROLES: Final[set[str]] = {"dispatcher", "admin"}

TERMINAL_ORDER_STATES: Final[set[str]] = {"delivered", "cancelled", "rejected"}
DEAD_ORDER_STATES: Final[set[str]] = {"cancelled", "rejected"}
RESCHEDULABLE_ORDER_STATES: Final[set[str]] = {"placed", "accepted", "picked", "packed", "assigned"}

# -- Payment Statuses & Mode Invariants -----------------------------------------

PAID_STATUSES: Final[set[str]] = {"paid_upi", "paid_cash", "partial_dues"}
UNPAID_STATUSES: Final[set[str]] = {"unpaid", "link_sent"}

# -- Delivery Code (PoD OTP) States --------------------------------------------

DELIVERY_CODE_STATES: Final[frozenset[str]] = frozenset({
    "none",
    "active",
    "expired",
    "locked",
    "unavailable",
    "used",
})


# -- Invariant Validation Functions ---------------------------------------------


def validate_order_transition(
    from_state: str,
    to_state: str,
    actor_role: str = "user",
) -> None:
    """Validate order state transition legality and role override guards.

    Raises InvalidStateTransitionError if illegal, or NeedDispatchOverrideError
    if dispatcher override permissions are missing.
    """
    legal_next = LEGAL_ORDER_TRANSITIONS.get(from_state, set())
    if to_state not in legal_next:
        raise InvalidStateTransitionError(
            message=f"Illegal transition {from_state} -> {to_state}.",
            details={"from": from_state, "to": to_state},
        )
    if from_state in OVERRIDE_FROM and to_state == "cancelled" and actor_role not in OVERRIDE_ROLES:
        raise NeedDispatchOverrideError(
            message="Post-assign cancel needs the dispatcher. Call support to cancel.",
            details={"from": from_state, "to": to_state},
        )


def validate_late_capture_action(order_state: str) -> Literal["credit", "refund"]:
    """Decide webhook ingestion behavior when money capture is confirmed.

    If the order is already in a dead terminal state (cancelled/rejected),
    the money MUST be refunded rather than crediting a dead order.
    """
    if order_state in DEAD_ORDER_STATES:
        return "refund"
    return "credit"


def validate_delivery_resolution(
    *,
    payment_mode: str,
    payment_status: str,
    is_subscription: bool = False,
    is_monthly_dues: bool = False,
    cash_collected: bool = False,
    amount_due: int = 0,
) -> tuple[bool, str]:
    """Verify that an order being delivered has valid financial settlement.

    Returns (is_valid, reason).
    """
    if payment_status in ("paid_upi", "paid_cash"):
        return True, "payment_confirmed"

    # Daily subscription delivery with ₹0 due today (monthly billing)
    if is_subscription and not is_monthly_dues and amount_due == 0:
        return True, "subscription_refill_zero_due"

    # Month-end dues or COD where cash was physically collected at the doorstep
    if cash_collected and amount_due >= 0:
        return True, "cash_collected_doorstep"

    # Subscription with pending monthly dues but uncollected cash
    if is_monthly_dues and amount_due > 0 and not cash_collected:
        return False, "monthly_dues_unconfirmed"

    # Unpaid COD with no cash collected
    if payment_mode == "cod" and amount_due > 0 and not cash_collected:
        return False, "cash_collection_unconfirmed"

    # Unsettled UPI
    if payment_mode == "upi" and payment_status in UNPAID_STATUSES:
        return False, "upi_unsettled"

    return True, "ok"


def validate_switch_to_cod(
    current_mode: str,
    current_status: str,
    order_state: str,
) -> None:
    """Validate switching payment mode from UPI to COD.

    Raises ConflictError if payment is already captured or order cannot be paid.
    """
    if order_state in DEAD_ORDER_STATES:
        raise ConflictError(
            message="Cancelled or rejected orders cannot change payment mode.",
            details={"state": order_state},
        )
    if current_mode == "cod":
        return
    if current_status in ("paid_upi", "paid_cash"):
        raise ConflictError(
            message="Paid orders cannot switch payment mode.",
            details={"payment_status": current_status},
        )


# -- Operational Defaults & Capacity Calculations (Phase 3 Hardening) -----------

DEFAULT_MAX_STOPS_PER_SHIFT: Final[int] = 25
DEFAULT_MAX_JARS_PER_SHIFT: Final[int] = 250


def calculate_vendor_capacity_headroom(
    current_stops: int,
    current_jars: int,
    max_stops: int = DEFAULT_MAX_STOPS_PER_SHIFT,
    max_jars: int = DEFAULT_MAX_JARS_PER_SHIFT,
) -> dict:
    """Calculate remaining stops and jars headroom and capacity status.

    Vendors operate with significant volume (up to 5,000 jars across multi-trip routes).
    Returns remaining quota, utilization percentage, and full status.
    """
    effective_max_stops = max(1, max_stops)
    effective_max_jars = max(1, max_jars)
    stops_left = max(0, effective_max_stops - current_stops)
    jars_left = max(0, effective_max_jars - current_jars)
    utilization_pct = round(
        max(current_stops / effective_max_stops, current_jars / effective_max_jars) * 100, 1
    )
    return {
        "stops_remaining": stops_left,
        "jars_remaining": jars_left,
        "stops_utilized": current_stops,
        "jars_utilized": current_jars,
        "max_stops": effective_max_stops,
        "max_jars": effective_max_jars,
        "utilization_pct": min(100.0, utilization_pct),
        "is_full": stops_left == 0 or jars_left == 0,
    }


# -- Rider Duty State Machine ---------------------------------------------------

LEGAL_RIDER_DUTY_TRANSITIONS: Final[dict[str, set[str]]] = {
    "off_duty": {"on_duty"},
    "on_duty": {"off_duty", "shift_ended"},
    "shift_ended": {"off_duty", "on_duty"},
}


def validate_rider_duty_transition(from_state: str, to_state: str) -> None:
    """Validate rider duty progression legality."""
    legal_next = LEGAL_RIDER_DUTY_TRANSITIONS.get(from_state, set())
    if to_state not in legal_next:
        raise InvalidStateTransitionError(
            message=f"Illegal rider duty transition {from_state} -> {to_state}.",
            details={"from": from_state, "to": to_state},
        )


# -- Return & Deposit Refund State Machine --------------------------------------

LEGAL_RETURN_TRANSITIONS: Final[dict[str, set[str]]] = {
    "requested": {"assigned", "rejected"},
    "assigned": {"picked", "rejected"},
    "picked": {"refunded", "rejected"},
    "refunded": set(),
    "rejected": set(),
}


def validate_return_transition(from_state: str, to_state: str) -> None:
    """Validate customer jar return lifecycle legality."""
    legal_next = LEGAL_RETURN_TRANSITIONS.get(from_state, set())
    if to_state not in legal_next:
        raise InvalidStateTransitionError(
            message=f"Illegal return transition {from_state} -> {to_state}.",
            details={"from": from_state, "to": to_state},
        )
