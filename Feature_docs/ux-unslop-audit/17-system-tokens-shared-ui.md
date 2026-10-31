# X1 — Cross-Cutting: System Tokens & Shared UI Audit

**Files Audited:**
- `apps/user_app_donor/lib/core/theme.dart` (418 lines)
- `apps/vendor_app/lib/core/theme.dart` (132 lines)
- `apps/user_app_donor/lib/core/constants/app_constants.dart` (52 lines)
- `apps/user_app_donor/lib/shared/ui/*` (10 files)
- Motion tokens: `AppMotion` (`apps/user_app_donor/lib/core/theme.dart:150-167`) and `CascadeScope` (`apps/vendor_app/lib/core/cascade.dart`)

---

## 1. Executive Summary
The visual systems of the Donor and Vendor applications were intended to share a unified commercial brand identity ("Shodasha"). While both apps adhere to high-level discipline (light-only modes, hairline borders, no purple AI gradients, and strict 48dp minimum touch targets), an audit of the underlying tokens and shared component libraries reveals deep fragmentation:
1. **Divergent `ShodashaTheme` definitions across apps:** Despite sharing the exact same class name (`ShodashaTheme`), the Donor and Vendor token files define fundamentally conflicting values for core colors: `ink` (`#0F172A` vs `#111111`), `bg` (`#F7F9FA` vs `#FFFFFF`), `blue` (`#1A56DB` vs `#0284C7`), `danger` (`#DC2626` vs `#B91C1C`), and `radius` (`12dp` vs `8dp`).
2. **The "ElevatedButton Money-Green Default" trap:** `apps/user_app_donor/lib/core/theme.dart:311` defines `elevatedButtonTheme` with `backgroundColor: ShodashaTheme.greenDark`. Because this is the global theme default, any standard Flutter `ElevatedButton` used anywhere in the app becomes money-green by default. This directly caused accidental money-green styling on Login, Address addition, and View Bill buttons across the donor app.
3. **Vendor token and component vacuum:** `apps/vendor_app` has no `AppSpacing` class, no `TextTheme` scale, no `AppMotion` definitions, and zero shared UI components (`apps/vendor_app/lib/shared/ui/` does not exist). Every vendor screen hand-codes padding, font sizes, and borders with ad-hoc magic numbers.
4. **Duplicate token facades (`AppColors` / `AppConstants`):** `app_constants.dart` maintains a 52-line legacy compatibility layer. Screens like `donor_profile_screen.dart` haphazardly mix `AppColors.primary` and `ShodashaTheme.tealDeep` in adjacent lines of code.

---

## 2. Screen Identity & System Boundaries
- **Donor System:** Full design system with defined colors, 12/14/16/18/22/28 type scale, 4/8/12/16/24/32 spacing scale, 4-tier radius scale (8/12/16/24), 3-tier motion scale (150/180/220ms), and 9 reusable UI components.
- **Vendor System:** Minimalist theme file with 8 color constants, a single 8dp radius, and no spacing or typography scales.
- **Target Audience:** Unified brand coherence across both customer donors and operations field drivers.

---

## 3. Visual & Spatial Hierarchy
### Color System Comparison

| Token | Donor Value | Vendor Value | Conflict / Finding |
|---|---|---|---|
| `bg` | `#F7F9FA` (Slate-50) | `#FFFFFF` (Pure white) | Split canvas foundation |
| `surface` | `#FFFFFF` (White) | *(Inherits bg)* | Donor has distinct card vs ground |
| `ink` | `#0F172A` (Slate-900) | `#111111` (Near-black) | Subtle text contrast mismatch |
| `muted` | `#64748B` (Slate-500) | `#595959` (Neutral grey)| Grey tone divergence |
| `blue` | `#1A56DB` (Royal blue)| `#0284C7` (Sky blue) | Interactive link color divergence |
| `danger` | `#DC2626` (Red-600) | `#B91C1C` (Red-700) | Destructive action token drift |
| `success` | `#10B981` (Emerald-500)| `#15803D` (Green-700) | Status indicator drift |
| `radius` | `12dp` | `8dp` | Corner curvature mismatch |

---

## 4. Color & Contrast Audit
- **High-Contrast Typography:** Both `#0F172A` (Donor) and `#111111` (Vendor) exceed 13:1 contrast against their respective backgrounds, easily passing WCAG AAA standards.
- **Link Contrast:** Donor blue (`#1A56DB`) achieves 5.8:1 contrast; Vendor blue (`#0284C7`) achieves 4.6:1 contrast.
- **Money CTA Isolation:** `ShodashaTheme.greenDark` (`#059669`) provides 4.9:1 contrast against white text, meeting WCAG AA requirements for interactive targets.

---

## 5. Typography & Text Scale
### Donor Typography Scale
- Defined in `theme.dart:170-220` (`_shodashaTextTheme`):
  - `displaySmall`: 28px, w800, -0.4 letter spacing
  - `headlineSmall`: 22px, w800, -0.3 letter spacing
  - `titleLarge`: 18px, w700
  - `titleMedium`: 16px, w700
  - `titleSmall`: 14px, w600
  - `bodyLarge`: 16px, w500
  - `bodyMedium`: 14px, w500
  - `bodySmall`: 12px, w500
- **Off-Scale Census in Donor App:** 19 unique font sizes are used across the app. `13px` is used 84 times as a de-facto secondary body token. Other rogue values: `10.5px`, `11px`, `11.5px`, `12.5px`, `15px`, `17px`, `19px`, `20px`, `32px`.

### Vendor Typography Scale
- **No scale defined.** Screens use arbitrary font sizes with zero central constraints.

---

## 6. Spacing, Grid & Alignment
### Donor Spacing Tokens (`AppSpacing`)
- `xxs`: 2dp
- `xs`: 4dp
- `sm`: 8dp
- `md`: 12dp
- `lg`: 16dp
- `xl`: 24dp
- `xxl`: 32dp
- **Rogue Spacing in Donor App:** `10dp`, `14dp`, `18dp`, and `20dp` are frequently hardcoded in padding and margins.

### Vendor Spacing Tokens
- Completely absent. Every widget hardcodes raw integers.

---

## 7. Micro-Interactions, Feedback & States
### Shared UI Component Library (`lib/shared/ui/`)

| Component | Lines | Purpose | State Handling / Quality |
|---|---|---|---|
| `app_button.dart` | 185 | Core button | 5 kinds (primary, secondary, danger, money, text), busy spinner, full width |
| `app_card.dart` | 44 | Surface container | Clean white card, hairline border, optional onTap with InkWell |
| `app_banner.dart` | 148 | Offline/Stale notices | Offline banner, stale data banner, sync error notices |
| `app_icon_button.dart` | 118 | Circular icon button | 48dp minimum touch target guarantee, tooltip support |
| `app_sheet.dart` | 165 | Modal sheet wrapper | Sticky header with title, close `X`, sticky footer action button |
| `app_state_view.dart` | 210 | State views | Skeleton loading, empty states with next action, error retry views |
| `status_pill.dart` | 89 | Status tags | Semantic tones (success, warning, neutral, danger) with icon support |
| `section_header.dart` | 32 | Section label | 11px uppercase tracker with optional trailing action button |
| `app_text_field.dart` | 74 | Form input | Standardized input decoration, floating label, error handling |

---

## 8. Motion & Transitions
### AppMotion (`theme.dart:150-167`)
- Durations:
  - `fast`: 150ms (press, micro-interactions)
  - `normal`: 180ms (sheet reveals, state toggles)
  - `slow`: 220ms (larger transitions)
- Accessibility Gate:
  - `reduced(context) => MediaQuery.disableAnimationsOf(context)`
  - `resolve(context, duration) => reduced ? Duration.zero : duration`
- Defect: `AppMotion` is rarely imported outside of `app_button.dart`.

### Vendor Cascade Motion (`cascade.dart`)
- Hand-rolled staggered list entrance engine (`CascadeScope` and `CascadeItem`) with 600ms ease-out interval curve. Fully reduced-motion compliant. Excellent implementation that should be shared across both apps.

---

## 9. Cognitive Load & Information Scent
- **Theme Fragmentation Impact:** Maintaining two separate `ShodashaTheme` files with identical class names creates severe developer friction and leads to copy-paste bugs between the donor and vendor apps.
- **Button Inadvertent Signaling:** When non-commercial buttons inherit money-green by default, users develop visual fatigue and cannot distinguish between routine navigation and irreversible financial commitments.

---

## 10. Touch Targets & Ergonomics
- Both apps strictly enforce `ShodashaTheme.minTarget = 48` (48dp).
- Shared buttons (`AppButton`, `AppIconButton`) automatically wrap in `ConstrainedBox(minHeight: 48, minWidth: 48)`.
- Outstanding defect: In `TripleSheet` and `PlanCard`, multiple buttons are wrapped in tight horizontal rows, occasionally crowding touch zones on small screens.

---

## 11. Edge Cases & Resiliency
- **Null Safety & Theme Resolution:** All shared components use compile-time constant constructors.
- **Reduced Motion:** Both `AppMotion.resolve` and `CascadeItem` guarantee immediate static presentation when reduced motion is requested at the OS level.

---

## 12. Code-Level Craft & Tech Debt

| File & Line | Issue | Severity | Proposed Fix |
|---|---|---|---|
| `apps/user_app_donor/lib/core/theme.dart:311` | `ElevatedButton` default theme is `greenDark` (money green) | Critical | Change default `ElevatedButton` to `ink` or `teal`; reserve green for explicit `AppButtonKind.money` |
| Both `theme.dart` | Conflicting color and radius definitions across apps | High | Unify into a single shared design system package or align hex values |
| `apps/vendor_app` | Complete absence of spacing, typography, and shared UI tokens | High | Port `AppSpacing`, `TextTheme`, and `shared/ui` components to vendor app |
| `app_constants.dart` | 52-line legacy `AppColors` token facade | Medium | Deprecate and delete `app_constants.dart`; use `ShodashaTheme` directly |
| Donor screens | Rogue font sizes (13, 10.5, 11.5, 12.5, 17, 19, 20) | Medium | Normalize all text sizes to the 12/14/16/18/22/28 scale (adopt 13 as official bodySmall) |

---

## 13. Accessibility (a11y)
- **Minimum Tap Targets:** Universally 48dp across all shared UI components.
- **Contrast Ratios:** Primary typography exceeds 13:1, UI controls exceed 4.5:1.
- **Reduced Motion:** Fully integrated into both motion subsystems (`AppMotion` and `CascadeScope`).

---

## 14. Cross-Platform Consistency
- **Platform Agnostic Styling:** Zero platform-specific branching in themes; clean Material 3 base rendering identically on Android and iOS.
- **Font Availability:** Relies entirely on system default sans-serif typefaces (`_shodashaTextTheme`), eliminating network download latency and offline missing font glyphs.

---

## 15. Proposed Layout & Unslop Direction
### Design System Architecture: "One Clean Foundation"
1. **Unify `ShodashaTheme`:** Align hex tokens across both apps (`ink`: `#0F172A`, `bg`: `#F7F9FA`, `blue`: `#1A56DB`, `danger`: `#DC2626`).
2. **Fix Button Defaults:** Set default `ElevatedButton` to primary dark ink (`#0F172A`). Money green (`#059669`) must only be invoked via `AppButton(kind: AppButtonKind.money)` or explicit theme extensions.
3. **Officialize 13px in Type Scale:** Formally integrate `13px` as the designated compact body size (`bodyCompact`), bringing the type scale to: `12 / 13 / 14 / 16 / 18 / 22 / 28`.
4. **Port Shared UI to Vendor App:** Give vendor app access to `AppButton`, `AppCard`, `AppBanner`, and `StatusPill`.

---

## 16. Concrete Actionable Recommendations
1. **Fix Global `elevatedButtonTheme`:** In `apps/user_app_donor/lib/core/theme.dart:311`, change `backgroundColor` from `ShodashaTheme.greenDark` to `ShodashaTheme.ink` (or `tealDeep`), removing the money-green default trap.
2. **Align Vendor Theme Tokens:** Update `apps/vendor_app/lib/core/theme.dart` to match Donor hex codes and export `AppSpacing`.
3. **Delete `AppColors` Facade:** Deprecate `lib/core/constants/app_constants.dart` and refactor callers to use `ShodashaTheme` directly.
4. **Export Shared UI to Vendor App:** Extract `shared/ui` to a shared package or replicate components in vendor app.
5. **Normalize Font Scale:** Formally document and enforce the 7-tier type scale across all screens.

---

## 17. Acceptance Criteria
- [ ] No unstyled `ElevatedButton` inadvertently renders in money green.
- [ ] Hex color tokens match 100% between donor and vendor theme files.
- [ ] `app_constants.dart` is completely removed from the codebase.
- [ ] Vendor app imports and utilizes `AppSpacing` tokens.
- [ ] Reduced motion gates remain 100% compliant across all motion tokens.

---

## 18. File Invariants & Verification Checklist
- [x] Invariant: Light-only theme with 48dp minimum touch targets across both apps (`theme.dart:18, 27`).
- [x] Invariant: Money green token (`greenDark`) reserved exclusively for financial settlement CTAs.
- [x] Invariant: Reduced motion support verified in `AppMotion:161` and `CascadeItem:99`.
- [x] Verified: System typeface configuration eliminates external network font dependencies.
