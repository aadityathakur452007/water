# UX Redesign Research + Checklists (006-auth-flow build input)

Date: 2026-10-01 · Branch target: new `006-auth-flow` (from main) · Skills: ui-checklist, redesign, design-basics guardrails, hallmark
Locks carried forward: light mode, black #111 text/primaries, blue #0284C7 actions-only, no purple, no gradients, no emojis, 8px grid, 48px targets, Hindi-first copy.

## 1. Sources read (with dates)

| # | Source | URL | Read | Takeaway for Shodasha |
|---|--------|-----|------|----------------------|
| 1 | Flipkart DESIGN.md (mirror, updated 2026-05-08) | https://explainx.ai/designs/whyashthakker-design-md-templates-skills/flipkart/design-md (src: github.com/whyashthakker/design-md-templates-skills) | 2026-10-01 | Tokens: bg #FFFFFF, ink #212121, brand blue #2874F0, action orange #FB641B, yellow #FFE000; Roboto; radii 2–4px; thin borders not shadows; dense cards (price/discount/rating/delivery); search bar anchored in colored header; state = flat color shifts |
| 2 | Amazon iOS DESIGN.md + Expo companion | https://github.com/Meliwat/awesome-ios-design-md/blob/main/design-md/misc/amazon/README.md | 2026-10-01 | Navy #131921 nav + yellow #FF9900 single conversion color; search-anchored top nav; a11y labels on every commerce action; haptics (success on add-to-cart, selection on stepper/chips, error on failure) |
| 3 | Crafty Bay Flutter ecommerce (GetX+REST, full auth→payment flow) | https://github.com/mostafejur21/ecommerce (+ ShRudra88/e_commerce_crafty_bay_updated) | 2026-10-01 | Canonical screen order: Splash → Login → Complete Profile → OTP → Home → Categories → Product Details → Cart → Checkout → Payment WebView → Profile; `pin_code_fields ^8.0.1` for OTP; bottom price bar + button pattern |
| 4 | Flutter perf best practices (official docs) | https://docs.flutter.dev/perf/best-practices | 2026-10-01 | saveLayer/Opacity/ClipRRect cost; `const`, small setState scope, AnimatedBuilder child, RepaintBoundary targeted, cacheWidth images, isolates for CPU work, 16ms budget |
| 5 | Foresight Mobile 2026 tune-up (Impeller default, retired SkSL warm-up) | https://foresightmobile.com/blog/how-to-optimise-your-flutter-app | 2026-10-01 | No shader warm-up on Impeller; profile don't guess; async≠off-thread (Isolate.run); image memCache sizing (4K→thumb ≈100x RAM save) |
| 6 | freeCodeCamp DevTools jank guide (UI vs raster threads) | https://www.freecodecamp.org/news/how-to-fix-app-jank-profiling-flutter-apps-with-devtools/ | 2026-10-01 | Profile mode only; UI-thread = Dart/rebuilds, raster = GPU/effects; fix→re-measure loop |
| 7 | chdr.tech jank checklist + Samioda 60fps + flutterstudio + startdebugging | various (see browser history 2026-10-01) | 2026-10-01 | itemExtent/prototypeItem on lists; precache next images; no IntrinsicHeight in rows; Timeline.startSync coarse spans; anti-regression per-sprint profiling |
| 8 | pub.dev package pages | pub.dev/packages/{table_calendar,flutter_animate,cached_network_image,pin_code_fields} | 2026-10-01 | table_calendar 3.2.1 ✓; flutter_animate 4.5.2 ✓; cached_network_image 4.0.2 ✓; **pin_code_fields v10 needs Flutter 3.47/material_ui — we are on 3.44 → pin ^9.4.0** |

## 2. First-run flow synthesis (what best-in-class does)

Splash (logo + one trust line, ≤1.5s, no login wall) → branded Login (logo/image top, phone form below, guest-browse link preserved — our flow-1 unwalled prices) → numeric-only OTP (6 boxes, paste, 60s resend, attempt caps — our F2 already does this; package it in `pin_code_fields`) → Location permission + map-pin (OSM, empty-state-first: "Add your address" when none) + Notification permission (FCM uses) → Home with address-first header. Every handoff states what happens next (ui-checklist Submitting-a-Form + Verifying-Account).

## 3. Deliberate differentiation (NOT Amazon/Flipkart)

| They do | We do instead | Why |
|---------|---------------|-----|
| Infinite catalog, search-first | 2-SKU repeat machine, reorder-first | Water is replenishment, not discovery |
| Cart as holding pen | Sticky book bar + one-tap repeat | One thumb, <30s reorder |
| Order history = receipts | Repeat history = reorder buttons (per past order: "Order again", bulk detector N≥6, "new vs repeat" tags) | Retention is the product |
| Delivery = date promise | 30-min window slots + pause/skip (existing subs engine) | Windows are our reliability moat |
| Discount theater | Deposit ledger honesty (Rs 150 visible, refundable) | Trust over coupons |

## 4. Package picks (tech-selection: no random defaults)

| Package | Ver | Why this one (alternatives rejected) |
|---------|-----|--------------------------------------|
| table_calendar | ^3.2.1 | Delivery-date picker for recurring/custom schedules; bespoke calendar = weeks of a11y bugs (rejected) |
| flutter_animate | ^4.5.2 | Transform+opacity micro-motion (150ms press, sheet entries); raw AnimationControllers per screen = boilerplate + jank risk (rejected) |
| cached_network_image | ^4.0.2 | memCacheWidth + placeholder + error widget for map tiles/product art; raw Image.network over-decodes (rejected per §5) |
| pin_code_fields | ^9.4.0 | Numeric-only OTP boxes + paste; v10 REQUIRES Flutter 3.47 (we are 3.44) — pinned to 9.x deliberately |
| (existing) flutter_map/geolocator/razorpay_flutter | kept | No change; OSM stays keyless |

## 5. Performance rules (applied to every screen below)

P1 `const` everything static · P2 setState scoped to smallest widget (no list-wide rebuilds) · P3 ListView.builder + itemExtent, never Column-for-lists · P4 images decoded at display size (cacheWidth/memCacheWidth) + precache next · P5 no Opacity-in-animation (use opacity-baked colors/FadeTransition), no full-screen blur, ClipRRect only on photos · P6 RepaintBoundary ONLY on animated islands (stepper value, shimmer) · P7 JSON/parse off build methods (cache derived lists) · P8 measure in `--profile` on device before/after (DevTools frames chart, UI-vs-raster call).

## 6. Per-screen checklists (ui-checklist applied)

### S1 Splash
- [ ] Logo + one trust line (RO+UV • Lab-tested), ≤1.5s, no login wall
- [ ] Error: backend unreachable → still enters guest home (prices unwalled)
- [ ] Happy: warm start skips splash when session restores
- [ ] Limit: no network calls block first frame (defer catalog fetch)

### S2 Login (branded: logo/art top, form below, guest link)
- [ ] Phone field: numeric keyboard, 10-digit, focus-loss error text (not color-alone)
- [ ] Button states: disabled-until-valid (50%), loading spinner, error shake text
- [ ] Guest link visible without scrolling (flow-1 preserved)
- [ ] Error: airplane/offline → offline banner + retry (States.md)
- [ ] Limit: no passwords, no social buttons v1 (phone-OTP only per contract)

### S3 OTP (numeric-only, `pin_code_fields`)
- [ ] 6 boxes, numeric keyboard only, SMS autofill + paste, masked +91 number shown
- [ ] 60s resend timer, 5-attempt force-resend, expired-code path with exact copy
- [ ] Happy: correct code → session saved → lands on location step (first run) else home
- [ ] Error: wrong code (attempts left), expired, rate-limited 429 + Retry-After
- [ ] Limit: no auto-submit before 6 digits; TalkBack labels per box

### S4 Location + Notification permission → map-pin
- [ ] System permission first; denied → manual map-pin path (never dead-end)
- [ ] First-run empty state: "Add your address" card (user owns zero addresses)
- [ ] OSM pin: drag-under-pin, locate button, confirm → saves lat/lng (0,0 rejected with copy)
- [ ] Notification ask AFTER location, with reason line (order/delivery alerts)
- [ ] Error: tiles offline → cached tiles + retry; locate timeout → manual pin copy

### S5 Home (storefront, ADR-029 as built)
- [ ] Address bar reflects default pin; Change → address list
- [ ] Search filters 2 SKUs with count + zero-result guidance (honest scope)
- [ ] Photo cards: image/name/price/stepper; tap → detail; stepper taps don't open detail
- [ ] Sticky bar total = water + deposit live; disabled state copy when N=0
- [ ] P2/P3: cards const-friendly, builder lists only
- [ ] Limit: container photo is 20l.jpg crop until real asset lands

### S6 Product detail buy-box
- [ ] Facts: description, tap vs no-tap, deposit/cap/hours; related-SKU cross-link
- [ ] Delivery-type chips with icons (once/calendar-repeat) — calendar opens for custom dates
- [ ] BUY applies qty+type, feedback (sheet closes → checkout opens), no double-tap double-order (idempotency key minted once)
- [ ] Error: N=0 impossible (min 1 in sheet); tanker N>10 → vendor-call sheet

### S7 Stepper checkout (multi-step: 1 Address → 2 Schedule → 3 Pay)
- [ ] Step indicator (1-2-3), back preserves inputs, per-step validation before Next
- [ ] Step 2 schedule: once → window slots (live capacity); recurring → calendar dates (table_calendar) + pause/skip explainer
- [ ] Step 3 pay: UPI/COD chips, COD caps messaging, processing row, error box (code→Hindi copy map), no raw status numbers
- [ ] Happy: server id returned; STALE_QUOTE retried once silently
- [ ] Perf: windows fetch off first frame; slot chips const; P8 profile the sheet open

### S8 Confirmation
- [ ] Server-minted id, window, amount, rider-pending note; primary Track order; sub shortcut for recurring
- [ ] WhatsApp appears ONLY as bill-share link (never post-purchase primary)
- [ ] Error: verify-lag note ("confirm ho raha hai") when gateway succeeded but webhook pending

### S9 Orders history (repeat-first, our differentiator)
- [ ] Past orders as reorder cards: items summary, total, "Order again" one-tap, repeat/new tags, bulk N≥6 badge
- [ ] States: skeleton → list → empty ("pehla order") → error + retry; 60s poll only when FCM dead (contract Finder-C7)
- [ ] P3: builder + itemExtent; bill lines memo, not recomputed per frame

### S10 Component checklist (every new component)
- [ ] Happy path renders with const constructor where static
- [ ] Error/empty/loading/offline states exist (no blank screens)
- [ ] 48px targets, 8px rhythm, TalkBack/semantics labels, no color-alone meaning
- [ ] No Opacity animation, no full-screen blur, images sized at display size
- [ ] Hindi copy reviewed (no emoji, one verb per action)

## 7. Next-build spec (006-auth-flow, needs APPROVAL)

1. Splash + branded login + `pin_code_fields` OTP (numeric-only) + permission-gated location/map-pin first-run.
2. Stepper checkout (Address → Schedule → Pay) with icon delivery-type + table_calendar dates for recurring.
3. Repeat-first order history (reorder buttons, repeat/new tags, bulk badge).
4. Packages: table_calendar, flutter_animate, cached_network_image, pin_code_fields ^9.4.0 (NOT v10 — Flutter 3.44).
5. Perf: apply P1–P8 per screen; `flutter analyze` 0 + full tests green + `--profile` DevTools pass on home scroll/sheet open before merge.
