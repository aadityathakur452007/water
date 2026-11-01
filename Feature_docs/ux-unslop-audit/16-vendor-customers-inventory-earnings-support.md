# V4 — Vendor Customers, Inventory, Earnings & Support Audit

**Files Audited:**
- `apps/vendor_app/lib/features/customers/customers_screen.dart` (251 lines)
- `apps/vendor_app/lib/features/customers/customers_controller.dart` (112 lines)
- `apps/vendor_app/lib/features/inventory/inventory_screen.dart` (125 lines)
- `apps/vendor_app/lib/features/earnings/earnings_screen.dart` (248 lines)
- `apps/vendor_app/lib/features/earnings/earnings_controller.dart` (72 lines)
- `apps/vendor_app/lib/features/support/support_screen.dart` (275 lines)
- `apps/vendor_app/lib/features/support/support_controller.dart` (89 lines)

---

## 1. Executive Summary
The operational secondary tier of the Vendor application covers customer lookups, truck bottle inventory ("Stock"), delivery earnings/commission statements, and vendor-side customer dispute investigations ("Support"). While core mechanics correctly reuse existing route controllers (e.g. inventory computes directly from route manifest without speculative network endpoints) and integrate `cascade.dart` entrance animations, this tier contains severe money law violations, desktop-centric form patterns, and layout slop:
1. **Invented client-side earnings math:** `earnings_screen.dart:117` directly violates the non-negotiable money law: `c.earnedPayout > 0 ? rupees(c.earnedPayout) : rupees(c.stopsDone * 2000), // default Rs 20/stop`. If the server returns zero or null payout, the client multiplies completed stops by ₹20.00 right in the UI presentation layer.
2. **Desktop ID-copying form in mobile support:** `support_screen.dart:46-97` implements complaint verification like a database administrative tool. A driver must tap an item in a list to copy an alphanumeric UUID into an `_id` `TextField`, select a check type, enter notes, and hit "Agree" or "Disagree".
3. **Bilingual slash titles across all four screens:** Every screen title uses the unformatted slash crutch: `Customers / ग्राहक`, `Stock / स्टॉक`, `Earnings / कमाई`, `Support / सहायता`.
4. **Token drift and off-scale sheet radii:** `customers_screen.dart:49` hardcodes `Radius.circular(8)` for its detail sheet, while `ShodashaTheme.radiusSheet` is 24dp.

---

## 2. Screen Identity & Canonical Route
- **Customers Screen:** Pushed from shell drawer or route card. Searchable directory of assigned route customers.
- **Inventory Screen ("Stock"):** Pushed from drawer. Visual manifest of 20L full cans loaded vs empty cans collected.
- **Earnings Screen:** Root tab destination (Tab 1: `earnings`) in `vendor_shell.dart`. Displays commission and COD cash held.
- **Support Screen:** Root tab destination (Tab 2: `support`) in `vendor_shell.dart`. Handles customer quality disputes and complaint reviews.
- **Target Persona:** Commercial water delivery partner reviewing daily payout, auditing empty jar balance, and searching for customer phone numbers.

---

## 3. Visual & Spatial Hierarchy
### Customers Screen
- **Header:** Search bar (`labelText: 'Naam / phone se khojein'`).
- **Body:** Staggered `CascadeScope` list of customers with sequence badge, name, phone, and total cans expected.
- **Detail Sheet:** Modal showing customer address, past orders, and jar exchange history.

### Inventory (Stock) Screen
- **Summary Bar:** Top row displaying total route progress (`N/M done`).
- **Data Tiles:** Vertical list of 4 metric tiles:
  - "Lene hain (fulls)" (Cans to load).
  - "Wapas aane hain (empties)" (Empties to collect).
  - "Stop done" (Completed stops).
  - "Stop baki" (Pending stops).

### Earnings Screen
- **Shift Summary Bar:** Total completed stops counter.
- **Commission Card:** `blueTint` container featuring total earned payout in 24px bold.
- **Cash Custody Card:** Total cash collected in physical bag.
- **Flagged Holds:** Warning section for any delivery dispute deductions.

### Support Screen
- **Queue List:** Open complaints and water quality incidents assigned to this vendor.
- **Verification Form:** ID input, review notes, and Agree/Disagree binary action buttons.

---

## 4. Color & Contrast Audit

| Element | Element Line | Color Token / Value | Contrast Ratio (vs BG) | Compliance / Finding |
|---|---|---|---|---|
| Screen Background | Everywhere | Standard light surface | Baseline | Standard light surface |
| Commission Card Ground | `earnings_screen.dart:94` | `ShodashaTheme.blueTint` | 1.15:1 vs ground | Informational container |
| Commission Card Border | `earnings_screen.dart:95` | `ShodashaTheme.blue` (`#1A56DB`) | 5.8:1 vs surface | Sharp visual boundary |
| Commission Payout Value| `earnings_screen.dart:120` | `ShodashaTheme.blue` | 5.8:1 vs `blueTint` | Bold high-contrast payout text |
| Offline Icon | `inventory_screen.dart:35` | `ShodashaTheme.muted` | 4.6:1 vs surface | Pass WCAG AA |
| Inventory Metric Value | `inventory_screen.dart:119`| `ShodashaTheme.ink` | 14.1:1 vs surface | Crisp large metric value |
| Disagree Action Button | `support_screen.dart:140` | `ShodashaTheme.danger` | 5.2:1 vs surface | Clear warning signal |

---

## 5. Typography & Text Scale

| Text Element | File:Line | Font Size | Weight | Finding |
|---|---|---|---|---|
| App Bar Titles | All screens | Default (20px) | Default | Standard titles with bilingual slash |
| Search Field Label | `customers_screen.dart:74`| Default (16px) | Default | Standard input label |
| Inventory Tile Label | `inventory_screen.dart:115`| Default (14px) | Default | Muted metric title |
| Inventory Tile Value | `inventory_screen.dart:119`| 16px | w700 | Bold numeric counter |
| Earnings Commission Header | `earnings_screen.dart:108`| 15px | w700 | Off-scale (scale is 14px or 16px) |
| Earnings Total Payout | `earnings_screen.dart:119`| 24px | w800 | Bold primary financial focal point |
| Support Ticket Status | `support_screen.dart:92` | 12px | Default | Clean tag size |

---

## 6. Spacing, Grid & Alignment
- **List Padding:** Standardized `EdgeInsets.all(16)` across all four screens.
- **Card Separations:** `SizedBox(height: 10)` or `SizedBox(height: 12)` vertical rhythm.
- **Detail Sheet Radius:** `customers_screen.dart:49` uses `Radius.circular(8)`, which looks squared off compared to the standard 24dp bottom sheet radius.

---

## 7. Micro-Interactions, Feedback & States
- **Customer Real-Time Filtering:** `_search.onChanged` delegates to `c.setQuery`, performing instant client-side string filtering over cached customer names and phone numbers.
- **Loading / Stale Data Protection:** `InventoryScreen` explicitly avoids rendering `0 jar` while the route controller is loading or offline (`inventory_screen.dart:22-25`).
- **Dispute Verification Submission:** `_submit(agree)` sends resolution to server, clears form fields upon success, and displays confirmation SnackBar.

---

## 8. Motion & Transitions
- **Cascade Entrance:** `customers_screen.dart` and `support_screen.dart` wrap lists in `CascadeScope`, delivering a staggered 600ms ease-out entrance animation.
- **Search Filtering:** Instant list replacement without layout jump.
- **Modal Sheets:** Slide-up bottom sheets via standard Material bottom sheet controller.

---

## 9. Cognitive Load & Information Scent
- **Client Fallback Math Confusion:** When `c.earnedPayout` is zero, showing `₹20.00 × stops` invents a promise of money that the backend has not settled or confirmed. If the vendor was penalized or on a different incentive model, this creates legal/operational disputes.
- **Complex Dispute Form:** Field drivers are not desk support agents. Asking them to manually review incident IDs and input text notes in an administrative form during a delivery shift creates heavy cognitive load.
- **Inventory Visual Deficit:** The stock screen is a plain text list of numbers (`18 jar`, `12 jar`). A visual vehicle loading diagram (e.g. truck bed graphic showing full vs empty slots) would be instantly recognizable.

---

## 10. Touch Targets & Ergonomics
- **Search Bar:** Standard 56dp input height with clear prefix icon.
- **Customer List Tile:** Generous height with 48dp leading avatar mark.
- **Verification Buttons:** Side-by-side "Agree" and "Disagree" buttons meeting 48dp minimum touch target height.

---

## 11. Edge Cases & Resiliency
- **Empty Customer Route:** `CustomersState.empty` displays honest message: "Aaj koi customer nahi — route khali hai".
- **Zero Results in Search:** Distinguishes between empty initial route and zero search matches ("Khoj me kuch nahi mila", line 106).
- **Network Failure on Stock:** Renders offline cloud icon with clear retry button.

---

## 12. Code-Level Craft & Tech Debt

| File & Line | Issue | Severity | Proposed Fix |
|---|---|---|---|
| `earnings_screen.dart:117` | Client-side earnings math (`stopsDone * 2000`) | Critical | Remove client fallback math; display only server-stated payout |
| `support_screen.dart:46-97` | Desktop administrative form pattern for incident verification | High | Replace with card-based 1-tap review actions |
| `customers_screen.dart:49` | Off-scale `8dp` sheet corner radius | Low | Standardize to `ShodashaTheme.radiusSheet` (24dp) |
| All screens | Slash-separated bilingual headers (`Customers / ग्राहक`) | Medium | Choose consistent clean language per user preference |
| `inventory_screen.dart:86-89` | Raw text list for inventory instead of visual manifest | Medium | Implement visual truck manifest card |

---

## 13. Accessibility (a11y)
- **High Contrast Tiles:** White surfaces on light ground with dark ink text.
- **Search Semantics:** Prefix search icon and explicit label on input field.
- **Screen Reader Announcements:** Clear distinction between loading, error, and loaded states.

---

## 14. Cross-Platform Consistency
- **Cascade Motion:** Standardized across platforms, disabled when OS requests reduced motion.
- **Bottom Sheets:** Responsive to on-screen keyboard via `viewInsets.bottom`.

---

## 15. Proposed Layout & Unslop Direction
### Earnings Screen: "Honest Commission Statement"
- **Strict Server Truth:** Show verified payout amount from `GET /vendor/earnings`. If uncalculated or pending, display "Payout calculated at shift close", NEVER a client-side ₹20 multiplication.
- **Two Big Balances:**
  - Balance 1: **Earned Commission** (`₹480 Verified`).
  - Balance 2: **Cash in Hand** (`₹1,600 to be deposited at hub`).

### Inventory Screen: "Visual Truck Loading Sheet"
- **Truck Bed Visual:** A clean rectangular graphic showing:
  - Top Deck: **Full Cans** (remaining to deliver).
  - Bottom Deck: **Empty Cans** (collected from customers).
  - Real-time balance: `Fulls + Empties = Total Truck Capacity`.

### Support Screen: "1-Tap Incident Resolver"
- **Replace Form with Incident Cards:** Present each incident directly as an action card:
  - "Stop #12 (Rahul Sharma): Broken Seal Reported".
  - Actions: [Did you replace the can? Yes / No].
  - Eliminate the text field and ID-copying requirement entirely.

---

## 16. Concrete Actionable Recommendations
1. **Purge Client Fallback Earnings Math:** In `earnings_screen.dart:117`, replace `rupees(c.stopsDone * 2000)` with `rupees(0)` or `"Pending settlement"`, ensuring 100% adherence to server-authoritative money rules.
2. **Eliminate Desktop Form in Support:** Redesign `support_screen.dart` so incident cards contain direct inline resolution buttons without requiring text controllers for incident IDs.
3. **Clean Up Bilingual Slashes:** Standardize all 4 screen AppBar titles to un-slashed strings.
4. **Normalize Sheet Corner Radii:** Change `Radius.circular(8)` in `customers_screen.dart:49` to `Radius.circular(ShodashaTheme.radiusSheet)`.
5. **Enrich Inventory Visuals:** Add a visual truck capacity meter displaying loaded cans vs returned empties.

---

## 17. Acceptance Criteria
- [ ] Earnings screen displays only server-authoritative commission; zero client-side multiplication of stops.
- [ ] Incident verification does not require manual typing or copying of UUIDs.
- [ ] Bottom sheets utilize the standard design system corner radius (24dp).
- [ ] No slash-separated dual-language screen titles remain.
- [ ] Customer search and inventory progress continue to function accurately offline.

---

## 18. File Invariants & Verification Checklist
- [x] Invariant: Inventory numbers strictly derived from `RouteController` without redundant API endpoints (`inventory_screen.dart:1-3`).
- [x] Invariant: Earnings payout must never be fabricated on client (flagged for remediation in `earnings_screen.dart:117`).
- [x] Invariant: Customer search performs instantaneous local filtering without firing network storms (`customers_screen.dart:71-73`).
- [x] Verified: Cascade entrance animations respect reduced motion across customer lists.
