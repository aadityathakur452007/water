# Verification Report: 01 — Donor App: Auth, Shell Entry & Onboarding

**Document Audited:** `Feature_docs/ux-unslop-audit/01-donor-auth.md`  
**Target Codebase:** `apps/user_app_donor/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **D1-01** | Hero visual & background unslop | Remove stock photo (`login_hero.jpg`) and `tealTint` giant bubble background. Replace with tactile 20L canister emblem on neutral `surface`. | `apps/user_app_donor/lib/features/auth/login_screen.dart:461-531`<br>`Scaffold(backgroundColor: ShodashaTheme.surface)` with 64×64dp `ShodashaTheme.tealTint` container, `Icons.water_drop_rounded`, 24px w800 title, and quiet trust pill `RO+UV · Lab Tested · Bhopal`. | `[VERIFIED]` |
| **D1-02** | Form tokens & spacing hygiene | Standardize form inputs with theme tokens, removing 12.5px font sizes and off-scale 14px gaps. | `apps/user_app_donor/lib/features/auth/login_screen.dart:217-370, 534-586`<br>All gaps migrated to `AppSpacing` tokens (`xs`: 4dp, `sm`: 8dp, `md`: 12dp, `lg`: 16dp, `xl`: 24dp). 12.5px eliminated in favor of 12px `ShodashaTheme.bodySmall`. Borders use `ShodashaTheme.radius` (12dp) and theme colors. | `[VERIFIED]` |
| **D1-03** | 409 Account Exists focus shift | Auto-focus password field when 409 `ACCOUNT_EXISTS` pivots registration to sign-in. | `apps/user_app_donor/lib/features/auth/login_screen.dart:126-128`<br>`WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _passwordFocus.requestFocus(); });` | `[VERIFIED]` |
| **D1-04** | AuthGate false error notice on cold boot | Eliminate false `"Couldn't restore session"` notice on first-time clean install or timeout. | `apps/user_app_donor/lib/features/auth/auth_gate.dart:51-57`, `apps/user_app_donor/lib/features/auth/auth_controller.dart:562-569`<br>Timeout/error in `restoreSession()` safely falls back to idle with `_sessionNotice = null`. Banner only displays when explicitly flagged by forced logout. | `[VERIFIED]` |
| **D1-05** | First-run address prompt dismiss guard | Prevent outside scrim tap from permanently silencing first-run address prompt. | `apps/user_app_donor/lib/features/addresses/first_run_sheet.dart:54-60`<br>`if (add != null) { await markFirstRunDone(); }`<br>Dismissing sheet via scrim tap leaves flag unset so prompt can re-surface. | `[VERIFIED]` |
| **D1-06** | Prune dead fields and unused constants | Remove unused `newDeviceAlert`, `verified`, and dead string constants. | `apps/user_app_donor/lib/features/auth/auth_controller.dart:24-63, 140-146`, `apps/user_app_donor/lib/core/auth_impls.dart:20-25`<br>`newDeviceAlert`, `verified`, `signingIn`, `creating`, `terms`, `rateLimitedWait`, and `newDevice` completely pruned. | `[VERIFIED]` |
| **D1-07** | Notice banner tokenization | Tokenize notice banners to design system tokens with clean semantics. | `apps/user_app_donor/lib/features/auth/login_screen.dart:688-732`<br>Notice banner uses `ShodashaTheme.solarTint`/`solarBorder`/`warning` for warning tone and `ShodashaTheme.etaTint`/`tealDark`/`link` for info tone. Padding: `AppSpacing.md`, radius: `ShodashaTheme.radius`. | `[VERIFIED]` |
| **D1-08** | Canonical tagline harmonization | Harmonize canonical tagline across all auth entry points. | `apps/user_app_donor/lib/features/auth/login_screen.dart:502`<br>`apps/user_app_donor/lib/features/auth/auth_gate.dart:130`<br>`apps/user_app_donor/lib/features/auth/auth_controller.dart:26`<br>All consistently read: `"Pure 20L water delivered to your doorstep"`. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| Primary submit CTA | Canonical `AppButton` with `busy` spinner | `login_screen.dart:418-422`<br>`AppButton(label: create ? authStrings['createGo']! : authStrings['signInGo']!, busy: _submitting, onPressed: _submit)` | `[VERIFIED]` |
| First-run primary action | Canonical `AppButton` | `first_run_sheet.dart:116-119`<br>`AppButton(label: 'Add address', onPressed: () => Navigator.of(context).pop(true))` | `[VERIFIED]` |
| First-run secondary action | Minimum 48dp touch target `TextButton` | `first_run_sheet.dart:121-128`<br>`TextButton(style: TextButton.styleFrom(minimumSize: const Size.fromHeight(ShodashaTheme.minTarget)))` | `[VERIFIED]` |
| Forgot password button | Minimum 48dp touch target | `login_screen.dart:404`<br>`minimumSize: const Size(48, 48)` | `[VERIFIED]` |
| Mode switch button | Minimum 48dp touch target | `login_screen.dart:430`<br>`minimumSize: const Size(48, 48)` | `[VERIFIED]` |
| Password eye toggles | Bounded `IconButton` with accessibility tooltip | `login_screen.dart:619-628`<br>`IconButton(tooltip: visible ? 'Hide password' : 'Show password', ...)` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Page padding & container max-width | `kMaxContentWidth` (560dp) & `AppSpacing.lg` | `login_screen.dart:209-221`<br>`ConstrainedBox(constraints: BoxConstraints(maxWidth: kMaxContentWidth))` with `EdgeInsets.symmetric(horizontal: AppSpacing.lg)`. | `[VERIFIED]` |
| Hero spacing | `AppSpacing.xl`, `AppSpacing.sm`, `AppSpacing.xs` | `login_screen.dart:463-511`<br>Padding: `fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.sm)`; gaps: `AppSpacing.sm` (8dp), `AppSpacing.xs` (4dp). | `[VERIFIED]` |
| Form inter-field spacing | `AppSpacing.lg` (16dp) | `login_screen.dart:262, 279, 298, 330, 369`<br>All field gaps are `SizedBox(height: AppSpacing.lg)`. | `[VERIFIED]` |
| Label and helper micro-gaps | `AppSpacing.xs` (4dp) | `login_screen.dart:251, 321, 535`<br>Label and helper spacing use `AppSpacing.xs`. | `[VERIFIED]` |
| Button and action row spacing | `AppSpacing.md` (12dp) | `login_screen.dart:423`<br>`SizedBox(height: AppSpacing.md)`. | `[VERIFIED]` |
| First-run sheet padding & gaps | `AppSpacing.xl`, `AppSpacing.lg`, `AppSpacing.md`, `AppSpacing.sm` | `first_run_sheet.dart:71-120`<br>Padding: `fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.md)`; icon gap `AppSpacing.lg`, subtitle gap `AppSpacing.xs`, CTA gap `AppSpacing.lg`. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Screen Titles | 20px w800, letterSpacing -0.4 | `login_screen.dart:244-249`<br>`fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Subtitles | 14px w400, height 1.4 | `login_screen.dart:256-260`<br>`fontSize: 14, height: 1.4, color: ShodashaTheme.muted` | `[VERIFIED]` |
| Form Inputs | 16px w400 | `login_screen.dart:271, 287, 311, 341, 378`<br>`fontSize: 16, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Input Labels | 13px w700 | `login_screen.dart:538-542`<br>`fontSize: 13, fontWeight: FontWeight.w700, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Helper & Microcopy | 12px w400/w700 | `login_screen.dart:324-328, 450-454, 672-676`<br>`fontSize: 12, height: 1.4`. No fractional fonts (12.5px eliminated). | `[VERIFIED]` |
| Hero Brand Header | 24px w800, height 1.15 | `login_screen.dart:492-498`<br>`fontSize: 24, fontWeight: FontWeight.w800, color: ShodashaTheme.tealDeep` | `[VERIFIED]` |
| Trust Pill | 11px w600 | `login_screen.dart:521-526`<br>`fontSize: 11, fontWeight: FontWeight.w600, color: ShodashaTheme.tealDeep` | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Original String / Issue | Polished String | Code Evidence | Status |
|---|---|---|---|
| Trailing period on subtitle | `"Sign in with your mobile number and password"` | `auth_controller.dart:28`<br>Trailing period removed. | `[VERIFIED]` |
| Trailing period on subtitle | `"One account for every delivery"` | `auth_controller.dart:30`<br>Trailing period removed. | `[VERIFIED]` |
| Internal engineer jargon | `"By creating an account, you agree to Shodasha Terms & Privacy Policy."` | `login_screen.dart:446-448`<br>Removed `"Shodasha customer app · Password protected"`. | `[VERIFIED]` |
| Curt technical rate limit | `"Try again in $wait seconds"` | `login_screen.dart:671`<br>Replaced `"Try again in ${wait}s."`. | `[VERIFIED]` |
| Blaming session notice | `"Please sign in to continue"` | `auth_controller.dart:61`<br>Replaced `"Couldn't restore your session. Sign in again."`. | `[VERIFIED]` |
| Weak first-run prompt | `"Where should we deliver?"` / `"Save your address once for 1-tap reordering. You can edit it anytime."` | `first_run_sheet.dart:97, 107`<br>Clean, customer-centric value proposition. | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| Cold boot | Splash while session is verified (20s ceiling) | `auth_gate.dart:43-57, 100-146`<br>`_AuthSplash` with asset logo, progress indicator, and 20s timeout protection. | `[VERIFIED]` |
| Form submission | Busy spinner and input disablement | `login_screen.dart:418-422`<br>`_submitting` disables all text fields and sets `AppButton.busy`. | `[VERIFIED]` |
| 409 Account Exists | Auto-pivot + focus password field | `login_screen.dart:118-130`<br>Pivots to sign-in, retains phone, displays info banner, and schedules `_passwordFocus.requestFocus()`. | `[VERIFIED]` |
| Rate limiting (429) | 1-second countdown ticker with button lock | `login_screen.dart:70-79, 667-678`<br>`_startRateTimer()` updates countdown UI every second until unlocked. | `[VERIFIED]` |
| Network / 5xx error | Friendly retryable banner | `login_screen.dart:630-685`<br>`_errorPanel()` renders error message with tokenized danger styling. | `[VERIFIED]` |
| Scrim tap dismiss | Non-destructive onboarding deferral | `first_run_sheet.dart:54-60`<br>Tapping outside bottom sheet leaves `firstrun_done_v1` false. | `[VERIFIED]` |

---

## 7. Verification Test Suite Results

- `test/auth_gate_test.dart` (4 tests): **PASSED**
- `test/auth_password_test.dart` (19 tests): **PASSED**
- `test/login_screen_test.dart` (6 tests): **PASSED**
- `test/first_run_sheet_test.dart` (2 tests): **PASSED**
- **Total Auth Unit Tests:** **31 / 31 passed** with 0 failures, 0 errors.

---

## Conclusion

File `01-donor-auth.md` is **100% verified** against the current codebase in `apps/user_app_donor`. All P0–P3 unslop items (D1-01 through D1-08), component migrations, token adoptions, typography scale normalizations, copy polish, and state transitions are confirmed in production code with green test coverage.

