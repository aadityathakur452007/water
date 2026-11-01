# D8 — Donor Subscriptions & Plan Builder Audit

**Files Audited:**
- `apps/user_app_donor/lib/features/subscriptions/subscription_screen.dart` (1,633 lines)
- `apps/user_app_donor/lib/features/subscriptions/plan_builder_sheet.dart` (880 lines)
- `apps/user_app_donor/lib/features/subscriptions/subscription_controller.dart` (657 lines)

---

## 1. Executive Summary
The Subscriptions domain governs recurring water delivery, pause/resume scheduling, prepaid wallet top-ups, outstanding dues settlement, and plan cancellation. Architectural integrity is high: server-authoritative money fields (`GET /billing/dues`, `POST /subscriptions/estimate`), strict idempotency headers for payments, and realistic refund expectation management (no false promises of instant refunds). However, the implementation is weighed down by 3,170 lines across three files with noticeable craft slop:
1. **Severe action crowding in Plan Cards:** Subscription cards pack up to four text buttons ("Add top-up", "Pause/Resume", "Skip today", "Cancel") inside a loose `Wrap` widget. Destructive actions ("Cancel" in danger red) sit immediately adjacent to routine actions ("Skip today"), risking high-friction misclicks on 360dp mobile screens.
2. **Modal-inside-modal dropdown anti-pattern:** `plan_builder_sheet.dart` uses a raw Flutter `DropdownButtonFormField` for delivery address selection inside a 92% height modal sheet. Expanding the dropdown spawns an awkward popup overlay that clashes with the sheet's gesture boundaries.
3. **Design system token drift:** Despite using `AppButton` in places, multiple core interaction points bypass the component library in favor of manual `ElevatedButton.styleFrom` and `TextButton.styleFrom` (e.g., `_EmptyState:785`, `_PauseSheet:1254`).
4. **Sub-scale typography:** Micro-typography includes off-scale sizes like `10.5px` (`_StatusPill:1064`) and `11.5px` (`_paymentSummary:406`), violating the 12/14/16/18/22/28 donor type scale.

---

## 2. Screen Identity & Canonical Route
- **Subscription Screen:** Root tab destination (Tab 2: `subscriptions`) in `donor_shell.dart`. Canonical title: "Subscriptions".
- **Plan Builder:** Modal bottom sheet triggered via `showPlanBuilderSheet(...)` from empty state or action button.
- **Supporting Dialogs:** `_PauseSheet`, `_CancelSheet`, `_TopUpDialog`, and Dues payment intent alert.
- **Target Persona:** Residential household or office manager in Bhopal managing steady recurring 20L can replenishment (daily, alternate days, or weekly).

---

## 3. Visual & Spatial Hierarchy
### Subscriptions Screen
- **Primary Hero:** Outstanding dues banner (`_DuesStrip`, `subscription_screen.dart:651-734`) rendered in `tealTint` with bold 22px dues amount and money CTA if dues exist.
- **Secondary Cards:** List of active/paused subscription plans (`_PlanCard`), featuring address headline, status pill, SKU subtitle, next delivery timestamp, and action buttons.
- **Empty State:** Large centered card with circular `event_repeat` icon and "Build a plan" CTA.
- **Hierarchy Defect:** When dues are zero and plans are active, the screen lacks a focal anchor. Cards look identical and blend into a generic list without emphasizing the upcoming morning delivery slot.

### Plan Builder Sheet
- **Primary Anchor:** "Build your plan" headline at 20px bold (`plan_builder_sheet.dart:351-358`).
- **Configuration Blocks:** Quantity stepper card -> Rhythm chips (daily, alternate, weekly) -> Billing chips (per delivery, prepaid, postpaid) -> Payment chips (UPI, COD) -> Address dropdown -> Server estimate card.
- **Bottom Anchor:** Sticky bottom action area with `startPlan` button and dynamic payment summary disclaimer.

---

## 4. Color & Contrast Audit

| Element | File:Line | Color Token / Value | Contrast Ratio (vs BG) | Compliance / Finding |
|---|---|---|---|---|
| Screen Ground | `subscription_screen.dart:453` | `ShodashaTheme.bg` (`#F7F9FA`) | Baseline | Clean neutral slate |
| Card Surface | `subscription_screen.dart:840` | `ShodashaTheme.surface` (`#FFFFFF`) | Baseline | High contrast with ground |
| Dues Strip Ground | `subscription_screen.dart:668` | `ShodashaTheme.tealTint` (`#E6F7F5`) | 1.12:1 vs ground | Low border contrast; uses `teal.withValues(alpha: 0.25)` border |
| Dues Eyebrow | `subscription_screen.dart:690` | `ShodashaTheme.tealDeep` (`#0D6559`) | 7.1:1 vs `tealTint` | WCAG AAA compliant |
| Dues Amount | `subscription_screen.dart:700` | `ShodashaTheme.ink` (`#0F172A`) | 14.1:1 vs `tealTint` | High contrast, bold |
| Status Pill Active | `subscription_screen.dart:1051` | `teal` on `tealTint` | 4.8:1 | WCAG AA compliant |
| Status Pill Cancel | `subscription_screen.dart:1042` | `danger` (`#DC2626`) on `bg` | 5.2:1 | WCAG AA compliant |
| Low Balance Banner | `subscription_screen.dart:942` | `solarDark` on `solarTint` | 4.9:1 | WCAG AA compliant |
| Cancel Action Text | `subscription_screen.dart:1021` | `ShodashaTheme.danger` (`#DC2626`) | 5.4:1 vs surface | Clear warning signal |
| Plan Card Border | `subscription_screen.dart:841` | `ShodashaTheme.border` (`#E2E8F0`) | 1.2:1 vs ground | Crisp subtle demarcation |

---

## 5. Typography & Text Scale

| Text Element | File:Line | Font Size | Weight | Finding |
|---|---|---|---|---|
| Screen AppBar Title | `subscription_screen.dart:462` | 18px | w700 | Fits screen identity cleanly |
| Dues Strip Eyebrow | `subscription_screen.dart:687` | 11px | w800 | Legible uppercase eyebrow (`0.4` tracking) |
| Dues Total Amount | `subscription_screen.dart:697` | 22px | w900 | Strong focal point |
| Status Pill Label | `subscription_screen.dart:1064` | 10.5px | w800 | **Off-scale token**: Violates 12px scale boundary |
| Plan Address Header | `subscription_screen.dart:855` | 15px | w800 | Off-scale (scale is 14 or 16) |
| Plan Detail Line | `subscription_screen.dart:870` | 13px | w600 | Second body size (widely used in repo) |
| Plan Builder Title | `plan_builder_sheet.dart:353` | 20px | w900 | Off-scale (scale is 18 or 22) |
| Payment Summary | `plan_builder_sheet.dart:406` | 11.5px | Default | **Off-scale token**: Fragmented font size |

---

## 6. Spacing, Grid & Alignment
- **List View Padding:** `subscription_screen.dart:497` uses `EdgeInsets.fromLTRB(16, 8, 16, 24)`.
- **Card Spacing:** List items separated by `SizedBox(height: 10)` (lines 534). Hardcoded 10dp deviates from `AppSpacing.sm` (8dp) or `AppSpacing.md` (12dp).
- **Plan Builder Padding:** `EdgeInsets.fromLTRB(16, 10, 16, 24)` with sections separated by `SizedBox(height: 16)`.
- **Alignment Defect:** In `_PlanCard`, text metadata rows (`_DetailRow` and `_MoneyRow`) use `MainAxisAlignment.spaceBetween`, pushing keys and values to opposite screen edges, which reduces scanning efficiency on wide devices.

---

## 7. Micro-Interactions, Feedback & States
- **Subscription Screen States:**
  - Initial load: Shows 3-item skeleton loader (`_SubsSkeleton`).
  - Refreshing: Linear progress indicator at list top (`subscription_screen.dart:502-506`) plus native `RefreshIndicator`.
  - Empty: Shows instructional onboarding card (`_EmptyState`).
  - Stale list on network error: Displays non-blocking amber `_StaleBanner` (`subscription_screen.dart:608-647`) with retry button while keeping cached data visible.
  - Active / Paused / Canceled / Awaiting Payment: Discrete status pill and context notes (`pausedUntil`, `canceledNote`).
- **Skip Today Action:**
  - Confirmed via modal dialog.
  - If cut-off has passed (`lateSkip`), presents distinct alert dialog prompting customer to call support directly with `kSupportPhone` (`subscription_screen.dart:212-230`).
- **Top-up Polling:**
  - Automated 5-iteration poll (every 3 seconds) for webhook confirmation in `_TopUpDialog`. If unconfirmed, retains "Check status" and "Copy link" buttons.

---

## 8. Motion & Transitions
- **Sheet Transitions:** Smooth bottom sheet modal transitions (`isScrollControlled: true`).
- **Quantity Stepper:** Instant number increment without digit roll or scale bump.
- **Chips Selection:** Instant standard Flutter ChoiceChip color change without animated pill slider.

---

## 9. Cognitive Load & Information Scent
- **Multiple Billing Modes:** Displaying "Per delivery", "Monthly prepaid", and "Monthly postpaid" can overwhelm first-time donors. Explanatory text under payment chips helps, but visual contrast between upfront cost vs delayed billing could be clearer.
- **Action Wrap Clutter:** In `_PlanCard`, actions like "Add top-up", "Pause", "Skip today", and "Cancel" all compete with identical text button weight. Destructive "Cancel" is differentiated only by red font color, creating accidental tap hazard.
- **Address Selection Friction:** Selecting an address via a standard form dropdown inside a bottom sheet feels cumbersome and non-native on mobile.

---

## 10. Touch Targets & Ergonomics
- **TextButton Wrap in Card:** TextButtons have default padding, but in a wrapped row, touch bounding boxes overlap on small 360dp screens.
- **Quantity Stepper:** `IconButton` components provide accessible 48x48dp tap areas.
- **ChoiceChips:** Tap targets satisfy minimum height standards (44dp+).
- **Sticky Start Plan Button:** Full-width `AppButton` at sheet bottom adheres strictly to thumb-zone ergonomics.

---

## 11. Edge Cases & Resiliency
- **Signed-Out State:** Plan builder checks `_signedOut` and renders dedicated `_SignedOutNote` with direct sign-in hook.
- **No Address Available:** Displays amber warning container with "Add address" action button that dismisses sheet and triggers address flow.
- **Network / Offline Estimate Failure:** Plan builder shows inline error and retry button without clearing current plan configuration.
- **Idempotency Discipline:** Plan builder regenerates `_idemKey` (`Uuid().v4()`) whenever plan parameters change, and resets upon `PAYLOAD_MISMATCH` error (`plan_builder_sheet.dart:268`).
- **Postpaid UPI Enforcement:** Selecting monthly billing automatically disables COD selection (`plan_builder_sheet.dart:536`), enforcing server billing constraints.

---

## 12. Code-Level Craft & Tech Debt

| File & Line | Issue | Severity | Proposed Fix |
|---|---|---|---|
| `subscription_screen.dart:785` | Manual `ElevatedButton.styleFrom` in empty state | Medium | Migrate to `AppButton` |
| `subscription_screen.dart:1254` | Manual `ElevatedButton.styleFrom` in `_PauseSheet` | Medium | Migrate to `AppButton` |
| `subscription_screen.dart:1064` | `10.5px` font in `_StatusPill` | Low | Standardize to 11px or 12px design token |
| `subscription_screen.dart:982-1026` | Card action buttons crammed in loose `Wrap` | High | Reorganize into primary action + overflow `...` menu |
| `plan_builder_sheet.dart:673-694` | `DropdownButtonFormField` inside bottom sheet | Medium | Replace with bottom sheet picker or clean address tiles |
| `plan_builder_sheet.dart:406` | `11.5px` font in payment summary | Low | Standardize to 12px design token |
| `subscription_screen.dart:560-567` | Skeleton loader uses solid teal container without shimmer | Low | Use standard neutral pulse or theme skeleton |

---

## 13. Accessibility (a11y)
- **Status Pill Semantics:** `_StatusPill` explicitly wraps text in `Semantics(label: 'Status: $label', excludeSemantics: true)` (`subscription_screen.dart:1052-1054`). Excellent accessibility hygiene.
- **Quantity Stepper:** Tooltips provided for decrease (`subStrings['removeJar']`) and increase (`subStrings['addJar']`).
- **Color Independence:** Billing pending vs active is conveyed by both label text and color.

---

## 14. Cross-Platform Consistency
- **Clipboard & URL Launching:** Uses `Clipboard.setData` and `launchUrl(..., mode: LaunchMode.externalApplication)` across UPI intents, working reliably on iOS and Android.
- **Keyboard Insets:** Clean handling of `MediaQuery.viewInsetsOf(context).bottom` across all modal sheets (`_PauseSheet`, `_CancelSheet`, `PlanBuilderSheet`).

---

## 15. Proposed Layout & Unslop Direction
### Subscription Tab: "The Living Schedule"
- **Upcoming Delivery Hero Card:** Replace generic card list with a prominent "Next Arrival" hero card for the nearest delivery (e.g., "Tomorrow, 7:00 AM – 9:00 AM • 2 Jars").
- **Tidy Plan Card Actions:**
  - Move routine actions ("Pause", "Skip next") to prominent secondary outline pills.
  - Move destructive/rare actions ("Cancel plan", "Change address") into a clean kebab (`...`) popup menu to eliminate accidental tap risk and declutter the card.
- **Dues Settlement Banner:** Keep the honest `_DuesStrip`, but streamline button placement to avoid double-stacking text buttons.

### Plan Builder: "Interactive Cadence Selector"
- **Rhythm Cards instead of Raw Chips:** Present Daily, Alternate Days, and Weekly as visual cadence cards with delivery frequency and estimate previews.
- **Address Tile Selector:** Replace the clunky form dropdown with a clean address selection row showing full street name and tap-to-change sheet.

---

## 16. Concrete Actionable Recommendations
1. **Declutter Card Action Buttons:** Refactor `_PlanCard:982-1026` from a flat `Wrap` of text buttons into a structured action row: primary action button + overflow kebab menu for cancellation.
2. **Eliminate Modal Dropdown:** Replace `DropdownButtonFormField` in `plan_builder_sheet.dart` with an interactive address card tile that opens an address selector sheet.
3. **Normalize Typography:** Replace off-scale `10.5px` and `11.5px` values with `12px` (`ShodashaTheme.caption`).
4. **Standardize Buttons on `AppButton`:** Remove inline `ElevatedButton.styleFrom` instances in `_EmptyState:785` and `_PauseSheet:1254`.
5. **Modernize Skeleton Loading:** Replace raw mint green containers in `_SubsSkeleton` with neutral grey bone elements.

---

## 17. Acceptance Criteria
- [ ] No destructive actions ("Cancel plan") sit unshielded adjacent to frequent actions ("Skip today").
- [ ] Plan builder uses native tile/sheet selection for delivery addresses rather than form dropdowns.
- [ ] Typography conforms strictly to the 12/14/16/18/22/28 type scale.
- [ ] All action buttons utilize `AppButton` without direct `ElevatedButton.styleFrom` overrides.
- [ ] Server-enforced rules (≥24h resume notice, UPI requirement for monthly billing, refund disclaimer) remain 100% intact.

---

## 18. File Invariants & Verification Checklist
- [x] Invariant: Server-authoritative dues (`GET /billing/dues`) and estimates (`POST /subscriptions/estimate`) without client math (`subscription_screen.dart:6-7`).
- [x] Invariant: Minimum 24h guard on delivery resumption enforced (`subscription_screen.dart:174`).
- [x] Invariant: Cancellation requires valid UPI ID and does not guarantee immediate refunds (`subscription_screen.dart:1300-1306`).
- [x] Verified: `subStrings` checked for complete copy coverage.
