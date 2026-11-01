# Verification Report: 07 — Donor App: Bill Screen & Rating Sheet

**Document Audited:** `Feature_docs/ux-unslop-audit/07-donor-bill-rating.md`  
**Target Codebase:** `apps/user_app_donor/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **D7-01** | WhatsApp button icon identity crisis | Align button icon with chat action by replacing `Icons.share_outlined` with `Icons.chat_outlined` on "Help on WhatsApp". | `apps/user_app_donor/lib/features/orders/bill_screen.dart:209-214`<br>`AppButton(label: ordersStringsHi['whatsappHelp']!, kind: AppButtonKind.secondary, icon: Icons.chat_outlined, onPressed: () => _share(context, o))` | `[VERIFIED]` |
| **D7-02** | Truncate raw order UUID in Bill AppBar | Format AppBar title to clean 8-character uppercase `#$_orderRef` (e.g. `Bill · #B4890211`). | `apps/user_app_donor/lib/features/orders/bill_screen.dart:39-42, 60-69`<br>`_orderRef => id.length > 8 ? id.substring(0, 8).toUpperCase() : id; title: Text('Bill · #$_orderRef')` | `[VERIFIED]` |
| **D7-03** | Enriched bill line items & notice scale | Enrich primary line item with quantity/SKU summary (`o.itemSummary`) instead of bare "Water"; standardize footer notice to 12px. | `apps/user_app_donor/lib/features/orders/bill_screen.dart:114-119, 181-190`<br>`_Line(label: o.itemSummary.trim().isNotEmpty ? o.itemSummary.trim() : '20L Water Refill', ...)` and notice `fontSize: 12`. | `[VERIFIED]` |
| **D7-04** | Rating complaint shortcut conditionality | In `rating_sheet.dart`, conditionally reveal the complaint shortcut only on critical ratings (`<= 3` stars). | `apps/user_app_donor/lib/features/orders/rating_sheet.dart:145-147`<br>`if (widget.onSupport != null && ((alreadyRated && (widget.order.stars ?? 0) <= 3) \|\| (!alreadyRated && _stars > 0 && _stars <= 3))) ...` | `[VERIFIED]` |
| **D7-05** | Rating sheet design tokens & AppButton migration | Migrate raw `ElevatedButton` to canonical `AppButton`; replace hardcoded padding with `AppSpacing` tokens. | `apps/user_app_donor/lib/features/orders/rating_sheet.dart:98-104, 139-144`<br>Padding: `fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl)`. `AppButton(label: ordersStringsHi['rateSubmit']!, kind: AppButtonKind.primary, busy: _busy)`. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| Rating submit CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`) with busy spinner | `rating_sheet.dart:139-144`<br>`AppButton(label: ordersStringsHi['rateSubmit']!, kind: AppButtonKind.primary, busy: _busy, onPressed: ...)` | `[VERIFIED]` |
| Rating complaint link | Accessible `TextButton` with 48dp minimum target | `rating_sheet.dart:150-157`<br>`TextButton(style: TextButton.styleFrom(foregroundColor: ShodashaTheme.blue, minimumSize: const Size(48, ShodashaTheme.minTarget)))` | `[VERIFIED]` |
| Bill screen support CTA | Canonical `AppButton` with `Icons.chat_outlined` | `bill_screen.dart:209-214`<br>`AppButton(label: ordersStringsHi['whatsappHelp']!, kind: AppButtonKind.secondary, icon: Icons.chat_outlined, ...)` | `[VERIFIED]` |
| Star rating buttons | Bounded `IconButton` with semantic tooltips | `rating_sheet.dart:123-135`<br>`IconButton(iconSize: 36, tooltip: '$i / 5', ...)` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Bill screen outer padding | `AppSpacing.lg` (16dp), `md` (12dp), `xxl` (32dp) | `bill_screen.dart:73-78`<br>`EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl)`. | `[VERIFIED]` |
| Rating sheet outer padding | `AppSpacing.xl` (24dp), `AppSpacing.lg` (16dp) | `rating_sheet.dart:99-104`<br>`EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl)`. Replaced hardcoded values. | `[VERIFIED]` |
| Rating sheet vertical gaps | `AppSpacing.md` (12dp), `AppSpacing.sm` (8dp) | `rating_sheet.dart:118, 138, 148`<br>`SizedBox(height: AppSpacing.md)` and `AppSpacing.sm`. | `[VERIFIED]` |
| Bill card divider padding | `AppSpacing.md` (12dp) | `bill_screen.dart:139-142`<br>`EdgeInsets.symmetric(vertical: AppSpacing.md)`. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Bill Total Amount | 22px w800, letterSpacing -0.4 | `bill_screen.dart:158-163`<br>`fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Bill Line Item Label | 14px w500 | `bill_screen.dart:238-242`<br>`fontSize: 14, fontWeight: FontWeight.w500, color: ShodashaTheme.muted` | `[VERIFIED]` |
| Bill Line Item Amount | 14px w600 | `bill_screen.dart:247-251`<br>`fontSize: 14, fontWeight: FontWeight.w600, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Bill Frozen Notice | 12px w500 | `bill_screen.dart:185-189`<br>`fontSize: 12, fontWeight: FontWeight.w500, color: ShodashaTheme.muted`. Standardized from 11px. | `[VERIFIED]` |
| Rating Sheet Title | 17px w700 | `rating_sheet.dart:111-115`<br>`fontSize: 17, fontWeight: FontWeight.w700, color: ShodashaTheme.ink` | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Original String / Issue | Polished String | Code Evidence | Status |
|---|---|---|---|
| Raw 32-character UUID in AppBar | `"Bill · #B4890211"` | `bill_screen.dart:61`<br>Truncated 8-character uppercase order ID. | `[VERIFIED]` |
| Generic "Water" line item | `"2 × 20L Refill"` / `o.itemSummary` | `bill_screen.dart:115-117`<br>Itemized SKU summary replacing bare "Water" label. | `[VERIFIED]` |
| Delivery notice status | `"Bill frozen at delivery"` | `bill_screen.dart:183`<br>Accurate, clear legal audit copy. | `[VERIFIED]` |
| Dues explanation | `ordersStringsHi['duesNote']` | `bill_screen.dart:199`<br>Transparent explanation of past dues inclusion. | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| Star selection (0 stars) | Submit button disabled | `rating_sheet.dart:143`<br>`onPressed: (alreadyRated \|\| _stars < 1 \|\| _busy) ? null : _submit`. | `[VERIFIED]` |
| Rating 4–5 stars | Complaint shortcut suppressed | `rating_sheet.dart:145-147`<br>Hides complaint shortcut completely on positive ratings. | `[VERIFIED]` |
| Rating 1–3 stars | Complaint shortcut displayed | `rating_sheet.dart:145-147`<br>Reveals complaint link immediately on critical rating. | `[VERIFIED]` |
| Submitting rating | Busy indicator on AppButton | `rating_sheet.dart:142`<br>`busy: _busy` prevents repeated taps. | `[VERIFIED]` |
| Rating failure (network) | Sheet stays open for retry | `rating_sheet.dart:64-72`<br>Preserves selected stars and displays retry SnackBar. | `[VERIFIED]` |
| Pending refund on bill | Blue-tint warning banner | `bill_screen.dart:82-110`<br>Displays frozen refund amount with clear information icon. | `[VERIFIED]` |

---

## 7. Verification Test Suite Results

- `test/bill_rating_test.dart` (2 tests): **PASSED**
  - `BillScreen` renders truncated 8-char uppercase order ref and enriched SKU line.
  - `RatingSheet` hides complaint shortcut on 4–5 stars and reveals on 1–3 stars.
- **Total Bill & Rating Tests:** **2 / 2 passed** with 0 failures, 0 errors.

---

## Conclusion

File `07-donor-bill-rating.md` is **100% verified** against the current codebase in `apps/user_app_donor`. All P0–P3 unslop items (D7-01 through D7-05), WhatsApp icon alignment, truncated order ref in AppBar, enriched line items, conditional rating complaint shortcut, `AppButton` migration, and tokenized padding are confirmed in code with green test coverage.
