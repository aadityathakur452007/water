# 23 — Key Owner Strategic Decisions

**Branch:** `037-uiux-unslop-audit`  
**Date:** 2026-10-31  
**Scope:** Exactly 7 High-Impact Architectural & Design Decisions Requiring Owner Sign-off Before Implementation

---

### Decision 1: Vendor App Language & Localization Architecture

- **Context:** The vendor app currently displays bilingual text concatenated with slashes on nearly every button and title (`"Duty / ड्यूटी"`, `"Triple / तीन काम एक साथ"`, `"Door Locked / Ghar band hai"`). This clutters the UI, breaks layout constraints on 360dp screens, and creates visual friction for drivers.
- **Option A (Recommended): Clean Single-Locale Toggle (Hindi default, English optional).**
  - Drivers select their preferred language once (defaulting to Hindi). All screens display 100% clean, unslashed text in that single language.
  - *Consequence:* Eliminates line wrapping, halves reading time, makes buttons legible, professional UI. Requires a simple language toggle in Profile.
- **Option B: Retain Slashed Bilingual Strings.**
  - Keep current slash-separated strings across all screens.
  - *Consequence:* Continues to cause text clipping and visual clutter on small devices.

---

### Decision 2: Vendor Shell Navigation Architecture (Bottom Tab 4 vs Drawer)

- **Context:** In `vendor_shell.dart:277-279`, tapping the 4th bottom navigation tab item ("More") does not navigate to a screen; it programmatically slides out an Android side navigation drawer over the view.
- **Option A (Recommended): Replace Side Drawer with a Dedicated "More / Tools" Hub Screen.**
  - Tapping Tab 4 switches the body of `VendorShell` to a clean grid screen displaying Stock Log, Driver Support, WhatsApp SOS, and Profile.
  - *Consequence:* Standard mobile navigation ergonomics. Eliminates confusing dual-paradigm gesture conflicts (swipe vs tap).
- **Option B: Expand Bottom Navigation to 5 Tabs.**
  - Show Route, Customers, Sync, Earnings, Profile directly in the bottom bar.
  - *Consequence:* Tight bottom bar padding on 360dp devices; leaves auxiliary tools (Stock Log, Support) needing a home.

---

### Decision 3: Vendor Duty Gate Scope & Enforcement

- **Context:** `vendor_shell.dart:140-165` currently overlays a blocking full-screen guard whenever the driver is off-duty. Drivers cannot view past delivery earnings, check stock, or contact support while off the clock.
- **Option A (Recommended): Soft Sticky Duty Banner with Route Lock.**
  - Off-duty state displays a clear, high-contrast banner at the top of the app (`"You are currently Off Duty — Turn On Duty to receive delivery stops"`). Route tabs and stop acceptance buttons are disabled, but Earnings, Profile, and Support remain fully accessible.
  - *Consequence:* Respects driver utility and autonomy. Drivers can review their daily pay and account details from home without toggling active duty.
- **Option B: Retain Full-Screen Blocking Lockout.**
  - Force drivers to turn On Duty before any feature or screen can be opened.
  - *Consequence:* Drivers turn on duty prematurely just to check their earnings, polluting backend dispatch availability metrics.

---

### Decision 4: Vendor Doorstep Handover Consolidation (Triple + PoD)

- **Context:** When completing a delivery at a customer doorstep (`stop_detail_screen.dart`), the driver must currently navigate two disjoint bottom sheets: `TripleSheet` (to record empty cans and collect cash) and `PoDSheet` (to enter the customer's delivery OTP).
- **Option A (Recommended): Unified 2-Step Handover Sheet.**
  - Consolidate into a single sequential bottom sheet: **Step 1:** Bottle Exchange & Cash Collection (auto-checks order amount); **Step 2:** Customer OTP Verification & Final Submit.
  - *Consequence:* Halves driver doorstep completion time (under 15 seconds), eliminates desynchronization between collected jars and delivery confirmation.
- **Option B: Keep Separate Triple & PoD Sheets.**
  - Maintain two independent buttons and sheets on `StopDetailScreen`.
  - *Consequence:* Persistent risk of drivers collecting empties without entering the OTP or vice versa.

---

### Decision 5: Repeat Order Machine & Booking Sheet Consolidation

- **Context:** Ordering a 20L water can currently requires navigating 3 sequential modal sheets (`customer_home_screen.dart` -> `product_detail_sheet.dart` -> `booking_sheet.dart` -> `quote_confirm.dart`). There is no 1-tap reorder card on the home screen despite water delivery being a high-frequency habit.
- **Option A (Recommended): 1-Tap Quick Reorder Card + Single-Sheet Booking Flow.**
  - Home screen features a prominent "Quick Reorder Last Order" card (1-tap to quote & confirm). If ordering fresh, tapping a product opens a single, clean checkout sheet containing quantity, delivery slot, and payment choice.
  - *Consequence:* Reduces repeat order friction from 5 taps across 3 sheets down to 1 tap. Significantly boosts customer reorder velocity.
- **Option B: Preserve Multi-Sheet Drill-Down.**
  - Keep Product Detail Sheet separate from Quantity Stepper and Confirmation Sheet.
  - *Consequence:* High checkout abandonment and state loss when users accidentally dismiss sheets.

---

### Decision 6: Client-Side Fallback Earnings Math Elimination

- **Context:** `vendor_app/lib/features/earnings/earnings_screen.dart:117` multiplies `stopsDone * 2000` paise (₹20/stop) on the client when `earnedPayout <= 0`.
- **Option A (Recommended): Strict Server-Authoritative Payout Display.**
  - Delete `_fallbackCalculation()` entirely. If the backend has not settled the day's earnings, display `"Settlement pending at end of day"` with completed stop counts, rather than a fabricated rupee total.
  - *Consequence:* Upholds system-wide money integrity and prevents driver disputes when actual tiered or zoned payout rates differ from the ₹20 flat estimate.
- **Option B: Keep Client-Side Estimated Calculation.**
  - Retain the `stopsDone * 2000` fallback calculation.
  - *Consequence:* Violates core financial invariants and sets false expectations for driver compensation.

---

### Decision 7: Unified Design Tokens & Shared UI Export to Vendor App

- **Context:** The donor app uses a clean design system (`AppSpacing`, standard radius, `shared/ui`), while the vendor app has zero shared tokens and relies on arbitrary magic numbers (`EdgeInsets.all(12)`, `EdgeInsets.all(13)`).
- **Option A (Recommended): Export Core Layout Tokens & Primitives to Vendor App.**
  - Provide `AppSpacing`, standard radius, and shared buttons to the vendor app, ensuring both apps share identical ergonomic foundations while maintaining their distinct color personalities (Water Blue for Donor, Logistics Slate for Vendor).
  - *Consequence:* Consistent code quality, faster feature development, and uniform typography across the entire fleet.
- **Option B: Keep Vendor App Styling Ad-Hoc & Isolated.**
  - Continue maintaining independent, hardcoded styling in `vendor_app`.
  - *Consequence:* Higher maintenance burden, recurring layout bugs, and visual inconsistency.
