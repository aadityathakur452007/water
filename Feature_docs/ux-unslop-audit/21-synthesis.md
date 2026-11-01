# 21 — Cross-Cutting UI/UX Audit Synthesis

**Branch:** `037-uiux-unslop-audit`  
**Date:** 2026-10-31  
**Scope:** Lead Agent Synthesis of 20 Field Audits (12 Donor Screens, 4 Vendor Clusters, 4 Cross-Cutting Audits)  
**Baseline Verification:** Donor `flutter test` 75/75 passed; Vendor `flutter test` 68/68 passed; Analyzers 100% clean. Zero application code touched.

---

## 1. Audit Coverage & Roster Table

Every screen, modal, bottom sheet, controller, and shared UI component in both applications has been comprehensively audited across 20 distinct markdown documents following the strict 18-section contract.

| ID | Domain | Target Screens & Controllers | Audit Document | Status |
|---|---|---|---|---|
| **D1** | Donor Auth | `login_screen.dart`, `auth_gate.dart`, `auth_controller.dart`, `first_run_sheet.dart` | `01-donor-auth.md` | **Done** |
| **D2** | Donor Shell & Nav | `donor_shell.dart`, `notifications_screen.dart` | `02-donor-shell-nav.md` | **Done** |
| **D3** | Donor Home | `customer_home_screen.dart`, `top_bar.dart`, `mode_selection_cards.dart`, `live_purity_card.dart`, `featured_products.dart` | `03-donor-home.md` | **Done** |
| **D4** | Donor Booking | `booking_sheet.dart`, `stepper.dart`, `product_detail_sheet.dart`, `quote_confirm.dart`, `booking_controller.dart`, `product_catalog.dart` | `04-donor-booking.md` | **Done** |
| **D5** | Donor Orders | `my_orders_screen.dart`, `order_card.dart`, `orders_controller.dart` | `05-donor-orders.md` | **Done** |
| **D6** | Donor Tracking | `tracking_screen.dart` (polling, OTP, live state, cancel/reschedule) | `06-donor-tracking.md` | **Done** |
| **D7** | Donor Bill & Rating | `bill_screen.dart`, `rating_sheet.dart` | `07-donor-bill-rating.md` | **Done** |
| **D8** | Donor Subscriptions | `subscription_screen.dart`, `plan_builder_sheet.dart`, `subscription_controller.dart` | `08-donor-subscriptions.md` | **Done** |
| **D9** | Donor Wallet | `donor_wallet_screen.dart`, `payment_history_screen.dart`, `wallet_controller.dart` | `09-donor-wallet.md` | **Done** |
| **D10** | Donor Addresses | `address_screen.dart`, `map_picker.dart`, `selected_address_store.dart` | `10-donor-addresses.md` | **Done** |
| **D11** | Donor Profile | `donor_profile_screen.dart`, `edit_profile_sheet.dart`, `profile_controller.dart` | `11-donor-profile.md` | **Done** |
| **D12** | Donor Support & Returns | `support_screen.dart`, `support_controller.dart`, `return_sheet.dart`, `returns_controller.dart` | `12-donor-support-returns.md` | **Done** |
| **V1** | Vendor Auth & Shell | `vendor_code_screen.dart`, `auth_gate.dart`, `vendor_strings.dart`, `vendor_shell.dart`, `profile_screen.dart` | `13-vendor-auth-shell-profile.md` | **Done** |
| **V2** | Vendor Route & Stops | `route_screen.dart`, `route_controller.dart`, `stop_detail_screen.dart`, `pod_sheet.dart`, `triple_sheet.dart`, `stops_controller.dart` | `14-vendor-route-stops.md` | **Done** |
| **V3** | Vendor Duty & Sync | `duty_screen.dart`, `duty_controller.dart`, `sync_screen.dart`, `sync_controller.dart`, `core/cascade.dart` | `15-vendor-duty-sync.md` | **Done** |
| **V4** | Vendor Business Surfaces | `customers/*`, `inventory/inventory_screen.dart`, `earnings/*`, `support/*` | `16-vendor-customers-inventory-earnings-support.md` | **Done** |
| **X1** | Cross-Cutting Tokens | `theme.dart` (both apps), `app_constants.dart`, `shared/ui/*`, `AppMotion` | `17-system-tokens-shared-ui.md` | **Done** |
| **X2** | Cross-Cutting Code Hygiene | Dead code, unused parameters, copy-paste across apps | `18-duplication-dead-code.md` | **Done** |
| **X3** | Cross-Cutting Flows | Cross-screen state machines, navigation stacks, mermaid flow maps | `19-flows-state-machines-nav.md` | **Done** |
| **X4** | Cross-Cutting Copy & A11y | Copywriting, localization, screen readers, WCAG, motion, polling | `20-copy-a11y-motion.md` | **Done** |

---

## 2. Recurring Systemic Themes

Across all 20 audits, several patterns repeated in 3 or more independent screens. In accordance with audit standards, these are classified as **systemic architectural defects**, not isolated component slips.

### Theme 1: The `ElevatedButton` Money-Green Trap (`theme.dart:311`)
- **Found in:** D1 (`login_screen.dart`), D7 (`bill_screen.dart`), D9 (`donor_wallet_screen.dart`), D10 (`address_screen.dart`), D11 (`donor_profile_screen.dart`), X1 (`theme.dart`).
- **Defect:** In `apps/user_app_donor/lib/core/theme.dart:311`, the global `elevatedButtonTheme` specifies `backgroundColor: ShodashaTheme.greenDark` (`#15803D`). As a result, every unstyled `ElevatedButton` in the donor application defaults to transaction money-green. Non-monetary buttons like "Login", "Add New Address", "Save Changes", and "View Detailed Bill" glow in the exact color reserved strictly for "Pay Now", "Book Can", or "Confirm Order".
- **Verdict:** System token defect. The global theme must set neutral/brand primary for general elevated buttons, reserving `ShodashaTheme.greenDark` for an explicit `AppButton.money()` variant.

### Theme 2: Client-Side Fabricated Money Math
- **Found in:** V4 (`earnings_screen.dart:117`), V2 (`stop_detail_screen.dart:415`), X1 (`vendor_app/core/money.dart:16-23`), X4 (`20-copy-a11y-motion.md`).
- **Defect:** `vendor_app/lib/features/earnings/earnings_screen.dart:117` contains a fallback calculation multiplying `stopsDone * 2000` paise (₹20/stop) when `earnedPayout <= 0`. Similarly, `vendor_app/core/money.dart:16-23` hardcodes `* 150` jar deposit and `* 3` cap fee multipliers on the client.
- **Verdict:** Violation of the system non-negotiable money invariant. All money amounts, earnings, deposits, and settlement summaries must be strictly server-authoritative. If uncalculated, the UI must show a pending settlement state (`"Awaiting day-end settlement"`), never invent currency figures on the client.

### Theme 3: Nested Multi-Sheet Labyrinths
- **Found in:** D3/D4 (`customer_home_screen.dart` -> `product_detail_sheet.dart` -> `booking_sheet.dart` -> `quote_confirm.dart`), V2 (`stop_detail_screen.dart` -> `triple_sheet.dart` / `pod_sheet.dart`), X3 (`19-flows-state-machines-nav.md`).
- **Defect:** Booking a single 20L water can requires stacking up to 3 modal bottom sheets sequentially. If a user dismisses one, the entire state chain breaks or confuses the back stack. In the vendor app, completing a single doorstep delivery is split into two disjoint sheets ("Triple" for jar handoff and "PoD" for OTP/proof), prompting for cash and empty jars redundantly across both modals.
- **Verdict:** Flow defect. Consolidate into single-modal multi-step flows or inline screens.

### Theme 4: The "Slash-Separated" Bilingual Crutch
- **Found in:** V1 (`vendor_strings.dart`, `vendor_shell.dart`), V2 (`stop_detail_screen.dart`), V3 (`duty_screen.dart`, `sync_screen.dart`), V4 (`inventory_screen.dart`, `customers_screen.dart`), X4 (`20-copy-a11y-motion.md`).
- **Defect:** The vendor app attempts localization by printing both English and Hindi on a single line separated by slashes: `"Duty / ड्यूटी"`, `"Triple / तीन काम एक साथ"`, `"Door Locked / Ghar band hai"`, `"Stock / स्टॉक"`. This clutters the UI, doubles cognitive load, wraps button text on 360dp devices, and creates a messy visual aesthetic.
- **Verdict:** Localization defect. The vendor app must offer a dedicated language toggle (Hindi vs English), presenting clean, unslashed text in the active locale.

### Theme 5: Vendor Design Token & Shared Component Vacuum
- **Found in:** V1, V2, V3, V4, X1 (`17-system-tokens-shared-ui.md`).
- **Defect:** While `user_app_donor` possesses `AppSpacing`, standard radius constants, and 12 reusable `shared/ui` widgets, `vendor_app` has none of them. The vendor app contains raw magic numbers on every screen (`EdgeInsets.all(12)`, `EdgeInsets.all(13)`, `SizedBox(height: 18)`), inconsistent card elevations, and duplicated micro-widgets.
- **Verdict:** Design system architecture defect. Export core layout tokens (`AppSpacing`, `AppRadius`, `AppShadows`) and shared UI primitives into a shared package or direct vendor mirror.

### Theme 6: Internal System Leaks in Retail Copy
- **Found in:** D3 (`featured_products.dart:36`), D11 (`donor_profile_screen.dart:401`), D2 (`notifications_screen.dart:288`), D7 (`bill_screen.dart`), X4 (`20-copy-a11y-motion.md`).
- **Defect:** Technical debugging and database internals leak into production user copy: `"Server prices"` chips in product catalog, `"The app does not display live plant telemetry because the API does not expose it"` in purity sheets, and raw 36-character database UUIDs (`Order 8f3b14a2-7c91-4d02-a123-9f8e7d6c5b4a`) in notification headlines and bills.
- **Verdict:** Copywriting & UX defect. Sanitize all user-facing text to speak human retail language.

### Theme 7: Utility Duplication & Redundant Formatting
- **Found in:** D5, D6, D7, D8, D9, D12, X2 (`18-duplication-dead-code.md`).
- **Defect:** The exact same 12-month string array `const months = ['Jan', 'Feb', 'Mar', ...]` is independently declared inside 6 separate donor screen files. The 154-line product search modal in `donor_shell.dart:462-616` implements full catalog filtering for a static 2-SKU inventory.
- **Verdict:** Code duplication defect. Consolidate date formatting into `AppDateUtils` and retire the redundant search modal.

---

## 3. Top 10 Flow Defects (Ranked with Evidence)

| Rank | Defect Description | Severity | Affected Screens & Exact Location | Evidence & Impact |
|---|---|---|---|---|
| **1** | **Fragmented Vendor Handover (Dual Sheet Confusion)** | **P0** | `stop_detail_screen.dart:214-230`, `triple_sheet.dart`, `pod_sheet.dart` | Delivery completion is fractured into two separate modal sheets. Drivers must open `TripleSheet` to record empties/cash, then close it and open `PoDSheet` to enter the OTP. Empty jar counts and cash payments are prompted in both places, causing delivery record desynchronization. |
| **2** | **Fabricated Client-Side Earnings Fallback** | **P0** | `vendor_app/lib/features/earnings/earnings_screen.dart:117` | `_fallbackCalculation()` multiplies `stopsDone * 2000` paise (₹20/stop) when backend payout is 0 or uncalculated. Violates the non-negotiable invariant that all money is server-authoritative; leads to driver pay disputes. |
| **3** | **Triple-Nested Modal Booking Chain** | **P1** | `customer_home_screen.dart:182`, `product_detail_sheet.dart:104`, `booking_sheet.dart:290`, `quote_confirm.dart:88` | Ordering a 20L can requires traversing 3 nested sheets (`ProductDetail` -> `BookingSheet` -> `QuoteConfirm`). Tapping outside or swiping down discards state midway without a draft save; lack of a 1-tap reorder card on home adds 4 unnecessary taps. |
| **4** | **Bottom Tab 4 Triggers Side Navigation Drawer** | **P1** | `vendor_app/lib/features/shell/vendor_shell.dart:277-279` | Tapping the 4th tab item ("More") executes `_scaffoldKey.currentState?.openDrawer()`, causing an off-screen side drawer to slide out over the UI instead of rendering a destination screen in the shell body. |
| **5** | **Tracking Back Navigation Re-Opens Stale/Cancelled Order** | **P1** | `tracking_screen.dart:420-435`, `my_orders_screen.dart:188` | Cancelling an order from `TrackingScreen` pops back to `MyOrdersScreen`, but leaves the detail route on the navigator stack. Pressing back from orders reopens the cancelled tracking view, which then attempts to resume polling for a dead order. |
| **6** | **Nagpur Default Coordinates for Bhopal Water Service** | **P1** | `apps/user_app_donor/lib/features/addresses/map_picker.dart:19` | When geolocation permission is denied, the map picker centers on Nagpur (`21.1458, 79.0882`) instead of central Bhopal (`23.2599, 77.4126`), causing address pin drops 350 km away in Maharashtra. |
| **7** | **Off-Duty Full-Screen Blocking Lockout** | **P1** | `vendor_app/lib/features/shell/vendor_shell.dart:140-165`, `duty_screen.dart` | Going off-duty places a full-screen blocking overlay across the entire vendor shell, preventing drivers from viewing their past delivery earnings, checking stock, or contacting driver support while off the clock. |
| **8** | **Zero-Balance Stale Flash on Failed Wallet Load** | **P1** | `donor_wallet_screen.dart:94-112`, `wallet_controller.dart` | Wallet screen initializes balance to `₹0` during initial fetch. If the network times out or fails, the screen remains at ₹0 without an error banner, alarming customers into believing their prepaid balance was wiped. |
| **9** | **Plan Builder Allows Zero-Schedule Submission** | **P1** | `plan_builder_sheet.dart:284-310`, `subscription_controller.dart` | Deselecting all delivery days in the recurring schedule allows the user to click "Proceed to Payment", creating a subscription that requests money but schedules 0 weekly deliveries. |
| **10** | **Fragile String-Scraping for Operational Offline Status** | **P2** | `sync_screen.dart:84`, `customer_home_screen.dart:114` | Screens inspect human error message strings (`c.result!.contains('Network')`, `e.message.toLowerCase().contains('internet')`) to toggle offline banners instead of checking structured HTTP status codes or socket exception types. |

---

## 4. Top 10 Craft Defects (Ranked with Evidence)

| Rank | Defect Description | Severity | Affected Screens & Exact Location | Evidence & Impact |
|---|---|---|---|---|
| **1** | **Global ElevatedButton Theme Inherits Money-Green** | **P1** | `apps/user_app_donor/lib/core/theme.dart:311` | `elevatedButtonTheme` defines `backgroundColor: ShodashaTheme.greenDark`. All standard buttons across the entire app (Login, Add Address, Save Profile, View Bill) glow in green, diluting transaction intent. |
| **2** | **Slash-Separated Bilingual Typography Clutter** | **P2** | `vendor_app/lib/features/auth/vendor_strings.dart:12-48`, `vendor_shell.dart` | Every label displays dual languages concatenated with slashes: `"Customers / ग्राहक"`, `"Duty / ड्यूटी"`, `"Triple / तीन काम एक साथ"`. Double text length triggers text clipping and visual noise. |
| **3** | **Internal Engineering Leaks in User-Facing Copy** | **P2** | `featured_products.dart:36`, `donor_profile_screen.dart:401`, `notifications_screen.dart:288` | Exposes internal system details: `"Server prices"` catalog tag, `"The app does not display live plant telemetry because the API does not expose it"` disclaimer, and raw 36-char UUIDs in notification headers. |
| **4** | **154-Line Search Engine Overlay for a 2-SKU Catalog** | **P2** | `donor_shell.dart:462-616` | A 154-line modal search engine with dynamic filtering and regex matching exists solely to search between exactly two products: "20L Normal Water" and "20L Chilled Water". |
| **5** | **Missing Type & Spacing Scale in Vendor App** | **P2** | `vendor_app` (All 11 feature directories) | Vendor app has no `AppSpacing` or typography tokens. Every widget specifies arbitrary inline paddings (`10`, `13`, `15`, `18`, `22`), leading to visual jitter and inconsistent layout rhythms. |
| **6** | **6× Redundant Month Name String Array Declarations** | **P2** | `my_orders_screen.dart:340`, `order_card.dart:182`, `tracking_screen.dart:884`, `bill_screen.dart:140`, `subscription_screen.dart:210`, `payment_history_screen.dart:120` | `const months = ['Jan', 'Feb', 'Mar', ...]` is declared locally in 6 separate files instead of using a unified `AppDateUtils` helper. |
| **7** | **Misnamed String Dictionaries (English in `Hi` Maps)** | **P2** | `apps/user_app_donor/lib/features/auth/auth_controller.dart:18`, `orders_controller.dart:38` | `authStringsHi` and `ordersStringsHi` are labeled with the Hindi language suffix (`Hi`), but contain 100% English strings. |
| **8** | **Inconsistent Metric Pill Styling Across Screens** | **P2** | `order_card.dart:95`, `tracking_screen.dart:210`, `stop_detail_screen.dart:140` | Status pills vary in border radius (4dp vs 8dp vs 16dp) and font weight across different screens for the identical `dispatched` or `delivered` status. |
| **9** | **Missing Screen Reader Semantics on Key Visual Indicators** | **P2** | `donor_profile_screen.dart:88`, `live_purity_card.dart:142`, `customer_home_screen.dart:74` | Profile monogram avatar has no semantic label (`Semantics(label: 'User Avatar')`); TDS purity indicators read as isolated numeric values without "parts per million" context. |
| **10** | **Tight Touch Target Clusters on 360dp Devices** | **P3** | `plan_builder_sheet.dart:185`, `triple_sheet.dart:210` | Counter stepper buttons (`-` and `+`) and day chips cluster with less than 8dp gap on small screens, causing fat-finger misclicks. |

---

## 5. Contradictions & Audit Nuances

During the cross-screen audits, several design tensions and conflicting agent observations were analyzed and reconciled:

1. **Vendor App Language Architecture (Bilingual vs Pure Single Locale):**
   - *Conflict:* V1 noted the vendor app is intentionally bilingual for driver accessibility; X4 identified slash-separated strings (`"Duty / ड्यूटी"`) as visual clutter.
   - *Code Resolution:* The code proves that slash concatenation hurts readability and breaks layout constraints on small screens (`vendor_strings.dart:12`). The solution is not to eliminate Hindi, but to implement a **true single-locale toggle** (Hindi or English) where the entire interface cleanly reflects the chosen language.
2. **Offline Outbox vs Real-Time State Invalidation:**
   - *Conflict:* V2 and V3 praise the offline outbox for route operations; D6 warns that caching order states can show outdated delivery steps.
   - *Code Resolution:* Vendor route mutations are offline-first via SQLite/SharedPreferences outbox (`SyncController`), which is correct for delivery drivers in basements. Donor app orders are real-time retail actions requiring live server state (`OrdersController`). Both patterns are valid within their respective domains.
3. **Duty Gate Scope (Hard Blocker vs Soft Navigation Guard):**
   - *Conflict:* V1 treated off-duty as an intentional lock; V4 noted drivers cannot see earnings or contact support when off duty.
   - *Code Resolution:* `vendor_shell.dart:140` blocks the entire screen. Off-duty should prevent accepting active delivery stops, but should **never** lock drivers out of viewing their earned money or profile settings.

---

## 6. What Genuinely Works (Non-Negotiable System Invariants)

The audit revealed exceptional architectural foundations that must be strictly preserved during visual and flow refinement:

1. **The Offline Vendor Outbox (`SyncController`):**
   - Rock-solid queued delivery mutations with idempotency keys that survive network loss in low-connectivity areas.
2. **Zero Client-Side Money Settlement:**
   - Server-authoritative quote, dues, and payment state machines. The server is the sole financial authority.
3. **Delivery OTP Verification Security:**
   - OTP is strictly server-minted, revealed only when an order is `dispatched`, and verified securely at the doorstep.
4. **Hardware-Accelerated Reduced-Motion Guard (`AppMotion` & `cascade.dart`):**
   - Respects OS-level accessibility settings with zero-duration fallbacks and transform-only animations.
5. **Single-Flight API Request Deduplication:**
   - Controllers reliably prevent double-submits, duplicate payment intents, and redundant network requests.
6. **40 MB Binary Gate:**
   - Strict size budgeting that keeps the production Android donor APK under 40 MB without bloated dependencies.
