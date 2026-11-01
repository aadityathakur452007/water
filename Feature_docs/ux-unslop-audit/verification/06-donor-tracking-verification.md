# Verification Report: 06 — Donor App: Tracking Screen & Delivery Code

**Document Audited:** `Feature_docs/ux-unslop-audit/06-donor-tracking.md`  
**Target Codebase:** `apps/user_app_donor/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **D6-01** | Tracking screen component modularity | Ensure cards have clear encapsulation and clean state wiring without regressions. | `apps/user_app_donor/lib/features/orders/tracking_screen.dart:930-1310`<br>`_WindowCard`, `_LiveStopsAheadBanner`, `_RiderCard`, and `_DeliveryCodeCard` isolated with explicit parameters. | `[VERIFIED]` |
| **D6-02** | Live stops ahead and arrival copy unslop | Unslop live tracking and OTP banner copy: calm brand tone, no exclamation marks or algorithmic leaks. | `tracking_screen.dart:1037-1050, 1182-1187`<br>`'Next stop is yours'`, `'Arriving now · Please keep your empty jar ready'`, `'Estimated arrival in ~X–Y mins · Keep empty jar ready'`, `'Delivery complete · Code verified'`, `'Code locked after wrong attempts · Request a new code'`. | `[VERIFIED]` |
| **D6-03** | Reschedule slot selection | Honor server-backed rescheduling without booking closed slots. | `tracking_screen.dart:275-340`<br>Reschedule flow validates available service dates and slots with server POST. | `[VERIFIED]` |
| **D6-04** | Centralized date utilities & navigation debounce | Prune duplicate calendar formatters into `date_utils.dart`; preserve navigation debounce guards. | `tracking_screen.dart:36-60, 88`<br>Uses `kShortMonths` and `kShortWeekdays`; `_pushingBill` prevents duplicate route transitions. | `[VERIFIED]` |
| **D6-05** | Spacing and typography token hygiene | Replace non-token gaps (10px, 3px) with `AppSpacing.sm` / `xs`; eliminate fractional fonts (12.5, 11.5). | `tracking_screen.dart:950, 978, 1045, 1093, 1219, 1234, 1238`<br>10px gaps converted to `AppSpacing.sm` (8dp), 3px gaps to `AppSpacing.xs` (4dp). Time window normalized from w900 to w700. Fractional fonts eliminated. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| Reissue delivery code CTA | Bounded `AppButton` (48dp height floor) | `tracking_screen.dart:1280-1296`<br>`AppButton(label: 'Get new code', kind: AppButtonKind.secondary, busy: controller.reissueBusy, height: ShodashaTheme.minTarget, ...)` | `[VERIFIED]` |
| Call rider button | Minimum 48dp touch target | `tracking_screen.dart:1118-1132`<br>`SizedBox(height: ShodashaTheme.minTarget, child: OutlinedButton(...))` | `[VERIFIED]` |
| Delivered order actions | Canonical `AppButton` hierarchy (View bill secondary, Rate delivery ghost) | `tracking_screen.dart:676-695`<br>`AppButton(label: 'View bill', kind: AppButtonKind.secondary)` and `AppButton(label: 'Rate delivery', kind: AppButtonKind.ghost)` | `[VERIFIED]` |
| Cancel & Reschedule buttons | Bounded 48dp targets with clean secondary styling | `tracking_screen.dart:700-725`<br>`OutlinedButton` with `minimumSize: const Size(48, ShodashaTheme.minTarget)` | `[VERIFIED]` |
| Terminal error support CTA | Canonical `AppButtonKind.danger` | `tracking_screen.dart:730-745`<br>`AppButton(label: 'Contact support', kind: AppButtonKind.danger, onPressed: widget.onSupport)` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Window card gaps | `AppSpacing.sm` (8dp) | `tracking_screen.dart:950`<br>`SizedBox(width: AppSpacing.sm)`. Replaced off-scale 10px gap. | `[VERIFIED]` |
| Stops ahead banner gaps | `AppSpacing.md` (12dp) horizontal, `AppSpacing.xs` (4dp) vertical | `tracking_screen.dart:1030, 1045`<br>`SizedBox(width: AppSpacing.md)` and `SizedBox(height: AppSpacing.xs)`. Replaced 3px gap. | `[VERIFIED]` |
| Rider card gaps | `AppSpacing.sm` (8dp) | `tracking_screen.dart:1093`<br>`SizedBox(width: AppSpacing.sm)`. Replaced 10px gap. | `[VERIFIED]` |
| Delivery code icon & text gaps | `AppSpacing.sm` (8dp) horizontal, `AppSpacing.xs` (4dp) vertical | `tracking_screen.dart:1219, 1234`<br>`SizedBox(width: AppSpacing.sm)` and `SizedBox(height: AppSpacing.xs)`. Replaced 10px and 3px gaps. | `[VERIFIED]` |
| Card internal padding | `AppSpacing.lg` (16dp) | `tracking_screen.dart:942, 1005, 1072, 1195`<br>`padding: const EdgeInsets.all(AppSpacing.lg)`. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Window Time Display | 16px w700, letterSpacing -0.2 | `tracking_screen.dart:977-981`<br>`fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: ShodashaTheme.ink` (standardized from w900) | `[VERIFIED]` |
| Stops Ahead Headline | 15px w800 | `tracking_screen.dart:1040-1043`<br>`fontSize: 15, fontWeight: FontWeight.w800, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Rider Name | 15px w700 | `tracking_screen.dart:1110-1113`<br>`fontSize: 15, fontWeight: FontWeight.w700, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Delivery Code Status Headline | 14px w800 | `tracking_screen.dart:1226-1231`<br>`fontSize: 14, fontWeight: FontWeight.w800, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Support & Helper Text | 12px w400, height 1.35 | `tracking_screen.dart:1238-1242`<br>`fontSize: 12, height: 1.35, color: ShodashaTheme.muted`. 12.5px eliminated. | `[VERIFIED]` |
| Refund Pending Label | 11px w600 | `tracking_screen.dart:738`<br>`fontSize: 11, fontWeight: FontWeight.w600, color: ShodashaTheme.muted`. 11.5px eliminated. | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Original String / Issue | Polished String | Code Evidence | Status |
|---|---|---|---|
| Exclamation mark in banner | `"Next stop is yours"` | `tracking_screen.dart:1037`<br>Replaced `"Your stop is next!"`. | `[VERIFIED]` |
| Wordy arrival instructions | `"Arriving now · Please keep your empty jar ready"` | `tracking_screen.dart:1048`<br>Replaced `"The driver is arriving at your address. Please keep your empty jar ready."`. | `[VERIFIED]` |
| Algorithmic estimate copy | `"Estimated arrival in ~X–Y mins · Keep empty jar ready"` | `tracking_screen.dart:1049`<br>Replaced `"Estimated time: about X–Y minutes. Keep your empty jar outside."`. | `[VERIFIED]` |
| Trailing period on status badge | `"Delivery complete · Code verified"` | `tracking_screen.dart:1182`<br>Replaced `"Delivery complete — code used."`. | `[VERIFIED]` |
| Choppy locked code note | `"Code locked after wrong attempts · Request a new code"` | `tracking_screen.dart:1187`<br>Replaced `"For your safety this code is locked. Get a new one."`. | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| Cold order fetch | Skeleton placeholder cards | `tracking_screen.dart:901-930`<br>`_TrackingSkeleton` renders placeholder containers matching card layout. | `[VERIFIED]` |
| Lifecycle pause/resume | Pause polling timer in background | `tracking_screen.dart:138-149`<br>`didChangeAppLifecycleState` pauses/resumes polling to preserve battery/data. | `[VERIFIED]` |
| Live stops ahead (0 stops) | Special arrival banner | `tracking_screen.dart:1000, 1036-1049`<br>`isNext ? 'Next stop is yours' : 'Driver is X stops away'`. | `[VERIFIED]` |
| Code locked (5 failed OTPs) | Locked state with reissue CTA | `tracking_screen.dart:1180, 1187, 1200`<br>Displays danger border and enables `_reissueCode()`. | `[VERIFIED]` |
| Code verified on PoD | Used state confirmation | `tracking_screen.dart:1182, 1190`<br>Displays green checkmark and `'Delivery complete · Code verified'`. | `[VERIFIED]` |
| Reduced motion | Instant scale/opacity swap | `tracking_screen.dart:835-870`<br>`MediaQuery.disableAnimationsOf(context)` bypasses 200ms scale transition. | `[VERIFIED]` |

---

## 7. Verification Test Suite Results

- `test/tracking_screen_test.dart` (4 tests): **PASSED**
  - Renders `'Next stop is yours'` when `stopsAhead` is 0.
  - Renders stops away banner and estimated arrival when `stopsAhead > 0`.
  - Renders sanitized delivery code verified status when used.
  - Renders clean locked code notice after wrong attempts.
- **Total Tracking Screen Tests:** **4 / 4 passed** with 0 failures, 0 errors.

---

## Conclusion

File `06-donor-tracking.md` is **100% verified** against the current codebase in `apps/user_app_donor`. All P0–P3 unslop items (D6-01 through D6-05), calm copy polish on stops ahead and OTP status banners, elimination of non-token 10px/3px gaps, normalization of 12.5px/11.5px font sizes, window time font weight scaling, and date utilities consolidation are confirmed in code with green test coverage.

