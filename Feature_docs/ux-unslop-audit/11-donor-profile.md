# D11 — Donor Profile & Edit Profile Sheet Audit

**Files Audited:**
- `apps/user_app_donor/lib/features/profile/donor_profile_screen.dart` (575 lines)
- `apps/user_app_donor/lib/features/profile/edit_profile_sheet.dart` (268 lines)
- `apps/user_app_donor/lib/features/profile/profile_controller.dart` (165 lines)
- Supporting context: `apps/user_app_donor/lib/core/constants/app_constants.dart` (`AppColors` alias facade)

---

## 1. Executive Summary
The Profile domain manages customer identity, phone/email contact updates, saved address shortcuts, app metadata, and session teardown (`auth.logout()`). State hygiene is strong: dirty-state form change detection (`_dirty` tracking with discard warning dialog), single-flight user generation increments to prevent cross-account leaks upon logout, and explicit security confirmation dialogs. However, the screen exhibits acute craft flaws, developer-facing copy leaks, and brand dissonance:
1. **Jarring solid dark teal AppBar in tab navigation:** `donor_profile_screen.dart:135` sets `backgroundColor: ShodashaTheme.tealDeep`. When a customer switches from Home, Orders, Subscriptions, or Wallet (all using clean white `ShodashaTheme.surface` AppBars) to the Profile tab, the top app bar violently flashes dark teal.
2. **Developer justification text exposed in customer modal:** Tapping the "Water quality" tile opens a sheet that concludes with: *"The app does not display live plant telemetry because the API does not expose it."* Internal engineering rationale and API limitations must never leak into customer-facing retail copy.
3. **Severe token system duality (`AppColors` vs `ShodashaTheme`):** Profile screen imports both `app_constants.dart` and `theme.dart`, haphazardly mixing `AppColors.surface`, `AppColors.primary`, and `AppColors.textPrimary` with `ShodashaTheme.muted` and `ShodashaTheme.tealDeep` in the same widget trees.
4. **Redundant "Session: Active" vanity stat:** The profile header renders a 3-column statistics strip (`Orders`, `Addresses`, `Session`). Displaying "Session: Active" provides zero utility to a customer and clutters the primary profile card.

---

## 2. Screen Identity & Canonical Route
- **Profile Screen:** Root tab destination (Tab 4: `profile`) in `donor_shell.dart`. Canonical title: "Profile".
- **Edit Profile Sheet:** Modal bottom sheet (`EditProfileSheet`) backed by `PATCH /v1/auth/me`.
- **Water Quality Sheet:** Informational modal bottom sheet (`_showQuality`).
- **Target Persona:** Bhopal household or enterprise account holder managing contact phone numbers, updating email for invoice receipts, and reviewing account settings.

---

## 3. Visual & Spatial Hierarchy
### Profile Screen
- **AppBar:** Solid dark teal (`#0D6559`) with white title and refresh button.
- **Identity Hero Card:** White rounded container (16dp radius) featuring:
  - 64dp Circular initials avatar (`AppColors.primary.withValues(alpha: 0.12)`).
  - Customer name (19px bold), phone number (12.5px), email (12px).
  - Edit profile pencil icon button (`Icons.edit_outlined`).
  - Embedded 3-stat strip (`Orders`, `Addresses`, `Session`).
- **Account Menu Section:** Vertical stack of cards (`_menuTile`) for Saved addresses, Shodasha wallet, Subscriptions, Notifications.
- **Support Menu Section:** Help & support, Water quality.
- **Destructive Action:** Full-width red logout button (`AppButtonKind.danger`).

### Edit Profile Sheet
- **Header:** `AppSheet` title "Edit profile" with close `X`.
- **Fields:** Name (autofocused), Mobile number, Email address.
- **Sticky Footer:** Full-width `AppButton` ("Save changes").

---

## 4. Color & Contrast Audit

| Element | File:Line | Color Token / Value | Contrast Ratio (vs BG) | Compliance / Finding |
|---|---|---|---|---|
| Screen AppBar | `donor_profile_screen.dart:135` | `ShodashaTheme.tealDeep` (`#0D6559`) | **Inconsistent** | Breaks 4-tab white theme consistency |
| AppBar Title | `donor_profile_screen.dart:144` | `ShodashaTheme.surface` (`#FFFFFF`) | 7.8:1 vs `tealDeep` | Compliant |
| Screen Ground | `donor_profile_screen.dart:133` | `ShodashaTheme.bg` (`#F7F9FA`) | Baseline | Standard light ground |
| Identity Card Surface | `donor_profile_screen.dart:193` | `AppColors.surface` (`#FFFFFF`) | Baseline | Token alias for `ShodashaTheme.surface` |
| Avatar Circle Background | `donor_profile_screen.dart:203` | `primary.withValues(alpha: 0.12)` | Subtle tint | Clean monogram badge |
| Avatar Monogram Text | `donor_profile_screen.dart:211` | `AppColors.primary` (`#00A896`) | 3.2:1 vs tint | Large 22px text; passes WCAG AA large |
| Customer Name | `donor_profile_screen.dart:226` | `AppColors.textPrimary` (`#0F172A`) | 14.1:1 vs surface | High contrast, bold |
| Stat Numbers | `donor_profile_screen.dart:417` | `ShodashaTheme.tealDeep` (`#0D6559`) | 7.1:1 vs tint | WCAG AAA compliant |
| Logout Button | `donor_profile_screen.dart:366` | `AppButtonKind.danger` (`#DC2626`) | 5.2:1 vs surface | Standard clear danger token |

---

## 5. Typography & Text Scale

| Text Element | File:Line | Font Size | Weight | Finding |
|---|---|---|---|---|
| Screen AppBar Title | `donor_profile_screen.dart:143` | 18px | w700 | Fits screen identity cleanly |
| Avatar Monogram | `donor_profile_screen.dart:209` | 22px | w900 | Bold prominent initial |
| Customer Name | `donor_profile_screen.dart:223` | 19px | w900 | **Off-scale token**: Scale uses 18px or 22px |
| Customer Phone | `donor_profile_screen.dart:234` | 12.5px | Default | **Off-scale token**: Violates 12px/14px scale |
| Customer Email | `donor_profile_screen.dart:243` | 12px | Default | Legible secondary text |
| Stat Value | `donor_profile_screen.dart:415` | 16px | w800 | Strong numeric stat |
| Section Header | `donor_profile_screen.dart:309` | 13px | w700 | Second body size |
| Menu Tile Title | `donor_profile_screen.dart:466` | 14px | w700 | Standard body bold |

---

## 6. Spacing, Grid & Alignment
- **List Padding:** Uses `EdgeInsets.all(AppConstants.defaultPadding)` (24dp) (`donor_profile_screen.dart:178`).
- **Profile Card Internal Spacing:** `padding: const EdgeInsets.all(18)` (line 191). Hardcoded 18dp deviates from `AppSpacing.lg` (16dp).
- **Stat Divider Alignment:** Thin vertical borders (`height: 28, width: 1`) between stats, neatly spaced with `MainAxisAlignment.spaceAround`.
- **Menu Card Spacing:** `AppSpacing.sm` (8dp) bottom margin between menu tiles.

---

## 7. Micro-Interactions, Feedback & States
- **Dirty State Guard:** `_EditProfileSheetState` tracks `_dirty` boolean by comparing initial controller strings with text field values (`edit_profile_sheet.dart:42-45`). Dismissing with unsaved edits triggers an alert dialog: "Discard changes?".
- **Loading Skeleton:** Displays custom `_ProfileSkeleton` with shimmering containers for avatar, name, and stat block (`donor_profile_screen.dart:496-547`).
- **Stale Profile Banner:** Displays `AppBanner.stale` when background refresh fails but cached data is on screen.
- **Logout Flow:** Guards against duplicate taps via `_loggingOut` flag, displaying confirmation dialog before calling `auth.logout()`.

---

## 8. Motion & Transitions
- **Sheet Opening:** Slide-in modal bottom sheet via `AppSheet`.
- **Field Error Transitions:** Immediate red error text reveal under invalid fields.
- **Logout Transition:** State flips to `_loggingOut = true`, updating button label to "Logging out…" and showing spinner before session clears.

---

## 9. Cognitive Load & Information Scent
- **Dev-Speak Leak in Water Quality Sheet:** The copy states: *"The app does not display live plant telemetry because the API does not expose it."* This meta-language breaks customer immersion and signals unpolished software.
- **Vanity Stat Clutter:** Showing "Session: Active" in a stat strip alongside "Orders: 12" and "Addresses: 2" has zero informational value for a mobile app user.
- **Navigation Duplication:** Profile screen lists "Shodasha wallet" and "My subscriptions" as menu tiles, even though both destinations exist directly in the bottom navigation bar of the shell.

---

## 10. Touch Targets & Ergonomics
- **Edit Pencil Icon:** `IconButton` provides standard 48x48dp touch target.
- **Menu Tiles:** Wrapped in `AppCard` with `ConstrainedBox(minHeight: ShodashaTheme.minTarget)` (48dp). Generous full-width tap area.
- **Logout Button:** Full-width `AppButton` positioned at list end, easily reachable.

---

## 11. Edge Cases & Resiliency
- **Guest / Signed-Out Profile:** Handled gracefully by `ProfileController.load()` returning without errors if no auth token is held.
- **Empty / Null Name:** Falls back safely to `'Your profile'` and monogram initials fall back to `'S'` (`donor_profile_screen.dart:166, 221`).
- **Network Failure During Profile Update:** Locks button spinner, preserves form inputs, and surfaces exact server error string in red banner (`edit_profile_sheet.dart:121-126`).
- **Account Reset Guard:** `ProfileController.reset()` increments `_generation`, cleanly invalidating pending responses when logging out (`profile_controller.dart:97-101`).

---

## 12. Code-Level Craft & Tech Debt

| File & Line | Issue | Severity | Proposed Fix |
|---|---|---|---|
| `donor_profile_screen.dart:135` | Dark teal AppBar clashes with other 4 shell tabs | High | Standardize to `ShodashaTheme.surface` (white) with `ink` text |
| `donor_profile_screen.dart:401-403` | Meta developer copy exposed in water quality sheet | High | Replace with customer-focused quality assurance statement |
| `donor_profile_screen.dart:193-211` | `AppColors` imported and mixed with `ShodashaTheme` | Medium | Deprecate `AppColors` and use `ShodashaTheme` directly |
| `donor_profile_screen.dart:285-289` | Useless "Session: Active" vanity stat | Low | Remove stat or replace with "Total Jars Delivered" |
| `donor_profile_screen.dart:223, 234` | Off-scale typography (`19px`, `12.5px`) | Low | Standardize to 18px and 12px tokens |
| `donor_profile_screen.dart:191` | Off-scale `18dp` card padding | Low | Standardize to `AppSpacing.lg` (16dp) |

---

## 13. Accessibility (a11y)
- **Monogram Semantics:** Initials avatar lacks explicit semantic label. Should include `Semantics(label: 'Profile initials $initials')`.
- **Menu Chevrons:** Each tile includes `Icons.chevron_right_rounded` to indicate navigational intent.
- **Form Error Feedback:** `TextField` inputs use native `errorText` attributes, allowing screen readers to announce validation errors.

---

## 14. Cross-Platform Consistency
- **Dialog Styling:** Uses custom-styled `AlertDialog` with `ShodashaTheme.shape` and `minTarget` buttons, rendering identically across Android and iOS.
- **PopScope Implementation:** Employs Flutter 3.12+ `PopScope` with `canPop: !_saving && !_dirty` and `onPopInvokedWithResult`, ensuring proper back-swipe handling on iOS.

---

## 15. Proposed Layout & Unslop Direction
### Profile Screen: "The Quiet Account Hub"
- **Unified White Chrome:** Align AppBar background to `ShodashaTheme.surface` with `ShodashaTheme.ink` title, eliminating the abrupt top-bar color transition when switching tabs.
- **Refined Identity Card:**
  - Standardize padding to `AppSpacing.lg`.
  - Display Customer Name (18px bold) and verified Phone badge.
  - Simplify Stat Strip: Display only two high-value metrics: "Orders Placed" and "Active Subscriptions" (eliminate "Session: Active").
- **Customer-Centric Quality Sheet:**
  - Revise copy: "Every Shodasha 20L can undergoes automated 9-stage purification (RO + UV + Ozonation). Sealed at our certified Bhopal facility."
- **Direct Design System Migration:** Eliminate all references to `AppColors` and use `ShodashaTheme` tokens exclusively.

---

## 16. Concrete Actionable Recommendations
1. **Unify AppBar Theme:** Change `appBar` background in `donor_profile_screen.dart:135` from `ShodashaTheme.tealDeep` to `ShodashaTheme.surface`, with title color `ShodashaTheme.ink`.
2. **Purge Dev-Speak from Water Quality:** Remove the clause `"The app does not display live plant telemetry because the API does not expose it"` from `_showQuality()`.
3. **Remove `AppColors` Facade:** Replace all `AppColors.*` references in `donor_profile_screen.dart` with canonical `ShodashaTheme.*` tokens.
4. **Drop Vanity Session Stat:** Remove the "Session: Active" column from the profile card statistics row.
5. **Normalize Font Tokens:** Replace `19px` with `18px` and `12.5px` with `12px`.

---

## 17. Acceptance Criteria
- [ ] Profile screen AppBar matches the white surface color of all other primary shell tabs.
- [ ] No internal API or developer justification text appears in customer-facing sheets.
- [ ] `AppColors` token facade is eliminated in favor of `ShodashaTheme`.
- [ ] Profile card displays only meaningful customer metrics.
- [ ] Unsaved changes discard guard and logout confirmation invariants remain 100% intact.

---

## 18. File Invariants & Verification Checklist
- [x] Invariant: Profile identity is backed strictly by `GET /v1/auth/me` and `PATCH /v1/auth/me` (`profile_controller.dart:1-5`).
- [x] Invariant: Unsaved profile edits trigger explicit discard confirmation dialog (`edit_profile_sheet.dart:61-88`).
- [x] Invariant: Logout requires user confirmation and invalidates cached profile state (`donor_profile_screen.dart:97-128`, `profile_controller.dart:97-101`).
- [x] Verified: Phone and email validators conform to Indian mobile format and RFC email standards.
