# D7 — Donor Bill Screen & Rating Sheet Audit

**Files Audited:**
- `apps/user_app_donor/lib/features/orders/bill_screen.dart` (251 lines)
- `apps/user_app_donor/lib/features/orders/rating_sheet.dart` (180 lines)
- Supporting context: `apps/user_app_donor/lib/features/orders/orders_controller.dart` (bill formatting, `rate()` API, `ordersStringsHi`)

---

## 1. Executive Summary
The Bill Screen and Rating Sheet represent the final commercial and experiential touchpoints of an order lifecycle. Both components exhibit disciplined domain handling (server-authoritative paise calculations, immutable invoice amounts post-delivery, idempotency guard on ratings). However, both suffer from severe visual slop, copy confusion, and UI kit fragmentation:
1. **The "Share Bill" / "Help on WhatsApp" identity crisis:** `bill_screen.dart` renders a button titled "Help on WhatsApp" using an `Icons.share_outlined` icon, while the inline documentation describes it as a "secondary wa.me link" sending a hardcoded text message with order ID and total to support. It is neither a true invoice receipt share nor an explicit customer support channel.
2. **Missing receipt typography and itemized breakdown:** The bill treats a commercial tax invoice as a generic card list. It collapses water charges into a single aggregate ("Water: ₹160") with no unit pricing, no quantity (`2 × 20L`), no delivery timestamp, and no delivery address reference.
3. **Rating sheet violates its own documented conditional logic:** `rating_sheet.dart` states in header comments that a complaint shortcut is offered for `≤3 stars`, yet the widget displays the complaint link unconditionally whenever `onSupport != null`, even if the user picks 5 stars.
4. **Design system bypass in rating sheet:** `rating_sheet.dart` bypasses `AppButton` and `AppCard` to hand-roll an inline `ElevatedButton.styleFrom` and `TextButton.styleFrom`, producing token drift in corner radii, typography, and disabled state colors.

---

## 2. Screen Identity & Canonical Route
- **Bill Screen:** Pushed route (`MaterialPageRoute`) from `my_orders_screen.dart:272` or `tracking_screen.dart:181`. No named route. Receives immutable `Order` model.
- **Rating Sheet:** Modal bottom sheet triggered via `showRatingSheet(...)` from `tracking_screen.dart:187` (auto-triggered on delivered state) or manual tap.
- **Target Persona:** Donor/Subscriber in Bhopal reviewing final financial ledger deductions (dues, cap charges, refunds) or providing quick delivery feedback.

---

## 3. Visual & Spatial Hierarchy
### Bill Screen
- **Primary Anchor:** Total invoice price displayed at 22px bold (`bill_screen.dart:151-156`) with `letterSpacing: -0.4`.
- **Secondary Anchor:** Itemized breakdown list (`_Line` items for Water, Jar deposit, Cap charges, Previous dues, Payments received).
- **Auxiliary Signals:** Blue-tint banner for pending refunds (`bill_screen.dart:80-103`), bottom status pill for payment status.
- **Defect:** Visual weight is heavily front-loaded on a plain card without clear receipt structure. The order ID in the AppBar (`#${o.id}`) takes prominence despite being an opaque 36-character UUID string.

### Rating Sheet
- **Primary Anchor:** Five large star icons (36dp, `rating_sheet.dart:118`).
- **Secondary Anchor:** Full-width submit button (48dp height).
- **Defect:** Lack of intermediate feedback tags. If a user selects 1 or 2 stars, there is no categorization chips (e.g., "Late delivery", "Damaged seal", "Rider conduct"), forcing immediate jump to an external support screen.

---

## 4. Color & Contrast Audit

| Element | File:Line | Color Token / Value | Contrast Ratio (vs BG) | Compliance / Finding |
|---|---|---|---|---|
| Screen Background | `bill_screen.dart:43` | `ShodashaTheme.bg` (`#F7F9FA`) | Baseline | Neutral clean foundation |
| Bill Card Surface | `bill_screen.dart:106` | `ShodashaTheme.surface` (`#FFFFFF`) | Baseline | White card on light grey bg |
| Refund Notice Card | `bill_screen.dart:80` | `ShodashaTheme.blueTint` (`#EBF5FF`) | 1.15:1 vs surface | Low container contrast; relies on borderless fill |
| Refund Notice Text | `bill_screen.dart:97` | `ShodashaTheme.blue` (`#1A56DB`) | 5.8:1 vs `blueTint` | WCAG AA compliant |
| Bill Item Label | `bill_screen.dart:233` | `ShodashaTheme.muted` (`#64748B`) | 4.6:1 vs surface | Pass WCAG AA |
| Bill Item Value | `bill_screen.dart:243` | `ShodashaTheme.ink` (`#0F172A`) | 14.2:1 vs surface | High contrast, crisp |
| Star Selected | `rating_sheet.dart:126` | `ShodashaTheme.solarDark` (`#B45309`) | 4.8:1 vs surface | Amber-700. Compliant |
| Star Unselected | `rating_sheet.dart:127` | `ShodashaTheme.muted` (`#64748B`) | 4.6:1 vs surface | Outline icon, clear contrast |
| Submit Button Disabled | `rating_sheet.dart:142` | `ink.withValues(alpha: 0.3)` | 2.1:1 vs surface | Meets disabled text expectations |
| Complaint Text Link | `rating_sheet.dart:167` | `ShodashaTheme.blue` (`#1A56DB`) | 5.9:1 vs surface | WCAG AA compliant |

---

## 5. Typography & Text Scale

| Text Element | File:Line | Font Size | Weight | Line Height | Finding |
|---|---|---|---|---|---|
| AppBar Title | `bill_screen.dart:59-63` | 17px | w700 | Default | Truncates raw UUID into `Bill · #8f3...` |
| Refund Banner Copy | `bill_screen.dart:93-98` | 13px | w600 | 1.35 | Compact and legible |
| Line Item Label | `bill_screen.dart:231-235` | 14px | w500 | Default | Clear standard body |
| Line Item Amount | `bill_screen.dart:240-245` | 14px | w600 | Default | Aligns neatly with labels |
| Bill Total Amount | `bill_screen.dart:150-156` | 22px | w800 | Default | Strong visual anchor, `-0.4` letter spacing |
| Bill Status Footer | `bill_screen.dart:178-183` | 11px | w500 | Default | Too small on low-res screens (11px); should be 12px |
| Rating Sheet Title | `rating_sheet.dart:105-109` | 17px | w700 | Default | Centered prompt |
| Complaint Button | `rating_sheet.dart:170` | Unspecified (14px) | w500 | Default | Standard TextButton typography |

---

## 6. Spacing, Grid & Alignment
- **Bill Screen Padding:** Outer padding is `EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl)` (24, 16, 24, 32). Clean generous spacing.
- **Itemized Table Alignment:** `_Line` uses `Row` with `Expanded` label and trailing amount. Line vertical padding is `5px` (`bill_screen.dart:225`), creating a tight receipt-like density inside the card.
- **Rating Sheet Padding:** Hardcoded `EdgeInsets.fromLTRB(24, 16, 24, 24)` (`rating_sheet.dart:98`) instead of using `AppSpacing.lg` and `AppSpacing.md` tokens.
- **Star Alignment:** Centered `Row` containing 5 `IconButton` widgets with 36dp icons.

---

## 7. Micro-Interactions, Feedback & States
- **Bill Screen States:**
  - `o.refundPending == true`: Displays dedicated blue banner with frozen amount.
  - `o.state == OrderState.delivered`: Displays `Bill frozen at delivery`; non-delivered displays `Final bill is confirmed after delivery`.
  - `o.prevDuesPaise > 0`: Appends informative explanatory note (`duesNote`).
  - WhatsApp share click: Launches URL asynchronously; displays SnackBar on failure (`bill_screen.dart:32-36`).
- **Rating Sheet States:**
  - Idle (0 stars): Submit button disabled (`onPressed: null`).
  - Star selected (1–5): Submit button activates immediately.
  - Submitting: Button replaces text with a 20x20 `CircularProgressIndicator` (`rating_sheet.dart:150-157`).
  - Already rated (`widget.order.rated == true`): Star taps disabled, submit button disabled.
  - Error state (`RateResult.failed`): Sheet stays open, displays SnackBar error, allows retry (`rating_sheet.dart:63-70`).
  - Success (`RateResult.success`): Sheet pops, displays success SnackBar.

---

## 8. Motion & Transitions
- **Bill Screen:** Standard push transition from navigator. No custom heroic transitions on numbers or cards.
- **Rating Sheet:** Standard modal bottom sheet sliding transition using `ShodashaTheme.radiusSheet` (24dp).
- **Star Selection:** Instant color swap (`star` vs `star_border`). Missing micro-bounce/spring animation when a star is tapped.

---

## 9. Cognitive Load & Information Scent
- **UUID Confusion:** The user sees `Bill · #8f3b14...` which has zero mnemonic value. Customers identify orders by date, time slot, and items ("Yesterday 7 AM • 2 Jars").
- **Share vs Support Confusion:** A user tapping "Help on WhatsApp" with a share icon expects either to reach an agent or to send a receipt to their spouse. Sending an automated short message to `kSupportPhone` without opening a native share sheet creates friction.
- **Missing Commercial Context:** No indication of delivery address, payment method (COD vs UPI vs Prepaid Wallet), or GST/tax breakdown if applicable.

---

## 10. Touch Targets & Ergonomics
- **Rating Stars:** 5 `IconButton` widgets with 36dp icon size. Default Flutter `IconButton` minimum target is 48x48dp, satisfying touch ergonomics.
- **Submit Button:** Explicitly wrapped in `SizedBox(height: ShodashaTheme.minTarget)` (48dp). Fully accessible.
- **Complaint Shortcut:** Uses `TextButton` with `minimumSize: const Size(48, ShodashaTheme.minTarget)` (48dp).

---

## 11. Edge Cases & Resiliency
- **WhatsApp Missing / Launch Failure:** Clean try-catch block in `_share` (`bill_screen.dart:28-31`) gracefully falling back to a SnackBar warning.
- **Zero / Negative Amounts:** Handled cleanly by `formatRupees` helper; negative payments explicitly prepend a minus sign (`bill_screen.dart:130`).
- **Rapid Tap on Rating Submit:** Guarded by `_busy` flag check (`rating_sheet.dart:59`).
- **Network Failure During Rating:** Sheet stays open with selection preserved (`rating_sheet.dart:66`), preventing accidental double-rating or user confusion.

---

## 12. Code-Level Craft & Tech Debt

| File & Line | Issue | Severity | Proposed Fix |
|---|---|---|---|
| `bill_screen.dart:20-25` | Hardcoded support WhatsApp share text instead of invoice share | Medium | Use standard `Share.share` or format clean receipt text |
| `bill_screen.dart:203-205` | Icon is `share_outlined` but label is `whatsappHelp` | Low | Align label and icon (either "Share bill" or "Contact support") |
| `bill_screen.dart:56` | Unformatted raw order ID in AppBar | Low | Format as 4-character suffix `#...${id.substring(id.length - 4)}` |
| `rating_sheet.dart:2` | Comment says complaint offered for `≤3 stars`, code shows it always | Medium | Check `_stars > 0 && _stars <= 3` before showing complaint shortcut |
| `rating_sheet.dart:98` | Hardcoded padding `EdgeInsets.fromLTRB(24, 16, 24, 24)` | Low | Use `AppSpacing.lg` and `AppSpacing.md` |
| `rating_sheet.dart:135-159` | Direct `ElevatedButton` style bypass instead of `AppButton` | Medium | Standardize with `AppButton(label: ..., kind: AppButtonKind.primary)` |

---

## 13. Accessibility (a11y)
- **Star Rating Tooltips:** Each star icon has a tooltip: `tooltip: '$i / 5'` (`rating_sheet.dart:119`), providing clear screen reader cues.
- **Semantic Bill Lines:** `_Line` items are simple text rows. Screen readers read "Water 160 Rupees", which is understandable.
- **Color Independence:** Rating stars distinguish state via both icon shape (`Icons.star` vs `Icons.star_border`) and color (`solarDark` vs `muted`).

---

## 14. Cross-Platform Consistency
- **WhatsApp URL Scheme:** Uses `https://wa.me/...` with `LaunchMode.externalApplication`, which reliably resolves on Android, iOS, and web without needing raw `whatsapp://` URI intent permissions.
- **Modal Sheet Corner Radii:** Consistent top corner radius matching design tokens.

---

## 15. Proposed Layout & Unslop Direction
### Bill Screen: "The Clean Retail Receipt"
- **Receipt Header:** Clean off-white surface with subtle dashed/perforated separator. Display delivery timestamp, formatted short order number (`#8F3B`), and destination address summary.
- **Itemized Table:**
  - Water line item enriched with quantity: `20L Can × 2 @ ₹80 = ₹160`.
  - Jar Deposit: `Empty Jars Exchanged (2 returned, 0 new deposit) = ₹0`.
  - Clear dues / cap breakdown.
- **Action Split:**
  - Primary button: "Share Receipt" via system share sheet (text/PDF summary).
  - Secondary text button: "Need help with this bill? Chat with Support".

### Rating Sheet: "Intentional Feedback Modal"
- **Star Row:** Clean animated star buttons with 150ms scale-bounce.
- **Conditional Complaint Branch:**
  - If 4–5 stars: "Glad to keep Bhopal hydrated! What went well?" (Quick tags: "On time", "Polite rider", "Clean can").
  - If 1–3 stars: Complaint shortcut highlighted with tags: "Delayed delivery", "Damaged seal", "Rider issue", "Incorrect quantity".
- **Design System Consistency:** Standardize button to `AppButton`.

---

## 16. Concrete Actionable Recommendations
1. **Fix Complaint Visibility Invariant:** In `rating_sheet.dart`, conditionally reveal the complaint shortcut when `_stars > 0 && _stars <= 3` (or if already rated with low rating), fulfilling the contract specified in user-flows flow 6.
2. **Replace `ElevatedButton` with `AppButton`:** Migrate lines 135–159 in `rating_sheet.dart` to use `AppButton` with `AppButtonKind.primary` and `isLoading: _busy`.
3. **Decouple Share from Support in Bill:** In `bill_screen.dart`, change `_share` to share a cleanly formatted receipt summary via system share sheet, and provide a distinct "Help on WhatsApp" action if support inquiry is needed.
4. **Enrich Bill Line Items:** Include quantity and SKU name rather than a raw "Water" label.
5. **Shorten Order Reference:** Format AppBar and bill headers to use a human-readable short hash (e.g., `#B4-8902`).

---

## 17. Acceptance Criteria
- [ ] Bill screen displays itemized SKU name, quantity, price per jar, delivery timestamp, and payment status.
- [ ] Bill screen share button triggers system share sheet or proper receipt text, not hardcoded support message.
- [ ] Rating sheet displays complaint link only when rating is `≤ 3` stars.
- [ ] Rating sheet uses `AppButton` and design system tokens exclusively.
- [ ] Bill amounts continue to be strictly frozen and derived from server models with 0 client calculation divergence.

---

## 18. File Invariants & Verification Checklist
- [x] Invariant: Server-frozen amounts are strictly respected; no client-side recalculation of dues or totals (`bill_screen.dart:1-3`).
- [x] Invariant: Idempotent rating submission with server-guarded one-time rate check (`rating_sheet.dart:95-96`).
- [x] Verified: `ordersStringsHi` reviewed and checked for keys.
- [x] Verified: WhatsApp launcher handles failure gracefully without unhandled exceptions.
