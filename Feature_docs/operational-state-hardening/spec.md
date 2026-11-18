# Feature Spec: Phase 3 Operational State Machines & Vendor Capacity Hardening

## 1. Context & Objective
Following the backend order/payment fulfillment hardening (ADR-203, Phase 1) and mobile client flow hardening (ADR-204, Phase 2), Phase 3 hardens the **operational state machines** across vendor dispatch, rider duty execution, vendor capacity limits, and container deposit return lifecycles.

A critical design requirement raised by the owner is that **vendor delivery capacity is artificially constrained by a legacy default of 60 jars per shift**. Real delivery vendors operate with much higher capacity (e.g., 200–500 jars per shift with commercial vehicles or restocking routes). Phase 3 addresses this capacity choke point alongside three operational state machines.

---

## 2. Subsystem Specifications

### A. Mindful Vendor Capacity & Shift Limit Engine
* **Files**: `workers/api/src/app/api/v1/admin.py`, `workers/api/src/app/services/dispatch_service.py`, `apps/admin_app/src/routes/(main)/dashboard/vendors/-components/add-vendor-dialog.tsx`
* **Vulnerability / Choke Point**:
  1. `vendor_profile` default `max_jars_per_shift` was hardcoded to `60` in the SQL schema and Python services.
  2. `VendorCreateIn` in `admin.py` accepted `max_stops` but completely lacked `max_jars`, forcing newly registered vendors into the 60-jar limit unless retroactively patched via `/capacity`.
  3. `AddVendorDialog` in the admin frontend had no field for jar capacity.
  4. In `dispatch_service.py:check_capacity`, vendors were rejected with `CapacityExceededError: Vendor jar capacity reached` once 60 jars were assigned across their route stops.
* **Hardened Architecture**:
  1. **Higher Mindful Default**: Raise the standard shift jar default from `60` to `250` jars (and max stops default to `50`), with support for up to `5000` jars for high-capacity fleet vehicles.
  2. **Registration Wire-up**: Add `max_jars: int | None = Field(default=None, ge=1, le=5000)` to `VendorCreateIn`. Store `max_jars_per_shift` during atomic vendor creation.
  3. **Admin UI Input**: Add `Daily Shift Capacity (Jars)` (defaulting to 250) in `AddVendorDialog`.
  4. **Dynamic Headroom Calculator**: Provide a helper in `dispatch_service.py` to calculate remaining capacity headroom (`stops_remaining`, `jars_remaining`, `capacity_utilized_pct`).

---

### B. Rider Shift & Duty State Machine
* **Files**: `workers/api/src/app/core/state_machines.py`, `workers/api/src/app/api/v1/rider.py`, `apps/rider_app/lib/features/delivery/`
* **Current Vulnerability**: Rider duty is stored as a loose boolean or inferred from stop assignment without strict shift boundary states.
* **Formal State Machine**:
  ```mermaid
  stateDiagram-v2
      [*] --> OffDuty: Shift Idle
      OffDuty --> OnDuty: Rider Toggles On-Duty / Starts Shift
      OnDuty --> OffDuty: Temporary Break / Soft Pause
      OnDuty --> ShiftEnded: Route Completed / Day Close
      ShiftEnded --> OffDuty: Next Day Cycle / Reset
  ```
* **Transition Table**:
  ```python
  LEGAL_RIDER_DUTY_TRANSITIONS: Final[dict[str, set[str]]] = {
      "off_duty": {"on_duty"},
      "on_duty": {"off_duty", "shift_ended"},
      "shift_ended": {"off_duty"},
  }
  ```
* **Invariants**:
  - A rider cannot execute PoD delivery completions (`POST /rider/stops/{id}/complete`) while `off_duty` or `shift_ended`.

---

### C. Vendor Duty-Off & Reassignment Auto-Repool
* **Files**: `workers/api/src/app/services/vendor_service.py`, `workers/api/src/app/services/dispatch_service.py`
* **Vulnerability**: If a vendor goes off-duty mid-shift while holding uncompleted route stops, those stops risk being stranded unless dispatcher manually intervenes.
* **State Machine & Invariant**:
  - When `POST /vendor/duty` is called with `on_duty: false`:
    - All non-terminal stops (`status == 'pending'`) assigned to that vendor for today are automatically repooled back to the unassigned `placed` pool (`auto_repool`).
    - Audit log records `vendor.duty_off` with the exact count of repooled stops.

---

### D. Admin Return & Jar Deposit Refund State Machine
* **Files**: `workers/api/src/app/core/state_machines.py`, `workers/api/src/app/services/return_service.py` (or `admin.py`)
* **Formal State Machine**:
  ```mermaid
  stateDiagram-v2
      [*] --> Requested: Customer Submits Empty Jar Return
      Requested --> Assigned: Admin Assigns Vendor/Rider for Collection
      Assigned --> Picked: Vendor Collects Jars at Doorstep
      Picked --> Refunded: Admin / System Approves Deposit Payout
      Requested --> Rejected: Invalid Request / No Deposit Paid
      Assigned --> Rejected: Customer Cancelled / Address Unreachable
      Picked --> Rejected: Bottles Damaged / Fake Non-Brand Jars
      Refunded --> [*]
      Rejected --> [*]
  ```
* **Invariants**:
  - `mark_refunded` can strictly only be called from `picked`.
  - Double-refund protection: `refunded` is a terminal state. Calling refund again raises `ConflictError`.
  - Refund amount is strictly bounded by the customer's recorded `deposit_paid - deposit_refunded` in the ledger.

---

## 3. Verification Plan
1. Unit tests in `workers/api/tests/test_operational_state_machines.py`:
   - Mindful capacity checks (250 default, custom 500+ jars, capacity headroom).
   - Rider duty state transitions and off-duty delivery rejection.
   - Return state progression and double-refund prevention.
2. Flutter tests in `apps/rider_app` and `apps/vendor_app`.
3. Complete pytest and flutter analyze clean passes across the entire project.
