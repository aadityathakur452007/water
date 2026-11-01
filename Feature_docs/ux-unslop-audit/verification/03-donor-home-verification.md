# Verification Report: 03 — Donor App: Home Screen & Dashboard

**Document Audited:** `Feature_docs/ux-unslop-audit/03-donor-home.md`  
**Target Codebase:** `apps/user_app_donor/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **D3-01** | Repeat Order Machine hero card | Add dedicated 1-tap reorder card between greeting and mode selection cards using `OrdersController.reorderCandidate`. | `apps/user_app_donor/lib/features/home/customer_home_screen.dart:168-190, 318-381`<br>`_QuickReorderCard(order: candidate, onReorder: () => widget.onOrderProduct(refill: candidate.refillQty, container: candidate.containerQty))` with `AppButton(label: 'Reorder', kind: AppButtonKind.money)`. | `[VERIFIED]` |
| **D3-02** | Remove fake search bar from Top Bar | Eliminate decorative search bar input for 2-SKU catalog, reclaiming vertical screen space. | `apps/user_app_donor/lib/features/home/widgets/top_bar.dart:227-232`<br>Search bar input completely removed from `DonorTopBar`. Bottom of top bar is the clean address row. | `[VERIFIED]` |
| **D3-03** | Remove "Server prices" developer meta-label | Eliminate technical jargon from `SectionHeader` trailing label; replace with customer-friendly badge. | `apps/user_app_donor/lib/features/home/widgets/featured_products.dart:38-45`<br>`trailing: Text('Daily verified', style: TextStyle(fontSize: 12, color: ShodashaTheme.tealDeep, fontWeight: FontWeight.w700))` | `[VERIFIED]` |
| **D3-04** | Harmonize Mode Selection Cards | Unify `ModeSelectionCards` so Instant Order and Subscribe share a calm, neutral surface card design. | `apps/user_app_donor/lib/features/home/widgets/mode_selection_cards.dart:78-154`<br>Both cards use `color: ShodashaTheme.surface`, `BorderSide(color: ShodashaTheme.border)`, `ShodashaTheme.tealTint` circular icon badge, and `ShodashaTheme.ink` title. | `[VERIFIED]` |
| **D3-05** | Typed rates offline error detection | Replace fragile string scraping (`contains('internet')`) with typed domain property. | `apps/user_app_donor/lib/features/home/customer_home_screen.dart:82`<br>`final ratesOffline = widget.booking.ratesOffline;` (backed by `e.isOffline` on `BookingController`). | `[VERIFIED]` |
| **D3-06** | Fractional fonts & spacing token hygiene | Eliminate fractional 12.5px and 11.5px font sizes; convert hardcoded spacers to `AppSpacing` tokens. | `customer_home_screen.dart`, `featured_products.dart`, `mode_selection_cards.dart`, `live_purity_card.dart`<br>Font sizes normalized to 12px `bodySmall` and 11px `labelSmall`. Product tag padding `AppSpacing.sm` / `AppSpacing.xs`. Bottom padding `AppSpacing.xxl` (32dp). `StatusPillTone.brand` added for `RO + UV` trust pill. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| Reorder button | `AppButtonKind.money` (conversion green) | `customer_home_screen.dart:370-376`<br>`AppButton(label: 'Reorder', kind: AppButtonKind.money, expand: false, height: ShodashaTheme.minTarget, onPressed: onReorder)` | `[VERIFIED]` |
| Product card order CTA | Canonical `AppButtonKind.secondary` | `featured_products.dart:190-196`<br>`AppButton(label: actionLabel, kind: AppButtonKind.secondary, expand: false, height: ShodashaTheme.minTarget, onPressed: onTap)` | `[VERIFIED]` |
| Support card CTA | Canonical `AppButtonKind.ghost` | `customer_home_screen.dart:305-312`<br>`AppButton(label: 'Support', kind: AppButtonKind.ghost, expand: false, height: ShodashaTheme.minTarget, onPressed: onTap)` | `[VERIFIED]` |
| Top bar icon actions | Bounded `AppIconButton` (48×48dp) | `top_bar.dart:92-124`<br>`AppIconButton` for Notifications, Profile, and Shopping Bag with count badge. | `[VERIFIED]` |
| Trust pill | Standard `StatusPill` with brand tone | `customer_home_screen.dart:160-164`<br>`StatusPill(label: 'RO + UV', tone: StatusPillTone.brand, icon: Icons.verified_outlined)` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Top bar padding | `AppSpacing.lg` (16dp), `AppSpacing.sm` (8dp), `AppSpacing.md` (12dp) | `top_bar.dart:62-67`<br>`EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md)`. | `[VERIFIED]` |
| Top bar address vertical padding | `AppSpacing.xs` (4dp) | `top_bar.dart:141-143`<br>`EdgeInsets.symmetric(vertical: AppSpacing.xs)`. | `[VERIFIED]` |
| Mode card internal padding & gaps | `AppSpacing.lg` (16dp), `AppSpacing.md` (12dp), `AppSpacing.xs` (4dp) | `mode_selection_cards.dart:89, 116, 127, 140`<br>Padding: `all(AppSpacing.lg)`; icon gap: `AppSpacing.md`; title/subtitle gaps: `AppSpacing.xs`. | `[VERIFIED]` |
| Product card tag badge padding | `AppSpacing.sm` (8dp) horizontal, `AppSpacing.xs` (4dp) vertical | `featured_products.dart:141-144`<br>`EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs)`. | `[VERIFIED]` |
| Home list bottom padding | `AppSpacing.xxl` (32dp) | `customer_home_screen.dart:123`<br>`EdgeInsets.only(bottom: AppSpacing.xxl)`. Replaced off-scale 28dp padding. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Home Greeting | 14px w500 | `customer_home_screen.dart:141-144`<br>`fontSize: 14, fontWeight: FontWeight.w500, color: ShodashaTheme.muted` | `[VERIFIED]` |
| Home Headline | 24px w800, letterSpacing -0.6 | `customer_home_screen.dart:149-155`<br>`fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.15, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Mode Card Title | 16px w700 | `mode_selection_cards.dart:133-138`<br>`fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Mode Card Subtitle | 12px w400, height 1.35 | `mode_selection_cards.dart:146-150`<br>`fontSize: 12, height: 1.35, color: ShodashaTheme.muted`. 12.5px eliminated. | `[VERIFIED]` |
| Product Title | 15px w700 | `featured_products.dart:132-136`<br>`fontSize: 15, fontWeight: FontWeight.w700, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Product Price | 18px w800, letterSpacing -0.3 | `featured_products.dart:183-187`<br>`fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Product Subtitle | 12px w400, height 1.4 | `featured_products.dart:166-169`<br>`fontSize: 12, height: 1.4, color: ShodashaTheme.muted`. 12.5px eliminated. | `[VERIFIED]` |
| Purity Fact Values | 14px w800 | `live_purity_card.dart:187-192`<br>`fontSize: 14, fontWeight: FontWeight.w800, color: ShodashaTheme.tealDeep` | `[VERIFIED]` |
| Purity Fact Subtitles | 11px w700 / w400 | `live_purity_card.dart:203, 214`<br>`fontSize: 11, fontWeight: FontWeight.w700` (title) / `fontSize: 11, color: ShodashaTheme.muted` (detail). 11.5px eliminated. | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Original String / Issue | Polished String | Code Evidence | Status |
|---|---|---|---|
| "Server prices" developer meta-label | `"Daily verified"` | `featured_products.dart:39`<br>Clean, customer-facing pricing assurance. | `[VERIFIED]` |
| Retail retail copy: "Bring your own jar" | `"Exchange empty jar at delivery · RO + UV purified"` | `featured_products.dart:58`<br>Accurate doorstep exchange mechanics. | `[VERIFIED]` |
| Verbose deposit copy | `"Includes ₹150 refundable jar deposit"` | `featured_products.dart:69-70`<br>Clear and concise monetary explanation. | `[VERIFIED]` |
| Cold industrial copy: "plant desk" | `"Call or WhatsApp Bhopal support directly"` | `customer_home_screen.dart:295`<br>Warm, accessible customer service copy. | `[VERIFIED]` |
| Passive lab copy: "Ask support" | `"On WhatsApp"` | `live_purity_card.dart:147`<br>Direct and actionable communication channel. | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| Catalog rates loading | Placeholder skeleton cards | `featured_products.dart:47-48, 205-223`<br>`_ProductsSkeleton` displays placeholder surface cards during network fetch. | `[VERIFIED]` |
| Address loading | Inline 12px spinner in Top Bar | `top_bar.dart:161-174`<br>`CircularProgressIndicator` rendered next to address title without blocking interactions. | `[VERIFIED]` |
| Address error with retry | Tap-to-retry affordance | `top_bar.dart:50, 132-134, 205-214`<br>Tapping invokes `widget.addresses.load()`. | `[VERIFIED]` |
| Offline banner | Re-probe retry affordance | `customer_home_screen.dart:103-112`<br>`AppBanner.offline(onRetry: widget.booking.refreshRates)`. | `[VERIFIED]` |
| Pull to refresh | Parallel refresh of rates & addresses | `customer_home_screen.dart:114-120`<br>`Future.wait([widget.booking.refreshRates(), widget.addresses.load()])`. | `[VERIFIED]` |
| Purity telemetry shimmer | Gentle non-blocking entrance pulse | `live_purity_card.dart:25-37, 74-92`<br>`AnimationController` runs gentle 1.2s opacity tween on load; respects `MediaQuery.maybeDisableAnimationsOf(context)`. | `[VERIFIED]` |

---

## 7. Verification Test Suite Results

- `test/home_tab_test.dart` (4 tests): **PASSED**
  - Home tab renders unified mode cards, trust pill, and updated copy.
- `test/quick_reorder_test.dart` (2 tests): **PASSED**
  - Renders `QuickReorderCard` when reorder candidate exists and triggers `onOrderProduct`.
  - Suppresses card cleanly when no candidate exists.
- **Total Home Screen Tests:** **6 / 6 passed** with 0 failures, 0 errors.

---

## Conclusion

File `03-donor-home.md` is **100% verified** against the current codebase in `apps/user_app_donor`. All P0–P3 unslop items (D3-01 through D3-06), repeat order machine card, removal of fake search, pricing label polish, unified mode selection surfaces, typed offline error handling, and typography tokens are confirmed in code with green test coverage.

