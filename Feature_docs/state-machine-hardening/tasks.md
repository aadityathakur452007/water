# Tasks: Phase 1 State Machine Hardening

- [x] Task 1: Create `workers/api/src/app/core/state_machines.py` with pure transition tables and invariant validators.
- [x] Task 2: Refactor `workers/api/src/app/repositories/order_repo.py` to use `state_machines.py` constants and validators.
- [x] Task 3: Update `workers/api/src/app/services/payment_service.py` to use `validate_late_capture_action()` and `validate_switch_to_cod()`.
- [x] Task 4: Standardize `workers/api/src/app/services/delivery_code.py` using `DeliveryCodeState`.
- [x] Task 5: Implement `HandoverMode` and pure resolution in `apps/rider_app/lib/features/delivery/widgets/pod_sheet.dart`.
- [x] Task 6: Add backend unit tests in `workers/api/tests/test_state_machines.py` covering transition tables, invariants, and edge cases.
- [x] Task 7: Add rider app tests in `apps/rider_app/test/pod_sheet_test.dart`.
- [x] Task 8: Run full test suite: `uv run pytest` (522 passed, 1 skipped) and `flutter analyze` in all 3 apps (0 issues).
- [ ] Task 9: Context sync: Update `context/progress-tracker.md`, `context/flow.md`, and `context/decision.md`.
