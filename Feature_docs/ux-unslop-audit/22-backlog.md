# 22 — Prioritized Unslop Implementation Backlog

**Branch:** `037-uiux-unslop-audit`  
**Date:** 2026-10-31  
**Scope:** Unified Implementation Backlog from 20 Screen & Cross-Cutting Audits  
**Ordering Discipline:** Grouped into single-screen/feature implementation slices ordered strictly by:  
`Trust & Money (P0)` → `Blocked Flows (P1)` → `Navigation & States (P1/P2)` → `Craft (P2)` → `Polish (P3)`

---

## 1. Master Ranked Defect Table (P0, P1, P2)

| ID | Screen / Scope | Finding Summary | Severity | Effort | Target Files | Depends On |
|---|---|---|---|---|---|---|
| **DEF-01** | Vendor Route / Stops | Fragmented Delivery Handover: Consolidate `TripleSheet` and `PoDSheet` into a single 2-step modal to eliminate desynced jar and cash counts | **P0** | **M** | `apps/vendor_app/lib/features/route/stop_detail_screen.dart`, `triple_sheet.dart`, `pod_sheet.dart` | None |
| **DEF-02** | Vendor Earnings | Fabricated Client Money Math: Delete `stopsDone * 2000` client fallback and hardcoded multiplier constants; display only server-stated payouts | **P0** | **S** | `apps/vendor_app/lib/features/earnings/earnings_screen.dart:117`, `apps/vendor_app/core/money.dart:16-23` | None |
| **DEF-03** | Donor Home / Booking | 3-Sheet Booking Labyrinth: Introduce 1-tap repeat order card on Home; collapse `ProductDetail` + `BookingSheet` + `QuoteConfirm` into a single-sheet checkout | **P1** | **M** | `apps/user_app_donor/lib/features/home/customer_home_screen.dart`, `features/booking/booking_sheet.dart`, `quote_confirm.dart` | DEF-04 |
| **DEF-04** | Global Donor Theme | `ElevatedButton` Money-Green Trap: Reset default theme button color to brand/neutral; reserve `#15803D` strictly for `AppButton.money()` | **P1** | **S** | `apps/user_app_donor/lib/core/theme.dart:311`, `shared/ui/app_button.dart` | None |
| **DEF-05** | Vendor Shell & Nav | Bottom Tab 4 Side Drawer Trap: Retire side navigation drawer triggered from bottom bar; replace Tab 4 with dedicated "More / Tools" hub screen | **P1** | **M** | `apps/vendor_app/lib/features/shell/vendor_shell.dart:277-279` | DEF-07 |
| **DEF-06** | Donor Tracking & Orders | Tracking Stack Pollution: Clear navigation stack on order cancellation; prevent back-button reopening of cancelled/stale polling orders | **P1** | **S** | `apps/user_app_donor/lib/features/orders/tracking_screen.dart:420`, `my_orders_screen.dart:188` | None |
| **DEF-07** | Vendor Duty Gate | Off-Duty Full-Screen Lockout: Convert full-screen barrier into a persistent top notification banner; permit off-duty access to Earnings and Profile | **P1** | **S** | `apps/vendor_app/lib/features/shell/vendor_shell.dart:140-165`, `duty_screen.dart` | DEF-05 |
| **DEF-08** | Donor Addresses | Nagpur Default Coordinates: Replace Nagpur Maharashtra fallback (`21.1458, 79.0882`) with central Bhopal MP (`23.2599, 77.4126`) | **P1** | **S** | `apps/user_app_donor/lib/features/addresses/map_picker.dart:19` | None |
| **DEF-09** | Donor Wallet | Zero-Balance Flash on Network Failure: Display explicit skeleton shimmer followed by retry banner on load failure; never show ₹0 for failed fetches | **P1** | **S** | `apps/user_app_donor/lib/features/wallet/donor_wallet_screen.dart:94-112`, `wallet_controller.dart` | None |
| **DEF-10** | Donor Subscriptions | Zero-Schedule Plan Creation Guard: Disable "Proceed to Payment" in `PlanBuilderSheet` when 0 delivery days are selected in recurring schedule | **P1** | **S** | `apps/user_app_donor/lib/features/subscriptions/plan_builder_sheet.dart:284` | None |
| **DEF-11** | Vendor Localization | Slash-Separated Bilingual Clutter: Replace `"Duty / ड्यूटी"` inline slash strings with a dedicated clean Hindi / English language toggle | **P2** | **M** | `apps/vendor_app/lib/features/auth/vendor_strings.dart`, `vendor_shell.dart`, all feature screens | None |
| **DEF-12** | Cross-Cutting Copy | Engineering Leaks in User Copy: Remove `"Server prices"` chip, replace raw UUIDs with `#...8902`, reword technical API disclaimer in purity sheet | **P2** | **S** | `featured_products.dart:36`, `notifications_screen.dart:288`, `donor_profile_screen.dart:401`, `bill_screen.dart` | None |
| **DEF-13** | Donor Shell | 154-Line Search Engine for 2 SKUs: Remove modal search engine overlay from shell; replace with direct SKU chips or instant filter on home | **P2** | **S** | `apps/user_app_donor/lib/features/shell/donor_shell.dart:462-616` | DEF-03 |
| **DEF-14** | Vendor Design System | Vendor Token & Shared UI Vacuum: Export `AppSpacing`, standard radius tokens, and core `shared/ui` widgets from donor to vendor app | **P2** | **M** | `apps/vendor_app/lib/core/theme.dart`, all vendor feature UI files | DEF-04 |
| **DEF-15** | Cross-Cutting Code Hygiene | 6× Redundant Month Array: Consolidate duplicate `const months = [...]` declarations across 6 donor files into unified `AppDateUtils` | **P2** | **S** | `my_orders_screen.dart:340`, `order_card.dart:182`, `tracking_screen.dart:884`, `bill_screen.dart:140`, `subscription_screen.dart:210`, `payment_history_screen.dart:120` | None |
| **DEF-16** | Donor Localization Hygiene | Misnamed String Dictionaries: Rename `authStringsHi` and `ordersStringsHi` to `authStrings` and `ordersStrings` to reflect their actual English contents | **P2** | **S** | `apps/user_app_donor/lib/features/auth/auth_controller.dart:18`, `orders_controller.dart:38` | None |
| **DEF-17** | Cross-Cutting A11y & Semantics | Missing Accessibility Labels: Add semantic labels to profile avatar monogram, live purity TDS metrics, and order tracking dots | **P2** | **S** | `donor_profile_screen.dart:88`, `live_purity_card.dart:142`, `tracking_screen.dart:312` | None |
| **DEF-18** | Vendor Route / Sync | Fragile Error String Parsing: Replace `contains('Network')` and `contains('internet')` string inspection with typed HTTP/Socket error handling | **P2** | **S** | `sync_screen.dart:84`, `customer_home_screen.dart:114` | None |
| **DEF-19** | Donor Orders & Tracking | Status Pill Token Consistency: Standardize status pill border radius (8dp) and typography hierarchy across list cards and detail headers | **P2** | **S** | `order_card.dart:95`, `tracking_screen.dart:210`, `stop_detail_screen.dart:140` | DEF-04 |
| **DEF-20** | Donor Support & Returns | Support Phone Constant Sync: Unify emergency tanker and support telephone launcher to use `AppConstants.kSupportPhone` strictly | **P2** | **S** | `apps/user_app_donor/lib/features/support/support_screen.dart:412` | None |

---

## 2. Implementation Slices (One Screen / Module per Slice)

Implementation will proceed in strictly isolated, single-feature PR branches to ensure zero regression risk and continuous test verification.

### Slice 1: Vendor Trust, Money & Handover (`apps/vendor_app`)
- **Focus:** `DEF-01` (Dual Sheet Handover Consolidation) & `DEF-02` (Remove Fabricated Money Math).
- **Target Files:** `route/stop_detail_screen.dart`, `route/triple_sheet.dart`, `route/pod_sheet.dart`, `earnings/earnings_screen.dart`, `core/money.dart`.
- **Pre-Conditions:** None.
- **Verification:** Run `flutter test` in `apps/vendor_app` (68/68 must pass).

### Slice 2: Donor Token Foundation & Theme Reset (`apps/user_app_donor`)
- **Focus:** `DEF-04` (Fix `ElevatedButton` Money-Green Trap) & `DEF-14` (Export shared spacing tokens).
- **Target Files:** `lib/core/theme.dart`, `shared/ui/app_button.dart`.
- **Pre-Conditions:** None.
- **Verification:** Verify that `login_screen`, `address_screen`, and `donor_profile_screen` render neutral primary buttons while checkout buttons remain `#15803D`.

### Slice 3: Donor Core Home & Checkout Machine (`apps/user_app_donor`)
- **Focus:** `DEF-03` (1-Tap Reorder & 1-Sheet Booking) & `DEF-13` (Retire 154-line search modal).
- **Target Files:** `features/home/customer_home_screen.dart`, `features/booking/booking_sheet.dart`, `features/booking/quote_confirm.dart`, `features/shell/donor_shell.dart`.
- **Pre-Conditions:** Slice 2 completed.
- **Verification:** Place a 20L can order in test environment; verify single-modal transition and 75/75 passing tests.

### Slice 4: Vendor Shell, Duty Gate & Navigation Hub (`apps/vendor_app`)
- **Focus:** `DEF-05` (Retire Drawer; add "More" screen) & `DEF-07` (Soft Duty Banner).
- **Target Files:** `features/shell/vendor_shell.dart`, `features/duty/duty_screen.dart`, `features/profile/profile_screen.dart`.
- **Pre-Conditions:** Slice 1 completed.
- **Verification:** Switch duty off; verify Earnings and Profile tabs remain interactive while route stops are disabled.

### Slice 5: Cross-Cutting Reliability, Addresses & Hygiene (`Both Apps`)
- **Focus:** `DEF-06` (Tracking back navigation), `DEF-08` (Bhopal coordinates), `DEF-09` (Wallet zero-flash), `DEF-10` (Plan builder 0-schedule guard), `DEF-12` (Copy leaks), `DEF-15` (Month array deduplication), `DEF-16` (Dictionary rename), `DEF-17` (A11y labels).
- **Target Files:** `tracking_screen.dart`, `map_picker.dart`, `donor_wallet_screen.dart`, `plan_builder_sheet.dart`, `donor_profile_screen.dart`, `notifications_screen.dart`, `core/utils/date_utils.dart`.
- **Pre-Conditions:** Slices 1–4 completed.
- **Verification:** Both test suites pass (75 donor / 68 vendor). Zero analyzer warnings.

---

## 3. P3 Polish List ("Later" Execution Phase)

The following cosmetic micro-refinements are recorded for execution after core flows and craft defects are settled:

1. **Tight Touch Target Padding:** Expand tap margins on `PlanBuilderSheet` weekday chips and stepper icon buttons from 36dp to minimum 48dp bounding boxes.
2. **Subtle Elevation Shadows:** Normalize card elevation across donor order cards and vendor stop cards to a unified 2dp drop shadow (`BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))`).
3. **Empty State Illustrations:** Replace plain icon-and-text empty states with lightweight, branded SVG/vector spot illustrations representing clean water cans and doorstep delivery.
4. **Hero Counter Shimmer:** Add a subtle shimmer pulse on `LivePurityCard` when TDS telemetry updates.
5. **Haptic Feedback:** Wire `HapticFeedback.lightImpact()` to quantity stepper increments and primary order placement buttons.

---

## 4. Explicit "Do Not Touch" System Invariants

The following files, services, and architectural boundaries are **strictly locked** and must not be altered during UI/UX unslop implementation:

- **Server-Authoritative Pricing & Rates:** No client-side price overrides (`workers/api/src/app/services/pricing.py`, `OrderService.compute_quote`).
- **Payment & Dues State Machines:** UPI webhooks, COD dues posting, and idempotency guarantees (`dues_intents`, `payments`, `Idempotency-Key` headers).
- **Delivery OTP Security:** OTP minting and verification contracts remain server-owned (`/v1/orders/{id}` `delivery_otp` and `/v1/vendor/stops/{id}/pod`).
- **Database Schema & Migrations:** No changes to Cloudflare D1 tables or SQL migrations (`workers/api/src/app/db/migrations/*`).
- **Backend APIs & Worker Runtime:** Zero edits to `workers/api/*` or `apps/admin_app/*`.
- **Application Binary Size Gates:** Release APKs must remain strictly under 40 MB without introducing external UI framework dependencies.
