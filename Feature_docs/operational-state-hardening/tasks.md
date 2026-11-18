# Tasks: Phase 3 Operational State Machines & Vendor Capacity Hardening

- [x] Task 1: Mindful Vendor Capacity Modernization:
  - Add `max_jars` field to `VendorCreateIn` in `workers/api/src/app/api/v1/admin.py` (default 250, range 1..5000).
  - Update `create_vendor` to store `max_jars_per_shift` in `vendor_profile`.
  - Update default `max_jars_per_shift` in `dispatch_service.py` from 60 to 250.
  - Update `AddVendorDialog` in `apps/admin_app` to include `Daily Shift Capacity (Jars)` defaulting to 250.
- [x] Task 2: Rider Duty State Machine:
  - Add `LEGAL_RIDER_DUTY_TRANSITIONS` and `validate_rider_duty_transition()` in `workers/api/src/app/core/state_machines.py`.
  - Guard delivery completion against off-duty riders in `rider_service.py` and `rider.py`.
- [x] Task 3: Vendor Leave & Duty-Off Auto-Repool Validation:
  - Verify auto-repool invariants on unfulfilled stops when vendor toggles duty off or reports stockout.
- [x] Task 4: Return & Deposit Refund State Machine:
  - Add `LEGAL_RETURN_TRANSITIONS` and `validate_return_transition()` in `state_machines.py`.
  - Guard refund execution against double-refund and invalid origin states in `admin.py`.
- [x] Task 5: Automated Tests & Verification:
  - Unit tests in `workers/api/tests/test_operational_state_machines.py` (12/12 passed).
  - Run full test suites: `uv run pytest -q` (534 passed, 1 skipped), `flutter test` (all 229 passed across rider_app, vendor_app, user_app_donor), and `flutter analyze` (0 issues).
- [x] Task 6: Context Synchronization:
  - Update `context/progress-tracker.md`, `context/flow.md`, and record ADR-205 in `context/decision.md`.
