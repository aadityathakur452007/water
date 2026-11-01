# Verification Report: 05 — Donor App: Orders List & Order Card

**Document Audited:** `Feature_docs/ux-unslop-audit/05-donor-orders.md`  
**Target Codebase:** `apps/user_app_donor/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **D5-01** | Eliminate illegal green CTA on "View bill" | Closed order bill CTA must use `AppButtonKind.secondary`. Green is strictly reserved for money/conversion CTAs. | `apps/user_app_donor/lib/features/orders/order_card.dart:199, 219`<br>`AppButton(label: 'View bill', kind: AppButtonKind.secondary, onPressed: onBill)` | `[VERIFIED]` |
| **D5-02** | Truncate raw 32-character order UUID | Display clean 8-character uppercase reference instead of 32-character hash. | `apps/user_app_donor/lib/features/orders/order_card.dart:54-57, 106`<br>`_orderRef => id.length > 8 ? id.substring(0, 8).toUpperCase() : id; Text('#$_orderRef')` | `[VERIFIED]` |
| **D5-03** | Full card surface clickability | Entire `DonorOrderCard` must be tappable to navigate to live tracking (if active) or bill (if closed). | `apps/user_app_donor/lib/features/orders/order_card.dart:97-98`<br>`AppCard(onTap: _isClosed ? onBill : onTrack, child: Column(...))` | `[VERIFIED]` |
| **D5-04** | Omit empty active section when past orders exist | Omit the bulky "Active" section header and empty card when 0 active deliveries exist, revealing past orders above the fold. | `apps/user_app_donor/lib/features/orders/my_orders_screen.dart:174-180`<br>`if (active.isNotEmpty) ...[ SectionHeader(title: 'Active'), for (final o in active) DonorOrderCard(order: o), ...]` | `[VERIFIED]` |
| **D5-05** | Eliminate fractional and off-scale font sizes | Standardize price to 18px w800 (`titleLarge`), meta rows to 12px `bodySmall`, and spacing to `AppSpacing` tokens. | `apps/user_app_donor/lib/features/orders/order_card.dart:160, 262, 269`<br>Price: `fontSize: 18, fontWeight: FontWeight.w800`. Meta: `fontSize: 12, height: 1.4`. Icon gap: `SizedBox(width: AppSpacing.sm)`. | `[VERIFIED]` |
| **D5-06** | Copy sanitization & centralized date utilities | Centralize month/day names into `date_utils.dart`; replace technical leak copy in stale banners and order titles. | `order_card.dart:11, 51, 71`, `my_orders_screen.dart:156`<br>Replaced `"Server problem — showing the orders already loaded."` with `"Connection issue · Showing saved orders"`. Fallback title: `"20L Jar Delivery"`. Uses `kShortWeekdays`, `kShortMonths`. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| Active card CTA: Track order | Canonical `AppButton` with truck icon | `order_card.dart:234-238`<br>`AppButton(label: 'Track order', icon: Icons.local_shipping_outlined, onPressed: onTrack)` | `[VERIFIED]` |
| Closed card CTA: View bill | Canonical `AppButtonKind.secondary` | `order_card.dart:217-221`<br>`AppButton(label: 'View bill', kind: AppButtonKind.secondary, onPressed: onBill)` | `[VERIFIED]` |
| Closed card secondary: View details | Canonical `AppButtonKind.secondary` | `order_card.dart:225-229`<br>`AppButton(label: 'View details', kind: AppButtonKind.secondary, onPressed: onTrack)` | `[VERIFIED]` |
| Support needed CTA: Get help | Canonical `AppButtonKind.ghost` | `order_card.dart:205-209`<br>`AppButton(label: 'Get help', kind: AppButtonKind.ghost, onPressed: onSupport)` | `[VERIFIED]` |
| Pagination CTA | Canonical `AppButtonKind.secondary` with `busy` spinner | `my_orders_screen.dart:198-203`<br>`AppButton(label: 'Load older orders', kind: AppButtonKind.secondary, busy: c.isLoadingMore, onPressed: c.loadMore)` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Orders screen list padding | `AppSpacing.lg` (16dp), `AppSpacing.md` (12dp), `AppSpacing.xxl` (32dp) | `my_orders_screen.dart:141-146`<br>`EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl)`. | `[VERIFIED]` |
| Card bottom margin | `AppSpacing.md` (12dp) | `order_card.dart:96`<br>`EdgeInsets.only(bottom: AppSpacing.md)`. | `[VERIFIED]` |
| Card header to title gap | `AppSpacing.sm` (8dp) | `order_card.dart:124, 134`<br>`SizedBox(height: AppSpacing.sm)`. | `[VERIFIED]` |
| Meta row icon-to-text gap | `AppSpacing.sm` (8dp) | `order_card.dart:262`<br>`SizedBox(width: AppSpacing.sm)`. Replaced off-scale 6px gap. | `[VERIFIED]` |
| Divider vertical padding | `AppSpacing.md` (12dp) | `order_card.dart:168`<br>`EdgeInsets.symmetric(vertical: AppSpacing.md)`. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Order Reference Number | 12px w600 | `order_card.dart:110-113`<br>`fontSize: 12, fontWeight: FontWeight.w600, color: ShodashaTheme.muted` | `[VERIFIED]` |
| Order Title Summary | 15px w700, letterSpacing -0.2 | `order_card.dart:128-132`<br>`fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Quantity Badge Text | 12px w700 | `order_card.dart:149-152`<br>`fontSize: 12, fontWeight: FontWeight.w700, color: ShodashaTheme.tealDeep` | `[VERIFIED]` |
| Total Price | 18px w800, letterSpacing -0.3 | `order_card.dart:159-163`<br>`fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Meta Row Text | 12px w500, height 1.4 | `order_card.dart:269-273`<br>`fontSize: 12, height: 1.4, fontWeight: FontWeight.w500`. 12.5px eliminated. | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Original String / Issue | Polished String | Code Evidence | Status |
|---|---|---|---|
| Raw 32-character UUID `#2236358550c8425abd9a23f1af39839e` | `"#22363585"` | `order_card.dart:56`<br>Uppercase 8-character reference code. | `[VERIFIED]` |
| Technical server reference | `"Connection issue · Showing saved orders"` | `my_orders_screen.dart:156`<br>Replaced `"Server problem — showing the orders already loaded."`. | `[VERIFIED]` |
| Generic fallback item title | `"20L Jar Delivery"` | `order_card.dart:51`<br>Replaced `"Water order"`. | `[VERIFIED]` |
| Empty orders CTA | `"Book water"` | `my_orders_screen.dart:170`<br>Direct, positive call to action. | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| Initial loading | 4-line skeleton placeholder | `my_orders_screen.dart:121`<br>`AppStateView.loading(lines: 4, message: 'Loading your orders')`. | `[VERIFIED]` |
| Initial error (empty cache) | Full-page error state with retry | `my_orders_screen.dart:125-132`<br>`AppStateView.error(isNetwork: c.isOffline, onRetry: c.load)`. | `[VERIFIED]` |
| Zero orders ever | Empty state with "Book water" CTA | `my_orders_screen.dart:160-173`<br>`AppStateView.empty(title: 'No orders yet', ...)`. | `[VERIFIED]` |
| Zero active orders with past orders | Silently omit "Active" section | `my_orders_screen.dart:174-180`<br>Reveals past orders immediately above fold. | `[VERIFIED]` |
| Offline / network error with cache | Sticky `AppBanner.offline` / `stale` | `my_orders_screen.dart:148-159`<br>Preserves in-memory list and offers retry. | `[VERIFIED]` |
| Cursor pagination failure | Contextual stale banner at list bottom | `my_orders_screen.dart:205-210`<br>`AppBanner.stale(message: 'Could not load older orders', onRetry: c.retryLoadMore)`. | `[VERIFIED]` |

---

## 7. Verification Test Suite Results

- `test/donor_order_card_test.dart` (2 tests): **PASSED**
  - Donor card maps live order and exposes Track.
  - Secondary "View bill" styling on closed orders verified.
- `test/my_orders_screen_test.dart` (8 tests): **PASSED**
  - Omits Active section when user has only past orders.
  - Shows Active and Past sections when both exist.
  - Shows clean stale banner on connection issues.
  - Shows empty state with "Book water" CTA when 0 orders.
- **Total Orders List & Card Tests:** **10 / 10 passed** with 0 failures, 0 errors.

---

## Conclusion

File `05-donor-orders.md` is **100% verified** against the current codebase in `apps/user_app_donor`. All P0–P3 unslop items (D5-01 through D5-06), secondary button styling on closed orders, full-card clickability, omission of empty active section, 8-character uppercase UUID truncation, typography scaling, and sanitized copy are confirmed in code with green test coverage.

