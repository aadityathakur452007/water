# X2 — Cross-Cutting: Code Duplication & Dead Code Audit

**Files Audited:**
- `apps/user_app_donor/lib/core/constants/app_constants.dart` (52 lines)
- `apps/user_app_donor/lib/features/shell/donor_shell.dart:462-616` (`_SearchSheet`, 154 lines)
- `apps/user_app_donor/lib/features/auth/auth_controller.dart` (`newDeviceAlert`, `verified`)
- `apps/user_app_donor/lib/core/money.dart` vs `apps/vendor_app/lib/core/money.dart`
- Copy-paste date arrays across 6 files in `apps/user_app_donor`
- Dual `ShodashaColors` / `AppColors` token facades

---

## 1. Executive Summary
This audit surveyed the entire codebase across `apps/user_app_donor` and `apps/vendor_app` for dead code, unread variables, copy-pasted utilities, and redundant architectural abstractions. The codebase possesses zero speculative plugin abstractions, which is commendable; however, multiple feature ports left behind substantial structural baggage:
1. **6× Copy-Pasted Month Names Array:** Six separate files independently define the identical list `const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']` to avoid adding an `intl` dependency.
2. **154-Line Search Modal for a 2-SKU Catalog:** `donor_shell.dart:462-616` implements `_SearchSheet`, a complete searching subsystem with input controllers, empty search results, error views, and rate listeners—all to filter between exactly two products: "20L refill can" and "20L can + new jar".
3. **Four Conflicting Rupee Formatting Aliases:** Across the codebase, four separate wrapper functions exist that do nothing other than forward integer paise to `formatInr()`: `formatRupees()`, `rupeesLabel()`, `formatInr()`, and `rupees()`.
4. **Dead Controller Fields & Illusory Variables:** `auth_controller.dart` maintains `newDeviceAlert` (bool) and `verified` (bool), neither of which is ever read by any widget, test, or persistence layer. Similarly, `authStringsHi` is named as a Hindi map but filled with 100% English strings.
5. **Double Token Facade:** `app_constants.dart` maintains `AppColors` and `AppConstants`, aliasing `ShodashaTheme` properties into redundant symbols (`AppColors.surface`, `AppColors.primary`).

---

## 2. Inventory of Duplicate & Dead Code

| Item / Finding | Location(s) | Lines of Waste | Proposed Resolution |
|---|---|---|---|
| Month Names Array | 6 files in `apps/user_app_donor` | ~60 lines | Centralize single `formatShortDate(DateTime)` in `core/date_utils.dart` |
| 2-SKU Search Engine | `donor_shell.dart:462-616` | 154 lines | Delete `_SearchSheet`; direct search icon to simple product picker or remove |
| Rupee Format Duplication | 4 files across controllers | ~25 lines | Standardize exclusively on `formatInr(int paise)` from `core/money.dart` |
| Dead Auth Fields | `auth_controller.dart:66, 73` | ~15 lines | Remove unread `newDeviceAlert` and `verified` properties |
| `AppColors` Token Facade | `app_constants.dart` | 52 lines | Delete `app_constants.dart`; point callers to `ShodashaTheme` |
| Misnamed `authStringsHi` | `auth_controller.dart:18` | Map name | Rename to `authStrings` or localize into real Hindi |
| Client Money Math | `vendor_app/core/money.dart:16-23` | 15 lines | Remove client `depositDueRs` (*150) and `capChargeRs` (*3) |
| Stepper Colors Facade | `stepper.dart:13-25` | 12 lines | Remove `ShodashaColors` alias class in booking stepper |

---

## 3. Detailed Duplication Analyses

### A. The 6× Copy-Pasted Month Array
The exact literal string:
```dart
const months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
```
is duplicated in:
1. `apps/user_app_donor/lib/features/wallet/donor_wallet_screen.dart:634`
2. `apps/user_app_donor/lib/features/wallet/payment_history_screen.dart:141`
3. `apps/user_app_donor/lib/features/support/support_screen.dart:30`
4. `apps/user_app_donor/lib/features/orders/order_card.dart:65`
5. `apps/user_app_donor/lib/features/orders/tracking_screen.dart:38`
6. `apps/user_app_donor/lib/features/booking/booking_sheet.dart:1556`

Each file wraps this in a private helper function (`_shortDate`, `_formatDate`, `_supportDate`). If month representation ever needs l10n or formatting changes, six disconnected files must be updated.

### B. The 154-Line 2-SKU Search Sheet
In `donor_shell.dart:462-616`:
- `_SearchSheet` is a full `StatefulWidget` (154 lines) embedded inside the 712-line navigation shell.
- It instantiates a search `TextEditingController`.
- It listens to `BookingController.rates`.
- It performs substring filtering: `item.title.toLowerCase().contains(q)`.
- The catalog contains exactly TWO hardcoded items:
  1. `20L refill can` (`_ProductPick(refill: 1, container: 0)`)
  2. `20L can + new jar` (`_ProductPick(refill: 0, container: 1)`)
- If the user types anything other than "refill" or "jar", it shows `AppStateView.empty(title: 'No matching can', message: 'Try “refill” or “jar”.')`.
- Building an entire search engine for a fixed 2-item inventory creates maintenance overhead for zero product utility.

### C. Rupee Formatting Proliferation
```dart
// core/money.dart
String formatInr(int paise) => ...;

// orders_controller.dart:219
String formatRupees(int paise) => formatInr(paise);

// subscription_controller.dart:191
String rupeesLabel(int paise) => formatInr(paise);

// booking_controller.dart:46
String rupeesLabel(int paise) => formatInr(paise);

// vendor_app/core/money.dart:5
String rupees(int paise) => ...;
```
Every single feature author invented their own wrapper name for formatting currency. Vendor app even uses an entirely different ASCII string (`Rs $body`) instead of the standard `₹` symbol.

### D. Dead Code in Authentication
In `apps/user_app_donor/lib/features/auth/auth_controller.dart`:
```dart
bool _newDeviceAlert = false;
bool get newDeviceAlert => _newDeviceAlert;

bool _verified = false;
bool get verified => _verified;
```
- Grepping the entire repository confirms that `newDeviceAlert` is written during login but never read anywhere in `apps/user_app_donor`.
- `_verified` is toggled but never consumed by any UI gate, router, or widget.
- Furthermore, `const Map<String, String> authStringsHi = { ... }` is named `Hi` (Hindi) but contains 100% English strings.

### E. Client-Side Money Multipliers in Vendor App
In `apps/vendor_app/lib/core/money.dart`:
```dart
int depositDueRs(int containersOrdered, int emptiesDeclared, {bool walletHoldsDeposit = false}) {
  if (containersOrdered <= 0 || walletHoldsDeposit) return 0;
  final short = containersOrdered - emptiesDeclared.clamp(0, containersOrdered);
  return (short > 0 ? short : 0) * 150;
}

int capChargeRs(int capsMissing) => capsMissing * 3;
```
Hardcoding `* 150` and `* 3` directly contradicts the system invariant that deposit rates and cap fees are server-authoritative and must never be multiplied on the client.

---

## 4. Proposed Deletions & Refactorings

```
1. DELETE   apps/user_app_donor/lib/core/constants/app_constants.dart (52 lines)
2. DELETE   _SearchSheet from apps/user_app_donor/lib/features/shell/donor_shell.dart:462-616 (154 lines)
3. DELETE   formatRupees(), rupeesLabel() wrappers across 3 controllers (~25 lines)
4. DELETE   newDeviceAlert and verified from auth_controller.dart (~15 lines)
5. DELETE   ShodashaColors in stepper.dart:13-25 (12 lines)
6. EXTRACT  core/date_utils.dart (formatDate) to eliminate 6× duplicated month arrays (-50 lines net)
7. REMOVE   depositDueRs and capChargeRs from vendor_app/core/money.dart (-15 lines)
----------------------------------------------------------------------------------------
TOTAL DELETED CODE: ~323 lines of dead code and duplicate boilerplate.
```

---

## 5. File Invariants & Verification Checklist
- [x] Verified: `newDeviceAlert` has 0 read sites across entire codebase.
- [x] Verified: `verified` has 0 read sites across entire codebase.
- [x] Verified: `months` array verified in all 6 source locations.
- [x] Verified: `_SearchSheet` verified in `donor_shell.dart:462-616`.
- [x] Invariant: Deleting dead code will not impact any existing unit or widget tests.
