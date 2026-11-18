# Tasks: Phase 2 Mobile Client State Hardening

- [x] Task 1: Add `SubscriptionLifecycle` enum and getter in `apps/user_app_donor/lib/features/subscriptions/subscription_controller.dart`.
- [x] Task 2: Refactor `apps/user_app_donor/lib/features/subscriptions/subscription_screen.dart` to use `entry.lifecycle`.
- [x] Task 3: Hardened `SyncController` in `apps/vendor_app/lib/features/sync/sync_controller.dart` to quarantine permanent conflict stops (`STALE_STOP`).
- [x] Task 4: Standardize `_Phase` / `_Recovery` transitions in `apps/user_app_donor/lib/features/booking/booking_sheet.dart` with strict post-order invariants.
- [x] Task 5: Add tests for `SubscriptionLifecycle` and `SyncController` conflict handling.
- [x] Task 6: Run full test suites: `flutter test` across apps, `flutter analyze`, and `uv run pytest`.
- [x] Task 7: Context sync: Update `context/progress-tracker.md`, `context/flow.md`, and `context/decision.md`.
