# Verification Report: 12 — Donor App: Support & Jar Returns

**Document Audited:** `Feature_docs/ux-unslop-audit/12-donor-support-returns.md`  
**Target Codebase:** `apps/user_app_donor/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **D12-01** | Visual hierarchy inversion on support screen | Invert section ordering in `SupportScreen` to elevate "Complaints" (`_ComplaintEntryCard` and `_ComplaintsSection`) above "Common questions" FAQs. | `apps/user_app_donor/lib/features/support/support_screen.dart:236-255`<br>Listview children order: `_HelplineCard`, `const _SectionLabel('Complaints')`, `_ComplaintEntryCard(...)`, `_ComplaintsSection(...)`, `const _SectionLabel('Common questions')`. | `[VERIFIED]` |
| **D12-02** | Helpline card internal padding standardization | Normalize `_HelplineCard` internal padding from 18dp to `AppSpacing.lg` (16dp). | `apps/user_app_donor/lib/features/support/support_screen.dart:278-283`<br>`padding: const EdgeInsets.all(AppSpacing.lg)`. | `[VERIFIED]` |
| **D12-03** | Return sheet hardcoded padding elimination | Replace hardcoded `20dp` padding in `ReturnSheet` with canonical `AppSpacing` tokens (`EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg + bottom)`). | `apps/user_app_donor/lib/features/returns/return_sheet.dart:100-105`<br>`padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom)`. | `[VERIFIED]` |
| **D12-04** | Normalize return sheet headers and typography scale | Scale `ReturnSheet` title and success headers from 20px w900 to 18px w700 (`titleLarge`), eliminate fractional 12.5px font sizes on summaries. | `apps/user_app_donor/lib/features/returns/return_sheet.dart:134-139, 319-324`<br>Title: `fontSize: 18, fontWeight: FontWeight.w700`. Success: `fontSize: 18, fontWeight: FontWeight.w700`. | `[VERIFIED]` |
| **D12-05** | Standardize sheet vertical spacers & add Done CTA | Standardize sheet vertical spacers to `AppSpacing.lg` (16dp); provide explicit `AppButton(label: 'Done')` on return success view. | `apps/user_app_donor/lib/features/returns/return_sheet.dart:311, 392-396`<br>`SizedBox(height: AppSpacing.lg)` and `AppButton(label: 'Done', onPressed: () => Navigator.of(context).pop(request))`. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| Helpline WhatsApp CTA | Canonical `AppButton` (`kind: AppButtonKind.secondary`, icon: `Icons.chat_outlined`) | `support_screen.dart:354-360`<br>`AppButton(label: 'WhatsApp', icon: Icons.chat_outlined, kind: AppButtonKind.secondary, onPressed: onWhatsApp)` | `[VERIFIED]` |
| Helpline Call CTA | Canonical `AppButton` (`kind: AppButtonKind.secondary`, icon: `Icons.call_outlined`) | `support_screen.dart:363-369`<br>`AppButton(label: 'Call us', icon: Icons.call_outlined, kind: AppButtonKind.secondary, onPressed: onCall)` | `[VERIFIED]` |
| Return sheet Submit CTA | Sticky `AppButton` (`kind: AppButtonKind.primary`, `busy: _controller.busy`) | `return_sheet.dart:282-286`<br>`AppButton(label: 'Send return request', busy: _controller.busy, onPressed: canSubmit ? _submit : null)` | `[VERIFIED]` |
| Return sheet Success Done CTA | Full-width `AppButton` (`kind: AppButtonKind.primary`) dismissing sheet | `return_sheet.dart:393-396`<br>`AppButton(label: 'Done', onPressed: () => Navigator.of(context).pop(request))` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Support screen list padding | `fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl)` | `support_screen.dart:224-229`<br>`EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl)`. | `[VERIFIED]` |
| Helpline card padding | `AppSpacing.lg` (16dp) | `support_screen.dart:279`<br>`padding: const EdgeInsets.all(AppSpacing.lg)`. Standardized from 18dp. | `[VERIFIED]` |
| Return sheet outer padding | `fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg + bottom)` | `return_sheet.dart:100-105`<br>`EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg + bottom)`. Standardized from 20dp. | `[VERIFIED]` |
| Return sheet vertical gaps | `AppSpacing.lg` (16dp) | `return_sheet.dart:311, 392`<br>`SizedBox(height: AppSpacing.lg)`. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Return Sheet Title | 18px w700, letterSpacing -0.2, ink | `return_sheet.dart:134-139`<br>`fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Return Success Header | 18px w700, letterSpacing -0.2, ink | `return_sheet.dart:319-324`<br>`fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Helpline Headline | 17px w900, surface | `support_screen.dart:317-321`<br>`fontSize: 17, fontWeight: FontWeight.w900, color: ShodashaTheme.surface` | `[VERIFIED]` |
| Section Trackers | 11px w800, letterSpacing 0.8, muted | `support_screen.dart:452-456`<br>`fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: ShodashaTheme.muted` | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Finding | Expected Copy | Code Evidence | Status |
|---|---|---|---|
| Helpline title & subtitle | Direct, calm assistance options | `support_screen.dart:318, 332`<br>`'Need help with an order?'` / `'Call our Bhopal team or chat with us on WhatsApp'`. | `[VERIFIED]` |
| Return SLA transparency | Clear refund timeline expectation | `return_sheet.dart:333-339`<br>`'Refund will be credited to ${request.refundUpi} within 10 working days of pickup.'`. | `[VERIFIED]` |
| External intent failure fallback | Helpful SnackBar on missed app launch | `support_screen.dart:154, 184`<br>`'WhatsApp did not open — number copied to clipboard.'` / `'Phone dialer did not open — number copied to clipboard.'`. | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Edge Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| External intent failure fallback | Copy phone to clipboard and notify user via SnackBar | `support_screen.dart:146-188`<br>`Clipboard.setData(...)` + SnackBar on intent failure. | `[VERIFIED]` |
| Return success state flip | Render clear confirmation summary with request ID and Done action | `return_sheet.dart:109-110, 295-397`<br>`final done = _controller.lastRequest; if (done != null) return _success(done);` | `[VERIFIED]` |
| Zero held jars return guard | Disable return submission when customer holds 0 jars | `return_sheet.dart:167-175, 202-211`<br>Held jars bounds check and submit disabled. | `[VERIFIED]` |
| Complaint window closure (422) | Surface server failure message and direct user to live WhatsApp | `support_screen.dart:106-116`<br>Handles 422 window expired gracefully. | `[VERIFIED]` |

---

## 7. File Invariants & Verification Checklist

- [x] Invariant: WhatsApp and Phone links derive strictly from `kSupportPhone` (`support_screen.dart:232, AppConstants.kSupportPhone`).
- [x] Invariant: Jar return SLA is fixed at 10 working days; refund amounts are strictly server-authoritative (`returns_controller.dart:36-41`).
- [x] Invariant: Complaint submission enforces reason code and length bounds (10–500 chars) with server 422 error visibility (`support_controller.dart:5-6`).
- [x] Invariant: Minimum 48dp bounding touch targets on all interactive elements.

---

## 8. Automated Test Verification

Targeted support and returns test suite execution:
- `apps/user_app_donor/test/support_returns_test.dart`

**Command Output:**
```
00:00 +0: SupportScreen renders complaints section before common questions
00:01 +1: ReturnSheet renders title with standardized 18px w700 typography
00:01 +2: All tests passed!
```
Status: **2 / 2 passed** (100% green).

