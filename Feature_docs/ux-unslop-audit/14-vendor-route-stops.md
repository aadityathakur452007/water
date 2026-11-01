# V2 — Vendor Route & Stops Execution Audit

**Files Audited:**
- `apps/vendor_app/lib/features/route/route_screen.dart` (704 lines)
- `apps/vendor_app/lib/features/route/route_controller.dart`
- `apps/vendor_app/lib/features/stops/stop_detail_screen.dart` (629 lines)
- `apps/vendor_app/lib/features/stops/pod_sheet.dart` (205 lines)
- `apps/vendor_app/lib/features/stops/triple_sheet.dart` (247 lines)
- `apps/vendor_app/lib/features/stops/stops_controller.dart`

---

## 1. Executive Summary
The Route and Stops domain is the operational workhorse of the delivery app. It orchestrates morning truck dispatch, sequenced stop progression, SOS vehicle stockout repooling, and doorstep jar reconciliation. Domain robustness is high: offline outbox queueing for both PoD and cash receipts, server-enforced overpay prevention (`amountDue` check before posting cash), and callable phone number validation (`_hasCallablePhone`). However, the operational interface exhibits profound workflow confusion, ad-hoc visual styling, and copy crutches:
1. **The "Triple" vs "PoD" dual-completion paradox:** `stop_detail_screen.dart` offers delivery drivers two competing bottom sheets to record delivery completion: "Triple" (`triple_sheet.dart`) and "PoD" (`pod_sheet.dart`). Both sheets ask for overlapping metrics (empties returned, cash collected), forcing field drivers to guess which button satisfies the delivery contract.
2. **Slash `/` bilingual crutch:** Throughout stop execution, the UI resorts to awkward slash-separated labels: `"Triple / तीन काम एक साथ"`, `"PoD / डिलीवरी पूरी करें"`, `"Tuta / Kharab jar"`, `"Door Locked / Ghar band hai"`. This doubles cognitive load for hurried drivers scanning screens in bright sunlight.
3. **Text-query navigation instead of coordinate routing:** `route_screen.dart:70-73` initiates Google Maps navigation using a raw address text search (`google.com/maps/search/?api=1&query=$address`) rather than launching directly to the verified latitude/longitude coordinates stored on the stop.
4. **Ad-hoc color explosion:** Stops code abandons the design system tokens in favor of raw Flutter palette colors: `Colors.deepOrange`, `Colors.orange`, `Colors.red.shade700`, `Colors.white`, and `ShodashaTheme.blue`.

---

## 2. Screen Identity & Canonical Route
- **Route Screen:** Primary tab (Tab 0: `route`) in `vendor_shell.dart`. Canonical title: "Aaj ka route".
- **Stop Detail Screen:** Pushed route (`MaterialPageRoute`) when tapping any stop card on the route.
- **Triple Sheet:** Modal bottom sheet for recording fulls delivered, empties collected, cap replacements, and cash/UPI split.
- **PoD Sheet:** Modal bottom sheet for OTP verification and customer delivery confirmation.
- **Stockout SOS Dialog:** Emergency prompt to repool remaining undelivered stops when truck inventory is depleted.
- **Target Persona:** Three-wheeler / commercial pickup driver navigating Bhopal streets (MP Nagar, Kolar, Arera Colony) executing 30–50 can deliveries per morning shift.

---

## 3. Visual & Spatial Hierarchy
### Route Screen
- **AppBar:** Title "Aaj ka route" with SOS stockout button and refresh action.
- **Shift Progress Header:** Shows completed vs total stops, total fulls to deliver, and cash collected so far.
- **Active Stop Hero:** The current active stop card is elevated and styled with primary border and action buttons ("Navigate", "Call", "Open Stop").
- **Upcoming Stops List:** Chronologically sequenced stop cards with sequence badge (`Stop 1`, `Stop 2`), customer name, address snippet, and jar count.

### Stop Detail Screen
- **Customer Identity:** Customer name, phone number with 10-digit call button, and address with navigation button.
- **Ledger Snapshot Card:** Current customer jar balance (held jars, outstanding dues).
- **Action Strip:** Two competing action buttons ("Triple" and "PoD") plus "Mark Failed / RTO".

---

## 4. Color & Contrast Audit

| Element | File:Line | Color Token / Value | Contrast Ratio (vs BG) | Compliance / Finding |
|---|---|---|---|---|
| Route Screen Ground | `route_screen.dart:147` | Material default | Baseline | Standard light surface |
| Stockout Alert Title | `route_screen.dart:84` | `Colors.orange` | 2.1:1 vs dialog bg | Low contrast; should use `solarDark` |
| Stockout Confirm Button | `route_screen.dart:114` | `Colors.red.shade700` | 4.8:1 vs white text | High contrast warning CTA |
| Damaged Can Counter | `triple_sheet.dart:130` | `Colors.deepOrange` | 3.5:1 vs surface | Pass WCAG AA large |
| Stepper Add Icon | `triple_sheet.dart:78` | `ShodashaTheme.blue` | 5.8:1 vs surface | Compliant |
| Stop Sequence Badge | `route_screen.dart:250` | `ShodashaTheme.tealTint` | Tinted pill | Clear numbering anchor |
| RTO Failure Action | `stop_detail_screen.dart:133`| `Colors.deepOrange` | 3.5:1 vs surface | Ad-hoc raw color |

---

## 5. Typography & Text Scale

| Text Element | File:Line | Font Size | Weight | Finding |
|---|---|---|---|---|
| Route AppBar Title | `route_screen.dart:149` | Default (20px) | Default | Standard AppBar title |
| Stockout Dialog Notice | `route_screen.dart:95` | 13px | Default | Compact explanatory text |
| Stepper Counter Digit | `triple_sheet.dart:74` | 20px | w700 | Large, clear numeric font for drivers |
| Triple Sheet Title | `triple_sheet.dart:104` | 18px | w700 | Headline with bilingual slash |
| Stop Label Detail | `stop_detail_screen.dart:131` | Default (16px) | Default | High visibility customer identifier |

---

## 6. Spacing, Grid & Alignment
- **Route List Padding:** Uses `EdgeInsets.all(16)` with stop cards separated by `SizedBox(height: 12)`.
- **Triple Sheet Padding:** `EdgeInsets.only(left: 20, right: 20, top: 20, bottom: viewInsets.bottom + 20)`. Hardcoded 20dp padding.
- **Stepper Tap Grid:** Stepper `IconButton` widgets have `constraints: BoxConstraints(minWidth: 48, minHeight: 48)` (`triple_sheet.dart:66`), strictly satisfying touch target ergonomics.

---

## 7. Micro-Interactions, Feedback & States
- **One-Handed Steppers:** Both fulls and empties steppers in `TripleSheet` allow rapid single-tap incrementing/decrementing with direct bounds checking (`value > 0`).
- **Damaged Jar Sub-Flow:** Revealing damaged cans (`_empties > 0`) conditionally mounts a damaged can stepper and reason dropdown (`cracked`, `leaking_valve`, `seal_broken`).
- **Offline Outbox Replay:** If posting cash or PoD fails due to network outage, the transaction is enqueued into `widget.outbox` (`stop_detail_screen.dart:78-83`) and synced automatically when connection restores.
- **SOS Stockout Execution:** Dispatches `api.reportStockout`, repools undelivered stops, displays confirmation SnackBar with repooled count, and reloads the route.

---

## 8. Motion & Transitions
- **Stop Details Push:** Platform slide transition from route card to stop detail.
- **Completion Sheets:** Smooth modal bottom sheet reveal via `showModalBottomSheet`.
- **Navigation Launch:** Hands off immediately to native external Google Maps application.

---

## 9. Cognitive Load & Information Scent
- **Operational Redundancy:** Drivers are baffled by having both "Triple" and "PoD". In modern logistics, Proof of Delivery and Physical Asset Exchange (fulls/empties/caps) belong in a single unified doorstep handover flow.
- **Dual-Language Visual Noise:** Combining English and Hindi on the same visual line (`"Triple / तीन काम एक साथ"`, `"Customer_Refused / Customer ne mana kiya"`) clutters the interface and slows down decision-making.
- **Navigation Latency:** Searching Google Maps by text query can yield ambiguous results or drop the pin at the neighborhood center instead of the exact customer gate coordinates.

---

## 10. Touch Targets & Ergonomics
- **48dp Stepper Discipline:** Steppers explicitly declare `minWidth: 48, minHeight: 48` constraints, ensuring field usability with damp or gloved hands.
- **Call Button:** Validates phone format and renders prominent phone dialer shortcut.
- **Sticky Finish CTA:** Sheets position primary submit button at the bottom of the column within easy thumb reach.

---

## 11. Edge Cases & Resiliency
- **Overpay Prevention:** `_postCash` queries `c.amountDue(orderId)` before posting cash (`stop_detail_screen.dart:71`), ensuring driver cannot accidentally charge more than the server-authoritative balance.
- **Non-Callable Phone Numbers:** `_hasCallablePhone` checks length and prefix (starting 6–9), disabling dialer on dummy or invalid numbers (`stop_detail_screen.dart:59-64`).
- **Network Outage During Delivery:** Outbox queues both triple verification and cash receipt simultaneously with idempotent replay tags.
- **Emergency Stock Depletion:** Stockout dialog provides immediate release valve for empty trucks without forcing false failure marks on customers.

---

## 12. Code-Level Craft & Tech Debt

| File & Line | Issue | Severity | Proposed Fix |
|---|---|---|---|
| `stop_detail_screen.dart:10-12` | Two competing sheets ("Triple" vs "PoD") for finishing delivery | High | Consolidate into a single unified "Complete Delivery" modal sheet |
| `route_screen.dart:70-73` | Navigation uses text address query instead of Lat/Lng | High | Pass `geo:${stop.lat},${stop.lng}` coordinates to map launcher |
| `triple_sheet.dart:104, 107` | Slash-separated bilingual strings throughout UI | Medium | Set clean Hindi or English strings based on user language preference |
| `route_screen.dart:84, 114` | Raw palette colors (`Colors.orange`, `Colors.red.shade700`) | Medium | Standardize with `ShodashaTheme` warning and danger tokens |
| `triple_sheet.dart:98` | Hardcoded `20dp` padding in sheets | Low | Standardize to `AppSpacing.lg` |

---

## 13. Accessibility (a11y)
- **High Contrast Steppers:** Large numeric values (20px bold) centered between circular plus and minus icons.
- **Semantic Call Action:** Call button verifies valid mobile digits before enabling phone intent.
- **Screen Reader Announcements:** Form validation states announce required fields and error messages clearly.

---

## 14. Cross-Platform Consistency
- **Navigation Intent Scheme:** Uses standard `https://www.google.com/maps/...` with `LaunchMode.externalApplication`, resolving reliably across Android devices and iPhones.
- **Telephone Launcher:** `tel:$phone` intent cleanly invokes native system dialer on all platforms.

---

## 15. Proposed Layout & Unslop Direction
### Route Screen: "The Frictionless Morning Manifest"
- **Clean Shift Summary:** Compact top bar showing: `18/32 Delivered • 14 Remaining • 36 Jars on Truck`.
- **Unified Stop Card:**
  - Sequence badge + Customer Name + Delivery Window.
  - One-tap "Start Delivery" button that opens coordinate navigation directly.
- **SOS Emergency Tile:** Position "Report Vehicle Stockout" inside the route menu rather than competing with the top bar refresh.

### Stop Execution: "Unified Doorstep Handover"
- **Merge Triple and PoD into One Modal:**
  - Step 1: **Cans Exchanged** (Fulls handed over, Empties collected, Damaged cans).
  - Step 2: **Payment & OTP** (Collect ₹Total COD or verify prepaid OTP).
  - Step 3: **Confirm & Finish** (Single button submission that syncs all ledger and delivery flags in one transaction).
- **Coordinate-First Map Navigation:** Launch navigation directly using `google.navigation:q=${stop.lat},${stop.lng}` on Android with fallback to web coordinates.

---

## 16. Concrete Actionable Recommendations
1. **Consolidate Triple & PoD into One Screen:** Merge `TripleSheet` and `PodSheet` into a single, cohesive 2-step delivery handover modal.
2. **Switch Navigation to Coordinates:** Update `_navigate()` to use `geo:${stop.lat},${stop.lng}?q=${stop.lat},${stop.lng}` instead of encoding raw street address strings.
3. **Eliminate Slash Bilingual Crutch:** Clean up UI text to display clear, un-slashed strings (either clean Hindi or clean English).
4. **Replace Raw Flutter Colors:** Migrate `Colors.deepOrange`, `Colors.orange`, and `Colors.red.shade700` to `ShodashaTheme.solarDark` and `ShodashaTheme.danger`.
5. **Normalize Sheet Padding:** Change hardcoded `20dp` padding in `triple_sheet.dart` and `pod_sheet.dart` to `AppSpacing.lg`.

---

## 17. Acceptance Criteria
- [ ] Delivery completion is handled in a single unified flow (no separate Triple vs PoD confusion).
- [ ] Navigation button launches external maps with exact geographic coordinates.
- [ ] No slash-separated dual-language labels remain in the stops workflow.
- [ ] All colors and spacing conform strictly to `ShodashaTheme`.
- [ ] Offline outbox queueing, overpay prevention, and stockout repooling remain 100% intact.

---

## 18. File Invariants & Verification Checklist
- [x] Invariant: Proof of delivery and cash receipts queue to offline outbox upon network failure (`stop_detail_screen.dart:75-84`).
- [x] Invariant: Server overpay prevention verified via `amountDue` check before cash post (`stop_detail_screen.dart:70-74`).
- [x] Invariant: Stockout reporting repools remaining route stops without creating false delivery failures (`route_screen.dart:126-133`).
- [x] Verified: Phone validation properly guards against dead links on invalid numbers.
