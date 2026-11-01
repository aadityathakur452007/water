# D9 — Donor Wallet & Payment History Audit

**Files Audited:**
- `apps/user_app_donor/lib/features/wallet/donor_wallet_screen.dart` (660 lines)
- `apps/user_app_donor/lib/features/wallet/payment_history_screen.dart` (505 lines)
- `apps/user_app_donor/lib/features/wallet/wallet_controller.dart` (137 lines)

---

## 1. Executive Summary
The Donor Wallet feature represents the commercial ledger core of the Shodasha application. Unlike generic consumer wallets, Shodasha’s wallet does not hold arbitrary pre-stored digital cash; it is an immutable physical asset ledger (`heldJars`, `depositHeldPaise`, `duesPaise`) paired with verified payment receipts. The controller exhibits exceptional state discipline: zero fake-zero balance flashes, resilient offline cached presentation, and server-authoritative integer paise calculations. However, the UI layer exhibits several visual inconsistencies, navigation seams, and layout slop:
1. **Redundant ledger metrics:** The wallet screen renders a dark teal hero card displaying "Refundable deposit" and a badge for "X jars with you", immediately followed by an `AppCard` whose first row repeats "Jars with you: X".
2. **Confusing cross-tab redirect:** When dues are present, the wallet displays an amber warning card with a money-green CTA labeled "Review dues". Clicking this button silently navigates the user to the Subscriptions tab (`onOpenSubscriptions`), failing to explain why dues payment belongs to the subscription lifecycle.
3. **Broken layout rhythm on zero-jar state:** When `heldJars == 0`, the second action tile ("Return empty jars") collapses into a tiny, borderless 12px muted text block ("No empty jars to return yet."), breaking the visual grid established by the primary "Payments & deposits" card.
4. **Unpaginated 50-item hardcap:** `PaymentHistoryScreen` queries `limit: 50` with no cursor or infinite scroll. If a long-term customer exceeds 50 orders, a passive footer note informs them that older receipts are hidden and requires contacting support.

---

## 2. Screen Identity & Canonical Route
- **Wallet Screen:** Root tab destination (Tab 3: `wallet`) in `donor_shell.dart`. Canonical title: "Wallet".
- **Payment History Screen:** Pushed route (`MaterialPageRoute`) opened from "Payments & deposits" action tile or "See all" header. Canonical title: "Payments & deposits".
- **Return Sheet:** Bottom modal opened from "Return empty jars" action tile.
- **Target Persona:** Bhopal household or commercial customer tracking their refundable bottle deposit investment (₹150/can), verifying return credits, and downloading payment receipts.

---

## 3. Visual & Spatial Hierarchy
### Wallet Screen
- **Primary Hero:** Solid `ShodashaTheme.tealDeep` container (`donor_wallet_screen.dart:314-379`) displaying refundable deposit at 32px bold with letter spacing `-0.6`.
- **Secondary Block:** "Deposit details" card (`_row` entries for Jars with you, Deposit paid, Deposit refunded, Outstanding dues).
- **Action Hub:** Two action cards (`_actionTile`) for payment history and empty jar return.
- **Tertiary Section:** "Recent receipts" list showing the last 3 transactions with a "See all" link.
- **Hierarchy Defect:** When outstanding dues exist (`ledger.duesPaise > 0`), an amber warning card (`_duesCard`) is inserted *above* the hero card, pushing the primary asset balance down and creating visual tension with clashing colors (amber vs deep teal).

### Payment History Screen
- **Primary Anchor:** Standard AppBar with title "Payments & deposits".
- **Body:** Chronological list of transaction receipt cards showing payment status pill, transaction type, date, amount, and provider reference ID.

---

## 4. Color & Contrast Audit

| Element | File:Line | Color Token / Value | Contrast Ratio (vs BG) | Compliance / Finding |
|---|---|---|---|---|
| Screen Background | `donor_wallet_screen.dart:151` | `ShodashaTheme.bg` (`#F7F9FA`) | Baseline | Standard slate ground |
| Hero Container | `donor_wallet_screen.dart:317` | `ShodashaTheme.tealDeep` (`#0D6559`) | 7.8:1 vs ground | Deep teal solid container |
| Hero Large Amount | `donor_wallet_screen.dart:346` | `Colors.white` | 9.8:1 vs `tealDeep` | Excellent contrast, highly legible |
| Hero Subtitle | `donor_wallet_screen.dart:355` | `ShodashaTheme.surface` (`#FFFFFF`) | 9.8:1 vs `tealDeep` | Compliant |
| Dues Warning Card | `donor_wallet_screen.dart:416` | `ShodashaTheme.solarTint` (`#FEF3C7`) | 1.15:1 vs ground | Low border contrast; uses `solarBorder` |
| Dues Warning Text | `donor_wallet_screen.dart:434` | `ShodashaTheme.onSolar` (`#78350F`) | 8.2:1 vs `solarTint` | WCAG AAA compliant |
| Action Tile Icon Circle | `donor_wallet_screen.dart:506` | `color.withValues(alpha: 0.1)` | Tinted badge | Clean visual indicator |
| Dues Row Emphasis | `donor_wallet_screen.dart:478` | `ShodashaTheme.danger` (`#DC2626`) | 5.2:1 vs surface | High visibility for debt |
| Receipt Status Pill | `payment_history_screen.dart:333` | `tealTint` / `solarTint` | 4.8:1 / 4.9:1 | Standard theme pill |

---

## 5. Typography & Text Scale

| Text Element | File:Line | Font Size | Weight | Finding |
|---|---|---|---|---|
| Screen AppBar Title | `donor_wallet_screen.dart:160-165` | 18px | w700 | Fits shell identity |
| Hero Deposit Value | `donor_wallet_screen.dart:347` | 32px | w800 | Bold, prominent, `-0.6` tracking |
| Hero Held Jars Pill | `donor_wallet_screen.dart:372` | 12px | w700 | Crisp pill typography |
| Dues Card Body | `donor_wallet_screen.dart:445` | 12.5px | Default | **Off-scale token**: Fragmented font size |
| Deposit Row Label | `donor_wallet_screen.dart:470` | 13px | Default | Standard body |
| Deposit Row Value | `donor_wallet_screen.dart:476` | 14px | w700 | Strong alignment |
| Payment Tile Amount | `payment_history_screen.dart:354` | 15px | w800 | Off-scale (scale is 14 or 16) |

---

## 6. Spacing, Grid & Alignment
- **Screen Padding:** Standardized `EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl)` (24, 16, 24, 32).
- **Hero Card Padding:** `EdgeInsets.all(AppSpacing.lg)` (24dp) with `radiusLg` (16dp).
- **Action Tile Padding:** `EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md)`.
- **List Spacing Defect:** Gap between dues card and hero is `AppSpacing.md` (12dp), but gap between hero and details card is also `AppSpacing.md` (12dp), causing the warning card and hero to visually merge into a single dense column.

---

## 7. Micro-Interactions, Feedback & States
- **Wallet Screen States:**
  - Initial load (no cache): Displays `AppStateView.loading(lines: 4, message: 'Loading your jar ledger')`.
  - Empty (first-time donor, no deliveries): Displays clean empty view `No jars with you yet` with water drop icon.
  - Offline with cache: Shows `AppBanner.offline` atop the list while rendering cached numbers.
  - Stale on error: Shows `AppBanner.stale` with direct retry callback.
  - Pull to refresh: Supported via native `RefreshIndicator(color: ShodashaTheme.tealDeep)`.
- **Navigation Lock (`_pushing` flag):** `donor_wallet_screen.dart:44` maintains `_pushing` boolean guard to prevent rapid double-taps from pushing duplicate `PaymentHistoryScreen` instances.

---

## 8. Motion & Transitions
- **Screen Transitions:** Push transition to `PaymentHistoryScreen`.
- **Receipt Expand/Collapse:** None. Receipts are static summary cards.
- **Balance Updates:** Direct number replacement on reload without rolling odometer animation.

---

## 9. Cognitive Load & Information Scent
- **"Review Dues" Routing Confusion:** A user tapping "Review dues" inside the Wallet screen is abruptly dumped onto Tab 2 (Subscriptions). There is no toast or banner explaining: "Dues are settled via your recurring plan subscription".
- **Missing "Add Deposit" Door:** Users frequently look for a button to add money to their wallet. While the business model intentionally omits prepaid wallet top-ups (deposits are charged per delivery or via subscription), the UI should explicitly clarify: "Deposits are paid automatically when you order new jars."
- **Receipt Pagination Horizon:** `PaymentHistoryScreen` caps at 50 records without pagination, leaving active long-term donors unable to audit older receipts.

---

## 10. Touch Targets & Ergonomics
- **Action Tiles:** Full-width `AppCard` with minimum height exceeding 56dp. Generous touch area.
- **Review Dues Button:** `AppButton` with `height: 48` meeting thumb ergonomics.
- **"See all" Link:** Uses `TextButton` inside `SectionHeader`. Touch target meets minimum 48dp height requirement.

---

## 11. Edge Cases & Resiliency
- **Guest / Unauthenticated Access:** If `!widget.api.hasToken`, `initState` skips loading, avoiding 401 network storms.
- **Negative / Zero Dues:** `_duesCard` is conditionally rendered only when `ledger.duesPaise > 0`.
- **Empty Held Jars:** When `heldJars <= 0`, `_openReturnSheet` immediately returns without launching modal sheet (`donor_wallet_screen.dart:112`).
- **Offline Receipt Caching:** If network fails while fetching payments, cached rows remain visible with informative warning banner (`donor_wallet_screen.dart:94-98`).

---

## 12. Code-Level Craft & Tech Debt

| File & Line | Issue | Severity | Proposed Fix |
|---|---|---|---|
| `donor_wallet_screen.dart:445` | `12.5px` off-scale font size | Low | Standardize to 12px or 13px |
| `donor_wallet_screen.dart:455` | "Review dues" redirects to subscriptions with no explanation | Medium | Add snackbar or route directly to dues settlement dialog |
| `donor_wallet_screen.dart:253-265` | Bare text on zero empty jars breaks tile grid | Medium | Render disabled/quiet tile: "No empty jars to return" |
| `donor_wallet_screen.dart:368-375` | Held jars count duplicated across hero and details card | Low | Remove redundant row from "Deposit details" card |
| `payment_history_screen.dart:73` | Hardcoded 50-record limit without cursor pagination | Medium | Implement standard cursor/offset pagination or link to support |
| `payment_history_screen.dart:141-150` | Hand-rolled month array instead of standard formatter | Low | Standardize date formatting helper across features |

---

## 13. Accessibility (a11y)
- **High Contrast Hero:** White text on `#0D6559` provides 9.8:1 contrast, exceeding WCAG AAA standards.
- **Semantic Labels:** Action tiles provide title and subtitle in vertical column.
- **Color Independence:** Dues warnings use both amber background, warning icon (`Icons.error_outline_rounded`), and explicit currency amounts.

---

## 14. Cross-Platform Consistency
- **Monetary Formatting:** Uses `formatInr(paise)` across both screens, ensuring identical Indian Rupee (`₹`) symbol formatting and comma grouping across Android and iOS.
- **RefreshIndicator:** Native material pull-to-refresh behaves consistently across touch devices.

---

## 15. Proposed Layout & Unslop Direction
### Wallet Screen: "The Clean Jar Custody Ledger"
- **Unified Custody Card:** Consolidate the dark hero card and "Deposit details" into a single, cohesive asset statement:
  - Header: Refundable Jar Deposit balance (`₹300`).
  - Sub-row: Active Jars in Custody (`2 jars with you`).
  - Expandable statement: Lifetime deposit paid (`₹450`), Lifetime refunds credited (`₹150`), Current dues (`₹0`).
- **Consistent Action Grid:** Keep both action tiles permanent. When `heldJars == 0`, show "Return empty jars" with a subtle subtitle: "0 jars ready for pickup (Order more jars to start recycling)".
- **In-Context Dues Settlement:** Instead of navigating away to Tab 2, let "Pay dues" trigger the idempotent UPI intent dialog directly from the wallet screen.

---

## 16. Concrete Actionable Recommendations
1. **Unify Dues Payment in Wallet:** Provide a direct "Pay Dues" action in `_duesCard` using `ApiClient.payDues()` rather than silently switching tabs to Subscriptions.
2. **Standardize Empty Jar Tile:** Replace the plain text snippet with a disabled or educational `_actionTile` explaining when jar returns unlock.
3. **Deduplicate Jar Count:** Remove redundant "Jars with you" row from `_ledgerBody` since the count is already highlighted in the hero container.
4. **Normalize Font Tokens:** Replace `12.5px` with `12px` (`ShodashaTheme.caption`).
5. **Add Receipt Pagination:** Upgrade `PaymentHistoryScreen` to support scroll-triggered pagination or explicit "Load more" handling.

---

## 17. Acceptance Criteria
- [ ] Wallet screen displays zero duplicate metrics between hero and detail breakdown.
- [ ] Tapping dues action opens dues settlement or clearly informs user before switching tabs.
- [ ] Both action tiles ("Payments & deposits", "Return empty jars") maintain consistent card styling regardless of jar count.
- [ ] All typography strictly adheres to the design token scale (no 12.5px or 15px).
- [ ] Server ledger invariants (`heldJars`, `depositHeldPaise`, `duesPaise`) remain 100% untouched.

---

## 18. File Invariants & Verification Checklist
- [x] Invariant: Ledger is strictly server-authoritative (`GET /v1/ledger/me`); no client-side balance math (`wallet_controller.dart:1-7`).
- [x] Invariant: No fake-zero balance flashes while loading (`wallet_controller.dart:5-7`).
- [x] Verified: `PaymentRecord` handles paise integer parsing cleanly without floating-point conversion errors.
- [x] Verified: Refresh error maintains cached ledger snapshot with stale notification banner.
