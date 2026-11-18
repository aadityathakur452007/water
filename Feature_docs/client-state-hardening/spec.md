# Feature Spec: Phase 2 Mobile Client State Hardening

## 1. Context & Objective
Following the backend and rider doorstep fulfillment hardening (ADR-203, Phase 1), Phase 2 addresses the three critical **client-side state machines** across the customer donor app (`apps/user_app_donor`) and vendor app (`apps/vendor_app`):
1. **Customer Subscription Lifecycle View Model (`apps/user_app_donor`)**: Eliminates overlapping/ambiguous subscription card states by formalizing a single, prioritized `SubscriptionLifecycle` enum.
2. **Vendor Offline Outbox & Reassignment Conflict Handler (`apps/vendor_app`)**: Solves infinite retry loops and cash custody stranding when an offline delivery encounters a `409 STALE_STOP` rejection.
3. **Customer Checkout & Payment Recovery Funnel (`apps/user_app_donor`)**: Consolidates 11+ scattered boolean flags into a typed `CheckoutStage` state machine, strictly enforcing that an order row created in D1 can never be duplicated on payment retries.

---

## 2. Detailed Subsystem Specifications

### A. Customer Subscription Lifecycle State Machine
* **File**: `apps/user_app_donor/lib/features/subscriptions/subscription_controller.dart` & `subscription_screen.dart`
* **Current Vulnerability**: The UI derives status on-the-fly from 8 separate properties (`canceled`, `paused`, `billingStatus`, `billingMode`, `holdFrom`, `holdTo`, `lowBalance`, `dueTodayPaise`).
* **Formal State Machine**:
  ```mermaid
  stateDiagram-v2
      [*] --> Active: Plan Created (Auto/Admin)
      Active --> Paused: Scenario Pause / Hold Dates Set
      Paused --> Active: Resume Plan / Hold Window Expired
      Active --> LowBalance: Prepaid Balance < 1 Delivery
      LowBalance --> Active: Balance Topped Up
      Active --> AwaitingPayment: Monthly Prepaid Plan Pending Topup
      AwaitingPayment --> Active: Topup Confirmed
      Active --> Canceled: User/Admin Cancels Plan
      Paused --> Canceled: User/Admin Cancels Plan
      LowBalance --> Canceled: User/Admin Cancels Plan
      AwaitingPayment --> Canceled: User/Admin Cancels Plan
      Canceled --> [*]
  ```

* **Prioritized Lifecycle Enum**:
  ```dart
  enum SubscriptionLifecycle {
    canceled,        // Highest precedence: canceled_at != null || status == 'canceled'
    paused,          // hold_from/to set or status == 'paused'
    awaitingPayment, // prepaid plan with pending_payment
    lowBalance,      // credit_balance_paise < delivery threshold
    active,          // active daily deliveries running
  }
  ```
* **Guarantees**:
  - `todayDeliveryOtp` card is only displayed when `lifecycle == SubscriptionLifecycle.active`.
  - Pause chips (`1 Day`, `2 Days`, `1 Week`) are only actionable when `lifecycle == SubscriptionLifecycle.active`.
  - Resume button is only displayed when `lifecycle == SubscriptionLifecycle.paused`.

---

### B. Vendor Offline Outbox & Reassignment Conflict Policy
* **File**: `apps/vendor_app/lib/features/sync/sync_controller.dart`
* **Current Vulnerability**: When a stop sync fails due to `409 STALE_STOP` (e.g. stop was reassigned to another driver or completed by admin while the vendor was offline), the stop remains in `_queue` AND `_rejected`. On the next auto-sync or manual sync, the vendor re-submits the identical stale stop, triggering repeated 409 errors and stranding collected cash (`cashAmountPaise`).
* **Formal State Machine**:
  ```mermaid
  stateDiagram-v2
      [*] --> Queued: Delivery Closed Offline
      Queued --> Syncing: Network Available / Sync Triggered
      Syncing --> Synced: 200 OK (Applied / Replayed)
      Synced --> [*]: Removed from Outbox
      Syncing --> Queued: Network Drop / 5xx (Retryable)
      Syncing --> ConflictStale: 409 STALE_STOP (Permanent)
      ConflictStale --> [*]: Auto-cleared from sync batch, Cash Custody Logged
  ```
* **Rules**:
  1. Permanent terminal rejections (`STALE_STOP`, `ALREADY_COMPLETED`) are quarantined from subsequent batch payloads to prevent infinite replay loops.
  2. If a quarantined stop carries `cashAmountPaise > 0`, the cash collection is preserved in local logs with a clear warning so the vendor's physical cash count matches admin handover.

---

### C. Customer Checkout & Payment Funnel
* **File**: `apps/user_app_donor/lib/features/booking/booking_sheet.dart`
* **Current Vulnerability**: The sheet coordinates slot fetching, order placement, and payment collection using loose flags (`_step`, `_phase`, `_recovery`, `_placed`, `_pendingUpi`, `_allowPop`).
* **Formal State Machine**:
  ```mermaid
  stateDiagram-v2
      [*] --> Configuring: Slot & Qty Selection
      Configuring --> Quoting: Fetching Real-Time Quote
      Quoting --> Configuring: Quote Ready
      Configuring --> SubmittingOrder: User Taps Pay/Confirm
      SubmittingOrder --> Completed: COD Order / Zero Due
      SubmittingOrder --> InFlightPayment: Order Created in D1, Launching Gateway
      InFlightPayment --> Completed: Webhook/Provider Success
      InFlightPayment --> Recovery: Gateway Cancelled / Network Dropped
      Recovery --> InFlightPayment: Retry Payment (Replays Same Idempotency Key)
      Recovery --> Completed: Switch to COD
      Completed --> [*]: Route to Tracking / Bill
  ```
* **Invariants**:
  1. Once `_placed` is set (order exists in D1), `_pay()` can never re-invoke `placeCheckout()`.
  2. Recovery transitions strictly route to `_recoverPayment()` or `_switchToCod()`.
  3. PopScope lock is active during `InFlightPayment` and `SubmittingOrder`.

---

## 3. Implementation Plan (Ponytail Compliance)

1. **`subscription_controller.dart`**:
   - Add `enum SubscriptionLifecycle`.
   - Add `SubscriptionLifecycle get lifecycle` getter on `SubscriptionEntry`.
   - Update `subscription_screen.dart` to use `entry.lifecycle`.
2. **`sync_controller.dart`**:
   - Add terminal conflict filter (`STALE_STOP`, `ALREADY_COMPLETED`).
   - Cleanly remove terminal conflicts from active `_queue` while retaining `_rejected` records.
3. **`booking_sheet.dart`**:
   - Standardize `CheckoutStage` enum and tighten payment recovery guards.
4. **Automated Verification**:
   - Unit tests for `SubscriptionLifecycle` resolution.
   - Unit tests for `SyncController` conflict pruning.
   - Widget tests for checkout recovery.
   - `flutter analyze` clean across all apps.
