# UI Context — Donor Customer App Design Language

> Scope: `apps/user_app_donor` (Flutter, Android). The user app, vendor app, admin web
> and legacy app have their own surfaces and are not governed by this file.

## Theme

Phone-first, calm, premium utility. The donor visual world is kept:

- Slate page ground + white cards, teal structure/navigation, solar badges/highlights.
- Green is **money-CTA only** (Book / Pay / Confirm). Never use green for tracking,
  navigation, or decorative emphasis.
- Blue is links/info only; never a filled surface.
- No purple/indigo gradients, no emoji, no fake riders/PINs/balances/addresses, no
  decorative font, no gradients in v1.
- Every screen must have explicit loading, empty, error, stale, offline, 4xx/5xx, 401,
  validation, submitting, retry and refresh states where the flow can reach them.
- Minimum interactive target: 48dp. WCAG AA contrast for normal text. Safe areas and
  keyboard insets are mandatory; sheets scroll and keep their sticky action reachable.

## Colors

Single source: `lib/core/theme.dart` (`ShodashaTheme`). `AppColors`/`AppConstants` are a
compatibility facade only; new code imports the theme and `shared/ui/shared_ui.dart`.

| Role | Token | Value |
|------|-------|-------|
| Page background | `ShodashaTheme.bg` | `#F8FAFC` |
| Surface / card | `ShodashaTheme.surface` | `#FFFFFF` |
| Primary text | `ShodashaTheme.ink` | `#0F172A` |
| Muted text | `ShodashaTheme.muted` | `#64748B` |
| Border | `ShodashaTheme.border` | `#E2E8F0` |
| Brand teal | `ShodashaTheme.teal` | `#0D9488` |
| Teal dark | `ShodashaTheme.tealDark` | `#0F766E` |
| White-on-teal | `ShodashaTheme.tealDeep` | `#115E59` |
| Teal tint | `ShodashaTheme.tealTint` | `#CCFBF1` |
| Money CTA | `ShodashaTheme.greenDark` | `#15803D` |
| Money green | `ShodashaTheme.green` | `#16A34A` |
| Success text | `ShodashaTheme.successDark` | `#047857` |
| Warning text | `ShodashaTheme.warning` | `#B45309` |
| Error | `ShodashaTheme.danger` | `#B91C1C` |
| Link / info | `ShodashaTheme.link` | `#0369A1` |
| Solar badge | `ShodashaTheme.solar` | `#FACC15` |
| Solar tint | `ShodashaTheme.solarTint` | `#FEF9C3` |
| Skeleton | `ShodashaTheme.skeleton` | `#E2E8F0` |

Rules:

- Money CTAs use `greenDark` with white text. Teal filled buttons use `tealDeep`.
- Status is never color-alone: pair every status with a label and/or icon.
- No screen-local hex, gradients, or a second token system.

## Typography

System platform font only (no font asset, no download). Type scale from
`ShodashaTheme`:

| Role | Size | Weight | Line height |
|------|------|--------|-------------|
| Display / hero | 28 | 800 | 1.2 |
| Headline | 22 | 800 | 1.25 |
| Section title | 18 | 700 | 1.3 |
| Card title | 16 | 700 | 1.35 |
| Body large | 16 | 500 | 1.5 |
| Body | 14 | 500 | 1.45 |
| Label / small | 12 | 600 | 1.2–1.4 |

- Keep headings tight (`letterSpacing` -0.4 to -0.3) and body readable.
- Do not use decorative/display fonts, all-caps body copy, or tiny muted text for
  essential information.
- Amounts use the one `formatInr` money formatter; never truncate paise with `~/ 100`.

## Border Radius

| Context | Token | Value |
|---------|-------|-------|
| Small chips/tiles | `radiusSm` | 8 |
| Cards/buttons/inputs | `radius` | 12 |
| Hero/feature cards | `radiusLg` | 16 |
| Bottom sheets | `radiusSheet` | 28 |

## Spacing & Layout

- `AppSpacing`: 4 / 8 / 12 / 16 / 24 / 32. Use the scale; no arbitrary screen padding.
- Phone-first content cap: `kMaxContentWidth = 560`; center wider layouts instead of
  stretching.
- Shell has five destinations: **Home / Orders / Plans / Wallet / Profile**. The
  screen title for the third tab remains “Subscriptions”; the short nav label is
  “Plans” so it fits at 360dp.
- Cards sit on the slate ground with a hairline border, no heavy elevation.
- Bottom navigation uses Material 3, 64dp height, teal tint indicator, 12px labels.
- Long content scrolls; sticky sheet footers stay above the keyboard and safe area.

## Components

Primary library: Material 3 plus the shared donor primitives (no third-party component
library, no new dependency).

`lib/shared/ui/shared_ui.dart`:

- `AppButton` — `money|primary|secondary|danger|ghost`; 48dp floor, 52dp default,
  busy keeps fill and blocks taps, disabled is inert.
- `AppIconButton` — 48dp target, tooltip, optional selected/badge.
- `AppCard` — white surface, border, large radius, consistent padding, optional tap.
- `AppSheet` + `showAppSheet` — safe-area bottom sheet, title/close, scroll controller,
  sticky footer, explicit dismiss/drag policy.
- `AppStateView` — `loading` skeleton, `empty`, `error(isNetwork)`, `stale`, `content`;
  one retry action; never raw status codes in user copy.
- `AppBanner` — offline / stale / success, with optional retry.
- `StatusPill` — label + tone `neutral|info|success|warning|danger|solar` + icon.
- `SectionHeader` — title + optional trailing action.
- `AppTextField` — label/helper/error/counter, autofill, keyboard/action, focus ring.

State grammar:

- Loading: skeleton or spinner, never a fake zero/empty value.
- Empty: explain the next action with one CTA.
- Error: network vs server copy; retry in place.
- Stale: keep the last real data and label it; never silently pass as fresh.
- 401/403: offer `Sign in again`; never a dead end.
- Money/booking: server is authority; no client price math or fabricated slots.

## Icons

Material Icons only. 20–24dp in cards/buttons; 48dp hit target regardless of glyph
size. No emoji, no mixed icon sets, no decorative icon soup.

## Motion

- `AppMotion.fast` 150ms (press/micro), `normal` 180ms (sheet/state), `slow` 220ms
  (larger state change).
- Use `AppMotion.resolve(context, duration)` / `AppMotion.reduced(context)` so
  `MediaQuery.disableAnimationsOf` is honoured.
- Animate transform/opacity only; never layout properties. Decorative image motion
  uses `TweenAnimationBuilder`; no animation package is required.
- Tracking polling pauses when the app is backgrounded and resumes on foreground.
- Hover/press feedback must be visible but subtle; no bounce/spring excess.

## Anti-slop checklist

- No purple/indigo gradients, glow blobs, emoji, fake reviews, fake data, fake riders,
  invented balances, or placeholder prices.
- No overlapping widgets, clipped nav labels, hidden safe-area content, or sub-48dp taps.
- No “Order confirmed” for a plan that only created a subscription without collecting
  payment.
- No fabricated delivery slots or fallback `08:00` / `Morning 8-12`.
- No green tracking/navigation CTA.
- No stale money/ledger/order data without a visible stale label.

## Verification

- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter test`
- `flutter build web --release` + 360×800 / 390×844 mocked-API smoke for
  login/home/orders/tracking.
- `flutter build apk --release --target-platform android-arm,android-arm64` with the
  production Worker URL and Razorpay test key; enforce the 40,000,000-byte gate.
