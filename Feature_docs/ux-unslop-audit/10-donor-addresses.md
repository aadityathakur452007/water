# D10 — Donor Addresses & Map Picker Audit

**Files Audited:**
- `apps/user_app_donor/lib/features/addresses/address_screen.dart` (1,520 lines)
- `apps/user_app_donor/lib/features/addresses/map_picker.dart` (433 lines)
- `apps/user_app_donor/lib/features/addresses/selected_address_store.dart` (39 lines)

---

## 1. Executive Summary
The Addresses domain governs physical doorstep delivery location management, 6-digit postal code serviceability checks, geographic coordinates mapping, and cross-screen address selection persistence (`SelectedAddressStore`). Domain rigor is evident: live auth gating to prevent 401s after filling forms, explicit 409 error propagation when active orders or subscriptions lock an address, and zero-key OpenStreetMap integration. However, the screen suffers from notable visual slop, geographical misconfiguration, and UI token fragmentation:
1. **Nagpur fallback coordinates in a Bhopal product:** `map_picker.dart:19` sets `kDefaultCenter = LatLng(21.1458, 79.0882)` (Nagpur, Maharashtra) as the camera fallback. For a hyper-local water delivery service operating exclusively in Bhopal, Madhya Pradesh (`23.2599, 77.4126`), users who deny location permission or experience GPS timeouts are dropped 350 km away in another state.
2. **Raw decimal coordinates as primary user feedback:** Upon placing a pin, `map_picker.dart:261-262` renders `Lat 23.25123, Lng 77.41234`. Raw floating-point coordinates have zero semantic meaning to a customer trying to confirm if the pin landed on their home in Arera Colony or Kolar Road.
3. **Inline list-tail button anti-pattern:** `address_screen.dart:607-615` appends the primary "Add address" action button as the final scrolling child of the `ListView` rather than pinning it in an ergonomic bottom app bar or clean FAB.
4. **Design token bypass and ad-hoc shadows:** Multiple buttons bypass `AppButton` in favor of manual `ElevatedButton.styleFrom(backgroundColor: ShodashaTheme.teal)` (lines 560, 608), while `map_picker.dart` injects ad-hoc `BoxShadow` definitions (lines 323, 375) not present in `ShodashaTheme`.

---

## 2. Screen Identity & Canonical Route
- **Address Screen:** Pushed route (`MaterialPageRoute`) from Shell profile tab, checkout sheet, or subscription builder. Canonical title: "Saved addresses".
- **Address Form Sheet:** Modal bottom sheet (`_AddressFormSheet`) with 12 distinct form fields (name, type, phone, pincode, full address, house, street, area, landmark, lift flag, map pin).
- **Map Picker:** Full-screen pushed route (`pickMapPin`) powered by OpenStreetMap (`flutter_map`).
- **Target Persona:** Bhopal resident or office administrator configuring exact water drop locations (including gate codes, floor number, and lift availability for heavy 20kg cans).

---

## 3. Visual & Spatial Hierarchy
### Address Screen
- **Header:** Simple AppBar with title "Saved addresses". Sub-header displays uppercase tracker: `SAVED DELIVERY ADDRESSES` with count badge (`N saved`).
- **Address Cards:** Vertical list of saved addresses. Selected address is highlighted with `teal.withValues(alpha: 0.08)` ground, `1.5px` teal border, and checkmark icon.
- **Empty State:** Centered location icon, 17px bold title, 14px muted explanation, and teal "Add address" button.
- **Defect:** Action placement is fragmented. The "Add address" button is embedded at the very end of the list item builder (`i == c.items.length + 1`), meaning users with 4+ addresses must scroll past all cards to add a new location.

### Map Picker
- **Primary Hero:** Interactive `FlutterMap` canvas with OpenStreetMap tiles.
- **Overlays:**
  - Floating top pill: Displays pin status or raw Lat/Lng coordinates (`map_picker.dart:247-272`).
  - Right-side FAB stack: Zoom in (`+`), Zoom out (`-`), and GPS locate (`my_location`).
  - Sticky bottom container: Full-width `AppButton` ("Use this location" or "Tap the map to select a pin").

---

## 4. Color & Contrast Audit

| Element | File:Line | Color Token / Value | Contrast Ratio (vs BG) | Compliance / Finding |
|---|---|---|---|---|
| Screen Background | `address_screen.dart:494` | `ShodashaTheme.bg` (`#F7F9FA`) | Baseline | Standard light slate ground |
| Card Background (Normal) | `address_screen.dart:628` | `ShodashaTheme.surface` (`#FFFFFF`) | Baseline | High contrast with ground |
| Card Background (Selected) | `address_screen.dart:627` | `teal.withValues(alpha: 0.08)` | 1.1:1 vs surface | Subtle tint indicating active state |
| Card Border (Selected) | `address_screen.dart:631` | `ShodashaTheme.teal` (`#00A896`) | 3.1:1 vs ground | Crisp 1.5px visual perimeter |
| Default Tag Background | `address_screen.dart:684` | `ShodashaTheme.tealTint` (`#E6F7F5`) | Tinted container | Neat pill decoration |
| Default Tag Text | `address_screen.dart:693` | `ShodashaTheme.teal` (`#00A896`) | 4.8:1 vs `tealTint` | WCAG AA compliant |
| Map Top Pill Surface | `map_picker.dart:248` | `ShodashaTheme.surface` | Baseline | Floating white banner |
| Map Top Pill Icon | `map_picker.dart:255` | `ShodashaTheme.blue` (`#1A56DB`) | 5.8:1 vs surface | High visibility pin icon |
| Floating Action Buttons | `map_picker.dart:282` | `surface` with `ink` icon | 14.1:1 | Sharp, clean contrast |

---

## 5. Typography & Text Scale

| Text Element | File:Line | Font Size | Weight | Finding |
|---|---|---|---|---|
| Saved Addresses Header | `address_screen.dart:588` | 11px | w800 | Uppercase tracker (`letterSpacing: 0.8`) |
| Saved Addresses Count | `address_screen.dart:597` | 12px | w800 | Clear badge counter |
| Address Label Header | `address_screen.dart:657-662` | Unspecified (14px) | w700 / w800 | Font size unconstrained; inherits theme |
| Default Badge Label | `address_screen.dart:692` | 12px | Default | Clean tag size |
| Map Pin Status Text | `map_picker.dart:264` | 13px | w600 | Legible body size |
| Map Bottom Button Text | `map_picker.dart:420` | Unspecified (14px) | w700 | Standard `AppButton` typography |

---

## 6. Spacing, Grid & Alignment
- **List View Padding:** `address_screen.dart:575` sets `EdgeInsets.fromLTRB(16, 8, 16, 96)`, leaving 96dp bottom padding for potential floating buttons.
- **Card Separation:** `ListView.separated` uses `SizedBox(height: 10)` (line 577). Off-scale 10dp deviates from `AppSpacing.sm` (8dp) or `AppSpacing.md` (12dp).
- **Map Floating Button Offset:** Zoom buttons positioned at `right: 16, bottom: 96` (`map_picker.dart:274-275`), clearing the bottom action bar cleanly.

---

## 7. Micro-Interactions, Feedback & States
- **Selection Interaction:** Tapping any address card triggers `c.select(a.id)` (`address_screen.dart:621`), which updates in-memory controller state and writes immediately through to `SelectedAddressStore` via SharedPreferences.
- **Serviceability Check Feedback:** As pincode is entered, `checkServiceable` runs asynchronously against `GET /windows?pincode`. Displays amber informational banner if pincode is unserviceable or unverified (`address_screen.dart:73-78`).
- **Deletion Guard (409 Handling):**
  - Prompted by native confirmation dialog.
  - If server returns 409 (`deleteBlockedBody`), presents clear error: "This address has active orders or subscriptions. Complete or cancel them first".
- **Map Tile Failure Handling:** If OSM tile fetching fails, displays a dismissible warning overlay with a "Retry" button (`map_picker.dart:311-362`).

---

## 8. Motion & Transitions
- **Map Movement:** Camera pans and zooms via `MapController.move(ll, zoom)`.
- **Form Opening:** Smooth bottom sheet modal transition (`isScrollControlled: true`).
- **Card Selection:** Instant border and background color flip without ripple or border animation.

---

## 9. Cognitive Load & Information Scent
- **Geographic Disconnect in Map Default:** If a user in Bhopal has location services turned off, the map opens centered on Nagpur, Maharashtra (`21.1458, 79.0882`), forcing them to zoom out and drag across two state borders to find Bhopal.
- **Cryptic Coordinates Feedback:** Reading `Lat 23.25123, Lng 77.41234` offers zero reassurance to a resident. Showing a reverse-geocoded string (e.g., "Near Shahpura Lake, Bhopal") or landmark indicator is essential.
- **Overcrowded Address Form:** The form has 12 distinct text inputs. For an on-demand water delivery app, separating this into two logical steps (1. Map Pin + Pincode Serviceability; 2. Door/Floor Details & Lift Flag) significantly reduces cognitive fatigue.

---

## 10. Touch Targets & Ergonomics
- **Card Selection Area:** The entire address card is wrapped in an `InkWell`, giving a generous 100dp+ touch target.
- **Map Zoom Controls:** Uses `FloatingActionButton.small` (40x40dp) with an 8dp vertical gap.
- **Map Confirm Button:** Full-width `AppButton` in `SafeArea` at screen bottom, perfectly positioned within the primary thumb reach zone.

---

## 11. Edge Cases & Resiliency
- **Guest / Signed-Out Handling:** `openAddressesGated` ensures unauthenticated users complete login before accessing address creation, eliminating mid-form 401 session expirations.
- **User Account Boundary:** `AddressController.reset()` increments `_generation`, cleanly aborting in-flight network requests from previous users upon logout (`address_screen.dart:286-295`).
- **GPS Disabled / Denied:** Handles both location service disabled and permission denied gracefully with clear instructions to drag the map manually or open settings (`map_picker.dart:88-109`).
- **Offline Resilience:** Shows explicit offline banner and cached addresses if network drops.

---

## 12. Code-Level Craft & Tech Debt

| File & Line | Issue | Severity | Proposed Fix |
|---|---|---|---|
| `map_picker.dart:19` | Nagpur coordinates (`21.1458, 79.0882`) used as default fallback | High | Change default fallback to Bhopal (`23.2599, 77.4126`) |
| `map_picker.dart:261-262` | Raw Lat/Lng strings shown to customer | Medium | Display human locality name or instruction |
| `address_screen.dart:607-615` | "Add address" button placed at end of scrollable list | Medium | Pin "Add new address" button to bottom bar or use FAB |
| `address_screen.dart:560, 608` | Direct `ElevatedButton.styleFrom` bypass instead of `AppButton` | Medium | Standardize with `AppButton` |
| `map_picker.dart:323, 375` | Inline ad-hoc `BoxShadow` definitions | Low | Replace with standard theme elevation token |
| `address_screen.dart:577` | Off-scale `10dp` list spacing | Low | Use `AppSpacing.sm` (8dp) or `AppSpacing.md` (12dp) |

---

## 13. Accessibility (a11y)
- **Map Pin Placement:** Tapping anywhere on the map drops the pin. Keyboard or switch navigation is challenging on canvas; map picker requires alternative text input flow for full accessibility compliance.
- **Semantic Address Type Icons:** Card displays `Icons.home_rounded` vs `Icons.apartment_rounded`, giving visual distinction between residential and corporate addresses.
- **Form Error Feedback:** Form validation displays immediate red helper text on invalid pincodes or blank address lines.

---

## 14. Cross-Platform Consistency
- **Geolocator Permissions:** Handled via standard `geolocator` package, correctly invoking Android and iOS location permission dialogs.
- **OpenStreetMap Tiles:** Renders reliably across all platforms without requiring Google Play Services or Apple MapKit API tokens.

---

## 15. Proposed Layout & Unslop Direction
### Address Screen: "The Frictionless Delivery Directory"
- **Pinned Bottom CTA:** Remove the trailing scrollable button. Pin a full-width `AppButton(label: 'Add new address', icon: Icons.add)` to the bottom `SafeArea`.
- **Card Information Layout:**
  - Distinct badge for "Delivery Address" (selected) and "Default".
  - Clean two-line format: House/Flat + Street in bold; Area + Pincode in muted secondary line.
  - Lift flag indicator: "🛗 Lift available" pill (vital for 20kg delivery riders).

### Map Picker: "Bhopal-Centered Pin Drop"
- **Accurate City Center Fallback:** Set `kDefaultCenter` to Bhopal (Bhadbhada / MP Nagar nexus: `23.2324, 77.4295`).
- **Human Locality Header:** Replace raw `Lat 23.xxx, Lng 77.xxx` with a descriptive locality chip or prompt: "Drag map to align pin over your gate".
- **Theme-Compliant Controls:** Replace raw `FloatingActionButton` with themed circular icon buttons.

---

## 16. Concrete Actionable Recommendations
1. **Fix Fallback Coordinates:** Update `kDefaultCenter` in `map_picker.dart:19` from Nagpur (`21.1458, 79.0882`) to central Bhopal (`23.2599, 77.4126`).
2. **Move "Add Address" to Sticky Footer:** Pin the "Add address" action button in a bottom navigation bar on `AddressScreen`, eliminating the need to scroll to the end of the list.
3. **Replace Raw Coordinates Display:** Replace decimal coordinates in the top map banner with a friendly confirmation prompt or reverse-geocoded area name.
4. **Standardize Action Buttons:** Replace all `ElevatedButton.styleFrom` instances with `AppButton`.
5. **Normalize Card Spacing:** Change list item separation from `10dp` to `AppSpacing.md` (12dp).

---

## 17. Acceptance Criteria
- [ ] Map picker defaults to Bhopal coordinates when GPS is disabled or unavailable.
- [ ] Map picker does not display raw decimal coordinates as primary user feedback.
- [ ] Address list provides a sticky, accessible "Add address" action button.
- [ ] All action buttons utilize `AppButton` without inline style overrides.
- [ ] Address CRUD and 409 conflict handling invariants remain 100% intact.

---

## 18. File Invariants & Verification Checklist
- [x] Invariant: Address CRUD adheres to contract §4.3 with zero data loss (`address_screen.dart:1-6`).
- [x] Invariant: 409 conflicts on active orders/subscriptions are explicitly reported to the user (`address_screen.dart:318-320`).
- [x] Invariant: Address selection writes through to `SelectedAddressStore` and persists across sessions (`selected_address_store.dart:26-37`).
- [x] Verified: Pincode and phone validation regex rules properly guard form submission.
