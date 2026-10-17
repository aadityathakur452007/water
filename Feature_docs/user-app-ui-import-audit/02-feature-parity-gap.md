# 02 — Feature Parity + Gap Matrix: production user app ↔ friend's restyled UI

**Purpose.** Decide what survives when the friend's UI skin (`shodasha-friend-ui`, local copy at
`C:\Users\Hp\AppData\Local\Temp\opencode\shodasha-friend-ui`) is re-wired onto the production
user app's backend and logic (`apps/user_app`). **Truth source is always the user app** — the
friend's UI is a demo-quality restyle with a hardcoded data layer (singletons, no real API).

**Legend for coverage:** ✅ FULL = behavior present · ◐ PARTIAL = visual-only or wrong rules ·
⚙ STATIC = hardcoded singleton data, no backend · ❌ MISSING = feature absent.

**Key structural fact.** The friend's app has **no API client at all** — `lib/shared/providers/app_providers.dart`
exposes `CartProvider`; `lib/features/orders/data/order_service.dart` holds a hardcoded `OrderItem`
list behind an `OrderStateNotifier` singleton; `lib/main.dart:6-14` only initializes Firebase.
Everything money/order related is in-memory theater.

**Money-unit note.** Production stores money as integer **paise** (`booking_controller.dart:31` `kCodCapPaise = 200000`);
the friend's UI uses **double rupees** (`subscription_service.dart:35` `pricePerDrop 65.0`, `_pricePerCan = 65` in
`cart_checkout_sheet.dart`). Every imported price widget needs a unit pass, not just a value swap.

**Architecture deltas the import must reconcile**

| Dimension | Production `user_app` | Friend's UI | Consequence for import |
|-----------|----------------------|-------------|------------------------|
| Data layer | `core/api_client.dart` (591 lines): typed methods, error envelope, token | Singletons (`OrderStateNotifier`, `AddressStateService`, `PlantTelemetryNotifier`) + `CartProvider` | Every widget call site re-binds to ApiClient methods |
| Money units | integer paise (`kCodCapPaise`) | double rupees | One conversion + formatting pass; never mix units |
| Cart model | none — booking stepper with sticky live total (`booking_sheet.dart`) | persistent `CartProvider` | Don't adopt; one money-truth source |
| Theming | our `core/theme.dart` bodies | `app_constants.dart` + `app_theme.dart` (Material2-forced, `main.dart:32`) | Port their tokens into our theme file, keep our handling |
| Order state | server statuses via `orders_controller.dart` + idempotent mutations | local status enum mutated on tap | Chips stay; mutations become API calls |
| App boot | guest → Home, register when needed | login-wall first (`main.dart:34`) | Re-order boot for guest browsing |

---

## 1. Production feature checklist (with endpoints) + friend's-UI coverage

| # | Feature | Our app (truth source) + endpoint | Friend's UI coverage | Verdict |
|---|---------|-----------------------------------|----------------------|---------|
| 1 | Register (name + email + phone) | `features/auth/name_number_screen.dart` + `features/auth/auth_controller.dart` → `POST /v1/auth/user/register`; token stored via `core/auth_impls.dart` | `features/auth/presentation/login_screen.dart` (546 lines): phone + 4-digit OTP, 30s resend timer, hardcoded rider/vendor whitelist phones. No name/email fields; OTP does not exist in backend | ❌ register fields; ◐ phone entry |
| 2 | Guest browsing (catalog without login) | `features/booking/home_screen.dart` + `product_catalog.dart` render without token; checkout gates | `lib/main.dart:34` boots straight to `LoginScreen`; no guest mode | ❌ |
| 3 | First-run locate → address | `features/auth/first_run_screen.dart`: locate me → confirm address (hourglass → catalog) | `home/presentation/widgets/top_bar.dart`: GPS fill via geolocator+geocoding — genuinely good UX — but saves into 3 hardcoded `savedAddresses` | ◐ |
| 4 | Addresses CRUD + OSM map pin | `features/addresses/address_screen.dart` (pincode regex, `(0,0)` reject, 409 edit-lock) + `map_picker.dart` (flutter_map/OSM, no API key). Address snapshot frozen at dispatch | `profile/presentation/saved_addresses_screen.dart` (171 lines): `AddressModel` + `AddressStateService` singleton, add/edit dialogs, **no map, no server** | ⚙ |
| 5 | Catalog + serviceability + delivery windows | `product_catalog.dart`: 2 SKUs — ₹28 refill can, ₹30 jar+container; ₹150 deposit/jar + ₹3 cap charge; `booking_sheet.dart` polls `GET /windows` capacity, `table_calendar` ≤6 dates | `home/presentation/widgets/featured_products.dart` + `mode_selection_cards.dart`: single product at **₹65/can** hardcoded; slot is a fixed string `"Morning (8:00 AM - 3:00 PM)"` in `top_bar.dart` | ◐ + **wrong prices** |
| 6 | Quote (server-total truth) | `checkout_service.dart`: `POST /quotes` before every order; unseen-state UI in `booking/quote_confirm.dart`; ₹150 deposit math is server truth | `orders/presentation/cart_checkout_sheet.dart:~` — `_canCount` × `_pricePerCan = 65` client arithmetic; total is never server-checked | ❌ |
| 7 | Idempotent checkout | `checkout_service.dart:92` `ensureIdempotencyKey()`; `POST /orders` + `Idempotency-Key`; `STALE_QUOTE` (409) re-quotes once (lines 9, 156-163) | None. "Confirm order" mutates a local list; double-tap risk is unmodeled | ❌ |
| 8 | UPI intent + verify-or-poll | `core/api_client.dart:562-568` `POST /payments/upi-intent {order_id}` + Idempotency-Key; verify-or-poll states in `checkout_service.dart` | None — payment never appears in the friend's flow | ❌ |
| 9 | COD fallback + caps | `booking_controller.dart:31` `kCodCapPaise = 200000` (₹2,000 COD cap); line 74: >3 held jars → COD blocked; `cod-confirm` best-effort in `checkout_service.dart:4` | None | ❌ |
| 10 | Razorpay option | `booking_sheet.dart` includes Razorpay sheet path | None | ❌ |
| 11 | Orders list, cancel/reschedule, paging, rating | `orders/orders_controller.dart` (831 lines): idempotent cancel + reschedule, cursor paging, rating-once (`api_client.dart:525`) | `orders/presentation/my_orders_screen.dart` — a **43-line stub** reading `OrderStateNotifier` static list | ⚙ |
| 12 | Live tracking | `orders/tracking_screen.dart` (1,088 lines): 4-step status matrix, delivery OTP, stops-ahead, rider name + call, RTO/failed banners | `orders/presentation/order_card.dart` shows hardcoded `deliveryPin '5892'`; statuses from the singleton. No timeline, no call, no failure states | ◐ |
| 13 | Payments history | `core/api_client.dart:379-381` `GET /payments/me` (limit query); `profile/payment_history_screen.dart:43` calls `listUserPayments(limit: 50)`, refund vs payment icons, real empty state | `profile/presentation/wallet_screen.dart` (173 lines): static balance, static rows | ⚙ |
| 14 | Ledger wallet (held / deposit / dues) | `profile/profile_screen.dart:5-6` `GET /ledger/me` read-only (held, deposit, dues); deposit display + waive logic in `booking_controller.dart:311` | `wallet_screen.dart` static number only | ⚙ |
| 15 | Subscriptions: pause / resume / skip | `subscriptions/subscription_screen.dart` (1,161 lines): pause `{hold_from, hold_to}` → routing excluded + FCM confirm (lines 5-7, 86-87); resume ≥24h pre-check then server 422 guard (lines 168-169); skip before cutoff else `late_skip` + vendor call CTA; auto-resume on hold_to | TWO competing screens: `orders/presentation/subscription_screen.dart` (259: plan modal, cans × ₹65, imports `data/subscription_service.dart:35 pricePerDrop 65.0`) and `subscriptions/presentation/subscription_screen.dart` (386: `_isPaused` boolean toggle, hardcoded `pausedDates {14,15,16}`) | ⚙ + wrong rules |
| 16 | Returns (jar return + UPI id) | `profile_screen.dart:190` `POST /returns` → request id + 10-working-day SLA; UPI-id collection | Absent everywhere | ❌ |
| 17 | Profile read + edit | `profile_screen.dart`: `GET /auth/me`, `PATCH /auth/me`; 10-digit phone rule; `@gmail.com` check (lines 863-864) | `profile/presentation/customer_profile_screen.dart` (212 lines): static fields, links out to `owner_control_center` + login | ⚙ |
| 18 | Support (WhatsApp + complaints) | `features/support/support_screen.dart`: `wa.me` deep link to `+91 93021 90067` (`booking_controller.dart:51`), `POST /complaints` (≤500 chars), `GET /complaints` | `profile/presentation/support_help_screen.dart` (190 lines): FAQ cards + `AlertDialog` **stubs** ("will be available soon" style) | ◐ |
| 19 | Pause-confirm notifications (FCM contract) | `subscription_screen.dart:5-7` — FCM confirm on pause | `home/notifications_screen.dart` (132 lines): fully hardcoded list — phantom data | ⚙ |
| 20 | Nav shell | `shell/user_shell.dart`: 4 tabs — Home, Orders, Support, Profile (lazy) | `home/presentation/widgets/bottom_nav_bar.dart:36-57`: 5 tabs — Home, My Orders, Subscriptions, Wallet, Profile (no Support tab) | ◐ |

**Coverage scorecard (rows 1-20): 0 FULL · 6 PARTIAL · 7 STATIC · 7 MISSING.**

| Verdict | Count | Rows |
|---------|-------|------|
| ✅ FULL | 0 | — not one production feature is reproduced behind real data |
| ◐ PARTIAL | 6 | 1 (auth entry), 3 (GPS UX), 5 (catalog shape), 12 (tracking chip), 18 (profile fields), 20 (nav) |
| ⚙ STATIC | 7 | 4 (addresses), 11 (orders stub), 13-14 (wallet), 15 (subs), 17 (profile data), 19 (notifications) |
| ❌ MISSING | 7 | 2 (guest), 6 (quote), 7 (idempotent checkout), 8 (UPI), 9 (COD), 10 (Razorpay), 16 (returns) |

---

## 2. Gap table, ranked by journey criticality

| Rank | Gap | Why it breaks the journey | Friend's current state | Fix effort |
|------|-----|---------------------------|------------------------|-----------|
| 1 | **Registration form** (name + email + phone → `POST /v1/auth/user/register`) | Without a token every authed endpoint 401s; the friend's login is a whitelist demo | `login_screen.dart` phone + 4-digit OTP; OTP is not in the backend at all | 3/5 — keep the OTP-lived visuals (timer, keypad), swap the model |
| 2 | **Quote + server-total truth** (`POST /quotes`, ₹150 deposit/jar + ₹3 cap) | Client-side math at ₹65/can is factually wrong for our 2-SKU catalog | `cart_checkout_sheet.dart` `_canCount × 65`; `subscription_service.dart:35` `pricePerDrop 65.0` | 5/5 — replace sheet arithmetic with quote + deposit plane |
| 3 | **Idempotent checkout + payment states** (`POST /orders` + Idempotency-Key; UPI intent + verify-or-poll; COD cap/blocks + `cod-confirm`) | Money path absent; double-tap creates duplicate orders invisible to the demo | "CONFIRM ORDER" writes to `OrderStateNotifier` only | 5/5 — the largest single build |
| 4 | **Address CRUD + map pin** (OSM picker, pincode regex, `(0,0)` reject, 409 edit-lock, snapshot-freeze at dispatch) | Orders cannot be dispatched; the demo addresses are decorative | `saved_addresses_screen.dart` singleton, no map | 4/5 |
| 5 | **Windows/capacity + serviceability** (`GET /windows`, ≤6-date calendar, Cod-cap interplay) | Demo slot is a fixed string; capacity/edge-day rules don't exist | `top_bar.dart` `_selectedSlot 'Morning (8:00 AM - 3:00 PM)'` | 4/5 |
| 6 | **Tracking reality** (4-step matrix, delivery OTP, stops-ahead, rider name + call, RTO/failed banners) | Post-dispatch trust is the churn killer; the PIN display mirrors our OTP idea but the timeline doesn't exist | `order_card.dart` static `deliveryPin '5892'` | 4/5 |
| 7 | **Ledger + payments history** (`GET /ledger/me`, `GET /payments/me`) | Held/dues/deposit is our financial trust surface; refunds must be visible | `wallet_screen.dart` static; no history screen at all | 3/5 |
| 8 | **Subscription rules engine** (pause range `{hold_from, hold_to}`, 24h resume guard → 422, skip cutoff → `late_skip`, auto-resume) | A boolean toggle silently violates server contracts the demo will never enforce | Two duplicate screens; `pausedDates {14,15,16}` hardcoded | 4/5 (incl. merging the two screens) |
| 9 | **Returns flow** (`POST /returns` → request id, 10-working-day SLA, UPI id) | Empty-jar economics need a make-good path; friend's UI has nothing | Absent | 3/5 — mostly build new inside friend's Profile look |
| 10 | **Support wiring** (`wa.me` + `POST /complaints` + `GET /complaints`) | Demo shows FAQ + dead dialogs; no phone path | `support_help_screen.dart` AlertDialog stubs | 2/5 |
| 11 | **Guest browsing** | Friend's app walls everything behind login; our app lets users see prices before registering | `main.dart:34` boots to `LoginScreen` | 2/5 — reorder app boot only |
| 12 | **Profile edit validation** (10-digit phone, `@gmail.com`) | Static fields would POST garbage if wired naively | `customer_profile_screen.dart` static | 2/5 |
| 13 | **Notification truth** | A hardcoded notifications list trains users to distrust our FCM confirmations | `notifications_screen.dart` | 1/5 (cut) or 4/5 (wire FCM) |

---

## 3. Friend's-UI extra features (not in production) — judgments

| Extra | Evidence | What it is | Verdict |
|-------|----------|-----------|---------|
| Live purity card | `home/presentation/widgets/live_purity_card.dart` (136 lines), `PlantTelemetryNotifier` | TDS/purity telemetry with sparkline | **Keep the card shell, cut the notifier** — it's attractive empty-state marketing; wire to nothing or to a real plant endpoint if one ever exists. Do not fake telemetry. |
| Mode-selection cards | `home/presentation/widgets/mode_selection_cards.dart` (192 lines) | Deliver-mode / plan-mode chooser on Home | **Repurpose** as the window/slot selector over `GET /windows`; visually distinct, good starting point. |
| Featured product rail | `featured_products.dart` (159 lines) | Horizontal SKU cards at ₹65 | **Reskin onto real catalog** (2 SKUs, ₹28/₹30 + deposit line). The layout is the value; the data is wrong. |
| GPS locate + geocoding fill | `top_bar.dart` geolocator + geocoding | Auto-fills address from device GPS | **Keep and wire** — feed results into our address validation + `POST`. This is the best UX idea in the friend's app. |
| Deliver-PIN handshake + empty-can collection stepper | `rider_delivery_screen.dart:25-48` (PIN verify, `markOrderDelivered(actualCollectedCans:)`) | Rider-side delivery confirmation matching our delivery-OTP concept | **Port to rider app later** (or a future vendor view), not the user app. Mentally validates our OTP design. |
| Rider dashboard | `rider_dashboard_screen.dart` (`class RiderDashboardScreen` at line 7, a `StatelessWidget`) — fully static | Rider queue | **Deletion candidate** for the user app; candidate seed for `vendor_app`/rider surface. |
| Plant hub | `plant_hub_screen.dart:186-193` — merges `PlantTelemetryNotifier` counters (dispatched cans, empties collected) with `OrderStateNotifier` | Plant-side stock/purity console | **Port target: `vendor_app`/admin**, not the customer app. |
| Owner control center | `admin/presentation/owner_control_center_screen.dart:4` `enum UserRole {customer, rider, vendor, owner}`; 3 tabs Riders(3)/Customers/Plant Hub (lines 121-123), hardcoded rider statuses (lines 22-38) | Admin console mock | **Port target: admin**, with the `UserRole` enum as a starting taxonomy note. |
| Notifications screen | `home/notifications_screen.dart` (132 lines), hardcoded list | Notification center | **Cut** unless FCM is wired; a phantom inbox is worse than none. |
| 30s OTP resend timer | `login_screen.dart` | Resend countdown | Keep ONLY if an OTP/SMS provider decision lands in the backend; currently delete with the OTP flow. |
| Cart model (`CartProvider`) | `shared/providers/app_providers.dart` | Persistent cart | **Don't adopt.** Our booking stepper with sticky live total covers it; a cart adds a second truth-source for money. |

---

## 4. Flow-by-flow deltas (the five journeys)

### J1 — Register → first order

| Step | Production app | Friend's UI |
|------|----------------|-------------|
| Entry | `user_shell.dart` allows guest → Home; register from `name_number_screen.dart`: name + email + 10-digit phone → `POST /v1/auth/user/register` | `main.dart:34` → `LoginScreen`: phone + OTP against a whitelist; cannot create an account our backend would accept |
| Where am I? | `first_run_screen.dart` locate flow | `top_bar.dart` GPS fill — same spirit, but drops into hardcoded addresses |
| Address | `address_screen.dart` + `map_picker.dart`: pincode regex, `(0,0)` reject, 409 edit-lock; snapshot frozen at dispatch | `saved_addresses_screen.dart`: singleton-only adds/edits |
| Catalog / slots | `product_catalog.dart` (₹28/₹30 + ₹150 deposit + ₹3 cap); `booking_sheet.dart` 3-step stepper with `GET /windows` capacity + ≤6-date calendar | `featured_products.dart` ₹65 rail; fixed `Morning (8:00 AM - 3:00 PM)` string |
| Money | `checkout_service.dart`: quote → `POST /orders` (Idempotency-Key, lines 8-9, 92, 156-163) → UPI intent + verify-or-poll (`api_client.dart:562-568`) or COD (cap ₹2,000, hold-block >3) + best-effort `cod-confirm` | `cart_checkout_sheet.dart`: count × ₹65 → confirm writes to `OrderStateNotifier`. **No payment step exists at all** |

**Delta:** 7 of 7 steps are wired in production and 1 of 7 in the friend's app. The friend's screens supply look-and-feel for steps 1-4 only.

### J2 — Repeat one-tap order

| Aspect | Production app | Friend's UI |
|--------|----------------|-------------|
| Entry surface | Home defaults reproduce the last order; repeat starts straight from Home | Same cart ritual every time; nothing "remembers" |
| Deposit memory | Wallet deposit state recognized — display + waive logic (`booking_controller.dart:311`; ≥1 deposit at line 92) | None — no wallet state at all |
| Pricing | Fresh server quote each repeat (`POST /quotes`) | Fixed `_canCount × 65` arithmetic |
| Completion | Quote → idempotent `POST /orders` | Singleton list append |
| Nearest analog | — | Subscription modal (`orders/presentation/subscription_screen.dart`, `pricePerDrop 65.0`), statically priced |

**Delta:** one-tap is a build item; the friend's UI has no surface designed for it. Add a "Repeat last order" card on Home, priced by quote.

### J3 — Track delivery

| Step | Production app | Friend's UI |
|------|----------------|-------------|
| Orders list | Cursor paging from `orders_controller.dart` (831 lines) | 43-line stub over the static singleton |
| Timeline | 4-step status matrix (`tracking_screen.dart`, 1,088 lines) | No timeline — a single status chip |
| Handshake | Delivery OTP per order | Static `deliveryPin '5892'` (`order_card.dart`, `order_service.dart`) |
| Rider contact | Rider name + call button | None |
| Failure paths | RTO/failed-delivery banners | None |
| Feedback | Rating, once per delivered order (`api_client.dart:525`) | None |
| Other side | — | `rider_delivery_screen.dart:25-48` verifies a hardcoded PIN, then `markOrderDelivered(actualCollectedCans:)` |

**Delta:** the PIN-handshake concept agrees with our delivery OTP, but the customer-facing surface must be rebuilt on the real paging + tracking payloads.

### J4 — Subscribe

| Capability | Production app | Friend's UI |
|------------|----------------|-------------|
| Activate | Activation + estimate (subscription contract §4.5) | Plan modal priced cans × ₹65 (`orders/presentation/subscription_screen.dart`, 259 lines) |
| Pause | Date range `{hold_from, hold_to}` → routing excluded + FCM confirm (`subscription_screen.dart:5-7`, 86-87) | `_isPaused` boolean toggle; `pausedDates {14,15,16}` hardcoded (386-line screen) |
| Skip | Cutoff-aware; after cutoff → `late_skip` + vendor call CTA | None |
| Resume | ≥24h pre-check locally, then server 422 + next-valid-date (lines 168-169) | None |
| Auto-resume | At `hold_to` | None |
| Screens | 1 | **2 duplicates** that must be merged |

**Delta:** a pause toggle instantly violates the server contract (a boolean cannot express a date range); no guard, no skip, no `late_skip`, wrong price. Merge the two screens first, then rewire to §4.5.

### J5 — Exit / return (cancel, reschedule, returns, support)

| Recovery path | Production app | Friend's UI |
|---------------|----------------|-------------|
| Cancel | Idempotent, with confirm (`orders_controller.dart`) | Impossible — orders are static list items |
| Reschedule | Idempotent, same controller | None |
| Returns | `POST /returns` → request id + 10-working-day SLA (`profile_screen.dart:190`), UPI id collected | Absent everywhere |
| Support | `wa.me` deep link to `+91 93021 90067` (`booking_controller.dart:51`), `POST /complaints` ≤500 chars + `GET /complaints` | `support_help_screen.dart`: FAQ + `AlertDialog` stubs, no phone |
| Money safety | Dues visible read-only in `GET /ledger/me` | None — dues concept doesn't exist |

**Delta:** the entire "undo / make-good" half of the product is unbuilt in the friend's UI; it must be designed into the friend's Profile and Order-card shells rather than ported.

---

## 5. Import difficulty rating per friend screen

| Screen / widget | Size | Difficulty (1-5) | Notes |
|------------------|------|------------------|-------|
| `core/constants/app_constants.dart` (palette) + `core/theme/app_theme.dart` | 36 + | **1** | Teal `0xFF0D9488` + solar accent; drop-in. Highest-value, cheapest import. |
| `bottom_nav_bar.dart` | ~61 | 1 | Swap 5 tabs → our 4 (Wallet becomes Support or re-house ledger under Profile). |
| `order_card.dart` | — | 2 | Good status-chip anatomy; rewire `deliveryPin` static to real tracking payload. |
| `notifications_screen.dart` | 132 | 2 (if cut) / 4 (if FCM-wired) | Recommend cut for v1. |
| `customer_home_screen.dart` | 111 | 3 | Pure orchestrator once children are re-wired; low risk. |
| `support_help_screen.dart` | 190 | 3 | Replace dialog stubs with `wa.me` launch + complaints list. |
| `featured_products.dart` | 159 | 3 | Keep layout; map to `/catalog` SKUs; delete ₹65. |
| `mode_selection_cards.dart` | 192 | 3 | Becomes slot/window picker over `GET /windows`. |
| `customer_profile_screen.dart` | 212 | 3 | Wire `GET/PATCH /auth/me`; remove owner-control-center link (admin belongs elsewhere). |
| `top_bar.dart` | 585 | 3-4 | GPS fill keep; 3 hardcoded addresses + slot string must go server-side. |
| `login_screen.dart` | 546 | 4 | Keep visuals (timer, keypad); replace OTP model with name/email/phone register. |
| `subscriptions/presentation/subscription_screen.dart` | 386 | 4 | Re-model pause as date range; merge with its duplicate. |
| `wallet_screen.dart` | 173 | 4 | UI is a shell; must gain `GET /ledger/me` + payments history entry. |
| `saved_addresses_screen.dart` | 171 | 4 | Singleton → server CRUD; add OSM map picker from `map_picker.dart`. |
| `my_orders_screen.dart` | **43** | 4 (rebuild, not port) | The stub is trivially deletable; the real orders/tracking hub is a genuine build. |
| `cart_checkout_sheet.dart` | 278 | 5 | Hard to *fix*; easier to replace with quote/checkout surfaces from `booking_sheet.dart` + `quote_confirm.dart` restyled with these tokens. |
| `live_purity_card.dart` + `plant_service.dart` | 136 + | 3 (with product decision) | Keep shell, delete notifier, or park pending a real plant endpoint. |
| `rider_*` / `plant_hub_*` / `owner_control_center.dart` | large | n/a (port) | Out of user-app scope; candidate seeds for `vendor_app`/admin bundles. |

### Hardcoded artifacts that must be stripped during import

| Hardcoded artifact | Friend's UI location | Production replacement |
|--------------------|----------------------|------------------------|
| ₹65 per can (repeated everywhere) | `cart_checkout_sheet.dart`, `subscription_service.dart:35`, both subscription screens | `POST /quotes` totals; catalog ₹28 / ₹30 (+ ₹150 deposit, ₹3 cap) |
| Delivery PIN `'5892'` | `order_card.dart`, `order_service.dart`, `rider_delivery_screen.dart:28-30` | Per-order delivery OTP from the tracking payload |
| `pausedDates {14,15,16}` | `subscriptions/presentation/subscription_screen.dart` | Pause range `{hold_from, hold_to}` API round-trip |
| Slot string `'Morning (8:00 AM - 3:00 PM)'` | `top_bar.dart` | `GET /windows` capacity result |
| 3 saved addresses | `top_bar.dart` | Server CRUD via the address manager |
| Static wallet balance + rows | `wallet_screen.dart` | `GET /ledger/me` + `GET /payments/me` |
| Phone whitelist (rider/vendor/demo) | `login_screen.dart` | Real register + 401 paths — the whitelist must not survive |
| Hardcoded rider statuses | `owner_control_center_screen.dart:22-38` | Out of scope here (admin/vendor port target) |
| Static notification list | `notifications_screen.dart` | FCM contract or deletion |

---

## 6. Verdict

**How much of the premium look survives re-wiring?** The design language survives cleanly —
palette, typography, spacing tokens, card shells, Home composition, mode cards, and the
product-rail aesthetics are agnostic to data and importable nearly as-is (app_constants.dart +
app_theme.dart + the hardest 4 screens' visual shells). What does **not** survive is roughly half
the shipped screens as *products*: login, checkout sheet, orders stub, subscription screens,
wallet, and addresses are all gameplay over hardcoded singletons. Realistically **~85-90% of the
visual identity and ~50-60% of the screen surfaces** carry forward; the money/order/persistence
paths must be re-skinned onto the production data layer rather than ported. One hard rule:
strip every ₹65 and every hardcoded number (`'5892'`, `pausedDates`, static wallet balance)
during import — those are the demo's most dangerous cargo.

**What survives vs what dies, in one table**

| Survives the import (near as-is) | Dies / rebuilds behind the look |
|----------------------------------|---------------------------------|
| Palette, type scale, spacing tokens (`app_constants.dart`) | Login model — OTP + whitelist → register form |
| Home shell, featured rail layout, mode cards | Checkout sheet internals (client math → quote + pay states) |
| Nav bar anatomy (5 → 4 tabs swap) | Orders stub (43 lines → real hub + tracking) |
| GPS locate UX in `top_bar.dart` | Subscription rules (toggle → date range engine) |
| Card/button anatomy, status chips | Wallet internals (static → ledger + payments history) |
| Address dialogs layout (no map exists yet) | Addresses backend (singleton → CRUD + OSM map) |

**Top-10 build items (priority order):**

1. Register screen (name + email + phone → `POST /v1/auth/user/register`) on `login_screen`'s visuals; delete OTP + whitelist; restore guest entry (`main.dart` boots to Home first).
2. First-run locate wizard — keep the GPS fill, wire into address validation + save.
3. Address manager — server CRUD + OSM map picker (pincode regex, `(0,0)` reject, 409 edit-lock, snapshot-freeze note).
4. Home feed re-wire — `/catalog` SKUs (₹28/₹30, ₹150 deposit/₹3 cap), `GET /windows` slot picker inside `mode_selection_cards`, kill the fixed morning string.
5. Booking stepper (3-step, ≤6-date calendar, capacity, bulk-confirm 6-10, tanker stop >10) in the friend's card/idle aesthetics.
6. Quote + checkout — `POST /quotes` server totals, `POST /orders` + Idempotency-Key, `STALE_QUOTE` one-retry; delete client-side money math.
7. Payment surfaces — UPI intent + verify-or-poll states, COD with ₹2,000 cap + hold-block messaging, `cod-confirm`; Razorpay path preserved.
8. Orders hub + tracking — replace the 43-line stub: list paging, idempotent cancel/reschedule, 4-step timeline, rider name + call, delivery OTP, RTO/failed banners, rating-once.
9. Money trust screens — wallet on `GET /ledger/me` (held/deposit/dues), payments history on `GET /payments/me`, returns on `POST /returns` (SLA + request id) inside the friend's Profile look.
10. Subscriptions consolidation — merge the two dupes; implement pause range + 24h resume guard + skip/late_skip; keep auto-resume; then Support wiring (`wa.me` + complaints) and a cut-or-wire decision on notifications.

---

**Provenance.** Every fact above was read directly from both trees: production `apps/user_app/lib` (20 files, incl. `core/api_client.dart` 591 lines, `orders_controller.dart` 831, `tracking_screen.dart` 1,088, `subscription_screen.dart` 1,161, `booking/*`, `addresses/*`, `profile/*`, `support/*`, `shell/user_shell.dart) and the friend's tree from the saved copy (28 `lib/**.dart` files, all screens listed in §5). No numbers were inferred; anything not observed in source is labeled as a build item rather than stated as existing behavior. This is a documentation-only deliverable — no code was modified.
