# Implementation Plan: Phase 1 State Machine Hardening

## Architecture & Scope
Following Ponytail principles (minimal code, zero new external dependencies, shortest working diff), we will formalize the critical fulfillment and money flow state machines with lightweight, typed transition tables and explicit invariant validators.

### 1. Backend Core State Machine Module (`workers/api/src/app/core/state_machines.py`)
- Define enums / constants:
  - `OrderState`: `placed`, `accepted`, `picked`, `packed`, `assigned`, `dispatched`, `delivered`, `failed`, `cancelled`, `rejected`.
  - `PaymentStatus`: `unpaid`, `link_sent`, `paid_upi`, `paid_cash`, `partial_dues`, `refund_pending`.
  - `DeliveryCodeState`: `none`, `active`, `expired`, `locked`, `unavailable`, `used`.
- Transition Tables:
  - `LEGAL_ORDER_TRANSITIONS`: Source of truth for state transitions (supports autonomous `assigned -> delivered` from ADR-201 and dispatcher override for `cancelled`).
  - `LEGAL_PAYMENT_TRANSITIONS`: Rules for advancing payment statuses.
  - `TERMINAL_ORDER_STATES`: `{'delivered', 'cancelled', 'rejected'}`.
- Invariant Validators:
  - `validate_order_transition(from_state, to_state, actor_role)`: Validates state progression or raises `StateConflictError` / `NeedDispatchOverrideError`.
  - `validate_delivery_resolution(order_state, payment_mode, payment_status, is_subscription, cash_received)`: Ensures an order cannot transition to `delivered` in an ambiguous financial state.
  - `validate_late_capture_action(order_state)`: Returns `"refund"` if order is in a terminal non-delivered state (`cancelled`, `rejected`), or `"credit"` if active.

### 2. Service & Repository Integration
- **`order_repo.py`**:
  - Import `LEGAL_ORDER_TRANSITIONS`, `OVERRIDE_FROM`, `OVERRIDE_ROLES` from `app.core.state_machines`.
  - Replace duplicate definitions to ensure a single system-wide source of truth.
- **`payment_service.py`**:
  - Update `webhook_ingest()` to invoke `validate_late_capture_action(order.state)`. If `"refund"`, auto-queue the refund immediately rather than setting `payment_status = 'paid_upi'` on a dead order.
  - Update `switch_to_cod()` to ensure `payment_status` is legal for mode switching.
- **`delivery_code.py`**:
  - Standardize `state()` and `reissue_available()` against `DeliveryCodeState`.

### 3. Rider App Doorstep Handover State Machine (`apps/rider_app`)
- **`pod_sheet.dart`**:
  - Define `enum HandoverMode { dailySubscription, monthEndDues, standardCod, prepaid }`.
  - Implement pure resolution function:
    ```dart
    HandoverMode resolveHandoverMode(Map<String, dynamic> stop) {
      final isSub = stop['is_subscription'] == true;
      final isDues = stop['is_monthly_dues'] == true;
      final isCod = stop['payment_mode'] == 'cod';
      final amountDue = (stop['amount_due'] as num?)?.toInt() ?? 0;
      final isPaid = stop['payment_status'] == 'paid_upi';

      if (isSub && !isDues) return HandoverMode.dailySubscription;
      if (isDues && amountDue > 0) return HandoverMode.monthEndDues;
      if (!isSub && isCod && amountDue > 0) return HandoverMode.standardCod;
      if (isPaid || amountDue == 0) return HandoverMode.prepaid;
      return HandoverMode.standardCod;
    }
    ```
  - Cleanly drive banner display, cash confirmation requirement, and submission validation using `switch (mode)`.

### 4. Tests & Invariant Verification
- `workers/api/tests/test_state_machines.py`:
  - Unit tests for all legal and illegal transitions.
  - Late UPI capture refund guard tests.
  - Delivery resolution invariant tests.
- `apps/rider_app/test/pod_sheet_test.dart`:
  - Unit tests for `resolveHandoverMode` and doorstep validation rules.
