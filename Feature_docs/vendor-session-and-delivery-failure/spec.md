# Specification: Vendor App Session Persistence & Delivery Failure Sync

**Author:** Antigravity  
**Date:** 2026-11-19  
**Status:** Under User Review (Design Approval Phase)

---

## 1. Problem Statement

1. **Vendor App Unwanted Daily Logouts (Session Eviction)**:
   - **User Feedback**: *"my vendor app logout on its own after 24 hr or something please handle it with care"*
   - **Root Cause Identified**:
     - In `apps/vendor_app/lib/features/auth/auth_controller.dart:345`, `restoreSession()` reads `expiresAtIso` (the access token expiry, 30m–24h).
     - When the vendor closes the app and re-opens it the next morning (or after 24h), `DateTime.now().isAfter(expiresAt)` is `true`.
     - `restoreSession()` immediately executes `await _store.clear()`, wiping the stored access token and refresh token, and dumping the vendor on the login screen every day.
     - Even though a valid `refreshToken` exists (valid for up to 30 days in `workers/api`), `vendor_app` never attempted to silently refresh the session during cold-boot restore.
     - Furthermore, if temporary poor network connectivity occurs on boot, wiping credentials would be catastrophic.

2. **Vendor Cancelled Delivery Still Shows as "Will Deliver" on User Screen**:
   - **User Feedback**: *"vendor cancled the delivery beacuse of certain reason but in the user screen nothing shows and showing it will deliver that is the problem"*
   - **Root Cause Identified**:
     - When a vendor reports a delivery failure / RTO (e.g. Door Locked, Customer Unreachable) via `POST /v1/vendor/stops/{stop_id}/fail`, `vendor_service.py:719` attempts `OrderRepo.transition(stop["order_id"], "failed", ...)`.
     - In `workers/api/src/app/core/state_machines.py`, `LEGAL_ORDER_TRANSITIONS["assigned"] = {"dispatched", "delivered", "cancelled"}`.
     - Crucially, `"failed"` is **NOT** listed in `LEGAL_ORDER_TRANSITIONS["assigned"]`!
     - In our autonomous delivery architecture (ADR-201 / ADR-197), vendor deliveries run in `"assigned"` state. When the vendor marks the stop failed, `validate_order_transition("assigned", "failed")` throws `InvalidStateTransitionError: Illegal transition assigned -> failed`.
     - In `vendor_service.py:722`, `except Exception: pass` silently swallowed this error.
     - Consequently, `stops.status` became `'failed'`, but `orders.state` remained stuck in `'assigned'`!
     - On the customer app (`customer_home_screen.dart` & `tracking_screen.dart`), orders in `'assigned'` state are treated as active and display: *"Assigned to delivery partner · Arriving soon / Will deliver"*!
     - Additionally, the customer app never received the failure reason (e.g., Door Locked, Customer Unreachable) in the order response.

---

## 2. Architecture & Design Decisions

### A. Vendor App Session Persistence & Silent Auto-Renew

1. **Auto-Recovery on App Launch (`apps/vendor_app/lib/features/auth/auth_controller.dart`)**:
   - In `restoreSession()`, when `DateTime.now().isAfter(expiresAt)`:
     - Check if a `refreshToken` exists.
     - Attempt silent renewal via `await refreshSession()`.
     - If `refreshSession()` succeeds: update stored session tokens and set `_status = AuthStatus.authenticated`. The vendor proceeds straight to the dashboard without entering their code again.
     - If `refreshSession()` fails with a network exception (offline / poor cellular connection): **DO NOT WIPE THE STORE**. Retain the session and allow the vendor to proceed (offline sync outbox remains intact).
     - If `refreshSession()` fails with a true 401/expired rejection from server (e.g., after the absolute 30-day cap or explicit admin revocation): only then execute `await _store.clear()`, set `_status = AuthStatus.idle`, and surface the honest session expired notice.

### B. State Machine Fix & Customer Delivery Failure Surfacing

1. **Backend State Machine (`workers/api/src/app/core/state_machines.py`)**:
   - Update `LEGAL_ORDER_TRANSITIONS`:
     ```python
     "assigned": {"dispatched", "delivered", "failed", "cancelled"},
     ```
   - This permits autonomous vendor delivery failure directly from the `"assigned"` state without throwing an exception.

2. **Backend Error Propagation & Stop Failure Handling (`workers/api/src/app/services/vendor_service.py`)**:
   - In `fail_stop()`: ensure `OrderRepo.transition(stop["order_id"], "failed", ...)` succeeds.
   - Log any failure explicitly (`log.error(...)`) rather than a blank `pass`.
   - Update `OrderDetailOut` (`workers/api/src/app/schemas/orders.py` and `order_service.py:detail`) to include `failure_reason` and `failure_code` extracted from the stop row.

3. **Customer App Failure Notification & Screen Updates (`apps/user_app_donor`)**:
   - **`orders_controller.dart`**: Parse `failure_reason` on `Order`.
   - **`customer_home_screen.dart`**:
     - When an order transitions to `OrderState.failed`, it immediately disappears from `_ActiveDeliveryCard` ("Arriving soon").
     - Renders a prominent, informative status alert banner if today's order was marked failed:
       *"Today's delivery could not be completed (${formattedReason}). Tap for options or to contact support."*
   - **`tracking_screen.dart`**:
     - Replaces 4-step progress dots with high-contrast red alert banner displaying the exact vendor reason:
       - `DOOR_LOCKED`: *"Delivery attempted — Door was locked. Keep your empty jar ready for the next attempt."*
       - `CUSTOMER_UNREACHABLE`: *"Delivery attempted — Phone was unreachable."*
       - `CUSTOMER_REFUSED`: *"Delivery cancelled — Customer refused delivery."*
       - `INCORRECT_ADDRESS`: *"Delivery failed — Address incomplete or unreachable."*
       - `RESCHEDULE_REQUESTED`: *"Delivery rescheduled on request."*
     - Action button immediately switches to *"Talk to Support"* or *"Reschedule Delivery"*.
   - **`order_card.dart`**: Displays `Delivery failed` status pill in red with the failure reason subtitle.

---

## 3. Verification Plan

1. **Vendor Auth Session Tests (`apps/vendor_app/test/phase05_splita_test.dart`)**:
   - Test cold boot with expired access token and valid refresh token: verifies `restoreSession()` silently renews and keeps vendor authenticated.
   - Test cold boot with network timeout: verifies store is NOT wiped.
   - Test cold boot after 30-day cap: verifies polite logout.
2. **Backend Transition & Failure Tests (`workers/api/tests/test_operational_state_machines.py`)**:
   - Test `fail_stop` on an order in `"assigned"` state: verifies order transitions to `"failed"`, stop status is `"failed"`, and failure reason is recorded.
   - Test `GET /v1/orders/{id}`: verifies `state == "failed"` and `failure_reason` is returned.
3. **Customer App Widget Tests (`apps/user_app_donor/test/tracking_screen_test.dart`)**:
   - Test that when an order is `OrderState.failed`, tracking screen displays the formatted failure reason banner, hides stops ahead / rider call, and shows support CTA.
   - Test that `customer_home_screen.dart` does NOT show a failed order as an active delivery on the way.
4. **Full Workspace Gate**:
   - `workers/api`: `uv run pytest` (534+ tests passing).
   - `apps/vendor_app`: `flutter test` and `flutter analyze` (0 issues).
   - `apps/user_app_donor`: `flutter test` and `flutter analyze` (0 issues).
