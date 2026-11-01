# Slice 2 Specification: Donor Token Foundation & Theme Reset

- **Branch:** `037-uiux-unslop-audit`
- **Target App:** `apps/user_app_donor` & `apps/vendor_app`
- **Defects Addressed:** `DEF-04` (ElevatedButton Money-Green Trap), `DEF-14` (Vendor Design System & Token Vacuum)
- **Status:** In Progress

---

## 1. Problem Statement & Root Cause

### DEF-04: ElevatedButton Money-Green Trap
- **Location:** `apps/user_app_donor/lib/core/theme.dart:311`
- **Root Cause:** `elevatedButtonTheme` sets `backgroundColor: ShodashaTheme.greenDark` (`#15803D`).
- **Impact:** Any standard Flutter `ElevatedButton` without an explicit `styleFrom` override accidentally defaults to money green. This violates the core design system principle that emerald green is reserved strictly for financial/money CTAs (Pay, Confirm Order, Add Funds). Screens such as `address_screen.dart` (discard dialog), `subscription_screen.dart` (skip confirm), and `payment_history_screen.dart` (sign in) accidentally rendered non-financial actions in money green.
- **Remediation:**
  1. In `apps/user_app_donor/lib/core/theme.dart`, change `elevatedButtonTheme`'s default `backgroundColor` to `ShodashaTheme.tealDeep` (`#115E59`), which provides WCAG AA compliant contrast on white while matching the brand primary structure.
  2. Verify that `AppButton.money()` in `apps/user_app_donor/lib/shared/ui/app_button.dart` explicitly specifies `ShodashaTheme.greenDark` (`#15803D`).
  3. Ensure all checkout, payment, and wallet money CTAs continue rendering in `#15803D`.

### DEF-14: Vendor Token & Shared UI Vacuum
- **Location:** `apps/vendor_app/lib/core/theme.dart`
- **Root Cause:** The vendor app lacks layout spacing tokens (`AppSpacing`), motion utilities (`AppMotion`), and shared UI primitives (`AppButton`), leading to magic numbers (`EdgeInsets.all(12)`, `EdgeInsets.all(13)`) and ad-hoc button implementations across driver screens.
- **Remediation:**
  1. In `apps/vendor_app/lib/core/theme.dart`, export `AppSpacing` (4, 8, 12, 16, 24, 32), `radiusSm` (6), `radius` (8), `radiusLg` (12), `radiusSheet` (24), `kMaxContentWidth` (560), and `AppMotion` with reduced-motion support.
  2. Create `apps/vendor_app/lib/shared/ui/app_button.dart` mirroring donor's `AppButton` API but adapted to the vendor design identity (`AppButtonKind.primary` = `ShodashaTheme.ink`, `AppButtonKind.money` = `ShodashaTheme.success`).
  3. Update `apps/vendor_app/lib/features/stops/handover_sheet.dart` to use `AppSpacing` directly, eliminating the local `_Sp` shim.

---

## 2. Invariants & Guardrails
1. **Financial Authority:** Zero backend or pricing calculations are altered. Server remains the single authority on money.
2. **Color Semantics:**
   - Green (`#15803D` / `#16A34A`): Money CTAs ONLY (Pay, Book Now, Add Money).
   - Teal (`#0D9488` / `#115E59`): Brand primary structure and non-money primary actions in Donor App.
   - Ink (`#111111`): Logistics primary actions in Vendor App.
3. **Ergonomic Accessibility:** 48dp minimum touch target preserved on all buttons.
4. **Performance:** No extra widget rebuilds or heavy wrappers; const constructors and token references only.

---

## 3. Verification Plan
1. `flutter analyze` in `apps/user_app_donor` (0 issues).
2. `flutter analyze` in `apps/vendor_app` (0 issues).
3. `flutter test` in `apps/user_app_donor` (75 / 75 passing).
4. `flutter test` in `apps/vendor_app` (70 / 70 passing).
5. Add unit tests for `AppButton` in vendor app to guarantee token stability.

