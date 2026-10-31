# Slice 5 — Cross-Cutting Reliability, Addresses & Hygiene

**Branch:** `037-uiux-unslop-audit`  
**Defects addressed:** DEF-06, DEF-08, DEF-09, DEF-10, DEF-12, DEF-15, DEF-16, DEF-17  
**ADR:** ADR-161

---

## Scope

### DEF-08 — Central Bhopal Default Coordinates
- File: `apps/user_app_donor/lib/features/addresses/map_picker.dart:19`
- Replace Nagpur, Maharashtra fallback (`21.1458, 79.0882`) with central Bhopal, MP (`23.2599, 77.4126`).

### DEF-10 — Zero-Schedule Plan Creation Guard
- File: `apps/user_app_donor/lib/features/subscriptions/plan_builder_sheet.dart`
- In recurring schedule mode, prevent proceeding to payment when 0 weekdays are selected (`selectedDays.isEmpty`).

### DEF-09 — Wallet Zero-Flash Guard on Error
- File: `apps/user_app_donor/lib/features/wallet/donor_wallet_screen.dart`
- Avoid rendering a false ₹0 when ledger/wallet fetch has failed; display error state with retry.

### DEF-06 — Tracking Navigation Stack Clean-up
- File: `apps/user_app_donor/lib/features/orders/tracking_screen.dart`
- On cancellation or navigation back, ensure navigation stack doesn't allow popping back to stale cancel confirmation states.

### DEF-12 — Engineering Leak Scrubbing
- `featured_products.dart`: Clean up debug / "Server prices" chip or disclaimer.
- `donor_profile_screen.dart`, `notifications_screen.dart`: Truncate raw UUIDs to clean `#...8902` format.

### DEF-15 — Unified Month Array
- Extract `const months = [...]` to `apps/user_app_donor/lib/core/utils/date_utils.dart` and reuse across orders, bill, tracking, and payments.

### DEF-16 & DEF-17 — Dictionary Rename & A11y Semantics
- Rename `authStringsHi` / `ordersStringsHi` to `authStrings` / `ordersStrings` (since copy is English).
- Add Semantics labels to avatar, purity TDS, and tracking dots.

---

## Acceptance Criteria

- [ ] `flutter analyze` 0 issues (donor + vendor)
- [ ] `flutter test` donor 80/80 + vendor 71/71
- [ ] Backend `uv run pytest -q` 487 passed / 1 skipped
- [ ] Context files updated and committed with Slice 5 commit

