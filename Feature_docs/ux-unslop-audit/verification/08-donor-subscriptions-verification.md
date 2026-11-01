# Verification Report: 08 — Donor App: Subscriptions & Plan Builder

**Document Audited:** `Feature_docs/ux-unslop-audit/08-donor-subscriptions.md`  
**Target Codebase:** `apps/user_app_donor/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **D8-01** | Replace raw button bypasses in empty state & sheets | Migrate raw `ElevatedButton.styleFrom` in `_EmptyState` and `_PauseSheet` to canonical `AppButton`. | `apps/user_app_donor/lib/features/subscriptions/subscription_screen.dart:805-809, 1295-1299`<br>`AppButton(label: subStrings['buildPlan']!, kind: AppButtonKind.primary, icon: Icons.add)` and `AppButton(label: subStrings['pauseConfirm']!, kind: AppButtonKind.primary)`. | `[VERIFIED]` |
| **D8-02** | Declutter plan card action buttons | Relocate destructive "Cancel plan" action from open text row into secondary kebab menu (`PopupMenuButton<String>`), preventing accidental taps. | `apps/user_app_donor/lib/features/subscriptions/subscription_screen.dart:1037-1069`<br>`PopupMenuButton<String>(tooltip: 'More options', ... PopupMenuItem(value: 'cancel', child: Row(children: [Icon(Icons.cancel_outlined, color: ShodashaTheme.danger), Text(subStrings['cancel']!, ...)])))` | `[VERIFIED]` |
| **D8-03** | Modernize skeleton loader container | Replace raw mint green containers in `_SubsSkeleton` with standard neutral surface container and theme skeleton bone elements. | `apps/user_app_donor/lib/features/subscriptions/subscription_screen.dart:560-590`<br>`Container(decoration: BoxDecoration(color: ShodashaTheme.surface, border: Border.all(color: ShodashaTheme.border), ...))` and `Container(color: ShodashaTheme.skeleton)`. | `[VERIFIED]` |
| **D8-04** | Normalize typography & scale in sheets | Normalize plan builder sheet title from 20px w900 to 18px w700, and eliminate off-scale 10.5px / 11.5px fonts in status pills and payment summary to standard 12px. | `apps/user_app_donor/lib/features/subscriptions/plan_builder_sheet.dart:354-362, 406-414`<br>`fontSize: 18, fontWeight: FontWeight.w700` and `fontSize: 12`. `subscription_screen.dart:1106-1114` status pill `fontSize: 12`. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| Empty state "Build a plan" CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`, icon: `Icons.add`) | `subscription_screen.dart:805-809`<br>`AppButton(label: subStrings['buildPlan']!, kind: AppButtonKind.primary, icon: Icons.add, onPressed: _buildPlan)` | `[VERIFIED]` |
| Plan card Cancel action | Accessible `PopupMenuButton<String>` with danger styling and min 48dp target | `subscription_screen.dart:1037-1069`<br>`PopupMenuButton<String>(tooltip: 'More options', icon: Icon(Icons.more_vert_rounded, size: 20))` | `[VERIFIED]` |
| Pause sheet confirm CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`) | `subscription_screen.dart:1295-1299`<br>`AppButton(label: subStrings['pauseConfirm']!, kind: AppButtonKind.primary, onPressed: _confirm)` | `[VERIFIED]` |
| Cancel sheet confirm CTA | Canonical `AppButton` (`kind: AppButtonKind.danger`) | `subscription_screen.dart:1477-1481`<br>`AppButton(label: subStrings['cancelConfirm']!, kind: AppButtonKind.danger, onPressed: _confirm)` | `[VERIFIED]` |
| Dues strip payment CTA | Canonical `AppButton` (`kind: AppButtonKind.money`, `expand: false`) | `subscription_screen.dart:735-740`<br>`AppButton(label: subStrings['payDues']!, kind: AppButtonKind.money, expand: false, onPressed: _payDues)` | `[VERIFIED]` |
| Start plan CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`) with busy indicator | `plan_builder_sheet.dart:400-404`<br>`AppButton(label: subStrings['startPlan']!, busy: _submitting, onPressed: canSubmit ? _submit : null)` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Subscription screen list padding | `fromLTRB(16, 8, 16, 24)` with 12dp item separators | `subscription_screen.dart:514-522, 557-559`<br>`EdgeInsets.fromLTRB(16, 8, 16, 24)` and `SizedBox(height: 12)`. | `[VERIFIED]` |
| Plan card padding | `AppSpacing.lg` (16dp) | `subscription_screen.dart:865-870`<br>`padding: const EdgeInsets.all(AppSpacing.lg)`. | `[VERIFIED]` |
| Plan builder sheet padding | `fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, ...)` | `plan_builder_sheet.dart:336-342`<br>`EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, ...)` | `[VERIFIED]` |
| Plan builder vertical header gap | Standardized `AppSpacing.lg` (16dp) | `plan_builder_sheet.dart:363`<br>`SizedBox(height: AppSpacing.lg)`. | `[VERIFIED]` |
| Action row divider & spacing | `AppSpacing.sm` (8dp), `AppSpacing.xs` (4dp) | `subscription_screen.dart:998-1000`<br>`SizedBox(height: AppSpacing.sm)` and `AppSpacing.xs`. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Plan Builder Title | 18px w700, letterSpacing -0.2 | `plan_builder_sheet.dart:356-361`<br>`fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Status Pill Label | 12px w800, letterSpacing 0.3 | `subscription_screen.dart:1108-1113`<br>`fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3` (off-scale 10.5px eliminated) | `[VERIFIED]` |
| Payment Summary Disclaimer | 12px, height 1.35, muted | `plan_builder_sheet.dart:409-413`<br>`fontSize: 12, height: 1.35, color: ShodashaTheme.muted` (off-scale 11.5px eliminated) | `[VERIFIED]` |
| Dues Amount Display | 22px w900, ink | `subscription_screen.dart:719-724`<br>`fontSize: 22, fontWeight: FontWeight.w900, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Dues Eyebrow | 11px w800, letterSpacing 0.4, tealDeep | `subscription_screen.dart:708-713`<br>`fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: ShodashaTheme.tealDeep` | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Finding | Expected Copy | Code Evidence | Status |
|---|---|---|---|
| Empty state title & body | Calm, supportive onboarding | `subscription_screen.dart:793-802`<br>`subStrings['emptyTitle']` ("No active plans") and `subStrings['emptyBody']` ("Set up daily, alternate-day, or weekly deliveries..."). | `[VERIFIED]` |
| Late skip alert dialog | Direct helpline guidance with `kSupportPhone` | `subscription_screen.dart:216-224`<br>`${subStrings['lateSkipBody']}$kSupportPhone${subStrings['lateSkipTail']}`. | `[VERIFIED]` |
| Honest cancellation refund copy | Transparent refund expectations (no false wallet promises) | `subscription_screen.dart:1340-1348`<br>`subStrings['cancelNote']` ("Cancelling will stop all future scheduled deliveries. Any uncollected refund is credited to your provided UPI ID."). | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Edge Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| Initial loading skeleton | Non-blocking neutral bone skeleton (`_SubsSkeleton`) | `subscription_screen.dart:484-486, 552-595`<br>`if (c.status == SubStatus.loading && c.items.isEmpty) return const _SubsSkeleton();` | `[VERIFIED]` |
| Stale list on network failure | Non-blocking amber `_StaleBanner` with cached list preserved | `subscription_screen.dart:523-535, 626-665`<br>`if (c.stale) const _StaleBanner()`. Retains cached plans in list view. | `[VERIFIED]` |
| Signed-out plan builder | Inline `_SignedOutNote` with direct sign-in hook | `plan_builder_sheet.dart:364-367`<br>`if (_signedOut) _SignedOutNote(onSignIn: ...)`. | `[VERIFIED]` |
| Missing delivery address | Notice banner directing user to address setup flow | `plan_builder_sheet.dart:642-687`<br>`if (_addresses.isEmpty) Container(..., child: Text('Add address'))`. | `[VERIFIED]` |
| Idempotent plan submission | Dynamic UUIDv4 regenerated upon parameter modifications | `plan_builder_sheet.dart:286-291`<br>`_idemKey = const Uuid().v4();` refreshed on rhythm/billing/qty alterations. | `[VERIFIED]` |

---

## 7. File Invariants & Verification Checklist

- [x] Invariant: Server-authoritative dues (`GET /billing/dues`) and estimates (`POST /subscriptions/estimate`) without client math (`subscription_screen.dart:6-7`).
- [x] Invariant: Minimum 24h guard on delivery resumption enforced (`subscription_screen.dart:174`).
- [x] Invariant: Cancellation requires valid UPI ID and does not guarantee immediate refunds (`subscription_screen.dart:1340-1348`).
- [x] Invariant: Mobile viewports (360dp) protected from destructive misclicks via `PopupMenuButton` isolation.

---

## 8. Automated Test Verification

Targeted subscription test suite execution:
- `apps/user_app_donor/test/subscription_screen_test.dart`
- `apps/user_app_donor/test/subscription_billing_test.dart`

**Command Output:**
```
00:00 +0: C:/Users/Hp/Water/apps/user_app_donor/test/subscription_screen_test.dart: empty state renders AppButton with primary styling for build plan
00:01 +3: C:/Users/Hp/Water/apps/user_app_donor/test/subscription_billing_test.dart: subscription billing payload monthly prepaid sends UPI and shows the server top-up
00:02 +5: C:/Users/Hp/Water/apps/user_app_donor/test/subscription_billing_test.dart: subscription billing payload prepaid card shows awaiting payment, balance and top-up
00:02 +6: All tests passed!
```
Status: **6 / 6 passed** (100% green).

