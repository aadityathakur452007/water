# V1 — Vendor Auth, Shell Navigation & Profile Audit

**Files Audited:**
- `apps/vendor_app/lib/features/auth/vendor_code_screen.dart` (249 lines)
- `apps/vendor_app/lib/features/auth/auth_gate.dart` (71 lines)
- `apps/vendor_app/lib/features/auth/vendor_strings.dart` (27 lines)
- `apps/vendor_app/lib/features/shell/vendor_shell.dart` (317 lines)
- `apps/vendor_app/lib/features/profile/profile_screen.dart` (471 lines)

---

## 1. Executive Summary
The Vendor application serves delivery partners in Bhopal who transport 20L water cans on commercial three-wheelers or pickup trucks. Architectural foundations reflect disciplined field engineering: offline-first outbox queues, duty-gated polling loops (`startDiscovery`/`stopDiscovery` stopped while off-duty or in background), and session restoration (`restoreSession`). However, the authentication, navigation shell, and profile subsystems suffer from profound navigation anti-patterns, copy fragmentation, and lack of visual system structure:
1. **The "Bottom Bar Opens Drawer" anti-pattern:** `vendor_shell.dart:277-279` configures the 4th bottom navigation tab ("More") to programmatically trigger a left-side `Drawer` (`_scaffoldKey.currentState?.openDrawer()`). Tapping a bottom navigation tab to slide out a side drawer violates both Android and iOS interaction guidelines and disorients field drivers.
2. **Duty gate hijacks the entire shell:** In `vendor_shell.dart:152-155`, when a driver is off-duty, the entire navigation shell is unmounted and replaced with `DutyScreen`. An off-duty driver cannot check their earnings, review tomorrow's inventory, or view their profile without turning duty ON.
3. **Hardcoded raw phone number bypassing constants:** `vendor_shell.dart:145` hardcodes `https://wa.me/919302190067`, despite `kSupportPhone` being imported and displayed at line 215 (`WhatsApp help ($kSupportPhone)`).
4. **Severe Hinglish copy fragmentation:** Unlike the donor app (pure English v1), the vendor app attempts a Hindi-first (Hinglish) approach. However, it fluctuates unpredictably between English ("Customers", "Stock", "Sync log"), Hinglish ("Aaj ke grahak, khoj ke saath", "Loading sheet: fulls/khaali", "Sab synced"), and broken developer Hindi ("Profile load nahi hua", "Nayi Chutti Request").
5. **Absence of tokens and design system scales:** Vendor app shares no type, spacing, or radius tokens with the donor app. Padding, font sizes, and borders are hand-coded inline everywhere (`EdgeInsets.all(24)`, `fontSize: 22`, `fontSize: 13`).

---

## 2. Screen Identity & Canonical Route
- **Vendor Code Screen:** Entry screen for unauthenticated drivers. Access-code only (admin-provisioned; no self-serve registration).
- **Vendor Shell:** Top-level shell with bottom navigation (Route, Earnings, Support, More) and left drawer.
- **Profile Screen:** Pushed route (`_push(ProfileScreen)`) from drawer. Covers vendor identity, vehicle details, working hours, leave requests, and logout.
- **Target Persona:** Bhopal delivery rider / truck driver operating in harsh sunlight, wearing delivery gloves, requiring massive 48dp+ tap targets and high-contrast text.

---

## 3. Visual & Spatial Hierarchy
### Vendor Code Screen
- **Primary Anchor:** Centered `Icons.local_drink` icon (64dp) and bold headline "Shodasha Vendor" (22px).
- **Form Inputs:** Mobile number (+91 prefix, 10 digits) and 32-character admin access code with visibility toggle.
- **Action CTA:** Full-width login button ("Login karein").
- **Auxiliary:** Secondary WhatsApp support link for drivers without an access code.

### Vendor Shell & Navigation
- **Top Bar:** Dependent on active tab (`RouteScreen`, `EarningsScreen`, `SupportScreen`).
- **30-Day Cap Banner:** Warning strip (`blueTint`) rendered at the top of the body when session cap expires within 24 hours.
- **Bottom Navigation Bar:** 4 tabs: Route, Earnings, Support, and "More" (which has a badge for pending offline sync items).
- **Drawer:** Contains Customers, Stock (Inventory), Sync log, Profile, WhatsApp help, Logout.

---

## 4. Color & Contrast Audit

| Element | File:Line | Color Token / Value | Contrast Ratio (vs BG) | Compliance / Finding |
|---|---|---|---|---|
| Screen Background | `vendor_code_screen.dart:77` | `Theme.scaffoldBackgroundColor` | Baseline | Standard surface |
| App Icon & Text | `vendor_code_screen.dart:85` | `ShodashaTheme.ink` (`#0F172A`) | 14.1:1 vs surface | Strong high contrast |
| Subtitle Copy | `vendor_code_screen.dart:96` | `ShodashaTheme.muted` (`#64748B`) | 4.6:1 vs surface | Pass WCAG AA |
| Session Cap Banner | `vendor_shell.dart:241` | `ShodashaTheme.blueTint` | 1.15:1 vs surface | Subtle informational ground |
| Cap Banner Text | `vendor_shell.dart:245` | `ShodashaTheme.ink` | 13.5:1 vs `blueTint` | High contrast, legible |
| Navigation Bar Icons | `vendor_shell.dart:284-309` | Material default scheme | ~7:1 | Standard theme contrast |
| Drawer Icons | `vendor_shell.dart:164-222` | Material default scheme | Standard | High recognition |

---

## 5. Typography & Text Scale

| Text Element | File:Line | Font Size | Weight | Finding |
|---|---|---|---|---|
| Login App Name | `vendor_code_screen.dart:90` | 22px | w700 | Large clear title |
| Login Subtitle | `vendor_code_screen.dart:101` | 12px | Default | Muted helper copy |
| Cap Banner Copy | `vendor_shell.dart:247` | 13px | w600 | Readable alert text |
| Drawer List Title | `vendor_shell.dart:165` | Default (16px) | Default | Standard list tile typography |
| Drawer List Subtitle | `vendor_shell.dart:166` | Default (14px) | Default | Hinglish explanatory text |
| Profile Screen Header | `profile_screen.dart:121` | 13px | Default | Inline leave prompt text |

---

## 6. Spacing, Grid & Alignment
- **Vendor Code Padding:** `EdgeInsets.all(24)` (`vendor_code_screen.dart:80`). Clean and spacious.
- **Form Field Gaps:** `SizedBox(height: 12)` and `SizedBox(height: 32)`.
- **Drawer ListTile Density:** Default Flutter `ListTile` density. Adequate spacing for casual indoor usage, but tight for outdoor drivers using one hand while sitting in a delivery truck.
- **Absence of Shared Tokens:** No references to `AppSpacing` tokens (`AppSpacing.sm`, `AppSpacing.md`, `AppSpacing.lg`) exist in `apps/vendor_app`. All values are magic numbers.

---

## 7. Micro-Interactions, Feedback & States
- **Login Validation:**
  - Phone validation: `isValidIndianPhone` checked upon blur (`_onPhoneFocus`) or submission.
  - Access code: `isValidAccessCode` (≥4 characters) with real-time toggleable visibility (`Icons.visibility` / `Icons.visibility_off`).
  - Loading: Button text changes to "Login ho raha hai…" with spinner.
  - Error: Surfaces backend errors directly (`invalidCredentials`, `rateLimited`, `deviceLimit`).
- **Sync Badge Counter:**
  - The "More" destination on the bottom navigation bar and the "Sync log" tile in the drawer dynamically display a `Badge(label: Text('$pending'))` showing un-synced offline delivery records (`vendor_shell.dart:183-186, 300-309`).
- **Lifecycle Polling Control:**
  - `didChangeAppLifecycleState` pauses discovery when app goes to background (`paused`/`inactive`) and resumes upon foreground resume (`vendor_shell.dart:101-109`).

---

## 8. Motion & Transitions
- **Drawer Slide:** Standard Material side-drawer sliding animation triggered from bottom tab tap.
- **Tab Switching:** Instant switching via `IndexedStack(index: _tab)` without transition animation.
- **Route Navigation:** Pushed routes (`_push(CustomersScreen)`) use standard platform slide transition.

---

## 9. Cognitive Load & Information Scent
- **Navigation Disorientation:** When drivers tap "More" expecting a menu screen, the screen stays unchanged while a drawer flies in from the left edge.
- **Hidden Core Workflows:** "Customers" and "Stock" (Vehicle Inventory) are critical daily tools for water delivery. Hiding them inside a drawer behind a "More" tab buries inventory audits under 2 levels of navigation.
- **Duty Lockout Friction:** Completely locking off-duty drivers out of the shell prevents them from checking yesterday's earnings or reviewing tomorrow's scheduled route before clocking in.

---

## 10. Touch Targets & Ergonomics
- **Login CTAs:** All touch targets on `VendorCodeScreen` meet or exceed 48dp height.
- **Bottom Navigation Bar:** Generous height (80dp) adhering to Material 3 navigation specifications.
- **Drawer Navigation:** `ListTile` elements have standard 56dp height.

---

## 11. Edge Cases & Resiliency
- **Session Cap Warning:** Warns driver 24h prior to the 30-day session cap expiration, preventing sudden mid-route lockouts without warning (`vendor_shell.dart:237-249`).
- **Access Code Masking:** Passwords/access codes default to obscured with visible toggle icon.
- **Offline Sync Queue Visibility:** Un-synced delivery receipts remain visible in sync queue counter even when offline.
- **Server Best-Effort Logout:** Logout clears local database session first, then informs server asynchronously.

---

## 12. Code-Level Craft & Tech Debt

| File & Line | Issue | Severity | Proposed Fix |
|---|---|---|---|
| `vendor_shell.dart:277-279` | Bottom tab "More" opens side Drawer | High | Replace Drawer with a dedicated "More" screen or bottom sheet |
| `vendor_shell.dart:145` | Hardcoded phone `919302190067` instead of `kSupportPhone` | Medium | Derive digits from `kSupportPhone` |
| `vendor_shell.dart:152-155` | Off-duty status completely locks out the entire shell | High | Allow access to Earnings, Profile, and Sync while off-duty |
| `vendor_shell.dart:163-228` | Inconsistent language mixing (English headers + Hinglish subtitles) | Medium | Align copy into consistent Hindi or English per locale |
| Whole App | Zero spacing, typography, or radius tokens imported | High | Establish shared tokens or vendor-specific design token file |

---

## 13. Accessibility (a11y)
- **High Visibility Icon:** Large 64dp water icon on login screen.
- **Input Labels:** Explicit `labelText` and `hintText` on both phone and code inputs.
- **Visibility Toggle Tooltip:** Dynamic tooltip (`Code dikhayein` / `Code chhupayein`) provides clear screen reader context.

---

## 14. Cross-Platform Consistency
- **NavigationBar:** Material 3 `NavigationBar` renders consistently on Android and iOS.
- **URL Launcher:** WhatsApp launcher uses `LaunchMode.externalApplication`.

---

## 15. Proposed Layout & Unslop Direction
### Vendor Shell: "The Field Driver Command Center"
- **5-Tab Navigation or Dedicated More Grid:**
  - Bottom Tab 1: **Route** (Stops, navigation, delivery status).
  - Bottom Tab 2: **Stock** (Truck inventory: Fulls loaded, Empties collected).
  - Bottom Tab 3: **Earnings** (Daily cash collected, delivery commission).
  - Bottom Tab 4: **Account / More** (Customers, Profile, Sync log, Support, Logout).
  - **Eliminate Side Drawer:** Replace the awkward side drawer with a clean, high-contrast grid menu on the "More" screen.
- **Gentle Duty Bar:**
  - Instead of replacing the entire screen when off-duty, render an amber top banner: "You are currently OFF DUTY. [Go On Duty to start deliveries]". Allow navigation to Earnings, Profile, and Help while off duty.
- **Unified Support Derivation:** Replace hardcoded `919302190067` with `kSupportPhone`.

---

## 16. Concrete Actionable Recommendations
1. **Eliminate Drawer Trigger on Bottom Tab:** Transform "More" into an actual screen tab displaying large touch cards for Customers, Inventory (Stock), Sync Log, Profile, and Help.
2. **Loosen Duty Gate:** Allow off-duty vendors to view non-operational tabs (Earnings, Profile, Sync history) with an on-duty toggle banner at the top of the Route tab.
3. **Harmonize Support Phone:** Update `_whatsapp()` in `vendor_shell.dart:145` to use `kSupportPhone`.
4. **Standardize Language Strategy:** Ensure all menu titles and subtitles follow a deliberate language policy rather than random ad-hoc Hinglish.
5. **Establish Vendor Design Tokens:** Create a unified `VendorTheme` token set defining spacing (8, 12, 16, 24dp), touch targets (min 48dp), and type scales for outdoor field visibility.

---

## 17. Acceptance Criteria
- [ ] Bottom navigation bar tabs open screens, never a side drawer.
- [ ] Off-duty vendors can view their profile and earnings without being blocked by a full-screen duty gate.
- [ ] WhatsApp support link derives exclusively from `kSupportPhone`.
- [ ] No hardcoded raw phone numbers remain in shell source code.
- [ ] Driver offline sync queue counter remains prominently visible.

---

## 18. File Invariants & Verification Checklist
- [x] Invariant: Access-code authentication with zero self-signup door (`vendor_code_screen.dart:1-3`).
- [x] Invariant: Route discovery polling strictly stops when off-duty or app is backgrounded (`vendor_shell.dart:91-109`).
- [x] Invariant: Session restoration handles 30-day cap warning with 24h grace period (`vendor_shell.dart:237-249`).
- [x] Verified: Phone validation regex adheres to standard 10-digit Indian mobile format (starting 6–9).
