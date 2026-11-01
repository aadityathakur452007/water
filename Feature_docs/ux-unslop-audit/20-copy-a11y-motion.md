# X4 — Cross-Cutting: Copy, Accessibility, Motion & Polling Audit

**Scope Audited:**
- Copywriting, localization patterns, and string dictionaries across both apps
- Accessibility (a11y), screen reader semantics, WCAG contrast ratios, and touch targets
- Motion systems, animation curves, and OS reduced-motion compliance
- Network polling loops, lifecycle listeners, and battery conservation

---

## 1. Executive Summary
This audit evaluated the sensory and ergonomic layers of both applications: what the user reads (copy), how assistive technologies perceive it (a11y), how the interface moves (motion), and how background network activity behaves (polling). Overall standards are high: strict 48dp minimum targets across core controls, zero battery-draining silent background polling, and built-in OS reduced-motion gates. However, several systematic defects mar the user experience:
1. **Developer and technical leaks in retail copy:** Internal implementation details leak directly into customer-facing text: *"Server prices"* in catalog headers, *"The app does not display live plant telemetry because the API does not expose it"* in water quality sheets, and raw 36-character database UUIDs in notification banners.
2. **The "Slash-Separated" bilingual crutch:** The vendor app relies heavily on clumsy slashes to display dual languages on a single line (`"Duty / ड्यूटी"`, `"Triple / तीन काम एक साथ"`, `"Door Locked / Ghar band hai"`), doubling reading time for drivers.
3. **Misnamed string dictionaries:** Multiple maps in the donor app (`authStringsHi`, `ordersStringsHi`) carry the `Hi` (Hindi) suffix despite containing 100% English copy.
4. **Fragile string scraping for operational state:** `sync_screen.dart` and `customer_home_screen.dart` parse human string contents (`c.result!.contains('Network')`, `e.message.toLowerCase().contains('internet')`) to determine UI iconography and offline banners.

---

## 2. Copy & Tone Audit

| Location | Current Copy | Defect / Issue | Proposed Fix |
|---|---|---|---|
| `featured_products.dart:36` | `"Server prices"` | Dev meta-label exposed in catalog | Remove tag or change to `"Current Rates"` |
| `donor_profile_screen.dart:401` | `"...because the API does not expose it."` | Engineering limitation leaked to customer | Replace with quality assurance statement |
| `notifications_screen.dart:288` | `"Order 8f3b14a2-7c91-4d02-a123-..."` | Raw 36-character UUID headline | Shorten to 4-character suffix: `"Order #...8902"` |
| `auth_controller.dart:18` | `authStringsHi` | Named Hindi, filled with English | Rename to `authStrings` |
| `orders_controller.dart:38` | `ordersStringsHi` | Named Hindi, filled with English | Rename to `ordersStrings` |
| Vendor App (All screens) | `"Customers / ग्राहक"`, `"Stock / स्टॉक"` | Slash-separated bilingual hack | Display pure Hindi or pure English per locale |
| `earnings_screen.dart:117` | `"...// default Rs 20/stop"` | Fabricated client-side earnings fallback | Display only server-stated payout |

---

## 3. Accessibility (a11y) & Touch Ergonomics Audit
- **Touch Target Sizing (WCAG 2.5.5 / 2.5.8):**
  - All standalone buttons (`AppButton`, `AppIconButton`, steppers) enforce `minHeight: 48, minWidth: 48`.
  - Exception: Tight button clusters in `_PlanCard` and `TripleSheet` risk fat-finger misclicks on 360dp screens.
- **Screen Reader Semantics:**
  - `_StatusPill` properly implements `Semantics(label: 'Status: $label', excludeSemantics: true)`.
  - Missing semantics: Monogram avatar in `donor_profile_screen.dart` lacks label; `LivePurityCard` TDS values are read as disjoint numbers.
- **Color Independence:**
  - Statuses use both color and distinct icons (`check_circle` for success, `error_outline` for danger, `schedule` for pending).

---

## 4. Contrast Ratio Verification (WCAG 2.1)

| Element | Background | Foreground | Ratio | Compliance |
|---|---|---|---|---|
| Primary Body Text | `#FFFFFF` (Surface) | `#0F172A` (Ink) | 14.1:1 | WCAG AAA |
| Muted Body Text | `#FFFFFF` (Surface) | `#64748B` (Muted) | 4.6:1 | WCAG AA |
| Primary Brand Teal | `#FFFFFF` (Surface) | `#00A896` (Teal) | 3.1:1 | WCAG AA Large (Fail normal text) |
| Money CTA Green | `#059669` (GreenDark) | `#FFFFFF` (White) | 4.9:1 | WCAG AA |
| Danger Alert Red | `#FFFFFF` (Surface) | `#DC2626` (Danger) | 5.2:1 | WCAG AA |
| Solar Alert Ground | `#FEF3C7` (SolarTint)| `#78350F` (OnSolar) | 8.2:1 | WCAG AAA |

*Finding:* Standard body text set in `#00A896` (Teal) fails WCAG AA for normal text (<18px). Teal must only be used on backgrounds or large headlines (≥18px bold). Text body should use `tealDeep` (`#0D6559`, 7.1:1) or `ink` (`#0F172A`).

---

## 5. Motion Systems & Reduced Motion Compliance
### AppMotion (`theme.dart:150-167`)
- Provides 3 calibrated duration tokens: `fast` (150ms), `normal` (180ms), `slow` (220ms).
- Checks `MediaQuery.disableAnimationsOf(context)` and reduces durations to `Duration.zero`.
- Defect: Seldom utilized across screens; transitions are mostly default platform pushes or instant state flips.

### Cascade Motion (`cascade.dart`)
- Hand-rolled staggered entrance controller with `Interval(begin, 1.0, curve: Curves.easeOut)`.
- Test-safe (`Ticker`-driven, zero `Timer` leaks).
- Checks `MediaQuery.disableAnimationsOf(context)` at line 99, returning static widgets when requested.

---

## 6. Network Polling & Background Behavior Audit
### Polling Inventory

| Location | Polling Interval | Stop Condition / Lifecycle Guard | Battery / Network Finding |
|---|---|---|---|
| `tracking_screen.dart:88` | 3 seconds | Stops upon `OrderState.delivered`, cancel, or dispose | Fast 3s loop; acceptable during active live delivery |
| `vendor_shell.dart:95` | Discovery poll | `stopDiscovery()` on off-duty, background, or dispose | Excellent lifecycle hygiene; zero background leaks |
| `subscription_screen.dart:1490` | 3 seconds (max 5) | Stops upon webhook confirmation or 5 iterations | Clean capped polling loop for prepaid UPI top-up |
| `customer_home_screen.dart` | Polling loop | None (manual pull-to-refresh) | Clean on-demand model |

*Finding:* Polling discipline is exemplary. Background lifecycle observers properly halt polling when the app is paused or inactive.

---

## 7. Concrete Actionable Recommendations
1. **Purge Internal Dev Copy:** Remove "Server prices" from catalog headers and remove API limitation disclaimers from the water quality sheet.
2. **Shorten Database IDs in UI:** Replace full 36-character UUIDs in notifications and bills with friendly 4-character suffixes (`#...8902`).
3. **Eliminate Bilingual Slashes:** Adopt a clean locale-driven string strategy for the vendor app rather than slash-separated strings.
4. **Eliminate String-Scraping for States:** Expose structured boolean flags (`isOffline`, `isNetworkError`) on API exceptions and controllers rather than running `message.contains('internet')`.
5. **Darken Teal for Body Text:** Restrict `ShodashaTheme.teal` (`#00A896`) to backgrounds and large headlines; use `ShodashaTheme.tealDeep` (`#0D6559`) for any colored body text to satisfy WCAG AA contrast.

---

## 8. Acceptance Criteria
- [ ] No internal API or developer justification copy is visible in the production UI.
- [ ] No raw 36-character UUIDs appear as primary titles or headlines.
- [ ] All body text achieves at least 4.5:1 contrast against its background.
- [ ] OS reduced-motion preferences are 100% honored across all animated widgets.
- [ ] Network polling loops terminate immediately when the app enters the background.
