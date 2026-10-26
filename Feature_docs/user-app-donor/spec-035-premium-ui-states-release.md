# Spec 035 - Premium states, performance, and release pipeline (donor customer app)

- **Status:** APPROVED 2026-10-23
- **Date:** 2026-10-23
- **Branch:** `035-premium-ui-states-release` (from `034-auth-password-delivery-otp`, HEAD `20cedff`)
- **Scope:** `apps/user_app_donor`, `.github/workflows/*`, donor Android manifest/build config
- **Out of scope:** `apps/user_app`, vendor/admin/legacy apps, backend business logic, Cloudflare deploy, `main` commits, push

## Approved owner decisions

1. **Release identity:** third side-by-side APK; keep `com.shodasha.shodasha_donor`; user-facing label
   becomes `Shodasha`; publish `shodasha-donor-vX.Y.Z.apk`. Existing user/vendor release legs stay intact.
2. **Notifications:** in-app notification center only. No `POST_NOTIFICATIONS`, no FCM, no background
   push. Every promised in-app tap must work.
3. **Artifact:** 2-ABI APK (`android-arm` + `android-arm64`), expected ~38 MB, enforced gate at
   40,000,000 bytes.
4. **Scope:** every P0/P1 from the five audits, targeted P2 polish, shared components, screen splits,
   CI, safe caching/coalescing, manifest permissions, and size gate.

## 1. Why

Five read-only audits (auth/home/shell, orders/tracking/returns, booking/address/subscriptions,
wallet/profile/support, and engineering/CI) found:

- **12 release-blocking items** (7 in customer flows, 5 in pipeline/packaging)
- **80+ P1 items** across state truth, money safety, interaction safety, contrast, tap targets,
  duplicate requests, and dead ends
- A coherent visual world worth keeping: slate ground, white cards, teal structure,
  solar highlights, green money CTAs, real server-fed prices, no fake content

The problem is not the palette. It is unreliable edges, inconsistent state grammar, two competing
token systems, oversized screen files, missing shared state components, and no donor leg in the
working GitHub pipeline.

## 2. Goal

Make every donor screen feel premium and behave truthfully under every state in `States.md`,
while keeping the app small, fast, accessible, and connected to the real Worker API.

Success means:

1. No known P0/P1 defect remains in the audited screens.
2. Every screen has explicit loading, empty, success, stale, offline, 4xx, 5xx, 401,
   validation, submitting, retry, and refresh states.
3. One token system and one shared state/component grammar across the app.
4. The app builds and runs from the same GitHub workflow family as the existing customer app,
   without breaking the existing user/vendor jobs.
5. A release artifact is <= 40 MB, targets the production Worker, and carries only permissions
   the app actually uses.
6. Repeated tab/screen visits do not duplicate money reads or network calls; safe reads are
   coalesced or cached; polling pauses when the app is backgrounded.

## 3. Non-goals

- No palette replacement, no purple/indigo gradients, no emoji, no new decorative font,
  no AI-slop illustration set, no fake riders/PINs/balances.
- No new backend feature, no push-notification backend, no Firebase.
- No change to the retired customer OTP contract, delivery-code lifecycle, or password auth.
- No switch of the production customer APK unless the owner explicitly chooses replacement.
- No Play Store upload, no Cloudflare deploy, no push to remote, no `main` commit.
- No full-screen rewrite; preserve the donor screen grammar and flows.

## 4. Decisions locked before this spec

| Decision | Value |
|---|---|
| Visual world | Refine incumbent donor world: slate ground, white cards, teal structure, solar highlights, green money CTAs |
| Money law | Green is only for Book/Pay/Confirm; tracking and navigation use teal |
| Auth | Mobile + password; no customer OTP; no Firebase |
| Delivery code | 24h lifecycle from 034; no change to server semantics |
| Data truth | Server is authority; no client money math; stale data must be labelled |
| App boundary | Donor app only; previous user app untouched |
| State source | `States.md` plus the five 035 audit reports |
| Minimum target | 48dp interactive target; WCAG AA contrast for normal text |

## 5. Owner decisions required

These are the only open product decisions. Recommended defaults are first.

1. **Release identity**
   - A (recommended): add donor as a **third side-by-side APK**; keep `com.shodasha.shodasha_donor`;
     change the user-facing label from `Shodasha Donor` to `Shodasha`; publish
     `shodasha-donor-vX.Y.Z.apk`.
   - B: make donor the production customer app, replace the old user APK in release; requires
     matching app id/signing and an uninstall/migration plan.
   - C: CI compile/test only; no donor release artifact yet.

2. **Notification scope**
   - A (recommended): in-app notification center only; fix dead notification taps; **no**
     `POST_NOTIFICATIONS`, no FCM, no background notification promise.
   - B: local notifications while the app is running; adds `POST_NOTIFICATIONS` and a local
     notification dependency.
   - C: full push via FCM/Worker; separate feature, new backend and dependency.

3. **Artifact strategy**
   - A (recommended): release APK for `android-arm` + `android-arm64` (~38 MB expected), CI gate
     at 40,000,000 bytes.
   - B: arm64-only APK (~21 MB expected) plus AAB for Play; drops 32-bit installs.
   - C: universal APK (measured 58.5 MB on the previous app) with no size gate; not recommended.

4. **Scope depth**
   - A (recommended): fix all P0/P1, targeted P2 polish, shared components, screen splits, CI,
     caching, permissions, size gate.
   - B: P0 + CI only.
   - C: A plus full P2 redesign of every screen; larger, slower, higher regression risk.

## 6. Product surfaces and flows

| Surface | Primary flow | Critical states |
|---|---|---|
| Auth | Open app -> restore session -> sign in/create -> home | restore, expired, invalid, rate-limited, offline, 5xx, submitting |
| Home | See last address/rates -> instant order or subscribe | address loading/error/empty, stale rates, no catalog, offline |
| Booking sheet | Qty -> schedule -> quote -> address -> payment -> confirm | quote loading/stale/error, pay busy, UPI unavailable, order created/payment pending, duplicate submit |
| My Orders | Active + closed orders -> track/bill | empty first order, loading, stale, pagination, action busy |
| Tracking | Status -> delivery code -> rider/support -> delivered/rating | code active/assigned/expired/locked/unavailable/used, reissue cooldown, poll, background, replay |
| Subscriptions | List -> build plan -> pause/resume/skip/cancel -> dues | guest, no address, estimate, cap 10, submit lock, UPI link, stale |
| Wallet | Balance/dues/held jars -> pay dues/return/history | zero vs empty, dues, held cap, stale, refresh, 401 |
| Addresses | List -> add/edit -> map pin -> serviceability -> save | GPS denied/off, no default pin, map failure, dirty guard, serviceability |
| Support | Help -> reason -> order -> submit -> list | no order id, 24h/72h window, invalid, sending, 404/409, external launch |
| Profile | Identity -> edit -> logout | stale, save failure, dirty, logout busy, session expired |

## 7. Visual direction

### 7.1 Tokens (one source of truth)

Keep `ShodashaTheme` as the single token source. Remove the duplicate `AppColors` palette over
time, or make it a compatibility facade that references `ShodashaTheme`. New/updated tokens:

| Token | Value | Use |
|---|---|---|
| `bg` | `#F8FAFC` | Page ground |
| `surface` | `#FFFFFF` | Cards/sheets |
| `ink` | `#0F172A` | Primary text |
| `muted` | `#64748B` | Secondary text (AA on white) |
| `border` | `#E2E8F0` | Hairline |
| `teal` | `#0D9488` | Brand structure, active states |
| `tealDark` | `#0F766E` | Filled teal surfaces, icon buttons on teal |
| `tealDeep` | `#115E59` | App bars/deep structure |
| `green` | `#16A34A` | Money CTA fill only |
| `greenDark` | `#15803D` | Money CTA fill where white label needed |
| `solar` | `#FACC15` | Badge/highlight, never CTA |
| `danger` | `#B91C1C` | Error text/actions |
| `successDark` | `#047857` | Success text/icons |
| `blue` | `#0284C7` | Links/info text only |
| `solarTint`, `greenSoft`, `tealTint` | existing | Status grounds |

Rules:

- No hardcoded hex in screens. Every color comes from `ShodashaTheme`.
- White text only on `tealDeep`/`tealDark`/`greenDark`/`danger`; never white70.
- 11px text is minimum for microcopy; body is 14px; titles 16/18/22/28.
- 48dp minimum for every tappable element, including icon buttons and card CTAs.
- 4/8/12/16/24/32 spacing scale; 16dp screen gutter; 24dp section gap.
- Cards: 16dp radius, 1px border, no elevation, 16dp internal padding.
- Bottom sheets: 28dp top radius, max 90% height, scroll-controlled, safe-area bottom,
  sticky footer CTA, no dismiss while a money mutation is in flight.
- Typeface: platform default (no new font asset). No all-caps body copy; status labels are
  sentence case.
- No purple, indigo, neon gradients, glassmorphism, emoji, fake avatars, or decorative shadows.

### 7.2 Laws applied

| Law | Application |
|---|---|
| Jakob | Keep standard mobile patterns: bottom nav, back, sheets, pull-to-refresh, system dialogs |
| Fitts | 48dp targets; primary CTA full-width at thumb reach; destructive actions separated |
| Hick | One primary action per state; progressive disclosure in booking; no duplicate CTAs |
| Miller | Chunk booking into Qty -> Schedule -> Review -> Pay; max 5 nav destinations |
| Proximity/common region | Group label + value + action in one card; separate sections with 24dp |
| Aesthetic-usability | Calm surfaces and clear hierarchy reduce perceived effort on money flows |
| Von Restorff | Exactly one green money CTA; solar reserved for delivery-code emphasis |
| Doherty | Immediate pressed/busy feedback; skeletons for >300ms loads; no silent taps |
| Peak-end | Strong confirmation, delivery-code reveal, and delivered/rating closure |
| Serial position | Put the delivery code and primary action at the top/bottom of tracking |
| Tesler | Absorb complexity: pickers, defaults, validation, and server truth where possible |
| Recognition over recall | Show order date/window, address label, full order id picker, saved UPI |
| Progressive disclosure | Advanced plan options and optional refund UPI stay collapsed until needed |

### 7.3 Interaction and motion

- Press: `InkWell`/`Material` ripple, visible disabled and busy states.
- Sheet enter: 180ms fade + 8dp slide; exit 150ms; no bouncing loops.
- Status/countdown: 150ms fade or scale only; no layout animation.
- Respect `MediaQuery.disableAnimations`; set durations to zero when true.
- Maximum one implicit animation per state change; no perpetual shimmer except a real skeleton.
- Keyboard: `adjustResize`, `SingleChildScrollView`, sticky CTA above keyboard, focus order logical.
- Haptics: only on add-to-cart/confirm if already available; no new dependency.

### 7.4 State grammar

Every async screen uses the same state model:

```
initial -> loading(skeleton) -> loaded | empty | stale | error
                              -> refreshing (content retained)
                              -> submitting (modal/CTA locked)
                              -> success (confirmation + next action)
```

- `NETWORK` -> global offline strip plus inline retry; never a 5xx offline banner.
- `5xx` -> "Server problem" + retry; keep cached content if present.
- `401/403` -> session-expired state with `Sign in`; preserve user intent where possible.
- `429` -> disable submit with live countdown; show `Retry-After`.
- `4xx` -> inline field/server message; no generic wall when a specific message exists.
- Cached content -> always visible with a `Showing last update` banner and retry.
- Empty first order -> one `Book water` CTA; not "No active deliveries" alone.

## 8. Wireframes (component trees)

### 8.1 Home

```
Scaffold
  SafeArea
    Column
      HomeTopBar (tealDeep, safe area)
        address row (loading/error/empty/selected)  [48dp]
        notification [48dp]  search [48dp]  cart [48dp]
      OfflineStrip (conditional, NETWORK only)
      RefreshIndicator
        ListView (maxWidth 560, 16 gutter)
          GreetingBlock (24)
          ModeSelectionCards (2 cards, 16 gap, InkWell)
          SectionHeader("Featured") (24 top)
          FeaturedProducts (horizontal, real prices, 48dp CTA)
          LivePurityCard
          SupportCard (label SUPPORT, opens support)
      NavigationBar (M3, 64 + safe area)
```

### 8.2 Booking sheet

```
ModalBottomSheet (isScrollControlled, 90% max, sticky footer)
  SheetHeader (close disabled only while paying)
  StepRail: Qty -> Schedule -> Review -> Pay
  Scroll body
    QtyStep: two product rows + Stepper (48dp)
    ScheduleStep: day chips + slot list; no preselected date; recap from server slot
    ReviewStep: address card, items, quote total, payment mode, legal note
    PayStep: quote status, UPI/COD, stale-quote banner
  Sticky footer: Back | Primary CTA (green only for Pay/Confirm)
  States: quote loading/error/stale, paying lock, order-created-payment-pending,
          UPI unavailable, duplicate-submit guard, 401 sign-in
```

### 8.3 Tracking

```
Scaffold
  AppBar (tealDeep, back, support)
  RefreshIndicator
    ListView
      HeaderCard: status pill, order id, address label, ETA/window
      DeliveryCodeCard (directly under header; solar emphasis)
        active countdown / assigned / expired / locked / unavailable / used
        reissue CTA + cooldown / replay outcome
      TrackerTimeline
      RiderCard (call only when phone non-empty; WhatsApp)
      BillSummary
      ActionRow (Cancel / Reschedule; Column below 380dp)
      Delivered: rating, proof, help
      Rejected: support/refund
  StaleBanner when poll failed with retained data
```

### 8.4 Subscription

```
Scaffold
  AppBar
  Body
    GuestState -> Sign in
    Empty -> Plan builder CTA
    DuesAlert (Pay rupees CTA above wallet/hero)
    PlanList -> PlanCard (status, next delivery, qty, pause/resume/skip/cancel)
    StaleBanner
  PlanBuilderSheet
    Qty (cap 10) -> mix -> address -> first delivery total
    sticky footer: Create plan; all inputs locked while submitting
```

### 8.5 Wallet, support, profile

```
Wallet: DuesAlert -> BalanceCard -> HeldJarsCard (return only if held>0)
        -> PaymentHistory -> ReturnSheet (lock while busy, cap at held)
Support: ContactActions (WhatsApp + call) -> ComplaintCta -> ComplaintList
         -> ComplaintSheet (order picker, reason with 24h/72h, counter, lock while sending)
Profile: IdentityCard -> EditSheet (dirty guard) -> Preferences -> Logout (busy)
```

## 9. Workstreams and requirements

### WS1 - Foundation: tokens, shared UI, state model

Files: `lib/core/theme.dart`, `lib/core/constants/app_constants.dart`,
new `lib/shared/ui/*`, `lib/shared/state/*`.

Required:

1. One token source; `AppColors` becomes a facade or is removed. No screen-level hex.
2. Add semantic tokens: `tealDeep`, `greenDark`, `danger`, `successDark`, `warning`.
3. Shared primitives:
   - `AppButton` (primary money, secondary teal, text link; 48/52dp; busy/disabled)
   - `AppIconButton` (48dp, tooltip, semantics)
   - `AppCard` (16 radius, border, 16 padding)
   - `AppSheet` (scroll-controlled, safe area, sticky footer, dismiss policy)
   - `AsyncStateView` (loading skeleton, empty, error, stale, content)
   - `OfflineBanner` / `StaleBanner`
   - `StatusPill` (icon + label + semantic color; never raw enum)
   - `SectionHeader`
   - `AppTextField` (label, helper, error, counter, autofill, keyboard type)
   - `AsyncCta`? Only if used by at least two screens; otherwise keep local.
4. `AppMotion` helper for 150-220ms and reduced-motion.
5. Shared `spacing` constants (4/8/12/16/24/32) and `maxContentWidth = 560`.

Ponytail rule: create a primitive only on its second real use. Do not build a speculative
component library.

### WS2 - Auth, home, shell

Fix every P0/P1 from the auth/home/shell audit:

- Logout: wipe local session/prefs first, then best-effort revoke with a 3s timeout; busy state.
- Login: disable submit during rate-limit countdown; early-return; fix busy contrast.
- Demo/profile edit busy states: full-opacity fill + white spinner.
- Home: wire cart to review/checkout, never `_instantOrder` when empty.
- Home support card: open support and label `SUPPORT`.
- Address top bar: render loading/error/empty/selected, not "ADD A DELIVERY ADDRESS" while loading.
- Mode copy: replace "45 mins" with the real fixed window.
- Notifications: every tile with promised detail gets `onTap` + chevron; fix date contrast.
- Contrast: white70 -> white on teal; profile app bar -> `tealDeep`; logout -> `danger`.
- Tap targets: top-bar circles 48dp; product CTA 48dp; product tag >=11px.
- Sheets: demo/profile water-quality scrollable; max height; safe area.
- Product cards: InkWell/semantics/pressed/focus, not raw GestureDetector.
- Stale rates: show banner when `rates != null && error != null`.
- Shell: use M3 `NavigationBar` (64dp, 12px labels) and preserve lazy tab mounting.
- Search sheet: scrollable, keyboard inset, real empty/loading/error states.

### WS3 - Orders, tracking, returns

- **P0 return sheet**: `isDismissible:false`, `enableDrag:false`, `PopScope` while POST in flight;
  one request per sheet; no duplicate pickup/refund.
- **P0 reschedule**: no default slot; require explicit date + slot; show weekday/date.
- Build next 7 serviceable days; day selector.
- Map `delivery_address` into `addressLabel`; fallback line1/city.
- Add `partial_dues`; never show full total as due.
- User-facing status labels; no raw enum.
- Card CTA 48dp; tracking CTA teal, not money green.
- Tracking action row stacks below 380dp.
- Delivery code directly under header; all six states; reissue cooldown from `Retry-After`.
- Pagination error isolated from refresh error; clear on successful retry.
- Bill: real payment line or honest `paymentStatus`/due, never `—` when paid.
- Closed card: primary Bill + secondary View details; tracking remains reachable.
- Rated order: no dead-end rating sheet; read-only stored rating.
- Rejected: support/WhatsApp/refund path.
- Call only when phone non-empty; otherwise "number unavailable".
- Returns: map 429/422 to specific messages; lock while busy; cap at held jars.
- First-order empty state with `Book water`.
- Dates on closed/history rows.

### WS4 - Booking, addresses, subscriptions

- **P0 map**: no New Delhi default; no selected pin until map tap or successful GPS fix;
  disable Save until explicit selection.
- **P0 dues**: launch returned UPI link; add Copy link and Wallet handoff; actionable failure.
- **P0 subscription truth**: no "first cycle paid online"/"Order confirmed" without payment;
  copy derives from actual payment state.
- Booking: single-flight Next guard, validate destination step; no skipped schedule.
- Recap uses selected server slot, not `Morning 8-12`.
- Slot loading does not block dismissing; only paying blocks close.
- After order creation show "Order placed - confirming payment", not "Placing".
- 401 during checkout -> Sign in preserving quote.
- Address serviceability: unchecked/checking/serviceable/notServiceable/unknown;
  invalidate on pincode edit; block save; no step-jump bypass.
- Dirty address form: `PopScope` discard confirmation; `enableDrag:false` while dirty.
- Plan builder: cap 10, snapshot idempotency key, lock inputs/close while submitting.
- Signed-out/no-address blockers get Sign in / Add address CTAs.
- Cancel: validate UPI or prefill saved; no blank refund id.
- First-run sheet icon not stretched.
- Quote sheet scroll-controlled, safe area, sticky CTA.
- Rename "Total today" to "First delivery total" or "Due on first delivery".

### WS5 - Wallet, profile, support

- Support: delivered-order picker with full id copy + prefill; manual 32-hex fallback.
- Support validation: touched on edit/blur; visible error; counter.
- Support reason: explicit selection; 24h/72h label; selected order deadline.
- Support actions: WhatsApp + tappable `tel:`; expired dialog includes both.
- Support errors: 404/409 specific; preserve safe server message.
- Complaint sheet: lock while sending; `PopScope`; capture messenger before pop.
- Complaints list: pull-to-refresh; stale/error banner with retained items.
- Profile: clear `ProfileStatus.error` after successful PATCH.
- Logout: busy + "Logging out..."; local wipe first.
- Wallet: keep cached ledger on refresh error with stale banner; full error only if no snapshot.
- Payment history: preserve cached rows; stale banner; scrollable.
- Return empty jars: hide/disable at zero held; cap quantity at held.
- Dues: `Pay rupees` alert above deposit hero.
- Edit profile: dirty guard; no dismiss while saving.
- Contrast fixes across wallet/profile/support.

### WS6 - Network, caching, performance

1. `ApiClient` single-flight key includes method + URL + **token fingerprint**; `clearInflight()`
   on auth boundary/login/logout.
2. Add a small opt-in TTL read cache for `GET /catalog`, `GET /windows`,
   `GET /serviceability` (max 60s; no cache for money/order/ledger/delivery-code).
   Stale cached reads must show a stale label.
3. Add 401 refresh once:
   - `POST /auth/refresh` with stored refresh token + device id;
   - persist rotated tokens; retry the original request once;
   - on failure force logout with session-expired notice;
   - never call the refresh endpoint recursively.
4. Remove duplicate ledger calls: shell init + wallet tab must not both fetch the same ledger.
5. Parallelize independent subscription reads with `Future.wait`.
6. Pause tracking polling when app is backgrounded; resume on foreground.
7. Avoid duplicate route pushes (orders/tracking) with in-flight guards.
8. Keep `IndexedStack` lazy mounting; use `const` widgets; avoid whole-screen rebuilds.
9. Do not cache wallet, orders, delivery code, session, or complaint submissions.
10. Release base URL: pass `SHODASHA_API_BASE=https://water.adityathakur452007.workers.dev/v1`;
    fail release builds if the base is loopback.

### WS7 - Android permissions and manifest

Current: `INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`.

Required:

- Keep fine + coarse location; no background location.
- Add `<uses-feature android:name="android.hardware.location" required="false"/>` and
  `android.hardware.location.gps` required=false.
- Add package-visibility `<queries>` only for intents the app launches: `tel`, `mailto`,
  `https`, and `upi` if the UPI link is launched externally.
- Debug manifest: `android:usesCleartextTraffic="true"` for local API only.
- Release manifest: no cleartext; HTTPS only.
- Add `POST_NOTIFICATIONS` **only if** owner chooses local notifications (decision 2B/2C).
  If A, add nothing; in-app notifications need no permission.
- No `ACCESS_BACKGROUND_LOCATION`, `SCHEDULE_EXACT_ALARM`, contacts/SMS/phone-state.
- Label: `Shodasha` (decision 1A) or owner-selected production identity.

### WS8 - CI, release, size

Minimal, non-breaking pipeline change:

1. `ci.yml`: add donor to matrix:
   ```yaml
   - app: donor
     dir: apps/user_app_donor
     label: Shodasha Donor (customer parity)
   ```
   Existing user/vendor legs unchanged. Donor gets analyze, test, debug APK, artifact.
2. `release.yml`:
   - If 1A: add donor to build matrix with prod API define and `--target-platform
     android-arm,android-arm64`; add donor download, existence check, rename, checksum, body row,
     and `files:` entry.
   - If 1C: add a separate `build-donor` preflight job only; do not attach to release.
   - Keep existing user/vendor entries and names intact.
3. Size gate: after donor build, `test "$(stat -c%s ...)" -le 40000000`; fail with the measured size.
4. Production define: donor build must pass the Worker URL; no localhost in release.
5. Signing: use owner keystore secrets when provided; do not silently ship a new debug certificate
   as an upgrade. If secrets are absent, CI debug build still passes; release donor step must fail
   or be clearly non-production. Owner action documented.
6. R8/minify stays on; verify Razorpay reflection with a release smoke.
7. Remove unused dependencies only after verifying usage:
   - `flutter_animate` (one decorative use) -> built-in AnimatedOpacity/Scale.
   - `permission_handler` (only for `openAppSettings`) -> `geolocator` has `openAppSettings`.
   - Keep `table_calendar`, `flutter_map`, `geocoding`, `razorpay_flutter` unless a safe
     replacement is proven.
8. Expected size:
   - previous universal: 58,553,018 bytes (measured)
   - 2-ABI estimate: ~38 MB
   - arm64-only: ~21 MB
   - split-per-abi: ~19/21/23 MB
   - Gate: 40,000,000 bytes.

## 10. File split plan

Do not create a flat `components/` dump. Split by feature and promote only shared primitives.

```
lib/shared/ui/
  app_button.dart
  app_card.dart
  app_sheet.dart
  app_text_field.dart
  async_state_view.dart
  offline_banner.dart
  section_header.dart
  status_pill.dart

lib/features/auth/widgets/
  auth_header.dart
  auth_form.dart

lib/features/home/widgets/
  home_top_bar.dart
  home_address_line.dart
  home_actions.dart

lib/features/orders/widgets/
  tracking_header.dart
  delivery_code_card.dart
  tracker_timeline.dart
  tracking_actions.dart
  reschedule_sheet.dart

lib/features/booking/widgets/
  booking_sheet_header.dart
  booking_step_schedule.dart
  booking_step_review.dart
  booking_footer.dart

lib/features/addresses/widgets/
  address_card.dart
  address_form_sheet.dart
  serviceability_row.dart

lib/features/subscriptions/widgets/
  plan_card.dart
  dues_alert.dart
  plan_builder_footer.dart

lib/features/support/widgets/
  complaint_sheet.dart
  complaint_card.dart
  support_actions.dart

lib/features/wallet/widgets/
  wallet_summary.dart
  payment_row.dart
  return_sheet.dart
```

Screen targets:

| File | Current | Target |
|---|---:|---:|
| `booking_sheet.dart` | 1,584 | < 700 after step widgets |
| `tracking_screen.dart` | 1,503 | < 650 after tracking widgets |
| `address_screen.dart` | 1,446 | < 650 after form/card extraction |
| `subscription_screen.dart` | 1,187 | < 650 after plan/dues widgets |
| `orders_controller.dart` | 1,182 | split mapper/model/repository if low risk |
| `support_screen.dart` | 854 | < 500 after complaint widgets |
| `login_screen.dart` | 734 | < 500 after form/header |

Rule: no behavior change during extraction; each split must keep tests green.

## 11. Acceptance criteria

### Customer

- [ ] Every P0 in section 1 is fixed and covered by a test or deterministic widget check.
- [ ] Every P1 in the five audits is fixed or explicitly recorded as accepted P2 with reason.
- [ ] No dead-end action: every promised tap does something; every blocked state offers recovery.
- [ ] No false money copy; no green tracking CTA; no hidden stale data.
- [ ] 48dp targets, AA contrast, scrollable sheets, safe areas, keyboard insets.
- [ ] No purple/indigo gradients, emoji, fake data, hardcoded colors, or duplicate token system.
- [ ] First-order, first-address, zero-held, zero-dues, rated, rejected, expired-code states exist.
- [ ] App resumes cleanly; tracking poll pauses in background.

### Engineering

- [ ] `dart format lib test` clean.
- [ ] `flutter analyze` zero issues.
- [ ] `flutter test` all green; new tests cover P0 regressions.
- [ ] `flutter build apk --release --target-platform android-arm,android-arm64` succeeds.
- [ ] APK <= 40,000,000 bytes.
- [ ] Manifest merged permissions match section WS7; no unused dangerous permission.
- [ ] Donor CI leg green; existing user/vendor CI legs unchanged.
- [ ] Release workflow builds donor without breaking existing APK jobs.
- [ ] Local backend E2E passes against `workers/api` for auth/order/tracking/reissue.
- [ ] Web-server smoke renders login/home/orders/tracking without overflow at 360dp and 390dp.
- [ ] No backend regression: existing `workers/api` tests stay green.

## 12. Verification plan

1. Static: format, analyze, grep for hardcoded colors/emoji/purple, manifest inspection.
2. Unit/widget: new `state_components_test.dart`, `p0_regression_test.dart`,
   `manifest_contract_test.dart` (if feasible), updated existing tests.
3. Local API: start uvicorn on 8787 with a fresh DB; run auth register/login, quote, order,
   tracking, delivery-code reissue, PoD replay; stop processes.
4. Web smoke: `flutter run -d chrome --web-port=8099` with local base; inspect 360/390 widths.
5. Release: build 2-ABI APK; inspect size, signature, manifest, API base string.
6. CI: run the workflow syntax check locally if available; do not push.

## 13. Risks and owner actions

| Risk | Mitigation |
|---|---|
| Refactor regressions | Extract without behavior changes; tests per workstream; keep old paths until green |
| Parallel agents conflict | Foundation first; then disjoint feature workstreams; engineering on separate files |
| Release signing | Owner must provide keystore secrets; no silent debug-cert upgrade |
| Production Worker not live | Verify `GET /catalog` and auth smoke; fall back to local only in dev |
| APK size | 2-ABI + dependency cleanup + release size gate; no new assets/fonts |
| Notification ambiguity | Decide 2A/2B/2C before implementation; no fake notification promise |
| Time | Scope 4A is large; all workstreams can run in parallel after foundation, but gates are sequential |

## 14. Approval

**Approved by the owner on 2026-10-23.** Approved choices: third side-by-side APK,
in-app notifications only, 2-ABI APK with a 40 MB gate, all P0/P1 plus targeted P2.

Implementation order:

1. Commit this spec on `035-premium-ui-states-release` (no push).
2. Implement WS1 first; run format/analyze/tests.
3. Run WS2-WS8 in parallel agents on disjoint files.
4. Run full verification and context sync (`progress-tracker`, `flow`, `decision`,
   `ui-context`).
