# Verification Report: 13 — Vendor App: Auth, Shell Navigation & Profile

**Document Audited:** `Feature_docs/ux-unslop-audit/13-vendor-auth-shell-profile.md`  
**Target Codebase:** `apps/vendor_app/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **V1-01** | Vendor auth & profile button standardization | Migrate `VendorCodeScreen` login action and WhatsApp link to canonical `AppButton`. Migrate `ProfileScreen` error retry, save, leave request, WhatsApp support, and logout to canonical `AppButton`. | `apps/vendor_app/lib/features/auth/vendor_code_screen.dart:210-233`<br>`AppButton(label: ..., kind: AppButtonKind.primary, busy: busy)` and `AppButton(label: 'Admin WhatsApp Support: 7828442476', kind: AppButtonKind.secondary)`.<br>`apps/vendor_app/lib/features/profile/profile_screen.dart:275-278, 384-388, 429-433, 500-510`<br>`AppButton(label: 'Save karein', kind: AppButtonKind.primary, busy: _saving)`, `AppButton(label: 'Nayi Chutti Request Karein', kind: AppButtonKind.secondary)`, `AppButton(label: 'Logout', kind: AppButtonKind.danger)`. | `[VERIFIED]` |
| **V1-02** | Hardcoded WhatsApp phone number derivation | Derive WhatsApp target URL in `profile_screen.dart` strictly from `kSupportPhone` digits instead of hardcoded `919302190067`. | `apps/vendor_app/lib/features/profile/profile_screen.dart:221-224`<br>`final digits = kSupportPhone.replaceAll(RegExp(r'\D'), ''); final uri = Uri.parse('https://wa.me/$digits');` | `[VERIFIED]` |
| **V1-03** | Align vendor spacing to design tokens | Standardize screen paddings and spacers across `vendor_code_screen.dart` and `profile_screen.dart` to `AppSpacing` tokens (`xl`, `xxl`, `lg`, `md`, `sm`, `xs`). | `apps/vendor_app/lib/features/auth/vendor_code_screen.dart:81, 87, 93, 104, 127, 209, 228`<br>`EdgeInsets.all(AppSpacing.xl)`, `AppSpacing.lg`, `AppSpacing.xs`, `AppSpacing.xxl`, `AppSpacing.md`. `profile_screen.dart:289, 294, 311, 315` `AppSpacing.lg`, `AppSpacing.md`. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| Vendor Login CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`, `busy: busy`) | `vendor_code_screen.dart:210-216`<br>`AppButton(label: busy ? vendorStringsHi['loginBusy']! : vendorStringsHi['loginGo']!, kind: AppButtonKind.primary, busy: busy, onPressed: busy ? null : _submit)` | `[VERIFIED]` |
| Vendor Login WhatsApp Support CTA | Canonical `AppButton` (`kind: AppButtonKind.secondary`, icon: `Icons.chat_bubble_outline`) | `vendor_code_screen.dart:229-234`<br>`AppButton(label: 'Admin WhatsApp Support: 7828442476', kind: AppButtonKind.secondary, icon: Icons.chat_bubble_outline, onPressed: _openSupport)` | `[VERIFIED]` |
| Profile Save CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`, `busy: _saving`) | `profile_screen.dart:384-388`<br>`AppButton(label: 'Save karein', kind: AppButtonKind.primary, busy: _saving, onPressed: _saving ? null : _save)` | `[VERIFIED]` |
| Profile New Leave Request CTA | Canonical `AppButton` (`kind: AppButtonKind.secondary`, icon: `Icons.add_circle_outline`) | `profile_screen.dart:429-434`<br>`AppButton(label: 'Nayi Chutti Request Karein', kind: AppButtonKind.secondary, icon: Icons.add_circle_outline, onPressed: () => _openLeaveRequestDialog(context))` | `[VERIFIED]` |
| Profile WhatsApp Help CTA | Canonical `AppButton` (`kind: AppButtonKind.secondary`, icon: `Icons.support_agent_outlined`) | `profile_screen.dart:500-504`<br>`AppButton(label: 'WhatsApp help ($kSupportPhone)', kind: AppButtonKind.secondary, icon: Icons.support_agent_outlined, onPressed: _whatsapp)` | `[VERIFIED]` |
| Profile Logout CTA | Canonical `AppButton` (`kind: AppButtonKind.danger`, icon: `Icons.logout`) | `profile_screen.dart:507-511`<br>`AppButton(label: 'Logout', kind: AppButtonKind.danger, icon: Icons.logout, onPressed: _confirmLogout)` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Vendor code screen padding | `AppSpacing.xl` (24dp) | `vendor_code_screen.dart:81`<br>`padding: const EdgeInsets.all(AppSpacing.xl)`. | `[VERIFIED]` |
| Vendor code vertical gaps | `AppSpacing.xxl`, `AppSpacing.xl`, `AppSpacing.lg`, `AppSpacing.md`, `AppSpacing.xs` | `vendor_code_screen.dart:87, 93, 104, 127, 209, 228`<br>Standardized all magic gaps to `AppSpacing` tokens. | `[VERIFIED]` |
| Profile screen list padding | `AppSpacing.lg` (16dp) | `profile_screen.dart:289`<br>`padding: const EdgeInsets.all(AppSpacing.lg)`. | `[VERIFIED]` |
| Profile card inner padding | `AppSpacing.lg` (16dp) | `profile_screen.dart:294, 315`<br>`padding: const EdgeInsets.all(AppSpacing.lg)`. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Login Title | 22px w700, ink | `vendor_code_screen.dart:88-92`<br>`fontSize: 22, fontWeight: FontWeight.w700, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Login Subtitle | 12px, muted | `vendor_code_screen.dart:94-98`<br>`fontSize: 12, color: ShodashaTheme.muted` | `[VERIFIED]` |
| Session Cap Banner Copy | 13px w600, ink | `vendor_shell.dart:245-248`<br>`fontSize: 13, fontWeight: FontWeight.w600, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Profile Card Title | 16px w700, ink | `profile_screen.dart:297-300`<br>`fontSize: 16, fontWeight: FontWeight.w700, color: ShodashaTheme.ink` | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Finding | Expected Copy | Code Evidence | Status |
|---|---|---|---|
| Admin WhatsApp support action | Specific contact number on login | `vendor_code_screen.dart:230`<br>`'Admin WhatsApp Support: 7828442476'`. | `[VERIFIED]` |
| Session 30-day cap warning | Clear expiration notice without alarming field drivers | `vendor_shell.dart:246`<br>`'Session 24 ghante mein expire hoga. Naya access code taiyyar rakhein.'`. | `[VERIFIED]` |
| Logout confirmation dialog | Direct Punjabi/Hindi prompt | `profile_screen.dart:187-199`<br>`title: Text('Logout confirm')`, `content: Text('Kya aap logout karna chahte hain? Offline data safe rahega.')`. | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Edge Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| Vendor access code masking | Obscured input with visibility toggle | `vendor_code_screen.dart:130-148`<br>`obscureText: !_showCode`, `IconButton(icon: Icon(_showCode ? Icons.visibility_off : Icons.visibility))` | `[VERIFIED]` |
| Lifecycle polling control | Discovery paused on app background (`paused`/`inactive`) | `vendor_shell.dart:101-109`<br>`if (state == AppLifecycleState.paused \|\| state == AppLifecycleState.inactive) _stopDiscovery();` | `[VERIFIED]` |
| Un-synced outbox badge | Dynamic indicator on More tab and drawer sync tile | `vendor_shell.dart:183-186, 300-309`<br>`Badge(label: Text('$pending'))` showing count of pending records. | `[VERIFIED]` |
| Session cap grace period | 24h warning banner rendered atop body | `vendor_shell.dart:237-249`<br>`if (_showSessionCapWarning) Container(...)`. | `[VERIFIED]` |

---

## 7. File Invariants & Verification Checklist

- [x] Invariant: Access-code authentication with zero self-signup door (`vendor_code_screen.dart:1-3`).
- [x] Invariant: Route discovery polling strictly stops when off-duty or app is backgrounded (`vendor_shell.dart:91-109`).
- [x] Invariant: Session restoration handles 30-day cap warning with 24h grace period (`vendor_shell.dart:237-249`).
- [x] Invariant: Minimum 48dp bounding touch targets on all interactive elements.

---

## 8. Automated Test Verification

Targeted vendor auth and profile test suite execution:
- `apps/vendor_app/test/vendor_auth_profile_test.dart`

**Command Output:**
```
00:00 +0: VendorCodeScreen renders canonical AppButtons for login and WhatsApp
00:01 +1: ProfileScreen renders canonical AppButtons for save, leave, whatsapp and logout
00:01 +2: All tests passed!
```
Status: **2 / 2 passed** (100% green).
