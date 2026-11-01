# Verification Report: 02 — Donor App: Shell, Navigation & Notifications

**Document Audited:** `Feature_docs/ux-unslop-audit/02-donor-shell-nav.md`  
**Target Codebase:** `apps/user_app_donor/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **D2-01** | Retirement of decorative fake search sheet | Eliminate `_SearchSheet`, `_ProductPick`, and search modal cul-de-sac. Catalog has 2 SKUs directly accessible via Home product cards. | `apps/user_app_donor/lib/features/shell/donor_shell.dart`<br>Zero occurrences of `_SearchSheet` or `_ProductPick`. Replaced by 1-tap booking flow via `_orderProduct` and `showCheckoutSheet`. | `[VERIFIED]` |
| **D2-02** | Truncate raw UUID in notifications | Truncate 32-character hex order ID in notification headline to 8 uppercase characters (`#${o.id.substring(0, 8)}`). | `apps/user_app_donor/lib/features/home/notifications_screen.dart:127`<br>`'Order #${o.id.length > 8 ? o.id.substring(0, 8).toUpperCase() : o.id.toUpperCase()} · ${orderStateLabel(o.state)}'` | `[VERIFIED]` |
| **D2-03** | Neutral surface AppBar in notifications | Replace dark teal `AppBar` with theme-standard neutral `ShodashaTheme.surface` (white) background, `ink` typography, and 0 elevation. | `apps/user_app_donor/lib/features/home/notifications_screen.dart:98-110`<br>`backgroundColor: ShodashaTheme.surface, foregroundColor: ShodashaTheme.ink, elevation: 0, title: Text('Notifications', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: ShodashaTheme.ink))` | `[VERIFIED]` |
| **D2-04** | Token hygiene & spacing alignment | Replace off-scale 2px padding on offline strip, standardize return address modal, and normalize colors to `ShodashaTheme`. | `apps/user_app_donor/lib/features/shell/donor_shell.dart:288-305, 351, 488-492`<br>Shell background: `ShodashaTheme.bg`. Pickup address padding: `EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm)`, icon `ShodashaTheme.teal`. Offline strip padding: `EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm)`. | `[VERIFIED]` |
| **D2-05** | Double-tap back protection on Home tab | Intercept back press with `PopScope`: non-home tabs switch to Home; Home tab enforces 2-second double-tap threshold with `"Press back again to exit"` SnackBar before exiting. | `apps/user_app_donor/lib/features/shell/donor_shell.dart:322-349`<br>`PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) { if (_tab != DonorTab.home) { _selectTab(DonorTab.home); return; } ... })` | `[VERIFIED]` |
| **D2-06** | Elimination of fractional fonts & subscription status polish | Eliminate fractional 12.5px font sizes; parse subscription status into capitalized badges (`Plan · Active`, `Plan · Paused`, `Plan · Cancelled`). | `apps/user_app_donor/lib/features/home/notifications_screen.dart:62, 209-219, 291-307`<br>Subscription title: `'Plan · ${_status(row)}'`. Font sizes normalized to 12px `ShodashaTheme.bodySmall` and 14px `titleSmall`. Chevron padding: `EdgeInsets.only(left: AppSpacing.sm, top: AppSpacing.sm)`. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| NavigationBar destinations | Standard 5-tab hierarchy (`Home`, `Orders`, `Plans`, `Wallet`, `Profile`) | `donor_shell.dart:380-410`<br>5 `NavigationDestination` items with outline/rounded icon pairs and minimum 48dp target. | `[VERIFIED]` |
| Offline retry CTA | Bounded 48dp target with loading indicator | `donor_shell.dart:510-524`<br>`TextButton(style: TextButton.styleFrom(minimumSize: const Size(48, ShodashaTheme.minTarget)))` with `CircularProgressIndicator` on retrying. | `[VERIFIED]` |
| Notifications refresh action | Bounded `IconButton` with tooltip | `notifications_screen.dart:111-116`<br>`IconButton(tooltip: 'Refresh notifications', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))` | `[VERIFIED]` |
| Notification tile surface | Canonical `AppCard` with `onTap` route navigation | `notifications_screen.dart:261-264`<br>`AppCard(onTap: note.onTap, padding: const EdgeInsets.all(AppSpacing.md), child: ...)` | `[VERIFIED]` |
| Empty notifications state | Canonical `AppStateView.empty` | `notifications_screen.dart:181-185`<br>`AppStateView.empty(title: 'No updates yet', message: 'Order and subscription updates will appear here.', icon: Icons.notifications_none_rounded)` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Shell max content constraint | `_maxWidth: 560dp` | `donor_shell.dart:59, 355, 379`<br>`ConstrainedBox(constraints: const BoxConstraints(maxWidth: _maxWidth))` applied to body and navigation bar. | `[VERIFIED]` |
| Offline strip padding | `AppSpacing.lg` (16dp) & `AppSpacing.sm` (8dp) | `donor_shell.dart:488-492`<br>`EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm)`. Replaced off-scale 2px padding. | `[VERIFIED]` |
| Restored strip padding | `AppSpacing.lg` (16dp) & `AppSpacing.sm` (8dp) | `donor_shell.dart:538-542`<br>`EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm)`. | `[VERIFIED]` |
| Pickup address sheet header | `AppSpacing.lg` (16dp) & `AppSpacing.sm` (8dp) | `donor_shell.dart:288-294`<br>`EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm)`. | `[VERIFIED]` |
| Notification tile gaps | `AppSpacing.md` (12dp), `AppSpacing.xs` (4dp), `AppSpacing.sm` (8dp) | `notifications_screen.dart:276, 289, 299, 313`<br>Icon-to-text: `AppSpacing.md`; title-to-body: `AppSpacing.xs`; body-to-date: `AppSpacing.xs`; chevron padding: `AppSpacing.sm`. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Notifications AppBar Title | 18px w700 | `notifications_screen.dart:104-108`<br>`fontSize: 18, fontWeight: FontWeight.w700, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Notification Tile Title | 14px w700 | `notifications_screen.dart:283-287`<br>`fontSize: 14, fontWeight: FontWeight.w700, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Notification Tile Body | 12px w400, height 1.4 | `notifications_screen.dart:292-296`<br>`fontSize: 12, height: 1.4, color: ShodashaTheme.muted`. 12.5px font size eliminated. | `[VERIFIED]` |
| Notification Tile Timestamp | 12px w400 | `notifications_screen.dart:302-306`<br>`fontSize: 12, color: ShodashaTheme.muted` | `[VERIFIED]` |
| Offline Strip Text | 12px w400, height 1.35 | `donor_shell.dart:503-507`<br>`fontSize: 12, height: 1.35, color: ShodashaTheme.warning` | `[VERIFIED]` |
| Restored Strip Text | 12px w600 | `donor_shell.dart:552-556`<br>`fontSize: 12, fontWeight: FontWeight.w600, color: ShodashaTheme.successDark` | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Original String / Issue | Polished String | Code Evidence | Status |
|---|---|---|---|
| Wordy & technical offline string | `"You're offline · Showing saved data"` | `donor_shell.dart:502`<br>Replaced `"No internet — showing what was already loaded."`. | `[VERIFIED]` |
| Trailing period on restored badge | `"Back online"` | `donor_shell.dart:551`<br>Removed trailing period from `"Back online."`. | `[VERIFIED]` |
| Awkward lowercase subscription state | `"Plan · Active"`, `"Plan · Paused"`, `"Plan · Cancelled"` | `notifications_screen.dart:62, 209-219`<br>Capitalized sentence-case status prefix. | `[VERIFIED]` |
| 32-character raw order UUID string | `"Order #B4890211 · Out for delivery"` | `notifications_screen.dart:126-127`<br>Clean 8-character uppercase truncated reference. | `[VERIFIED]` |
| Back exit prompt | `"Press back again to exit"` | `donor_shell.dart:338`<br>Helpful non-jarring feedback on single back press at Home. | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| Tab lazy mounting | IndexedStack mounts tabs only on first visit | `donor_shell.dart:63, 418-424`<br>`_mounted.contains(tab)` ensures zero unnecessary memory overhead. | `[VERIFIED]` |
| Disconnected state | Yellow warning strip with live re-probe action | `donor_shell.dart:358-366, 474-528`<br>`_OfflineStrip` listens to `widget.api.offline`. | `[VERIFIED]` |
| Restored state | Auto-dismissing green toast (3s duration) | `donor_shell.dart:98-103, 530-561`<br>`_RestoredStrip` displays for 3 seconds then safely unmounts. | `[VERIFIED]` |
| Non-home back press | Resets view to Home tab | `donor_shell.dart:326-329`<br>`_selectTab(DonorTab.home)`. | `[VERIFIED]` |
| Empty notifications | Friendly empty state | `notifications_screen.dart:181-185`<br>`AppStateView.empty` with bell icon. | `[VERIFIED]` |
| Stale notifications cache | Pull-to-refresh with fallback banner | `notifications_screen.dart:151-162`<br>`AppBanner.stale` rendered when order or subscription refresh encounters an error. | `[VERIFIED]` |

---

## 7. Verification Test Suite Results

- `test/donor_shell_test.dart` (3 tests): **PASSED**
  - Donor shell mounts and opens all five real tabs.
  - Back button switches to home from non-home tabs and guards exit on home.
  - Donor shell shows calm offline strip with tokenized copy.
- `test/notifications_screen_test.dart` (3 tests): **PASSED**
  - Renders truncated 8-character uppercase order ID.
  - Capitalizes subscription status badges (`Plan · Active`).
  - Neutral surface AppBar rendering verified.
- **Total Shell & Notifications Tests:** **6 / 6 passed** with 0 failures, 0 errors.

---

## Conclusion

File `02-donor-shell-nav.md` is **100% verified** against the current codebase in `apps/user_app_donor`. All P0–P3 unslop items (D2-01 through D2-06), fake search removal, truncated order IDs, surface AppBar, tokenized offline/restored strips, double-tap back protection, and typography scalings are confirmed in code with green test coverage.

