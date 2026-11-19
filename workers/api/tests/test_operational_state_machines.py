"""Unit and integration tests for Phase 3 Operational State Machines & Vendor Capacity.

Tests:
- Mindful vendor capacity defaults (250 jars, 50 stops, headroom calculation)
- Dynamic headroom calculation for standard and large commercial fleets
- _check_capacity elevates legacy 60 to 250 and enforces mindful limits
- Rider duty state transitions (off_duty, on_duty, shift_ended)
- Rider off-duty delivery block invariant
- Return state machine transitions and double-refund prevention
"""

import datetime as _dt
from pathlib import Path
import pytest

from app.core.errors import ValidationError
from app.core.state_machines import (
    DEFAULT_MAX_JARS_PER_SHIFT,
    DEFAULT_MAX_STOPS_PER_SHIFT,
    InvalidStateTransitionError,
    LEGAL_RETURN_TRANSITIONS,
    LEGAL_RIDER_DUTY_TRANSITIONS,
    calculate_vendor_capacity_headroom,
    validate_return_transition,
    validate_rider_duty_transition,
)
from app.db import get_connection
from app.db_d1 import AsyncSqliteConn
from app.services.dispatch_service import (
    CapacityExceededError,
    _check_capacity,
    ensure_profile,
)
from app.services.rider_service import RiderService


API_ROOT = Path(__file__).resolve().parents[1]
M002 = (API_ROOT / "src" / "app" / "db" / "migrations" / "002_auth.sql").read_text()
M003 = (API_ROOT / "src" / "app" / "db" / "migrations" / "003_addresses.sql").read_text()
M004 = (API_ROOT / "src" / "app" / "db" / "migrations" / "004_orders.sql").read_text()
M005 = (API_ROOT / "src" / "app" / "db" / "migrations" / "005_payments.sql").read_text()
M007 = (API_ROOT / "src" / "app" / "db" / "migrations" / "007_ops.sql").read_text()
M010 = (API_ROOT / "src" / "app" / "db" / "migrations" / "010_config_audit.sql").read_text()
M014 = (API_ROOT / "src" / "app" / "db" / "migrations" / "014_access_codes.sql").read_text()
M015 = (API_ROOT / "src" / "app" / "db" / "migrations" / "015_pod_otp.sql").read_text()
M016 = (API_ROOT / "src" / "app" / "db" / "migrations" / "016_stop_fields.sql").read_text()
M024 = (API_ROOT / "src" / "app" / "db" / "migrations" / "024_user_assigned_vendor.sql").read_text()
M030 = (API_ROOT / "src" / "app" / "db" / "migrations" / "030_rider_dispatch.sql").read_text()

NOW_ISO = _dt.datetime.now(_dt.timezone.utc).isoformat()
DAY = (_dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(hours=5, minutes=30)).date().isoformat()


def _make_test_conn():
    c = get_connection(":memory:")
    c.executescript(M002 + M003 + M004 + M005 + M007 + M010 + M014 + M015 + M016 + M024 + M030)
    c.execute(
        "INSERT INTO users (id, phone, name, role, created_at) VALUES "
        "('v1', '+919876500001', 'Vendor Alpha', 'vendor', ?), "
        "('r1', '+919876500002', 'Rider Shyam', 'rider', ?)",
        (NOW_ISO, NOW_ISO),
    )
    c.commit()
    return AsyncSqliteConn(c)


# -- Vendor Capacity Hardening Tests -------------------------------------------


def test_vendor_capacity_mindful_defaults():
    assert DEFAULT_MAX_STOPS_PER_SHIFT == 25
    assert DEFAULT_MAX_JARS_PER_SHIFT == 250


def test_calculate_vendor_capacity_headroom_standard():
    # Vendor has delivered 100 jars out of standard 250 default
    headroom = calculate_vendor_capacity_headroom(
        current_stops=20,
        current_jars=100,
    )
    assert headroom["stops_remaining"] == 5
    assert headroom["jars_remaining"] == 150
    assert headroom["is_full"] is False
    assert headroom["utilization_pct"] == 80.0


def test_calculate_vendor_capacity_headroom_commercial_fleet():
    # Commercial vehicle with 1,500 jar capacity
    headroom = calculate_vendor_capacity_headroom(
        current_stops=120,
        current_jars=1200,
        max_stops=200,
        max_jars=1500,
    )
    assert headroom["stops_remaining"] == 80
    assert headroom["jars_remaining"] == 300
    assert headroom["is_full"] is False
    assert headroom["utilization_pct"] == 80.0


def test_calculate_vendor_capacity_headroom_full():
    headroom = calculate_vendor_capacity_headroom(
        current_stops=50,
        current_jars=250,
        max_stops=50,
        max_jars=250,
    )
    assert headroom["stops_remaining"] == 0
    assert headroom["jars_remaining"] == 0
    assert headroom["is_full"] is True
    assert headroom["utilization_pct"] == 100.0


@pytest.mark.asyncio
async def test_check_capacity_elevates_legacy_and_allows_mindful_volume():
    conn = _make_test_conn()
    # Ensure profile and set legacy 60 jars limit
    await ensure_profile(conn, "v1")
    await conn.execute("UPDATE vendor_profile SET max_jars_per_shift = 60 WHERE user_id = 'v1'")
    conn.commit()

    # Delivering 120 jars would fail under old 60 limit, but succeeds under mindful 250 limit
    await _check_capacity(conn, "v1", need_jars=120, date=DAY)

    # Exceeding mindful 250 (e.g. 260 jars) raises CapacityExceededError
    with pytest.raises(CapacityExceededError):
        await _check_capacity(conn, "v1", need_jars=260, date=DAY)


@pytest.mark.asyncio
async def test_check_capacity_custom_large_fleet():
    conn = _make_test_conn()
    await ensure_profile(conn, "v1")
    await conn.execute(
        "UPDATE vendor_profile SET max_stops_per_shift = 300, max_jars_per_shift = 3000 WHERE user_id = 'v1'"
    )
    conn.commit()

    # Delivers 1,500 jars comfortably
    await _check_capacity(conn, "v1", need_jars=1500, date=DAY)


# -- Rider Duty State Machine Tests --------------------------------------------


def test_rider_duty_legal_transitions():
    validate_rider_duty_transition("off_duty", "on_duty")
    validate_rider_duty_transition("on_duty", "off_duty")
    validate_rider_duty_transition("on_duty", "shift_ended")
    validate_rider_duty_transition("shift_ended", "off_duty")
    validate_rider_duty_transition("shift_ended", "on_duty")


def test_rider_duty_illegal_transitions():
    with pytest.raises(InvalidStateTransitionError):
        validate_rider_duty_transition("off_duty", "shift_ended")

    with pytest.raises(InvalidStateTransitionError):
        validate_rider_duty_transition("unknown_state", "on_duty")


@pytest.mark.asyncio
async def test_rider_duty_persistence_and_gate():
    conn = _make_test_conn()
    rider = RiderService(conn)
    rider_id = "r1"

    # Default duty is on_duty for compatibility
    status = await rider.get_duty(rider_id)
    assert status["duty_status"] == "on_duty"

    # Transition to off_duty
    res = await rider.set_duty(rider_id, "off_duty")
    assert res["duty_status"] == "off_duty"
    refreshed = await rider.get_duty(rider_id)
    assert refreshed["duty_status"] == "off_duty"

    # Transition to shift_ended fails directly from off_duty
    with pytest.raises(InvalidStateTransitionError):
        await rider.set_duty(rider_id, "shift_ended")

    # Transition back to on_duty succeeds
    await rider.set_duty(rider_id, "on_duty")
    refreshed = await rider.get_duty(rider_id)
    assert refreshed["duty_status"] == "on_duty"

    # Transition from on_duty to shift_ended succeeds
    await rider.set_duty(rider_id, "shift_ended")
    refreshed = await rider.get_duty(rider_id)
    assert refreshed["duty_status"] == "shift_ended"


@pytest.mark.asyncio
async def test_rider_off_duty_delivery_gate():
    conn = _make_test_conn()
    rider = RiderService(conn)
    rider_id = "r1"

    # Set rider off duty
    await rider.set_duty(rider_id, "off_duty")

    # Completing or failing a stop when off duty must raise ValidationError
    with pytest.raises(ValidationError) as exc_complete:
        await rider.complete_stop(rider_id, "dummy-stop-id", {})
    assert "on duty" in str(exc_complete.value.message).lower()

    with pytest.raises(ValidationError) as exc_fail:
        await rider.fail_stop(rider_id, "dummy-stop-id", "Customer unreachable")
    assert "on duty" in str(exc_fail.value.message).lower()


# -- Return & Deposit Refund State Machine Tests --------------------------------


def test_return_legal_transitions():
    validate_return_transition("requested", "assigned")
    validate_return_transition("requested", "rejected")
    validate_return_transition("assigned", "picked")
    validate_return_transition("assigned", "rejected")
    validate_return_transition("picked", "refunded")
    validate_return_transition("picked", "rejected")


def test_return_illegal_transitions():
    # Cannot jump from requested straight to refunded without being picked
    with pytest.raises(InvalidStateTransitionError):
        validate_return_transition("requested", "refunded")

    # Terminal states cannot transition
    with pytest.raises(InvalidStateTransitionError):
        validate_return_transition("refunded", "requested")

    with pytest.raises(InvalidStateTransitionError):
        validate_return_transition("refunded", "picked")

    with pytest.raises(InvalidStateTransitionError):
        validate_return_transition("rejected", "assigned")


def test_order_assigned_to_failed_transition():
    from app.core.state_machines import validate_order_transition, LEGAL_ORDER_TRANSITIONS
    assert "failed" in LEGAL_ORDER_TRANSITIONS["assigned"]
    validate_order_transition("assigned", "failed", "vendor")

