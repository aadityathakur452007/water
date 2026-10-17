# 03 — Backend Contract Violations (Friend-UI Import Audit)

**Audited repo (friend's app):** `C:\Users\Hp\AppData\Local\Temp\opencode\shodasha-friend-ui` (~34 Dart files, cited below as `lib/...`)
**Contract source (our side):** `workers/api` — Python on Cloudflare Workers + D1 (cited as `workers/api/src/app/...`)
**Contracts cross-checked against:** `context/decision.md` (ADR-110, ADR-112, ADR-111), `context/flow.md` (API Endpoints, 028 auth call maps), `context/architecture.md` (Stack, Backend Boundaries).

**Method:** every endpoint below was verified by grepping actual `@router.*` registrations in `workers/api/src/app/api/v1/*.py`; every friend-app claim was verified by reading the cited file. Nothing is inferred from behavior the code does not contain.

**Headline finding (verified, not speculation):** the friend's UI has **no network layer at all**. Repo-wide grep for `http|dio|HttpClient|Uri.|Socket|fetch` over `*.dart` returns only `top_bar.dart:35` (a GPS helper), which is not an HTTP client. There is no REST call, no base URL, no token store, no auth interceptor — anywhere.

---

## 1. Backend reality check (our side)

All routers are mounted under the `/v1` prefix by the app factory: `workers/api/src/app/main.py:41-53`.

### 1.1 Confirmed endpoint table (customer-relevant surface)

| Method | Path | Auth | Registered at (file:line) |
|--------|------|------|---------------------------|
| POST | `/v1/auth/user/register` | none (rate-limited) | `workers/api/src/app/api/v1/auth.py:144-158` |
| POST | `/v1/auth/refresh` | refresh token in body | `auth.py:161-163` |
| POST | `/v1/auth/logout` | Bearer | `auth.py:166-178` |
| GET | `/v1/auth/me` | Bearer | `auth.py:181-183` |
| PATCH | `/v1/auth/me` | Bearer + active | `auth.py:186-198` (fields: name, language, phone, email at `auth.py:78-82`) |
| POST | `/v1/auth/otp/start` / `otp/verify` / `demo` | none (legacy/OTP + QA doors) | `auth.py:89-92`, `95-102`, `105-114` |
| POST | `/v1/auth/vendor/login` | access code | `auth.py:117-128` |
| POST | `/v1/auth/admin/login` | access code | `auth.py:131-141` |
| GET | `/v1/catalog` | none (cached) | `catalog.py:34` |
| GET | `/v1/windows?date=&pincode=` | none (cached) | `catalog.py:60` |
| GET | `/v1/serviceability?pincode=` | none (cached) | `catalog.py:75` |
| POST | `/v1/leads` | none | `catalog.py:87` |
| POST | `/v1/quotes` | none (paise math server-side) | `quotes.py:26-54` |
| POST | `/v1/orders` | Bearer (role user) + `Idempotency-Key` header | `orders.py:78-85` (header enforced `orders.py:70-75,83`) |
| GET | `/v1/orders?limit=&cursor=` | Bearer | `orders.py:88-95` |
| GET | `/v1/orders/{id}` | Bearer | `orders.py:98-100` |
| GET | `/v1/orders/{id}/tracking` | Bearer | `orders.py:103-105` |
| PATCH | `/v1/orders/{id}/instructions` | Bearer + active | `orders.py:112-115` |
| POST | `/v1/orders/{id}/cancel` / `reschedule` | Bearer + active (cancel also idem key) | `orders.py:118-129` |
| POST | `/v1/orders/{order_id}/rating` | Bearer | `ratings.py:34` |
| POST | `/v1/payments/upi-intent` | Bearer + `Idempotency-Key` | `payments.py:47-51` |
| POST | `/v1/webhooks/upi` | HMAC signature (`X-Razorpay-Signature`) | `payments.py:54-60` |
| POST | `/v1/orders/{order_id}/cod-confirm` | Bearer | `payments.py:63-65` |
| POST | `/v1/payments/dues-intent` | Bearer + `Idempotency-Key` | `payments.py:68-71` |
| GET | `/v1/billing/dues` | Bearer | `payments.py:74-76` |
| GET | `/v1/ledger/me` | Bearer | `payments.py:81-92` (returns held/deposit_paid/deposit_refunded/wallet_held/dues) |
| GET | `/v1/payments/me?limit=` | Bearer | `payments.py:95-98` |
| GET | `/v1/invoices/{order_id}` | Bearer | `payments.py:101-103` |
| POST/PATCH/DELETE | `/v1/addresses[/...]` | Bearer | `addresses.py:70,76,85,98` |
| POST | `/v1/returns` (`qty`, `address_id`, `upi_id`) | Bearer | `returns.py:63` (schema `returns.py:35-38`) |
| GET | `/v1/returns`, POST `/v1/returns/{id}/pickup` | Bearer / vendor | `returns.py:97,111` |
| POST | `/v1/subscriptions` | Bearer + role=user + `Idempotency-Key` | `subscriptions.py:21-22,52-57` |
| POST | `/v1/subscriptions/estimate` | Bearer + role=user | `subscriptions.py:65-71` |
| GET | `/v1/subscriptions` | Bearer | `subscriptions.py:74-76` |
| POST | `/v1/subscriptions/{id}/pause`/`resume`/`skips`/`cancel` | Bearer + active | `subscriptions.py:79-95,103-113` (cancel accepts `upi_id`, `subscriptions.py:98-100`) |
| POST/DELETE | `/v1/devices` | Bearer | `devices.py:33,54` (FCM device registration/teardown) |
| POST | `/v1/complaints`, GET `/v1/complaints` | Bearer | `complaints.py:86,128` |
| GET/POST | `/v1/vendor/*`, `/complaints/{id}/verify`, `/quality/{id}/vendor-check` | vendor session | `vendor.py:99-256` |
| GET/POST/PATCH | `/v1/admin/*` (orders, users, vendors, zones, ledger, payouts, reconciliation, audit, metrics…) | admin session | `admin.py:153-1321` |

### 1.2 Exact auth request/response shapes (what any import must mirror)

**Request — `POST /v1/auth/user/register`** (`UserRegisterIn`, `workers/api/src/app/api/v1/auth.py:59-65`):

```json
{
  "name": "string, 1–100 chars",
  "email": "string 3–254, regex ^[a-zA-Z0-9._%+-]+@gmail\\.com$ (gmail-only, ADR-104)",
  "phone": "string 10–16, regex ^(\\+91|91|0)?[6-9]\\d{9}$",
  "device": { "id": "string 1–128", "integrity": "optional ≤256" }   // DeviceIn, auth.py:23-25
}
```

**Response — 200** (`auth_service.user_register` → `_issue_session`, `workers/api/src/app/services/auth_service.py:464-508, 510-549`):

```json
{
  "access_token":  "urlsafe token; access TTL 30 min (sessions.create, auth_service.py:531, ACCESS_TTL_MIN)",
  "refresh_token": "urlsafe token; refresh TTL 7 days rotating (auth_service.py:532)",
  "token_type": "bearer",
  "role": "user",
  "user_id": "hex id",
  "new_device_alert": false,
  "expires_at": "ISO access expiry",
  "details": { "integrity": "..." },
  "verified": false            // user_register sets it (auth_service.py:507)
}
```

Server-side register rules worth mirroring in UX copy: rate limits 5/phone/hr + 20/IP/hr (`auth_service.py:489-490`); blank name → `ValidationError`; non-gmail → `ValidationError` (`auth_service.py:484`); an existing **staff** number on that phone → `422 ROLE_RESERVED` ("This number belongs to a staff account", `auth_service.py:492-496`); existing user gets name/email **filled once if blank, never overwritten** (`auth_service.py:497-501`); device cap → `409` ("Too many accounts on this device", `auth_service.py:514-520`).

**Session lifecycle (contract):** every call carries `Authorization: Bearer <access>` (`api/auth_deps.py` — `flow.md:552-555`); refresh rotates the pair and preserves a 30-day absolute cap (`auth_service.py:553-574`; burned-token reuse kills the family, `auth_service.py:557-561`); logout supports `revoke_all` + per-device FCM teardown (`auth.py:166-178`, `flow.md:467`); profile edits go through `PATCH /v1/auth/me` with strict 10-digit phone and `@gmail.com` validation (ADR-110 §4).

### 1.3 Money truth (server-computed, integer paise)

- SKU rates: `REFILL_PAISE = 2800`, `CONTAINER_PAISE = 3000`, `DEPOSIT_PAISE = 15000`, `RATE_VERSION = "v1"` — `workers/api/src/app/services/pricing.py:10-14`.
- Quote math: `water_bill` = refills×2800 + containers×3000; `deposit_due = max(0, N−E−covered_jars) × deposit`; `deposit_already_paid_paise` from ledger wallet waives repeat deposits (`pricing.py:24-53`; ADR-111 §2).
- Quote output: `water_bill, deposit_due, cap_note, total, quote_hash, expires_at (UTC now+15min)` — `workers/api/src/app/schemas/catalog.py:52-58`; >10 jars → `422 OVER_LIMIT` (`quotes.py:18,41-45`).
- `CatalogOut` wire shape: `skus[{id: refill|container, price_paise}], deposit_per_jar, cap_charge, hours, holidays` — `schemas/catalog.py:10-20`.
- Order create is a full quote replay-check: client must echo `items, e, address_id, window_start, quote_hash, quote_total (echo; mismatch → 409), quote_rate_version, quote_expires_at, payment_mode (upi|cod)` — `schemas/orders.py:16-34`.
- Tracking exposes `delivery_otp`, `stops_ahead`, `rider {name, phone, stops_ahead}`, `tracker`, `bill`, `events` — `schemas/orders.py:66-73` (`GET /v1/orders/{id}/tracking`, `orders.py:103-105`; ADR-101 live stops-ahead).

---

## 2. Friend's app data layer dissection

### 2.1 What the declared persistence stack actually is

- `pubspec.yaml:8-18` declares `cloud_firestore: ^4.14.0`, `firebase_core: ^2.24.2`, `provider`, `shared_preferences`, `geocoding`, `geolocator`.
- **`cloud_firestore` is dead weight:** repo-wide grep for `Firebase|firebase|cloud_firestore|FirebaseFirestore` over `*.dart` hits only `lib/main.dart:3,9,11` (`Firebase.initializeApp()` wrapped in try/catch, then discarded). **Zero Firestore collections are read or written anywhere.** No `FirebaseAuth`, no `firebase_messaging`.
- **`shared_preferences` is also unused** (grep: `SharedPreferences|shared_preferences` → no matches).
- The real data layer = **five process-memory singletons keyed `static final instance`** (`ChangeNotifier`) plus `Provider`. Everything shown on screen is hardcoded seed data; all writes mutate RAM and vanish on app restart.

### 2.2 The "Firestore services" in truth (what they hold, where, cited)

| Singleton (file:line) | Reads (seed data) | Writes | Fields |
|---|---|---|---|
| `OrderStateNotifier` — `lib/features/orders/data/order_service.dart:34-139` | hardcoded `activeOrders` (`:38-53`, e.g. `#SHD-8492`, status `ON ROUTE`, `Rs 130.00`, `deliveryPin '5892'`) and `completedOrders` (`:55-70`) | `placeNewOrder` `:72-119` (client price parse `:89-92`, total = unit×count `:93`, **random 4-digit delivery PIN** `:98-99`, `emptyCansToReturn = count` `:111`); `markOrderDelivered` `:121-126`; aggregates `:128-137` | orderId, title, status, address, timeSlot, amount (string), deliveryAgent, emptyCansToReturn, orderedCansCount, eta, date, deliveryPin |
| `SubscriptionNotifier` — `lib/features/orders/data/subscription_service.dart:23-64` | seed sub `#SUB-9021` with `pricePerDrop: 65.0` (`:27-37`) | `togglePause` `:39-43`; `addNewSubscription` `:45-63` (client id `#SUB-…`, client slot string) | id, planTitle, frequency, deliveryTime, cansPerDrop, isPaused, pricePerDrop |
| `PlantTelemetryNotifier` — `lib/features/orders/data/plant_service.dart:3-26` | `basePlantStock 450`, `batchNumber 'BHP-X4-2026'`, `tdsValue 85`, `phValue 7.2`, `ozonationStatus` (`:8-12`) | `updatePlantData` `:14-25` (vendor/plant ops fields with **no backend counterpart at all**) | stock, batch, tds, ph, ozonation |
| `AddressStateService` — `lib/features/profile/presentation/saved_addresses_screen.dart:26-88` | 2 hardcoded addresses incl. `… Bhopal, MP - 462016` as free text (`:30-51`) | `setActiveAddress` `:60-65`; `addAddress` `:67-87` (id = `DateTime.now().millisecondsSinceEpoch` `:77`) | id, tag, title, landmark, floor, fullAddress, contact, isDefault — **no pincode, no address_id usable by the API** |
| `CartProvider` — `lib/shared/providers/app_providers.dart:4-76` + `CartItem` `lib/shared/models/product.dart:49-63` | — | add/remove/update qty `:17-62`; **`totalPrice = price×qty` client math** (`product.dart:55`) | product, quantity |
| `HomeDataProvider` — `lib/features/home/presentation/providers/home_data_provider.dart:4-38` | hardcoded catalog: `jar_20l @ ₹80.0`, `bottle_1l @ ₹25.0` (`:5-24`) | — | Product model `product.dart:5-24` (id, name, description, **double price in rupees**, type enum, imageUrl, stock, isActive) |

Screens write straight into these singletons, e.g. checkout bypasses `placeNewOrder` and inserts an `OrderItem` directly (`lib/features/orders/presentation/cart_checkout_sheet.dart:235-238`), and `SubscriptionPlan` even applies `discountPercent` client-side (`product.dart:98-99`).

### 2.3 The auth path in `login_screen.dart`

- Two "portals": customer vs partner (`lib/features/auth/presentation/login_screen.dart:7,17`).
- Partner gate is a **hardcoded whitelist map** `_partnerRegistry` with 3 phone numbers → roles rider/vendor (`login_screen.dart:30-34`), checked at `:68-73`; role decides the landing screen (`:104-116`).
- OTP: a 4-digit box set (`List.generate(4)`, `:20`); `_requestOtp` validates the 10-digit regex (`:63`) then fakes success via `Future.delayed` and a "OTP sent successfully" toast (`:79-87`). **No SMS is ever sent, no code is ever generated** — `_verifyOtpAndLogin` accepts **any** 4-digit entry (`:90-95`).
- Customer login just routes with the typed phone string: `CustomerHomeScreen(userPhone: phone)` (`:117-122`). **No user document, no session, no token, no profile** — identity is an unverified string plumbed through constructors (`customer_home_screen.dart:11-13`, default `'9893000000'`; consumed at `customer_profile_screen.dart:8-9,65`).

### 2.4 Persistence model the UI assumes

**"Auth = an OTP theater + a phone string; state = RAM singletons; network = nonexistent."** There is no token, no refresh, no server session, no durable storage (SharedPreferences declared but unused), no crash-surviving state. Restarting the app restores hardcoded demo orders/subscriptions/addresses regardless of who "logged in."

### 2.5 Verbs the friend UI assumes that have no customer-side /v1 counterpart

- **Nothing mints order statuses client-side.** Lifecycle transitions are server events (`placed → accepted → picked → packed → assigned → …`); the friend app fabricates `BOOKED` / `ON ROUTE` / `DISPATCHED` strings at will (`order_service.dart:106,42,224`). There is no "place order directly with a total" verb — `POST /v1/orders` re-checks the quote server-side and fails cheap on mismatch (`context/flow.md:431`: "Idempotent create (scoped key), quote re-check, OVER_LIMIT/HOLD_BLOCKED").
- **Nothing accepts rider-side delivery completion from this app.** PoD is `/v1/vendor/stops/{stop_id}/pod` under a vendor session (`vendor.py:140-143`); a customer app cannot verify delivery (and must never — the rider's fraud surface would move into the customer's hands).
- **No plant telemetry, no van stock, no rider fleet endpoints exist for this role.** `PlantTelemetryNotifier` and `OwnerControlCenterScreen`'s fleet data (`plant_service.dart:8-12`, `owner_control_center_screen.dart:17-50`) have no `/v1/*` counterpart for customers at all — those concepts live in vendor/admin surfaces.
- **No "recharge wallet" verb.** The only wallet top-up path is the security-deposit ledger (`/v1/ledger/me`, `payments.py:81-92`) fed by deposits/refunds server-side; dues are settled by UPI intent (`payments.py:68-71`), not a "recharge gateway".

### 2.6 What is genuinely absent for the port (verified non-existence)

- **No test coverage of any behavior that survives the port.** The repo ships one smoke test (`test/widget_test.dart`) — logic-level confidence about this codebase's data layer is zero by construction, which the import estimate must price in.
- **No feature-first discipline violation to warn about** in our house style (`context/architecture.md:24-52`): the friend's `lib/features/*` split is cosmetic only — data classes live beside screens (`orders/data/*.dart` imported by `presentation/*` directly, e.g. `cart_checkout_sheet.dart:4`, `my_orders_screen.dart:3`), so porting must re-establish the "controllers/api/providers" split along the way.
- **No platform wiring** (no `auth_gate`, no splash/restore, no deep links); `main.dart` boots straight into `LoginScreen` (`lib/main.dart:13,34`), meaning the "restore session" half of the auth lifecycle must be created from scratch in the port.

---

## 3. Violation table

Severity: **BLOCKER** = import breaks money/identity integrity; **BREAKING** = feature cannot function against our API; **COSMETIC** = display/wording-level.

| # | Friend's assumption (file:line) | Our contract | Severity | Rewiring work needed |
|---|---|---|---|---|
| a | Register/login = phone + fake 4-digit OTP, no name/email, no user doc (`login_screen.dart:61-125`); partners via hardcoded whitelist `:30-34` | Customers: **no OTP** — `POST /v1/auth/user/register {name, email(gmail), phone, device}` → bearer pair (`auth.py:144-158`, `auth_service.py:464-508`). Staff = separate apps, access codes (`auth.py:117-141`) | **BLOCKER** | Rebuild first-run identity: name + `@gmail.com` email + 10-digit phone form → register API → store tokens; delete OTP theater + partner registry; staff numbers → surface `422 ROLE_RESERVED` copy (`auth_service.py:492-496`) |
| b | No Bearer / refresh / session concept anywhere (zero HTTP client; tokens never stored; `login_screen.dart` routes a bare phone string) | Bearer on every call (`flow.md:552-555`); access 30 min, refresh 7d rotating, 30d absolute cap, device-fingerprint scoped (`auth_service.py:510-549,553-574`); 401→`/v1/auth/refresh`→retry→re-login (ADR-112 §1 pattern) | **BLOCKER** | Add an ApiClient (equivalent of our `apps/user_app/lib/core/api_client.dart` `hasToken` getter, ADR-112), Secure Storage for tokens, 401→refresh-once→retry loop, role!=user wipe (`flow.md:357`) |
| c | Order creation = client object insert: `cart_checkout_sheet.dart:220-244` builds `OrderItem … status 'DISPATCHED'` (id from `DateTime.now().millisecond` `:222`, empty `deliveryPin` `:232`); no quote, no hash, no window, no idempotency | `POST /v1/orders` requires `Idempotency-Key` header (`orders.py:83` + `orders.py:70-75`) and full quote echo `quote_hash/quote_total/quote_rate_version/quote_expires_at` + `address_id` + `window_start` + `payment_mode` (`schemas/orders.py:16-34`); mismatched echo → 409 | **BLOCKER** | Pre-checkout `POST /v1/quotes`; retain UUIDv4 idem key per submit (refresh on payment-mode switch, ADR-110 §2); map address pick → `address_id`; window pick → ISO `window_start`; delete local "DISPATCHED" state fabrication |
| d | Payment modes absent entirely — checkout goes straight to "Order Confirmed! Van is on the way" (`cart_checkout_sheet.dart:246-259`); no UPI screen, no COD option, wallet screen is a static `₹450.00` with a "Recharge Gateway will open shortly" snackbar (`wallet_screen.dart:55-60`) | `POST /v1/payments/upi-intent` → Razorpay intent link (`payments.py:47-51`); webhook verifies HMAC (`payments.py:54-60`); **client must poll `GET /v1/orders/{id}` until `payment_status == 'paid_upi'`** (ADR-110 §1); COD = `POST /v1/orders/{id}/cod-confirm` (`payments.py:63-65`); dues UPI = `dues-intent` (`payments.py:68-71`) | **BLOCKER** | Build payment-mode chooser + UPI intent launch (`intent['link']`), poll loop (e.g. 5×2s per ADR-110), honest fail UI with "Retry / COD chunein", COD confirm call; wire `ledger/me` + `payments/me` instead of static wallet |
| e | Price math client-side: hardcoded `₹65/can` in checkout (`cart_checkout_sheet.dart:27,32`) and `unitPrice=65` default (`order_service.dart:88-94`); catalog says `₹80` (`home_data_provider.dart:10`) and `₹25` bottle (`:20`) — three prices in one app | Server computes everything in paise: `POST /v1/quotes` → `total` (`quotes.py:26-54`, `pricing.py:24-53`); `lib/money`-style display-only conversion (`flow.md:637`) | **BLOCKER** | Delete all client multipliers; feed Pay labels from QuoteOut; convert display only (₹ = paise/100) |
| f | No windows/slots/serviceability by pincode: slot strings are display props (`'Morning (08:00 AM - 10:00 AM)'` `order_service.dart:44`; `'Instant Van Delivery'` `cart_checkout_sheet.dart:226`); address model has **no pincode field** (`saved_addresses_screen.dart:4-24`) | `GET /v1/windows?date=&pincode=` 30-min slots 08:00–20:00 (`catalog.py:60`; `flow.md:427`); `GET /v1/serviceability?pincode=` (`catalog.py:75`); unserviceable pin → `/v1/leads` (`catalog.py:87`) | **BLOCKER** | Add pincode capture on address (`POST /v1/addresses` per `addresses.py:76`), slots picker from windows API, serviceability gate + lead capture in UI flow |
| g | `AddressModel` is 7 display fields, pincode only inside a pasted string, coordinates lost (`saved_addresses_screen.dart:30-51`); no default-address ledger concept beyond an in-memory `isDefault` flag (`:53-65`) | Address CRUD via `/v1/addresses` (`addresses.py:70-98`) returning server `AddressOut`; **address snapshot frozen on dispatch** (ADR-102 §1); zone/vendor binding rides `users.assigned_vendor_id` (ADR-110 §3) | **BREAKING** | Replace model with server `AddressOut`; addresses are addressed by `address_id` in quote/order payloads; never edit a dispatched order's address |
| h | Rider screen, plant-hub screen and owner (admin) center ship **inside the customer app** (`login_screen.dart:4-5` imports `rider_dashboard_screen.dart` + `plant_hub_screen.dart`; `OwnerControlCenterScreen` defines `UserRole {customer, rider, vendor, owner}` `owner_control_center_screen.dart:4`; all fed by the same customer `OrderStateNotifier`, `rider_dashboard_screen.dart:57-67`, `plant_hub_screen.dart:186-193`) | Role model = `role=user` session only (`auth_service.py:545`); vendor login is access-code on a **different app** (`auth.py:117-128`); admin is web + access code (`auth.py:131-141`); vendor ops live behind `/v1/vendor/*` (`vendor.py:99-256`) and admin behind `/v1/admin/*` (`admin.py:153+`) | **BLOCKER** (identity boundary) | Strip rider/plant/owner screens from the customer build; a `role=user` Bearer earns 403 on any staff door (`flow.md:555`), so these screens can never be made to work inside this app |
| i | Subscription writes client-side: `addNewSubscription` mints `#SUB-…` ids (`subscription_service.dart:45-63`); plan modal computes `cost = cans × ₹65` (`orders/presentation/subscription_screen.dart:20`) and calls add (`:96`); pause toggles a bool `:39-43`; second subscription screen has a standalone local pause state with const paused dates (`features/subscriptions/presentation/subscription_screen.dart:12-34`) | `POST /v1/subscriptions` (role=user + Idempotency-Key; `SubCreateIn {address_id, qty, sku_mix, window, schedule_type, recurrence, payment_method, next_run}` `subscriptions.py:24-57`); `POST /v1/subscriptions/estimate` = server first-cycle amount for the Pay label (`subscriptions.py:65-71`); pause needs `hold_from/hold_to` (`:35-37`); skip = date `:44-45`; cancel prorates + schedules pickup with `upi_id` (`:98-113`); **repeats waive deposit already paid** (`pricing.py:25,47-53`; ADR-111 §2) | **BREAKING** | Replace both subscription screens' logic with the API: first-cycle estimate → create → pause(resume) with dates → skip → cancel; kill client price math and client ids; features/list via `GET /v1/subscriptions` |
| j | Client rupee/double money everywhere: `double price` (`product.dart:9`), `'Rs $totalAmount.00'` strings (`order_service.dart:94`, `cart_checkout_sheet.dart:204`), static `₹450.00` wallet (`wallet_screen.dart:55`), client discount (`product.dart:98-99`) | Wire money is **integer paise** end to end (`schemas/orders.py:1`, `schemas/catalog.py:1`, `pricing.py:10-12`); server computes all money (`flow.md:296,637`) | **BLOCKER** for any payment path | Purge `double` money fields; parse/display API paise only; ledger card shows held/deposit_paid/deposit_refunded/dues from `/v1/ledger/me` (`payments.py:81-92`) — matches the deposit-visibility requirement of ADR-110 §4 |
| k | FCM/device story: no `firebase_messaging` dep (pubspec has none, `pubspec.yaml:8-18`), push notifications are a hardcoded const list (`notifications_screen.dart:9-42`) | `POST /v1/devices` (201) + `DELETE /v1/devices` (`devices.py:33,54`); logout deletes own-device FCM token (`auth.py:166-178`, `flow.md:467`); pause confirms queue FCM (`subscriptions.py:83`) | **BREAKING** (notifications never arrive) | Add FCM token registration after session mint + teardown at logout; notification list fed from real events (or honest empty state) |
| l | Product catalog shape = `Product{id, name, description, double price, ProductType, imageUrl, stock}` with `jar_20l`/`bottle_1l` (`product.dart:5-24`, seeded `home_data_provider.dart:5-24`) | Catalog = **2 SKUs only**: `refill` ₹28 (2800p) and `container` ₹30 (3000p) + `deposit_per_jar` 15000p + `cap_charge` (`schemas/catalog.py:10-20`, `pricing.py:10-12`); no bottle SKU, no stock field, `sku` is a closed `Literal` (`schemas/orders.py:7`, `schemas/catalog.py:7`) — a `bottle_1l` item would fail Pydantic *and* quote validation | **BREAKING** | Re-map UI SKUs to `refill` (with-repeat container buying = `container` SKU) and deposit ₹150/jar notice; drop the 1L bottle product or gate it behind lead capture |
| m | ETA/agent/status fabricated on order creation: `eta '~25 mins'`, `deliveryAgent 'Mahesh (Delivery Van)'`, `status 'BOOKED'` (`order_service.dart:110,106`), `'Instant Van Delivery'` (`cart_checkout_sheet.dart:226`), delivery PIN generated by the customer (`:98-99`) | Live stops-ahead tracker + server-minted `delivery_otp` + `rider{name, phone, stops_ahead}` surfaced only through `GET /v1/orders/{id}/tracking` / detail (`schemas/orders.py:66-73`, `orders.py:103-105`; ADR-101 §3) | **BLOCKING for trust** (rows: honesty + PoD security) | Delete client ETAs/agent strings/PINs; tracking screen reads the tracking endpoint; delivery OTP is revealed only near PoD and verified server-side by the vendor app |
| n | Empty-jar handling: `emptyCansToReturn = count` auto-set at ordering (`order_service.dart:111`), rider decrements client-side (`rider_delivery_screen.dart:16,22,37`) | Empties are a priced quote input `e` (0..N, validated `e ≤ N`, `schemas/orders.py:27-33`); deposit is charged only for net uncovered containers (`pricing.py:43-53`); empties ledger + `POST /v1/returns {qty, address_id, upi_id}` (`returns.py:35-38,63`) | **BREAKING** | Replace auto-`emptyCansToReturn` with an explicit empties selector feeding `e`; deposit visible from quote; doorstep returns via `/v1/returns` with refund upi_id |
| o | Support/quality surfaces are static text (`support_help_screen.dart` has no data object); no complaint object anywhere | `POST /v1/complaints`, `GET /v1/complaints` owner-scoped (`complaints.py:86,128`); vendor verify flow exists on the vendor door (`vendor.py:213-219`) | **BREAKING** (customer tickets would vanish into the void) | Wire the help screen's primary action to a complaint create form; list own tickets; keep static FAQ content as-is |

### 3.1 Severity roll-up

- **BLOCKER (5):** identity/auth shape (a), session/bearer absence (b), order-creation contract (c), payment pipeline absence (d), client-side money math (e); row (h) is a **BLOCKER-level identity boundary** on top.
- **BLOCKING-in-effect (2):** fabricated delivery state/PIN (m) and the internal price contradiction inside one app (e) — each alone would let a customer ship a trust/money bug into production.
- **BREAKING (6):** addresses without pincode / no server `address_id` (g), subscriptions against client objects (i), FCM/device missing (k), catalog shape (l), empties/returns (n), complaints (o).
- **COSMETIC after rewiring (copy rework only):** "Recharge Gateway will open shortly" (`wallet_screen.dart:58-60`), "Van is on the way 🚚" (`cart_checkout_sheet.dart:255`), "OTP sent successfully" (`login_screen.dart:86`) — each promises something the backend does not do at that instant and must become honest in-app states.

### 3.2 Two cross-cutting observations

1. **Client-minted delivery PIN is a trust inversion, not just a missing field.** `order_service.dart:98-99` generates the PoD PIN inside the *customer's* app, and the "rider" app in the same package checks it client-side (`rider_delivery_screen.dart:28-33`). Under our contract the server mints the OTP at dispatch into stops, exposes it to the owner via `OrderDetailOut.delivery_otp` (`schemas/orders.py:68`), and the vendor verifies it server-side (`vendor.py:140-143`). Porting the friend's PIN flow as-is would let a customer forge its own delivery-proof — that alone justifies refusing a mechanical port of the rider screens.
2. **Real GPS is present and worth keeping deliberately.** `top_bar.dart:34-100` performs genuine `geolocator` permission flow + `placemarkFromCoordinates` reverse geocoding. It must be repointed so the captured `postalCode` drives `GET /v1/serviceability` / `GET /v1/windows` (rows f, g); the free-text address insert into `_savedAddresses` (`top_bar.dart:89-99`) must be replaced by a server `address_id` (`addresses.py:76`).

---

## 4. Auth-flow correctness verdict

### 4.1 Friend's login → home → order walk (where identity breaks vs our API)

1. `LoginScreen` opens → user types 10-digit phone (`login_screen.dart:61-66`). Fine so far — the regex matches ours. **But our customer door has no phone+OTP at all**: `otp/start|verify` exist for legacy/dev doors (`auth.py:89-102`), while the committed customer door is register (`ADR-097`, `flow.md:50,496-497`).
2. "OTP sent" toast after 600 ms fake delay (`:79-87`) — with our API nothing was sent; there is no code to verify. **Break #1: no such endpoint for customers.**
3. `_verifyOtpAndLogin` accepts any 4 digits (`:90-95`) — even if it called `otp/verify`, it sends no `device.fingerprint`, no `firebase_id_token` shape, and would mint a staff-style session, not the register contract. **Break #2: wrong contract + any-code acceptance.**
4. Route lands on `CustomerHomeScreen(userPhone: phone)` (`:117-122`) with **no `access_token`, no session, no `/v1/auth/me` profile, no role check** — every subsequent call would 401. **Break #3: identity = a string.**
5. Home tab renders catalog from hardcoded `HomeDataProvider` (`customer_home_screen.dart:28-50`) — no `GET /v1/catalog`, wrong prices/roles (rows e, l). **Break #4.**
6. "Order" taps run `OrderStateNotifier.placeNewOrder` (`featured_products.dart:63`, `mode_selection_cards.dart:79`) or the checkout sheet direct insert (`cart_checkout_sheet.dart:235-238`): no quote (`/v1/quotes`), no `Idempotency-Key`, no `address_id` (addresses aren't server-resident at all), no `window_start`, no `payment_mode`. **Break #5: the order would have nothing authoritative to send.** And the UI already claims success + "DISPATCHED" — a lie our server would never corroborate (`GET /v1/orders/{id}` isn't called).
7. Rider/vendor/owner screens (`login_screen.dart:104-116`) route partners into in-app dashboards fed by the same notifier — with our API a `role=user` session gets 403 on all staff doors (`flow.md:555`). **Break #6: cross-role screens that an API cannot serve here.**
8. Profile shows `+91 $userPhone` (`customer_profile_screen.dart:65`) with no `PATCH /v1/auth/me` (ADR-110 §4). **Break #7: profile is untethered.**

### 4.2 Our 028 flow for comparison (committed behavior)

`AuthGate: splash → restoreSession → shell / NameNumberScreen` (`flow.md:361`): first-run shows **name + number** screen (`flow.md:352-365`), `AuthController.registerNameNumber → AuthApi.register → POST /v1/auth/user/register {name, phone, device}` (with ADR-097 adding the required `email`), 200 `role==user` → `SessionStore.save` → shell; `role!=user` → wipe + honest error (`flow.md:357`); `verified:false` carried until first PoD (`flow.md:360`); guest browse is allowed but anything money-shaped demands the session (ADR-112 §2 lazy tab mounting guards this).

### 4.3 Correct target flow (sequence)

```mermaid
sequenceDiagram
    autonumber
    participant U as Customer UI
    participant API as Workers /v1 API
    participant RZP as Razorpay (Upstream)
    participant WH as Razorpay Webhook

    Note over U: First-run: naam + gmail + number (no OTP for customers)
    U->>API: POST /v1/auth/user/register {name, email(@gmail.com), phone, device}
    API-->>U: 200 {access_token(30m), refresh_token(7d), token_type:bearer, role:"user", verified:false}
    Note over U: store bearer pair; attach Authorization on EVERY call

    U->>API: GET /v1/catalog (skus refill/container paise, deposit_per_jar)
    U->>API: GET /v1/addresses (Bearer)
    U->>API: GET /v1/serviceability?pincode=… (else /v1/leads)
    U->>API: GET /v1/windows?date=…&pincode=…
    U-->>U: qty stepper (display only, prices = quote later)

    U->>API: POST /v1/quotes {items, e, address_id, window_start}
    API-->>U: {water_bill, deposit_due, cap_note, total(paise), quote_hash, expires_at(+15m)}
    U-->>U: show server total only

    U->>API: POST /v1/orders {items, e, address_id, window_start, quote_hash, quote_total, quote_rate_version, quote_expires_at, payment_mode} + Idempotency-Key: uuid
    alt payment_mode = upi
        U->>API: POST /v1/payments/upi-intent {order_id} + Idempotency-Key
        API-->>U: 201 {intent link} (Razorpay, AGENCY_UPI_VPA)
        U->>RZP: launch UPI deep link / gateway
        RZP->>WH: payment.captured → HMAC-signed webhook
        WH->>API: POST /v1/webhooks/upi (verify signature; order → paid)
        loop until terminal
            U->>API: GET /v1/orders/{id} (Bearer)
            API-->>U: payment_status
        end
        Note over U: ONLY payment_status == paid_upi marks success;<br/>else honest fail → retry (new Idempotency-Key) or switch to COD
    else payment_mode = cod
        U->>API: POST /v1/orders/{id}/cod-confirm (Bearer)
        Note over U: switch UPI→COD forces a FRESH Idempotency-Key (422 PAYLOAD_MISMATCH guard)
    end

    loop rider approaches
        U->>API: GET /v1/orders/{id}/tracking (Bearer)
        API-->>U: {state, tracker, delivery_otp, stops_ahead, rider{name, phone}}
    end
    Note over U: show stops_ahead live; PoD OTP is server-minted
```

**Verdict of this section:** the friend's identity model is not "a different flavor" of ours — it is **present-tense mockery with zero server contract**. All 7 breaks above are structural; there is no partial-credit path.

---

## 5. What can be salvaged without touching the data layer

### 5.1 Data-agnostic (re-feed from our controllers as-is)

| Screen / widget | Why it survives | file:line |
|---|---|---|
| Theme + design tokens | Pure color/spacing constants, our stack also uses Material on Flutter | `lib/core/theme/app_theme.dart`, `lib/core/constants/app_constants.dart:3-36` |
| Notifications list rendering | Icon/title/desc/time rows over a plain list of maps; re-feed from push history | `lib/features/home/presentation/notifications_screen.dart:9-55` |
| Support/help screen | Static content, no data object behind it | `lib/features/profile/presentation/support_help_screen.dart` |
| Wallet card *layout* | Static widget; `⟨/v1/ledger/me⟩` fields (held/deposit_paid/deposit_refunded/dues, `payments.py:86-92`) map 1:1 into the same card — only the `₹450.00` literal and the fake recharge snackbar must go (`wallet_screen.dart:55-60`) | `lib/features/profile/presentation/wallet_screen.dart:23-60` |
| Address cards rendering | Card layout over any address list; needs recipes from `GET /v1/addresses` (`addresses.py:70-74`) | `lib/features/profile/presentation/saved_addresses_screen.dart:105-170` |
| Order card list rendering | Renders `OrderItem{title, status, amount, slot, agent, eta}` — all present in `OrderOut`/tracking fields (`schemas/orders.py:45-63,66-73`); needs a mapper | `lib/features/orders/presentation/order_card.dart`, `my_orders_screen.dart:21-41` |
| Home tab scaffolding (nav, hero, mode cards layout) | Navigation shell and hero are state-free plumbing (`IndexedStack`, tab indices) | `lib/features/home/presentation/customer_home_screen.dart:53-70`, `widgets/bottom_nav_bar.dart` |
| GPS pin capture (with contract rewrite) | Real `geolocator` + reverse geocode exists and is production-grade UX; must be repointed to pincode-first serviceability | `lib/features/home/presentation/widgets/top_bar.dart:34-100` |
| OTP visual kit | The 4-box + timer chrome is decent; *only* usable inside a staff app, not customer (no OTP door for customers) | `lib/features/auth/presentation/login_screen.dart:409-523` |

### 5.2 Welded to the (stub) data layer — rewire or discard

| Screen / widget | Why it doesn't survive as-is | file:line |
|---|---|---|
| Checkout sheet | Builds/mutates orders in-RAM, client price math, instant success feedback, no payment stage | `lib/features/orders/presentation/cart_checkout_sheet.dart:27,32,220-259` |
| Featured products showcase | Direct `placeNewOrder` trigger + hardcoded catalog | `lib/features/home/presentation/widgets/featured_products.dart:63`; catalog `home_data_provider.dart:5-24` |
| Mode selection cards | Same direct-order trigger | `lib/features/home/presentation/widgets/mode_selection_cards.dart:79` |
| Subscription screens (both) | Client ids/price math/pause bools; two divergent implementations sharing nothing | `lib/features/orders/presentation/subscription_screen.dart:20,96,130-133,247`; `lib/features/subscriptions/presentation/subscription_screen.dart:11-34` |
| Rider dashboard + delivery + plant hub + owner center | Cross-role screens welded to the single customer notifier; cannot exist inside a `role=user` app (row **h**) | `rider_dashboard_screen.dart:57-67`, `rider_delivery_screen.dart:25-47`, `plant_hub_screen.dart:11,94,186-193`, `owner_control_center_screen.dart:4-50` |
| Login screen *logic* | Fake OTP theater + partner whitelist + string identity | `lib/features/auth/presentation/login_screen.dart:30-34,61-125` |
| Cart provider + models | `totalPrice` client math + rupee doubles + client discount — contrary to server-paise truth (rows e, j) | `lib/shared/providers/app_providers.dart:4-76`, `product.dart:9,49-63,79-100` |

### 5.3 Field-mapping cheat sheet (friend field → our truth) for the implementing agent

| Friend-side field (file:line) | Our wire truth | Endpoint | Mapping note |
|---|---|---|---|
| `OrderItem.amount: 'Rs 130.00'` (`order_service.dart:10,45`) | `total: int` paise (`schemas/orders.py:55`) | `GET /v1/orders`, `/quotes` | display `rupees(total)` only |
| `OrderItem.deliveryPin` (`order_service.dart:16,30`) | `delivery_otp` minted by server (`schemas/orders.py:68`) | `GET /v1/orders/{id}` / `tracking` | read-only, near-PoD |
| `OrderItem.deliveryAgent` (`order_service.dart:11,46`) | `rider: {name, phone, stops_ahead}` (`schemas/orders.py:71`) | `GET /v1/orders/{id}/tracking` | `null` before assignment |
| `OrderItem.timeSlot` (`order_service.dart:9,44`) | `window_start`/`window_end` (`schemas/orders.py:59-60`) | `GET /v1/windows` → `POST /v1/orders` | ISO string, not prose |
| `OrderItem.emptyCansToReturn` (`order_service.dart:12`) | quote/order input `e` (`schemas/orders.py:18,27-33`) | `POST /v1/quotes`, `/orders`, `/returns` | explicit user choice |
| `SubscriptionNotifier.pricePerDrop: 65.0` (`subscription_service.dart:35`) | first-cycle estimate from server (`subscriptions.py:65-71`) | `POST /v1/subscriptions/estimate` | Pay label only |
| `AddressModel {tag,title,landmark,floor,fullAddress,contact}` (`saved_addresses_screen.dart:4-24`) | `AddressOut` (`addresses.py:70-76`) | `GET/POST /v1/addresses` | becomes `address_id` |
| `Product.price: double` (`product.dart:9`) | `SkuOut.price_paise: int` (`schemas/catalog.py:10-12`) | `GET /v1/catalog` | no `double` |
| `ProductType.bottle1L` (`product.dart:1`, seeded at `home_data_provider.dart:20`) | no such SKU — `Literal["refill","container"]` (`schemas/catalog.py:7`) | — | drop or lead-gate |
| Notif item `'Deposit Recharged … Rs 500'` (`notifications_screen.dart:35-38`) | real `deposit_paid/deposit_refunded` (`payments.py:84-92`) | `GET /v1/ledger/me` | ledger card, not push |
| `CustomerHomeScreen.userPhone` (`customer_home_screen.dart:12-13`) | `GET /v1/auth/me → {user}` (`auth.py:181-183`, `flow.md:468`) + `PATCH /v1/auth/me` (`auth.py:186-198`) | `/v1/auth/me` | profile lives on server |
| `UserRole {customer, rider, vendor, owner}` (`owner_control_center_screen.dart:4`) | exactly one role per session (`auth_service.py:540,545`) | register / vendor-login / admin-login | staff split across apps |

### 5.4 Surfaces with no lint-checked network debt (fresh-build advantage)

- `test/widget_test.dart` and the stray repo-root `main.dart` are the only non-lib Dart files; the repo build surface is minimal enough that a visibility/swagger-free rewrite of `lib/` data files will not orphan tests (the single `widget_test.dart` is a build smoke).
- No flavors, no env config, no runtime base-url switching exists to unwind — the import starts from zero configuration, which removes one entire class of drift.

---

## Verdict

**This is not a drop-in replacement and not even a clean "skin to transplant" — it is a parallel build with a salvageable skin.** The friend's UI contains no network layer, no identity, no money truth: every screen is fed by five process-memory singletons seeded with hardcoded data, and auth is a fake OTP that accepts any code. Roughly the *presentation chrome* (theme, nav shell, list-card layouts, notification/rendering widgets) survives; everything that touches identity, money, order state, subscriptions, or addresses must be rebuilt against the `/v1` contracts. Realistically: keep the visual language, rewrite 100% of the data layer, and port generously from the proven `apps/user_app` controllers (register flow, ApiClient + refresh loop, booking controller with idempotency refresh, UPI poll-verify) rather than reinventing them.

**The 5 contract doors every imported screen must pass (in order):**

1. **Identity door** — session exists only via `POST /v1/auth/user/register {name, email(@gmail.com), phone, device}`; `role == "user"` is asserted on response; `Authorization: Bearer <access>` accompanies every subsequent call; `role != user` → wipe + re-login. No OTP UI for customers, no staff screens in this app.
2. **Money door** — nothing on screen computes money. Quantities may be incremented client-side; the amount shown always comes from `POST /v1/quotes` (or `/v1/subscriptions/estimate`), is integer paise on the wire, and is display-converted (÷100) only. Deposits (₹150/jar `deposit_per_jar`) and repeat-order deposit waiving are **server outputs**, never client math.
3. **Order door** — an order can only be placed after a quote: payload carries `quote_hash`, `quote_total` echo, `quote_rate_version`, `quote_expires_at`, server `address_id`, ISO `window_start`, and a fresh UUID `Idempotency-Key` header (regenerated whenever the payment mode changes or a payment retry happens).
4. **Payment door** — UPI means: `POST /v1/payments/upi-intent` → launch `intent['link']` → **poll `GET /v1/orders/{id}` until `payment_status == 'paid_upi'`** (webhook is the verifier; the client never declares success on return-from-app). COD means: switchable mode + `POST /v1/orders/{id}/cod-confirm`, with the fresh idempotency key from door 3. Failures show honest retry/COD fallback, never a pre-success toast.
5. **Data-truth door** — catalog comes from `GET /v1/catalog` (SKUs `refill`/`container`, paise); slots from `GET /v1/windows?date=&pincode=`; pincode eligibility from `GET /v1/serviceability` (miss → `/v1/leads`); addresses are server objects with stable `address_id` (frozen in snapshots once dispatched); live delivery truth from `GET /v1/orders/{id}/tracking` (`delivery_otp`, `stops_ahead`, `rider`) — the client never mints PINs, ETAs, order ids, or statuses.
