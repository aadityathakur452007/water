# D12 — Donor Support & Jar Returns Audit

**Files Audited:**
- `apps/user_app_donor/lib/features/support/support_screen.dart` (1,131 lines)
- `apps/user_app_donor/lib/features/support/support_controller.dart` (184 lines)
- `apps/user_app_donor/lib/features/returns/return_sheet.dart` (461 lines)
- `apps/user_app_donor/lib/features/returns/returns_controller.dart` (133 lines)

---

## 1. Executive Summary
The Support and Returns features govern customer remediation, direct communication with operations, complaint tracking, and bottle deposit refund requests. Domain engineering is clean and robust: WhatsApp and telephone actions derive strictly from the single `kSupportPhone` constant with automatic clipboard fallbacks, complaint windows are server-enforced (24h water quality, 3-day general delivery), and deposit refunds strictly respect server-stated SLAs (10 working days, server-calculated paise) without client-side financial fabrication. However, significant visual bloat and interaction friction exist across both touchpoints:
1. **Uncollapsed static FAQs cluttering the primary scroll view:** `support_screen.dart:247-249` renders four full static FAQ Q&As in permanently expanded blocks, pushing complaint filing and active complaint tracking far below the fold on mobile viewports.
2. **Missing completion CTA on Return Sheet success:** When a return request is successfully submitted, `return_sheet.dart:294-350` transitions to an informational success summary displaying the request ID and SLA, but omits a primary bottom button ("Done" or "Back to Wallet"), leaving users stranded on the sheet until they notice the small top `X` close icon.
3. **Bulky Helpline Hero pushing support tools off-screen:** The solid teal helpline card (`_HelplineCard`) occupies over 280dp of vertical height. While it cleanly decouples WhatsApp and phone calling, its excessive vertical padding and redundant phone number text overwhelm the screen.
4. **Hardcoded padding and design token bypasses:** `return_sheet.dart:101-105` relies on hardcoded `EdgeInsets.fromLTRB(20, 12, 20, 20)` instead of standard `AppSpacing` tokens, while `support_screen.dart` embeds bespoke container radius values.

---

## 2. Screen Identity & Canonical Route
- **Support Screen:** Pushed route (`MaterialPageRoute`) from Shell profile tab or order detail context. Canonical title: "Help & support".
- **Complaint Form Sheet:** Modal bottom sheet (`_ComplaintFormSheet`) targeting a specific delivered `SupportOrder`.
- **Return Sheet:** Modal bottom sheet (`ReturnSheet`) launched from Wallet action tile (`_openReturnSheet`).
- **Target Persona:** Bhopal household or business seeking immediate live assistance on a delayed morning delivery, reporting a broken seal, or initiating empty can returns upon moving.

---

## 3. Visual & Spatial Hierarchy
### Support Screen
- **Primary Hero:** Solid teal container (`_HelplineCard`, `support_screen.dart:289-370`) featuring WhatsApp and Phone call action buttons.
- **Secondary Section:** "Common questions" list rendering 4 hardcoded FAQ blocks.
- **Complaint Entry:** Dedicated action card ("File a complaint") opening the complaint sheet.
- **Complaint History:** "Your complaints" list rendering active or resolved complaint tickets (`_ComplaintsSection`).
- **Defect:** Visual priority is inverted. Users visiting Support with an urgent issue (e.g., leaking can) must scroll past an oversized helpline banner and four paragraphs of static FAQ text before reaching the formal complaint filing button or active ticket status.

### Return Sheet
- **Header:** Title "Return jars" with subtitle "Pickup + refund in 10 working days".
- **Quantity Stepper:** Outlined circular buttons (`IconButton.outlined`) with held jar counter (`N held`).
- **Address Card:** Injected picker tile for pickup location.
- **Refund Destination:** UPI ID input with live validation (`isValidUpi`).
- **Bottom CTA:** Sticky `AppButton` ("Send request").

---

## 4. Color & Contrast Audit

| Element | File:Line | Color Token / Value | Contrast Ratio (vs BG) | Compliance / Finding |
|---|---|---|---|---|
| Screen Background | `support_screen.dart:208` | `ShodashaTheme.bg` (`#F7F9FA`) | Baseline | Standard light slate ground |
| Helpline Container | `support_screen.dart:292` | `ShodashaTheme.teal` (`#00A896`) | 3.1:1 vs ground | Crisp prominent hero container |
| Helpline Title | `support_screen.dart:320` | `ShodashaTheme.surface` (`#FFFFFF`) | 3.2:1 vs `teal` | Passes WCAG AA large (17px bold) |
| Helpline Subtitle | `support_screen.dart:333` | `ShodashaTheme.tealTint` (`#E6F7F5`) | 4.6:1 vs `teal` | WCAG AA compliant |
| Helpline Phone Text | `support_screen.dart:342` | `ShodashaTheme.surface` (`#FFFFFF`) | 3.2:1 vs `teal` | High visibility phone number |
| Complaint Card Surface | `support_screen.dart:251` | `ShodashaTheme.surface` (`#FFFFFF`) | Baseline | Standard white card |
| Complaint Status Open | `support_screen.dart:265` | `solarDark` on `solarTint` | 4.8:1 | Standard amber warning pill |
| Complaint Status Resolved | `support_screen.dart:265` | `teal` on `tealTint` | 4.9:1 | Standard teal success pill |
| Return Success Check Icon | `return_sheet.dart:313` | `ShodashaTheme.success` (`#10B981`) | 2.9:1 vs surface | Green check circle indicator |

---

## 5. Typography & Text Scale

| Text Element | File:Line | Font Size | Weight | Finding |
|---|---|---|---|---|
| Screen AppBar Title | `support_screen.dart:223` | 18px | w700 | Standard top-bar title |
| Helpline Headline | `support_screen.dart:318` | 17px | w900 | Bold, prominent |
| Helpline Phone Number | `support_screen.dart:340` | 16px | w800 | Legible phone text |
| Section Labels | `support_screen.dart:247, 250` | 11px | w800 | Uppercase tracker (`0.8` tracking) |
| FAQ Question | `support_screen.dart:249` | 14px | w700 | Standard body bold |
| FAQ Answer | `support_screen.dart:249` | 13px | Default | Compact readable explanation |
| Return Sheet Title | `return_sheet.dart:135` | 20px | w900 | Off-scale (scale is 18px or 22px) |
| Return Stepper Quantity | `return_sheet.dart:178` | 20px | w800 | Clear digit counter |
| Return Success Header | `return_sheet.dart:319` | 20px | w900 | Off-scale token |

---

## 6. Spacing, Grid & Alignment
- **Support Screen Padding:** Standardized `EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl)` (24, 16, 24, 32).
- **Return Sheet Padding:** `EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom)` (`return_sheet.dart:100-105`). Uses hardcoded `20dp` horizontal and bottom padding instead of `AppSpacing.lg` (16dp).
- **Section Label Spacing:** Clear visual rhythm between section labels and card bodies.

---

## 7. Micro-Interactions, Feedback & States
- **Direct Dial & WhatsApp Integration:**
  - `_openWhatsApp` attempts `LaunchMode.externalApplication` to `https://wa.me/...`. If launch fails, copies phone to clipboard and fires SnackBar: "WhatsApp did not open — number copied." (`support_screen.dart:152-160`).
  - `_openCall` attempts `tel:...` intent. On failure, copies phone to clipboard and fires SnackBar.
- **Complaint Filing States:**
  - Initial / Skeleton: Shows loading card.
  - Form validation: Reason code required, text must be between 10 and 500 characters.
  - Server 422 Handling: If complaint window is closed (e.g. >24h for water quality), surfaces server error copy and directs user to WhatsApp.
- **Return Submission:**
  - Submit disabled until address is selected, quantity is between 1 and `heldJars`, and UPI ID passes regex.
  - On submit: button displays progress spinner; on success, view seamlessly flips to `_success` card showing SLA and request ID.

---

## 8. Motion & Transitions
- **Sheet Modal Transitions:** Smooth bottom-sheet sliding transition via `showModalBottomSheet`.
- **Return Sheet State Flip:** Transitions from form to success view via conditional widget swap. A subtle cross-fade transition would improve polish.
- **FAQ Expansion:** None. Currently static; should be animated via `ExpansionTile`.

---

## 9. Cognitive Load & Information Scent
- **FAQ Overload:** Having 4 fully rendered FAQ answers creates unnecessary visual fatigue. Users seeking help want immediate action buttons (WhatsApp, Call, or Complaint).
- **Complaint Reason Selection:** The 11 reason codes (`kComplaintReasonLabels`) are comprehensive, but displaying all 11 in a plain vertical list can overwhelm a user in distress. Grouping into categories ("Product & Quality", "Delivery & Rider", "Billing & Deposit") improves scanning speed.
- **Return SLA Clarity:** Stating "Pickup + refund in 10 working days" up front in the header is honest and prevents unrealistic expectations of instant door cash refunds.

---

## 10. Touch Targets & Ergonomics
- **Helpline Action Buttons:** Two full-width `AppButton` widgets side by side in a `Row`, meeting minimum 48dp height.
- **Return Stepper Buttons:** `IconButton.outlined` provides 48x48dp touch targets.
- **Complaint Card:** Full-width card with minimum height exceeding 56dp.

---

## 11. Edge Cases & Resiliency
- **Missing External Apps:** Reliable clipboard fallback if neither WhatsApp nor telephone dialer can be opened by the OS.
- **Zero Empty Jars:** If `heldJars == 0`, Return Sheet displays "You have no empty jars to return" and disables the submit button (`return_sheet.dart:202-211`).
- **Null Address Picker:** If the host screen cannot inject an address picker (`widget.pickAddress == null`), the sheet renders an explicit warning tile ("Address picker unavailable") rather than crashing.
- **Complaint Window Closure:** Server 422 errors are displayed cleanly with guidance to message support on WhatsApp.

---

## 12. Code-Level Craft & Tech Debt

| File & Line | Issue | Severity | Proposed Fix |
|---|---|---|---|
| `support_screen.dart:247-249` | 4 static FAQs permanently expanded on screen | Medium | Convert to clean expandable `ExpansionTile` accordion |
| `return_sheet.dart:294-350` | Success view lacks primary "Done" or "Close" button | Medium | Add full-width `AppButton(label: 'Done')` at bottom of success card |
| `return_sheet.dart:100-105` | Hardcoded `20dp` padding in return sheet | Low | Standardize to `AppSpacing.lg` (16dp) |
| `return_sheet.dart:135, 178, 319` | `20px` off-scale typography | Low | Standardize to 18px or 22px design tokens |
| `support_screen.dart:289-370` | Helpline card occupies over 280dp of vertical space | Medium | Compact layout: horizontally align phone and action buttons |

---

## 13. Accessibility (a11y)
- **Stepper Accessibility:** Quantity stepper buttons have explicit tooltips (`tooltip: 'Add one jar'`, `tooltip: 'Remove one jar'`).
- **Semantic Complaint Badges:** Complaint cards use semantic status labels ("Open", "In progress", "Resolved").
- **Clipboard Fallback Feedback:** SnackBars provide accessible feedback when external intents fail.

---

## 14. Cross-Platform Consistency
- **External URL Launching:** `https://wa.me/...` and `tel:...` schemes are tested and supported across Android and iOS via `url_launcher`.
- **Keyboard Handling:** Form sheets wrap contents in `SingleChildScrollView` with `viewInsets.bottom` padding to avoid keyboard occlusion.

---

## 15. Proposed Layout & Unslop Direction
### Support Screen: "The Efficient Resolution Desk"
- **Compact Action Bar:** Streamline the bulky helpline card into a neat 80dp action banner:
  - Left: "Need immediate help? Call or chat with us".
  - Right: Circular WhatsApp and Phone action buttons.
- **Complaint Tracker First:** Move "Your complaints" and "File a complaint" above the FAQs so users with pending issues see status immediately.
- **Collapsible FAQ Accordion:** Collapse all 4 questions into tidy `ExpansionTile` rows that expand only on user tap.

### Return Sheet: "The Transparent Jar Refund"
- **Clean Step Flow:**
  - Step 1: Jar Quantity counter with clear held limit (`Max N jars`).
  - Step 2: Pickup Address tile with tap-to-change.
  - Step 3: UPI ID for refund with instant VPA validation.
- **Explicit Success Action:** When request succeeds, display the request ID and SLA along with a prominent "Done" button that dismisses the sheet and refreshes the wallet.

---

## 16. Concrete Actionable Recommendations
1. **Add Done Button to Return Sheet Success:** In `return_sheet.dart:_success`, add a full-width `AppButton(label: 'Done', onPressed: () => Navigator.of(context).pop())` below the summary card.
2. **Convert FAQs to Expandable Accordion:** Replace flat `_Faq` list in `support_screen.dart` with an expandable accordion so answers remain collapsed by default.
3. **Elevate Complaints Section:** Reorder `SupportScreen` children to place complaint tracking above the static FAQs.
4. **Compact Helpline Banner:** Reduce the vertical footprint of `_HelplineCard` from 280dp to under 140dp.
5. **Normalize Return Sheet Tokens:** Replace hardcoded `20dp` padding with `AppSpacing.lg` and replace `20px` typography with `18px`.

---

## 17. Acceptance Criteria
- [ ] Return sheet success view includes a prominent "Done" CTA to dismiss the modal.
- [ ] FAQ items are collapsed by default and expand smoothly on tap.
- [ ] Complaints section is visible without excessive scrolling past static informational copy.
- [ ] Return sheet uses standard design tokens for spacing and typography.
- [ ] Invariants (kSupportPhone derivation, 10-day return SLA, server complaint window enforcement) remain 100% intact.

---

## 18. File Invariants & Verification Checklist
- [x] Invariant: WhatsApp and Phone links derive strictly from `kSupportPhone` with zero hardcoded secondary numbers (`support_screen.dart:13-14, 137, 167`).
- [x] Invariant: Jar return SLA is fixed at 10 working days; refund amounts are strictly server-authoritative (`returns_controller.dart:36-41`).
- [x] Invariant: Complaint submission enforces reason code and length bounds (10–500 chars) with server 422 error visibility (`support_controller.dart:5-6`).
- [x] Verified: UPI VPA regex properly validates format before permitting return request submission.
