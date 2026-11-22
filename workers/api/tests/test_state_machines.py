"""Unit tests for Phase 1 State Machine Hardening (app.core.state_machines).

Tests:
- Order state transition legality & role override rules
- Late capture refund guard for dead orders
- Delivery resolution financial invariants
- Switch to COD validation
- Delivery code state definitions
"""

import pytest

from app.core.errors import ConflictError
from app.core.state_machines import (
    DELIVERY_CODE_STATES,
    LEGAL_ORDER_TRANSITIONS,
    NeedDispatchOverrideError,
    validate_delivery_resolution,
    validate_late_capture_action,
    validate_order_transition,
    validate_switch_to_cod,
)


def test_legal_order_transitions():
    # Valid forward progressions
    validate_order_transition("placed", "accepted", "admin")
    validate_order_transition("accepted", "picked", "vendor")
    validate_order_transition("picked", "packed", "vendor")
    validate_order_transition("packed", "assigned", "admin")
    validate_order_transition("assigned", "dispatched", "vendor")
    validate_order_transition("dispatched", "delivered", "vendor")

    # Autonomous delivery progression (ADR-201)
    validate_order_transition("assigned", "delivered", "vendor")

    # Retry failed delivery
    validate_order_transition("dispatched", "failed", "vendor")
    validate_order_transition("failed", "dispatched", "vendor")


def test_illegal_order_transitions_raise():
    # Cannot jump steps
    with pytest.raises(ConflictError):
        validate_order_transition("placed", "delivered", "admin")

    with pytest.raises(ConflictError):
        validate_order_transition("accepted", "delivered", "vendor")

    # Terminal states have no outbound transitions
    with pytest.raises(ConflictError):
        validate_order_transition("delivered", "assigned", "admin")

    with pytest.raises(ConflictError):
        validate_order_transition("cancelled", "placed", "user")

    with pytest.raises(ConflictError):
        validate_order_transition("rejected", "accepted", "admin")


def test_cancellation_role_override_guard():
    # Placed order can be cancelled by user
    validate_order_transition("placed", "cancelled", "user")

    # Assigned or Dispatched order can now also be self-cancelled by user (ADR-214)
    validate_order_transition("assigned", "cancelled", "user")
    validate_order_transition("dispatched", "cancelled", "user")

    # Assigned or Dispatched can be cancelled by dispatcher or admin
    validate_order_transition("assigned", "cancelled", "dispatcher")
    validate_order_transition("assigned", "cancelled", "admin")
    validate_order_transition("dispatched", "cancelled", "dispatcher")
    validate_order_transition("dispatched", "cancelled", "admin")


def test_late_capture_action():
    # Dead orders must trigger a refund
    assert validate_late_capture_action("cancelled") == "refund"
    assert validate_late_capture_action("rejected") == "refund"

    # Active or delivered orders credit normally
    assert validate_late_capture_action("placed") == "credit"
    assert validate_late_capture_action("assigned") == "credit"
    assert validate_late_capture_action("dispatched") == "credit"
    assert validate_late_capture_action("delivered") == "credit"


def test_delivery_resolution_invariants():
    # 1. Paid UPI order
    valid, reason = validate_delivery_resolution(
        payment_mode="upi",
        payment_status="paid_upi",
        amount_due=0,
    )
    assert valid is True
    assert reason == "payment_confirmed"

    # 2. Daily subscription refill (monthly postpaid, ₹0 due today)
    valid, reason = validate_delivery_resolution(
        payment_mode="cod",
        payment_status="unpaid",
        is_subscription=True,
        is_monthly_dues=False,
        amount_due=0,
    )
    assert valid is True
    assert reason == "subscription_refill_zero_due"

    # 3. Daily subscription refill with month-end dues unconfirmed
    valid, reason = validate_delivery_resolution(
        payment_mode="cod",
        payment_status="unpaid",
        is_subscription=True,
        is_monthly_dues=True,
        cash_collected=False,
        amount_due=5600,
    )
    assert valid is False
    assert reason == "monthly_dues_unconfirmed"

    # 4. Daily subscription refill with month-end dues collected
    valid, reason = validate_delivery_resolution(
        payment_mode="cod",
        payment_status="unpaid",
        is_subscription=True,
        is_monthly_dues=True,
        cash_collected=True,
        amount_due=5600,
    )
    assert valid is True
    assert reason == "cash_collected_doorstep"

    # 5. Standard COD without cash collection
    valid, reason = validate_delivery_resolution(
        payment_mode="cod",
        payment_status="unpaid",
        is_subscription=False,
        cash_collected=False,
        amount_due=2800,
    )
    assert valid is False
    assert reason == "cash_collection_unconfirmed"

    # 6. Standard COD with cash collected
    valid, reason = validate_delivery_resolution(
        payment_mode="cod",
        payment_status="unpaid",
        is_subscription=False,
        cash_collected=True,
        amount_due=2800,
    )
    assert valid is True
    assert reason == "cash_collected_doorstep"

    # 7. Unsettled UPI
    valid, reason = validate_delivery_resolution(
        payment_mode="upi",
        payment_status="link_sent",
        amount_due=2800,
    )
    assert valid is False
    assert reason == "upi_unsettled"


def test_validate_switch_to_cod():
    # Valid switch from unpaid UPI to COD
    validate_switch_to_cod("upi", "unpaid", "placed")
    validate_switch_to_cod("upi", "link_sent", "accepted")

    # Already COD is a no-op
    validate_switch_to_cod("cod", "unpaid", "placed")

    # Cannot switch if already paid
    with pytest.raises(ConflictError):
        validate_switch_to_cod("upi", "paid_upi", "placed")

    # Cannot switch on cancelled order
    with pytest.raises(ConflictError):
        validate_switch_to_cod("upi", "unpaid", "cancelled")


def test_delivery_code_states():
    assert "none" in DELIVERY_CODE_STATES
    assert "active" in DELIVERY_CODE_STATES
    assert "expired" in DELIVERY_CODE_STATES
    assert "locked" in DELIVERY_CODE_STATES
    assert "unavailable" in DELIVERY_CODE_STATES
    assert "used" in DELIVERY_CODE_STATES
