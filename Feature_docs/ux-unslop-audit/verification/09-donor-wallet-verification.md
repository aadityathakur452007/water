# Verification Report: 09 — Donor App: Wallet & Payment History

**Document Audited:** `Feature_docs/ux-unslop-audit/09-donor-wallet.md`  
**Target Codebase:** `apps/user_app_donor/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **D9-01** | Redundant custody metrics across hero & card | Remove duplicated "Jars with you" row from "Deposit details" card since count is prominently badged in hero card. | `apps/user_app_donor/lib/features/wallet/donor_wallet_screen.dart:378-404`<br>`AppCard` details card contains only 'Deposit paid', 'Deposit refunded', and 'Outstanding dues'. Redundant jar count row pruned. | `[VERIFIED]` |
| **D9-02** | Zero-jar state breaks action tile visual grid | Preserve card grid rhythm on zero-jar custody by rendering a permanent, quiet disabled `_actionTile` instead of raw text. | `apps/user_app_donor/lib/features/wallet/donor_wallet_screen.dart:253-264, 483-535`<br>`_actionTile(..., subtitle: '0 jars in custody · Pickup unlocks when you have empty jars', disabled: true)`. Grid rhythm intact. | `[VERIFIED]` |
| **D9-03** | Confusing cross-tab dues redirect | Update dues action label to "Review dues in Plans" and provide explicit copy explaining that dues from monthly subscriptions/deliveries are settled in Plans. | `apps/user_app_donor/lib/features/wallet/donor_wallet_screen.dart:437-453`<br>Copy: "...Dues from monthly plans and deliveries are reviewed and cleared in the Plans tab." Button: `AppButton(label: 'Review dues in Plans', ...)`. | `[VERIFIED]` |
| **D9-04** | Payment history error state button bypass | Migrate `PaymentHistoryScreen._ErrorState` buttons from raw `ElevatedButton`/`OutlinedButton` to canonical `AppButton`; normalize message font to 14px. | `apps/user_app_donor/lib/features/wallet/payment_history_screen.dart:474-493`<br>`AppButton(label: 'Sign in', kind: AppButtonKind.primary)` and `AppButton(label: 'Try again', kind: AppButtonKind.secondary)`. Message `fontSize: 14`. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| Dues settlement CTA | Canonical `AppButton` (`kind: AppButtonKind.money`, `height: 48`) | `donor_wallet_screen.dart:448-454`<br>`AppButton(label: 'Review dues in Plans', kind: AppButtonKind.money, height: 48, onPressed: widget.onOpenSubscriptions)` | `[VERIFIED]` |
| Payment history retry CTA | Canonical `AppButton` (`kind: AppButtonKind.secondary`) | `payment_history_screen.dart:488-492`<br>`AppButton(label: 'Try again', kind: AppButtonKind.secondary, onPressed: () => onRetry())` | `[VERIFIED]` |
| Payment history sign-in CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`) | `payment_history_screen.dart:481-486`<br>`AppButton(label: 'Sign in', kind: AppButtonKind.primary, onPressed: onSignIn)` | `[VERIFIED]` |
| Action tiles | Accessible `AppCard` with min 56dp height and 48dp touch bounds | `donor_wallet_screen.dart:483-535`<br>`_actionTile` wrapping `AppCard(onTap: disabled ? null : onTap)` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Wallet outer padding | `fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl)` | `donor_wallet_screen.dart:184-188`<br>`EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl)`. | `[VERIFIED]` |
| Hero card padding & radius | `AppSpacing.lg` (16dp), `radiusLg` (16dp) | `donor_wallet_screen.dart:321-326`<br>`padding: const EdgeInsets.all(AppSpacing.lg)` and `BorderRadius.circular(ShodashaTheme.radiusLg)`. | `[VERIFIED]` |
| Card separators & gaps | `AppSpacing.md` (12dp), `AppSpacing.sm` (8dp), `AppSpacing.xs` (4dp) | `donor_wallet_screen.dart:234, 377, 436, 447`<br>`SizedBox(height: AppSpacing.md)`, `AppSpacing.sm`, `AppSpacing.xs`. | `[VERIFIED]` |
| Error state padding | `AppSpacing.xl` (24dp) | `payment_history_screen.dart:464`<br>`padding: const EdgeInsets.all(AppSpacing.xl)`. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Hero Deposit Amount | 32px w800, letterSpacing -0.6, white | `donor_wallet_screen.dart:347-353`<br>`fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: Colors.white` | `[VERIFIED]` |
| Hero Custody Pill | 12px w700, tealDeep on tealTint | `donor_wallet_screen.dart:367-372`<br>`fontSize: 12, fontWeight: FontWeight.w700, color: ShodashaTheme.tealDeep` | `[VERIFIED]` |
| Dues Body Copy | 12px, height 1.4, onSolar | `donor_wallet_screen.dart:441-445`<br>`fontSize: 12, height: 1.4, color: ShodashaTheme.onSolar` (off-scale 12.5px eliminated) | `[VERIFIED]` |
| Error State Message | 14px, muted | `payment_history_screen.dart:476`<br>`fontSize: 14, color: ShodashaTheme.muted` (normalized from 15px) | `[VERIFIED]` |
| Outstanding Dues Title | 14px w700, onSolar | `donor_wallet_screen.dart:427-431`<br>`fontSize: 14, fontWeight: FontWeight.w700, color: ShodashaTheme.onSolar` | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Finding | Expected Copy | Code Evidence | Status |
|---|---|---|---|
| Zero jars custody state | Calm, explanatory disabled tile | `donor_wallet_screen.dart:259`<br>`'0 jars in custody · Pickup unlocks when you have empty jars'`. | `[VERIFIED]` |
| Cross-tab dues routing | Explicit context linking to Plans tab | `donor_wallet_screen.dart:437-440, 449`<br>`'Clear dues to keep cash on delivery available... Dues from monthly plans and deliveries are reviewed and cleared in the Plans tab.'` / `'Review dues in Plans'`. | `[VERIFIED]` |
| Stale ledger banner | Calm stale message without alarm | `donor_wallet_screen.dart:219-224`<br>`AppBanner.stale(onRetry: ...)`. | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Edge Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| Initial loading (no cache) | Skeleton/loading state without fake zero balance | `donor_wallet_screen.dart:189-195`<br>`if (state.loading && state.ledger == null) return AppStateView.loading(...)`. | `[VERIFIED]` |
| Zero jars custody return tap | Disabled tile; prevents launching empty return flow | `donor_wallet_screen.dart:110-114, 260-262`<br>`if (ledger.heldJars <= 0) return;` / `disabled: true`. | `[VERIFIED]` |
| Outstanding dues banner | Conditioned strictly on `duesPaise > 0` | `donor_wallet_screen.dart:227-231`<br>`if (ledger.duesPaise > 0) _duesCard(ledger.duesPaise)`. | `[VERIFIED]` |
| Double-tap navigation guard | Prevent multiple pushes to payment history | `donor_wallet_screen.dart:44, 99-106`<br>`if (_pushing) return; _pushing = true; ... finally { _pushing = false; }`. | `[VERIFIED]` |

---

## 7. File Invariants & Verification Checklist

- [x] Invariant: Ledger is strictly server-authoritative (`GET /v1/ledger/me`); zero client-side balance math (`wallet_controller.dart:1-7`).
- [x] Invariant: No fake-zero balance flashes while loading (`wallet_controller.dart:5-7`).
- [x] Invariant: All rupee figures formatted via `formatInr(paise)` from integer values.
- [x] Invariant: Minimum 48dp bounding touch targets on all interactive elements.

---

## 8. Automated Test Verification

Targeted wallet test suite execution:
- `apps/user_app_donor/test/donor_wallet_screen_test.dart`

**Command Output:**
```
00:00 +0: zero-jar custody renders quiet disabled action tile without layout collapse
00:00 +1: active custody deduplicates jars count and shows dues action with Plans context
00:01 +2: All tests passed!
```
Status: **2 / 2 passed** (100% green).
