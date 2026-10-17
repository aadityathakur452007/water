# 04 — Engineering & Packaging Audit: Friend's `shodasha-friend-ui` as an Import Donor

- **Donor repo audited:** `C:\Users\Hp\AppData\Local\Temp\opencode\shodasha-friend-ui` (shallow clone, 1 visible commit)
- **Comparator:** `C:\Users\Hp\Water\apps\user_app` (our conventions: `features/<feature>/{screen,controller}`, single `core/api_client.dart` with Bearer/refresh/retry, ~136–138 tests across 20 test files, analyze-clean, KTS/AGP-9 Android packaging)
- **Audited against:** `context/code-standards.md`, `context/architecture.md` (Frontend Structure + Invariants 1–8)
- **Scope:** engineering + Android packaging quality of the donor as an import donor. No code modified.
- **Count method:** PowerShell regex sweeps over `lib/**/*.dart`; all counts reproducible.

---

## 1. Repo hygiene

| Item | State | Evidence |
|---|---|---|
| README | ❌ Untouched `flutter create` template ("A new Flutter project", codelab links, zero project docs) | `README.md:1-16` |
| `.metadata` | ⚠️ Flutter **beta** channel, revision `8fcb74db…` (a ~3.16-era beta, late 2023). Our app is on **stable** (`apps/user_app/.metadata:8`) | `.metadata:7-8` |
| SDK constraint | ⚠️ `>=3.0.0 <4.0.0` (very loose floor) vs ours `^3.12.2` | `pubspec.yaml:6` vs `apps/user_app/pubspec.yaml:22` |
| analysis_options | ❌ Includes `flutter_lints` but **disables 4 rules**: `prefer_const_constructors`, `prefer_const_literals_to_create_immutables`, `unnecessary_to_list_in_spreads`, `curly_braces_in_flow_control_structures`. Ours disables nothing (`apps/user_app/analysis_options.yaml:23-26` are comments only) | `analysis_options.yaml:1-8` |
| Lint set age | ⚠️ `flutter_lints 3.0.1` locked vs ours `^6.0.0` | `pubspec.lock:153-160` vs `apps/user_app/pubspec.yaml:57` |
| Git history | ❌ Shallow clone (`rev-parse --is-shallow-repository` = `true`): only 1 commit visible (`76e0eba "release: v1.1.0 - Full auth, RBAC login & logout for customer rider and plant vendor"`). Commit-message hygiene / course-artifact cleanup CANNOT be verified from this clone — noted as unverifiable, and the single message over-claims ("Full auth, RBAC") vs the hardcoded mock auth actually shipped (`lib/features/auth/presentation/login_screen.dart:30-34,61-125`) | git ls-files / log |
| Tracked junk (build artifacts) | ❌ `build_backups/Shodasha_v1.0.0_Stable.apk` — **14.5 MB APK binary committed** | `git ls-files` |
| Tracked junk (gradle output) | ❌ `android/build/reports/problems/problems-report.html` tracked; `.gitignore:33` only covers root `/build/`, so `android/build/` leaks in | `git ls-files`; `.gitignore` |
| Secrets — Firebase | ❌ **`android/app/google-services.json` is committed** with real identifiers: `project_id: "shodasha-mineral-water"`, `project_number: 410454933678`, Firebase Android API key `AIzaSyD-ox02sktuKz3ytFq68h82Q4`-style value at `google-services.json:18` — the only `AIza` hit in the repo. Treat as burned/rotatable; do not import. | `android/app/google-services.json:2-20` |
| Secrets — UPI/VPA | ✅ No VPA/PSP strings anywhere (`shodasha@upi`, `@ok…`, `sk_live` etc. → 0 hits). Only a cosmetic label `'Wallet Recharge (UPI)'` | `lib/features/profile/presentation/wallet_screen.dart:112` |
| Secrets — phone numbers | ⚠️ Hardcoded mock personal numbers pervade the app: partner registry `9826011111/222222/999999` (`login_screen.dart:30-34`), helpline `+91 98260 00112` and mock WhatsApp `+91 755-SHODASHA` (alphabetical, not dialable) (`support_help_screen.dart:114,133`), fleet PII-shaped data `+91 98260 11223` etc. (`owner_control_center_screen.dart:19-41`), `+91 98930 00000` (`customer_profile_screen.dart:147`), address contacts `+91 98930 12345` (`saved_addresses_screen.dart:38,48`). Mock data, not secrets — but all must be replaced/removed on import | cited files |
| Must never ship list | ❌ `build_backups/*` (APK), `test/widget_test.dart` (dead counter stub, see §5), `android/build/**` (report HTML), root `main.dart` (353-line parallel demo app `ShodashaApp`/`MasterHubScreen` — not the real entry (`lib/main.dart` uses `ShodashaWaterApp`); confuses grep and analyzers), committed `google-services.json` (§4) | files cited |

**Suspicious/version claims (task premise checked against reality):**
- ⚠️ `equatable: ^3.0.0` (`pubspec.yaml:10`) is **not fabricated** — pub.dev shows 3.0.0 published **2026-09-15** and the lock's sha256 matches exactly (`pubspec.lock:84-91`). It is current. The real problem: it is a **dead dependency** — 0 imports in `lib/`.
- ❌ `geolocator: ^11.1.0` (`pubspec.yaml:15`, locked at `pubspec.lock:203-210`) is 3 majors behind our `^14.1.1`, and the only consumer already uses the API shape that breaks on upgrade: `Geolocator.getCurrentPosition(desiredAccuracy:…, timeLimit:…)` (`lib/features/home/presentation/widgets/top_bar.dart:62-65`) — the `desiredAccuracy` argument is the deprecation path geolocator took in ≥13.
- ⚠️ `cloud_firestore ^4.14.0` + `firebase_core ^2.24.2` are **late-2023 vintage** and **entirely unused**: `cloud_firestore` has 0 imports in `lib/`. `firebase_core` is imported exactly once, just to init (`lib/main.dart:3,9`).
- ⚠️ `provider ^6.1.5+1` and `shared_preferences ^2.2.2` are declared-and-locked but `provider` is **never wired** — no `MultiProvider`/`Provider` anywhere in `lib/` (0 matches); `shared_preferences` has 0 imports.

---

## 2. Architecture violations (vs `context/code-standards.md` + `context/architecture.md`)

### 2.1 No real feature layering / data layer
- ❌ Half-hearted `data/` layer exists only in `features/orders` (`order_service.dart`, `subscription_service.dart`, `plant_service.dart`) — and every "service" is an **in-memory singleton of mock data**, not an API/repository:
  - `OrderStateNotifier.instance` with hardcoded Bhopal orders + delivery PINs (`lib/features/orders/data/order_service.dart:34-70`)
  - `SubscriptionNotifier.instance` (`subscription_service.dart:23-37`), `PlantTelemetryNotifier.instance` (`plant_service.dart:3-12`)
- ❌ The largest "state service" lives **inside a screen file**: `AddressStateService extends ChangeNotifier` defined in `lib/features/profile/presentation/saved_addresses_screen.dart:26-88` (service-in-presentation anti-pattern).
- ❌ No session store, no ApiClient, no error envelope, no repository seam — screens *are* the backend. Violates our Backend-Service-Repository pattern analog and Invariant 7 (`features/` never deep-reached — here everything is deep-reached).

### 2.2 Screens doing business logic (cart/checkout + order split)
- ❌ `cart_checkout_sheet.dart` (a widget) constructs business objects, mutates a public list on the notifier, and fires `notifyListeners()` from outside with a suppression comment:
  - Hardcoded price `_pricePerCan = 65` (`cart_checkout_sheet.dart:27`)
  - Order ID from `DateTime.now().millisecond * 7` — collision-prone (`:222`)
  - `notifier.activeOrders.insert(0, newOrder)` + `// ignore: invalid_use_of_protected_member… notifyListeners()` (`:235-238`)
  - Meanwhile `order_service.dart:72-119 placeNewOrder()` is the "official" path — a parallel order-placing pipeline.
- ❌ Order placement exists in **4 separate UI paths**: `cart_checkout_sheet.dart:220-244`, `order_service.dart:placeNewOrder` (used by `featured_products.dart:63`), `mode_selection_cards.dart:79-85`, and the dead `orders/subscription_screen.dart:96-101`. Each hardcodes ₹65 and its own ID scheme. Ours centralizes this in a feature controller + `checkout_service.dart`.

### 2.3 Provider wiring: god-provider file that is never wired
- ❌ `lib/shared/providers/app_providers.dart` is a 118-line "providers" file (`CartProvider:4`, `LocationProvider:78`, `HomeProvider:93`) — **dead from birth**: `lib/main.dart:20-37` declares `MaterialApp` with no `MultiProvider`; 0 provider wiring in the whole `lib/`.
- ❌ Actual state = 4 global singletons (`OrderStateNotifier`, `SubscriptionNotifier`, `PlantTelemetryNotifier`, `AddressStateService`) + `28 setState` + `18 notifyListeners` calls distributed across screens. Ours: per-feature controllers constructed through the shell.

### 2.4 Models placement & duplication
- ❌ `shared/models/product.dart` defines `Product/CartItem/DeliveryLocation/SubscriptionPlan` — **unused by the real UI** (`featured_products.dart:95-99` invents hardcoded `Map<String,Object>` products instead). Only consumers are the dead `HomeDataProvider` (`home_data_provider.dart:5-24`).
- ❌ Domain-model duplication: `DeliveryLocation` (`shared/models/product.dart:65-77`) vs `AddressModel` (`profile/presentation/saved_addresses_screen.dart:4-24`) — two address models in one codebase.
- ❌ `shared/models.dart` is a 1-line barrel (`export 'models/product.dart';`) — no `entities/` concept, violates our feature-first placement (models belong to the feature that owns them).

### 2.5 Literal duplication: TWO `SubscriptionScreen` classes
| | `features/subscriptions/…/subscription_screen.dart` | `features/orders/…/subscription_screen.dart` |
|---|---|---|
| Lines | 386 | 259 |
| Widget shape | StatefulWidget, local `setState`, calendar grid | StatelessWidget + `AnimatedBuilder` on `SubscriptionNotifier` |
| Styling | `AppColors.*` for chrome | Dark AppBar `0xFF0F172A`, blue gradient `0xFF0284C7→0369A1`, raw `Color(…)` everywhere |
| Importers | ✅ **LIVE** — imported by `customer_home_screen.dart:4` (Profile tab index 2) | ❌ **DEAD** — 0 importers in `lib/` (grep-verified) |
| Bug | Calendar pinned to "OCTOBER 2026" with hardcoded delivered/paused day sets (`:16-17,239`) | Line 228 string literal bug: `'${sub.frequency} \vert{}${sub.deliveryTime}'` renders a vertical-tab char + literal `vert{}` in UI |

**Verdict on which is dead code:** `features/orders/presentation/subscription_screen.dart` is dead (delete); the active one is `features/subscriptions/…`. Both are mock-only, neither talks to `SubscriptionService` (only the dead one does).

### 2.6 Stubs & dead screens
- ❌ `my_orders_screen.dart` is a 43-line stub: ListView + 3 mapped children (`:36`), no pull-to-refresh, no pagination, no error state, empty state only (`:33-34`).
- ❌ **Dead widgets/screens** (0 importers, grep-verified): `features/home/presentation/widgets/bottom_nav_bar.dart` (customer home builds its own `BottomNavigationBar` inline — `customer_home_screen.dart:71-107`), `widgets/live_purity_card.dart`, `SavedAddressesScreen` UI (only its `AddressStateService` is imported — and Profile's "Saved Addresses" tile just shows a SnackBar, `customer_profile_screen.dart:121-124`), `SupportHelpScreen` (0 importers).
- ❌ `core/theme/app_theme.dart` (`AppTheme.lightTheme`, 103 lines) — **never used**; `lib/main.dart` builds its own `ThemeData` inline with `useMaterial3: false`.

### 2.7 Role-mixing anti-pattern (vs our 3-surface split)
- ❌ One logically-mixed "everything" app: rider + vendor + owner consoles all ship inside the **customer** app:
  - Partner portal switch in login routes to `RiderDashboardScreen` / `PlantHubScreen` (`login_screen.dart:104-116`)
  - **Customer profile tile "Owner Control Center" opens the full owner fleet/customer console** with complete mock rider/customer PII tables (`customer_profile_screen.dart:99-111` → `admin/presentation/owner_control_center_screen.dart:17-70`)
  - **Customer order card has a rider action button** "RIDER: ENTER PIN & DELIVER CANS" that opens `RiderDeliveryScreen` (`order_card.dart:225-247`) — a customer-visible rider workflow
  - Customer sees the delivery PIN on the card (`order_card.dart:198-206`) and the rider screen even prints it as a hint (`rider_delivery_screen.dart:141`)
- ❌ Violates our split: user app + vendor app + Super Admin web (`architecture.md:6-7`) — the donor's ordering UI and ops UI must be separated at import.

---

### 2.8 `lib/` file classification (live / dead / partial)

| File | Lines | Status | How we know |
|---|---|---|---|
| `main.dart` | 37 | ✅ LIVE (entry) | `MaterialApp` → `LoginScreen` |
| `core/constants/app_constants.dart` | 36 | ✅ LIVE | imported by every screen |
| `core/theme/app_theme.dart` | 103 | ❌ DEAD | 0 imports of `AppTheme` (grep) |
| `shared/models.dart` + `shared/models/product.dart` | 2 / 100 | ❌ DEAD-in-practice | only consumer is dead `HomeDataProvider`; real UI uses hardcoded maps |
| `shared/providers/app_providers.dart` | 118 | ❌ DEAD | no `MultiProvider` anywhere; providers never instantiated |
| `features/auth/.../login_screen.dart` | 546 | ✅ LIVE — but mock-only auth (whitelist + `Future.delayed` OTP) | `:30-34`, `:79-87`, `:100-116` |
| `features/home/.../customer_home_screen.dart` | 111 | ✅ LIVE | IndexedStack of 5 tab screens |
| `features/home/.../widgets/top_bar.dart` | 585 | ✅ LIVE | imported by customer_home `:7` |
| `.../widgets/featured_products.dart` | 159 | ✅ LIVE | imported by customer_home `:8` |
| `.../widgets/mode_selection_cards.dart` | 192 | ✅ LIVE | imported by customer_home `:9` |
| `.../widgets/bottom_nav_bar.dart` | 62 | ❌ DEAD | 0 importers; home builds its own `BottomNavigationBar` inline |
| `.../widgets/live_purity_card.dart` | 136 | ❌ DEAD | only its own class declaration mentions it |
| `.../notifications_screen.dart` | 132 | ✅ LIVE | via `top_bar.dart:2` push |
| `.../providers/home_data_provider.dart` | 38 | ❌ DEAD | 0 importers; references missing assets `jar_20l.png`/`bottle_1l.png` |
| `features/orders/.../my_orders_screen.dart` | 43 | ✅ LIVE | customer_home tab 1; no builder, no refresh, no error state |
| `features/orders/.../order_card.dart` | 254 | ✅ LIVE | imports `rider_delivery_screen.dart` — role-mixed button |
| `features/orders/.../cart_checkout_sheet.dart` | 278 | ✅ LIVE | via `top_bar.dart:1`; bypasses notifier API |
| `features/orders/.../subscription_screen.dart` | 259 | ❌ **DEAD twin** | 0 importers; contains `\vert{}` string bug `:228` |
| `features/orders/.../rider_dashboard_screen.dart` | 263 | ✅ LIVE (wrong app) | via `login_screen.dart:4` partner portal |
| `features/orders/.../rider_delivery_screen.dart` | 184 | ✅ LIVE (wrong app) | via `order_card.dart:5` + `rider_dashboard_screen.dart:5` |
| `features/orders/.../plant_hub_screen.dart` | 419 | ✅ LIVE (wrong app) | via `login_screen.dart:5` vendor route |
| `features/orders/data/order_service.dart` | 139 | ⚠️ LIVE (mock singleton) | 4 UI placement paths + my_orders + rider + plant |
| `features/orders/data/subscription_service.dart` | 64 | ⚠️ LIVE-for-dead-screen | only consumer is the dead twin |
| `features/orders/data/plant_service.dart` | 26 | ⚠️ LIVE | plant_hub + (dead) live_purity_card |
| `features/subscriptions/.../subscription_screen.dart` | 386 | ✅ **LIVE twin** | customer_home `:4` |
| `features/profile/.../wallet_screen.dart` | 173 | ✅ LIVE | customer_home `:5` + profile push |
| `features/profile/.../customer_profile_screen.dart` | 212 | ✅ LIVE | customer_home `:6`; opens owner console |
| `features/profile/.../saved_addresses_screen.dart` | 171 | ⚠️ HALF-DEAD | screen UI never navigated to; only its embedded `AddressStateService` is consumed |
| `features/profile/.../support_help_screen.dart` | 190 | ❌ DEAD | 0 importers |
| `features/admin/.../owner_control_center_screen.dart` | 393 | ✅ LIVE (wrong app) | via profile tile |
| root `main.dart` (outside `lib/`) | 353 | ❌ DEAD demo | parallel `ShodashaApp`; git-tracked; not the build entry |
| `test/widget_test.dart` | 30 | ❌ RED stub | asserts counter template against the real app |

- ❌ Net: **9 fully dead Dart files inside `lib/` ≈ 1,008 lines** + 3 half-dead files, out of a ~4,000-line `lib/` — a large fraction of the codebase is dead, wrong-app, or unwired scaffolding that an import would have to triage file-by-file. (Including root `main.dart` + the red test stub, 1,391 dead lines total.)

---

## 3. Flutter code quality

### 3.1 Component size discipline (standard ≈ ≤300 lines, `code-standards.md:5`)

| File | Lines | Status |
|---|---|---|
| `features/home/presentation/widgets/top_bar.dart` | **585** (brief said 555 — it is 585 in today's checkout) | ❌ A top bar owning address CRUD sheet (`:151-475`), custom GPS fetch flow, time-slot picker |
| `features/auth/presentation/login_screen.dart` | 546 | ❌ (with well-disposed resources, see 3.5) |
| `features/orders/presentation/plant_hub_screen.dart` | 419 | ❌ + 4 un-disposed controllers |
| `features/admin/presentation/owner_control_center_screen.dart` | 393 | ❌ |
| `features/subscriptions/…/subscription_screen.dart` | 386 | ⚠️ borderline (double-height with the dead twin counted) |

### 3.2 const discipline
- ⚠️ 815 `const` occurrences across `lib/` — decent. But the two lints that enforce it are **switched off** (`analysis_options.yaml:5-6`), and large non-const ladders remain (e.g. `featured_products.dart:112-155` map-spread of full containers). Ours keeps default lint enforcement.

### 3.3 List rendering
- ⚠️ `ListView.builder` only in 4 spots (`owner_control_center_screen.dart:139,220`, `notifications_screen.dart:59`, `saved_addresses_screen.dart:109`).
- ⚠️ Everything else is bounded `Column`/`ListView` + spread-of-mapped-children (`my_orders_screen.dart:36`, `rider_dashboard_screen.dart:153,224`, `featured_products.dart:112`, `orders/subscription_screen.dart:180`). Fine for current hardcoded data, wrong pattern for real datasets; no `RefreshIndicator` anywhere (0 hits).

### 3.4 Image handling & asset truth
- ✅ `Image.asset('assets/images/login_hero.png')` exists in repo and is used with an `errorBuilder` fallback (`login_screen.dart:207-216`).
- ❌ **Featured products use `Icon` glyphs, not images at all** (the audit premise "featured uses asset images" is false in today's checkout): `featured_products.dart:96-99,129` renders `Icons.water_drop` etc.
- ❌ Asset inventory vs reality:
  - Present & used: `assets/images/login_hero.png`
  - Present & **unused** (screenshot-style mock assets with suspicious double extensions): `img_rider.png.jpg`, `img_login.png.jpg`, `img_home.png.jpg`, `img_delivered.png.jpg` (`assets/images/`)
  - **Referenced but missing**: `assets/images/jar_20l.png`, `assets/images/bottle_1l.png` (`home_data_provider.dart:12,21`) — would 404 if that (dead) provider were ever viewed; silently broken because dead.

### 3.5 Controller dispose hygiene
- Controller census: **12 `TextEditingController` instances created** across 4 files (login 5 = `_phoneController` + `List.generate(4,…)` OTP boxes; top_bar 2; plant_hub 4; rider 1).
- ✅ `login_screen.dart:37-47` disposes its 5 controllers + 4 focus nodes + 1 timer (best file in repo).
- ✅ `owner_control_center_screen.dart:88-92` disposes `TabController`.
- ❌ **7 leaked `TextEditingController`s across 3 files** (never `.dispose()`d):
  - `rider_delivery_screen.dart:15` `_pinController` — never disposed (class has no `dispose` override at all)
  - `top_bar.dart:152` `editCtrl`, `top_bar.dart:187` `manualAddrCtrl` — dialog/bottom-sheet scoped, never disposed
  - `plant_hub_screen.dart:12-15` `stockCtrl/batchCtrl/tdsCtrl/phCtrl` — method-scoped (dialog), never disposed

### 3.6 Material 2 vs 3 mismatch
- ❌ Active app theme is **Material 2** (`lib/main.dart:32 useMaterial3: false`); the *unused* `AppTheme` declares **Material 3** (`core/theme/app_theme.dart:11 useMaterial3: true`) — opposite presets, neither exercised. Ours runs a single coherent M3 `ThemeData` (`apps/user_app/lib/core/theme.dart`).

### 3.7 Theme hardcoding (measured)
- ❌ **247 `Color(0x…)` literals** across `lib/`; 14 are the definitions in `core/constants/app_constants.dart`, so **233 inline literals in screens/widgets** vs ours: colors only via `AppColors`/theme. (Top offenders: login 51, owner console 37, dead orders-subscription 23, live subscriptions 18, wallet 17.)
- ❌ Two brand palettes conflict: theme `primary` is teal `0xFF0D9488` (`app_constants.dart:5`), but the login + checkout + rider flows prime a **green** `0xFF16A34A` (e.g. `login_screen.dart:150,171,214`, `cart_checkout_sheet.dart:95,215`). No `Theme.of(context)` usage anywhere (0 matches) — `withOpacity` 30× for brand tints.

### 3.8 Responsive / layout risk
- ⚠️ `LayoutBuilder` 0×, `MediaQuery` 3× (only keyboard insets) — effectively zero responsive logic; heavy fixed geometry: 58×58 OTP boxes (`login_screen.dart:476`), 36×36 header buttons (`top_bar.dart:503-546`), fixed `SizedBox(height: 52)` CTAs. Acceptable on phones; breaks on wider form factors — ours is Android-only v1 too, but our screens were built with fewer hardcoded pixel cards.

### 3.9 Accessibility
- ❌ `Semantics` 0× in the entire `lib/`.
- ❌ Touch targets below 44/48dp despite the constant existing: `AppConstants.minTapTarget = 48.0` is defined (`app_constants.dart:33`) but honored by nobody — 36×36 icon buttons (`top_bar.dart:502-518`, `534-546`), 18dp edit/delete icon buttons inside ListTiles (`top_bar.dart:306-316`), 36px-height text buttons (`orders/subscription_screen.dart:238-252`).
- ⚠️ Tooltips only on 2 AppBar logout buttons (`rider_dashboard_screen.dart:23`, `plant_hub_screen.dart:170`).

### 3.10 Text overflow handling
- ⚠️ `maxLines` 5×, `TextOverflow.ellipsis` 6× — only on the long strings that visibly needed it (`cart_checkout_sheet.dart:107-114`, `top_bar.dart:298-299`, `order_card.dart:167-168`).
- ❌ The dead subscription screen ships a corrupted visible string: `'\vert{}'` renders literal garbage (`orders/subscription_screen.dart:228`).
- ❌ Product/order titles elsewhere are single-line-bounded but often without `maxLines` at all (e.g. `featured_products.dart:136`). Literal text like `'DELIVERY: … ▾'` is ellipsized (`top_bar.dart:558-563`).

### 3.11 Loading / empty / error states
- ❌ The entire data plane is synchronous in-memory, so **no screen has a genuine loading state**. `CircularProgressIndicator` appears 3× — all fake-latency or GPS chrome: login submit buttons (`login_screen.dart:388,536` — behind `Future.delayed(600/700ms)` mock OTP at `:79,100`), GPS pill (`top_bar.dart:239-243`).
- ✅ Empty states exist in exactly 2 places: `my_orders_screen.dart:33-34`, `rider_dashboard_screen.dart:134-151`.
- ❌ No try/catch/user-facing error or retry anywhere in interaction code (only Firebase-init swallow at `lib/main.dart:8-12` and GPS catch at `top_bar.dart:112-122`). Compare ours: `ApiException` codes + offline banner protocol (`apps/user_app/lib/core/api_client.dart:25-46`).

---

## 4. Android packaging audit (owner-flagged; donor vs `apps/user_app/android`)

### 4.1 Identity / package
- ❌ `namespace` and `applicationId` = **`com.example.shodasha`** (`android/app/build.gradle:22,40`; manifest activity hardcodes `com.example.shodasha.MainActivity`, `AndroidManifest.xml:11`). Ours: `com.shodasha.shodasha_app` (`apps/user_app/android/app/build.gradle.kts:27,38`). Full package rename required on import (manifest activity, both Kotlin dirs, `google-services.json` package_name, README/tests).
- ❌ **Two Kotlin MainActivities in parallel trees** — `src/main/kotlin/com/example/shodasha/MainActivity.kt` AND `src/main/kotlin/com/example/shodasha_mineral_water/MainActivity.kt` (identical 6-line stubs). The `_mineral_water` one matches the pubspec `name:` and is dead weight; keep only one after rename.
- ⚠️ Label: `"Shodasha Mineral Water"` vs ours `"Shodasha"` (donor `AndroidManifest.xml:7` vs user_app `AndroidManifest.xml:8`).

### 4.2 Permissions
| Permission | Donor | Ours | Notes |
|---|---|---|---|
| `INTERNET` | ✅ `manifest:2` | ✅ | equal |
| `ACCESS_FINE_LOCATION` / `COARSE` | ✅ `manifest:3-4` | ✅ | donor legitimately uses geolocator/geocoding (top_bar GPS) |
| `POST_NOTIFICATIONS` | ✅ absent (appropriate) | absent after Phase-4 removal (decision.md:598 — "POST_NOTIFICATIONS removed both manifests") | parity; neither sends notifications |
| `CALL_PHONE` / dialer | ✅ none | none needed (we use `url_launcher` tel:/wa.me which needs no permission) | donor's "Direct Call"/"WhatsApp" buttons are **fake dialogs only** (`support_help_screen.dart:110-138`) — no `url_launcher`, no `tel:`/`wa.me` |
| `queries` | ⚠️ only `com.google.android.gms` package (`manifest:30-32`) | PROCESS_TEXT intent (user_app `manifest:47-52`) | cosmetic |

- ✅ `hardwareAccelerated="true"`, `singleTop`, `adjustResize`, embedding v2 — all standard, matches ours.

### 4.3 Launcher icon / branding
- ❌-for-import: pure **Flutter defaults**: only `@mipmap/ic_launcher.png` at 5 densities (`mipmap-mdpi…xxxhdpi`), **no `mipmap-anydpi-v26`, no adaptive icon XML, no round icon, no branding**. Our baseline: `mipmap-anydpi-v26/ic_launcher.xml` + `flutter_launcher_icons` wired to `assets/logo.png` with white adaptive background (user_app `pubspec.yaml:62-68`, `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`). Donor icon assets must not ship; regenerate from our pipeline.
- ✅ Launch theme scaffolding present but default (`values/styles.xml`, `values-night/styles.xml`, `drawable[-v21]/launch_background.xml`); **no** `colors.xml` / `backup_rules.xml` / `data_extraction_rules.xml` (ours has all three, plus `allowBackup="false"` — donor allows backup implicitly).

### 4.4 Gradle / toolchain (vs our KTS setup)

| | Donor | `apps/user_app` |
|---|---|---|
| Build script | ❌ legacy **Groovy** `build.gradle` + legacy `apply plugin` loader (`android/settings.gradle:13-20` app_plugin_loader belt pattern) | ✅ KTS `build.gradle.kts` + `settings.gradle.kts` declarative plugins |
| AGP / Kotlin | ❌ AGP `8.1.0`, Kotlin `1.9.0` classpath (`android/build.gradle:27-28`) | ✅ AGP `9.0.1`, Kotlin `2.3.20` (`settings.gradle.kts:22-23`) |
| Gradle wrapper | ❌ 8.4 (`gradle-wrapper.properties:5`) | ✅ 9.1.0 |
| compile/target/min SDK | ❌ `compileSdkVersion 33`, `targetSdkVersion 33`, `minSdk 21` (`build.gradle:23,41-42`) — **targetSdk 33 fails 2026 Play upload policy** (needs ≥34/~35 under our toolchain it becomes `flutter.targetSdkVersion` automatically) | ✅ derived from `flutter.*` (`build.gradle.kts:28,41-43`) |
| JDK pinning | ❌ **machine-locked absolute path committed**: `org.gradle.java.home=C:/Program Files/Microsoft/jdk-17.0.20.101-hotspot` (`android/gradle.properties:2`) — build-breaking on any other machine; also `org.gradle.daemon=false` | ✅ no machine paths |
| Release signing | ❌ **debug-signed release**: `signingConfig signingConfigs.debug`, `minifyEnabled false`, `shrinkResources false` (`build.gradle:48-52`) — no keystore, no `key.properties`, no R8. Exactly the gap the owner suspected; our baseline wires `key.properties` + minify+shrink with debug fallback (`build.gradle.kts:47-66`) | ✅ |
| Firebase glue | ❌ `apply plugin: 'com.google.gms.google-services'` (`build.gradle:61`) + committed `google-services.json` (§1) | none |

### 4.5 Firebase removal work (it IS initialized at startup — contrary to brief premise)
- ❌ `lib/main.dart:6-14`: `WidgetsFlutterBinding.ensureInitialized()` + `await Firebase.initializeApp()` in a `try/catch` that **swallows all failures** (`debugPrint("Firebase init note: $e")`) — the app pretends Firebase boot always succeeded.
- ❌ Facets to rip out on import: ① `firebase_core` + `cloud_firestore` deps (`pubspec.yaml:9,11`), ② init block (`main.dart:3,8-12`), ③ google-services plugin line (`build.gradle:61`), ④ `android/app/google-services.json`, ⑤ `queries → com.google.android.gms` (optional, `manifest:31`). Since `cloud_firestore` has 0 imports, removal is dependency-surgical with zero UI fallout — no screen references Firestore.

### 4.6 Non-Android platform folders
- ⚠️ `ios/`, `macos/`, `windows/`, `linux/`, `web/` all present and are **pristine template copies** (e.g. `web/index.html` title is literally `shodasha_mineral_water`). For Android-only v1 these should be pruned at import time rather than carried.

### 4.7 Manifest side-by-side (donor vs our baseline)

| Aspect | Donor (`android/app/src/main/AndroidManifest.xml`) | `apps/user_app` | Import action |
|---|---|---|---|
| Package references | ❌ hardcoded `com.example.shodasha.MainActivity` (`:11`) | `.MainActivity` relative (`:15`) | rename + relative reference |
| Label | `Shodasha Mineral Water` (`:7`) | `Shodasha` (user_app `:8`) | pick one brand string |
| Backup policy | ❌ none (backup allowed implicitly) | `allowBackup="false"` + `dataExtractionRules` + `fullBackupContent` (user_app `:11-13`) | adopt ours (tokens must never back up) |
| Icon | ❌ `@mipmap/ic_launcher` raster only, no anydpi-v26 | same ref + adaptive XML exists | regenerate via flutter_launcher_icons from `assets/logo.png` |
| Hardware accel / windowSoftInput / embedding | ✅ identical defaults (`:16-17,27-28`) | identical | none |
| `queries` | only GMS package (`:30-32`) | PROCESS_TEXT intent (user_app `:47-52`) | swap to ours |
| Theme styles | ✅ default `LaunchTheme`/`NormalTheme`, `values-night` present | same + `colors.xml` | none |

### 4.8 Git-tracked inventory fact-check
- `git ls-files` = 168 tracked files; tracked junk confirmed by the same command: `build_backups/Shodasha_v1.0.0_Stable.apk`, `android/build/reports/problems/problems-report.html`, `android/app/google-services.json`.
- ✅ No `.idea/`, `.vscode/`, `.dart_tool/`, `.history/` committed — the `.gitignore` itself is the standard template (only gap: no `android/build/` pattern).

---

## 5. Testing & CI reality

- ❌ The **only** test file is the default counter stub `test/widget_test.dart`
  - Imports the real app (`:11`), pumps `ShodashaWaterApp`, then asserts the **counter template assertions**: `find.text('0')` findsOneWidget, `find.text('1')` findsNothing, tapping `Icons.add` (`:19-28`).
  - The actual app boots to `LoginScreen` with no counter UI and no `Icons.add` → **this test fails as-is**. It is a `flutter create` artifact that was never adapted. Must not ship.
- ❌ Zero feature tests, zero controller/service tests, zero widget tests of the actual flows, zero goldens, no `integration_test/`. Note the sharpest irony: the one behavior a green test *could* catch — login mock routing — is exactly the hardcoded part.
- ❌ No CI at all: no `.github/` (verified absent), no codemagic/bitrise config, no analysis workflow.
- Comparison baseline: our user_app ≈ **136–138 `test()`/`testWidgets()` cases across 20 files** (e.g. `api_parity_test.dart`, `auth_validation_test.dart`, `checkout_payload_test.dart`) — this audit's own count is 136 test-calls; the plan figure is ~138.
- **Test debt created by importing donor UI:** effectively wide-open — the donor contributes **0 tests and 1 red test**. Anything imported (home shell, checkout sheet, subscription calendar, rider screens) arrives with no coverage contract; parity with our 138-test bar means writing tests for behavior the donor doesn't even implement (API payloads, error codes, offline states).

**Minimum test debt the import creates (concrete list):**
1. Deleting/replacing `test/widget_test.dart` is mandatory before any CI run (it fails at first pump — the app shows `LoginScreen`, not a counter).
2. Every adopted screen needs at minimum: build-smoke test, initial-state test, empty-state test (2 screens have any), error-path test (donor has zero error paths to import).
3. The checkout quantity/total math (`_canCount * _pricePerCan`, `cart_checkout_sheet.dart:27,32`) and subscription pricing (`selectedCans * 65.0`, dead twin `:20`) must be unit-tested as controllers — they are inline in widgets today and untestable as-is.
4. Our `ApiClient`-backed screens (donor has none) become the entire testing surface — every donor "service" test would be testing a mock singleton of hardcoded data, i.e., worthless; skip inheriting them.
5. No goldens exist anywhere; no visual regression contract can be transferred.

---

## 6. Import mechanics risks

| Risk | Fact | Severity |
|---|---|---|
| Pubspec name collision | ✅ donor `name: shodasha_mineral_water` vs ours `shodasha_app` (pubspec.yaml:1 each). No direct package collision, but donor's name leaks across the repo: Kotlin folder `src/main/kotlin/com/example/shodasha_mineral_water/`, web title, root README h1. All rename targets. | ⚠️ |
| analysis_options strictness | ❌ donor ships with 4 lints disabled; copy-pasting donor files into our app under `flutter_lints 6` will surface a wave of `prefer_const_constructors` / `curly_braces` / `unnecessary_to_list_in_spreads` diagnostics to resolve file-by-file (counts: ~110 non-const constructor ladders in the top files) | ❌ (mechanical but noisy) |
| geolocator realism | ❌ donor code compiles only against geolocator ≤12 because of `desiredAccuracy:` (`top_bar.dart:62-65`); on our ^14 pin this call needs rework (`LocationSettings` or plain `getCurrentPosition()`). `geocoding ^3.0.0` vs ours `^4.0.0` — placemark path same API, OK | ❌ |
| cloud_firestore removal | ⚠️ **second-guess-free**: 0 imports in `lib/`; remove deps + gradle plugin + json + init block (§4.5). Risk is only that `Firebase.initializeApp()` try/catch currently *masks* boot failures on phones without Play services — after removal that whole class of silent weirdness disappears | ✅ easy |
| equatable / provider / shared_preferences dead deps | ❌ `equatable`, `provider`, `shared_preferences` locked but 0-imported (grep) → drop all three; prevents dead-dep carry-over | ⚠️ |
| Root `main.dart` demo app | ❌ 353-line `MasterHubScreen` demo sits at repo root (tracked in git). Out of `lib/`, it's invisible to `flutter run` but pollutes the analyzer's next `dart analyze .` and any file-search; delete at import | ⚠️ |
| Asset inventory to import | ✅ Present-in-repo and referenced correctly: `assets/images/login_hero.png` only. ⚠️ 4 unused double-extension weirdos (`img_*.png.jpg`) — inventory for possible image-crop reuse; ❌ 2 phantom references in dead code (`jar_20l.png`, `bottle_1l.png`) die with `HomeDataProvider` deletion | ⚠️ |
| Mock-everything data model | ❌ Every import candidate (home catalog, cart/checkout, subscription, orders, rider) reads/writes singletons of hardcoded Bhopal demo rows. Importing "UI only" means re-keying every screen onto `features/<feature>/{screen,controller}` + `core/api_client.dart`; expect **no donor data-layer code to survive** | ❌ |
| Language/copy drift | ⚠️ Support strings are hardcoded **Hinglish** (e.g. "Aapki query register ho gayi hai…" `support_help_screen.dart:48`) with no l10n scaffolding — vs our themed Hindi-first copy convention; copy requires rewrite, not adoption | ⚠️ |

### 6.1 Screen-by-screen import inventory (adopt as-is / adopt-then-rewire / skip)

| Donor screen/widget | Data wiring today | Import verdict |
|---|---|---|
| `login_screen.dart` (portal switch, 4-box OTP, resend timer) | hardcoded whitelist + fake OTP (`:30-34,79-125`) | ⚠️ **Adopt layout only**; auth must re-key to our OTP/Firebase → Workers → D1 session model (`architecture.md:93-96`). Drop the `_partnerRegistry` and partner portal entirely (our split removes rider/vendor from this app) |
| `customer_home_screen.dart` (5-tab IndexedStack shell) | none needed | ✅ **Adopt** — closest match to our `features/shell/user_shell.dart` concept; re-key tabs to our feature controllers |
| `top_bar.dart` (location/slot strip + address sheet + GPS fetch) | local list + geolocator/geocoding | ⚠️ **Adopt-with-surgery** — the only real-hardware code in the repo; port GPS flow onto `core/location_service.dart`; delete the 36dp icon-button row and inline cart badge `'2'` (`:542`) |
| `featured_products.dart` + `mode_selection_cards.dart` | hardcoded price maps | ⚠️ Adopt visuals; wire to our catalog API (`checkout_service.dart` model) |
| `cart_checkout_sheet.dart` | bypasses notifier, hardcodes ₹65 | ⚠️ Adopt layout; replace business logic with our `booking_controller`/`checkout_service`; delete the `invalid_use_of_protected_member` ignore |
| `my_orders_screen.dart` + `order_card.dart` | mock singleton list | ⚠️ Adopt card design (status pill/QTY badge/PIN chip comps are good); delete rider button + PIN display; wire to `orders_controller` |
| `subscriptions/.../subscription_screen.dart` (LIVE twin) | pure local state | ⚠️ Adopt calendar/pause UI; replace hardcoded October data with our `table_calendar`-based subs model |
| `orders/.../subscription_screen.dart` (dead twin) | SubscriptionNotifier | ❌ **Skip/delete** |
| `wallet_screen.dart`, `notifications_screen.dart` | fully hardcoded | ⚠️ Adopt visuals; wire to `ledgerMe`/notification API per `flow.md:46` |
| `customer_profile_screen.dart` | hardcoded name/phone | ⚠️ Adopt menu layout; delete owner-console tile + hardcoded `'Ayush Singh'` |
| `saved_addresses_screen.dart` | live service in same file | ⚠️ Adopt list UI; move `AddressStateService` into a proper `selected_address_store`-style file (ours: `features/addresses/selected_address_store.dart`) |
| rider_dashboard / rider_delivery / plant_hub / owner_control_center | mock ops screens | ❌ **Skip wholesale** — wrong app boundary (role-mixing §2.7); any salvage targets our vendor app, not the user app |
| `support_help_screen.dart` | hardcoded Hinglish dialogs | ⚠️ Adopt tile structure only if Hinglish (not Hindi) copy is acceptable after rewrite + real `url_launcher` tel:/wa.me |

### 6.2 What transfers cleanly vs what must be rebuilt
- ✅ **Transfers cleanly:** static layouts, screen composition order, color/shape vocabulary (once collapsed to one palette), the GPS+reverse-geocode interaction script, notification/transaction list item designs.
- ❌ **Must be rebuilt from our side:** every data fetch, every price, every order-ID scheme, auth flow, environment config (`--dart-define` base URL vs donor's none), state management (donor's 4 singletons → our per-feature controllers), error/offline protocol (donor has none → ours) — i.e., the entire engineering layer.

---

## Verdict

**Is the donor's engineering quality a blocker, a slowdown, or an accelerator? → A controlled slowdown.**
It blocks nothing outright (UI is importable pixel-for-pixel and mock-wires cleanly), but accelerates only one aspect: visual design/screen composition. Engineering-wise it contributes negative value: red default test, zero coverage, disabled lints, dead dependencies (equatable/provider/shared_preferences/cloud_firestore), two duplicate subscription screens, four parallel order-placement paths, 4 unwired global singletons, 233 hardcoded color literals off-theme, 3 under-48dp touch-target clusters, 7 un-disposed controllers across 3 files, M2-in-boot/M3-in-dead-code split, legacy Groovy gradle on AGP 8.1 targeting SDK 33 with a committed machine JDK path, debug-signed unreleasable APKs (while the v1.0.0 APK, 14.5 MB, is committed to git), and a committed Firebase config that the in-code init silently swallows.

### The 10 mandatory fixes before any import
1. **Repackage Android identity:** `com.example.shodasha` → our `com.shodasha.…` applicationId/namespace; fix manifest activity, both Kotlin dirs (drop the duplicate `shodasha_mineral_water` MainActivity), and delete/replace `google-services.json` (`build.gradle:22,40,61`).
2. **Strip Firebase entirely:** drop `firebase_core`/`cloud_firestore` deps, the try/catch init in `lib/main.dart:8-12`, the google-services plugin line (`android/app/build.gradle:61`), and the committed JSON with the `AIza…` key.
3. **Never ship:** `build_backups/Shodasha_v1.0.0_Stable.apk` (14.5 MB), `android/build/**` HTML report, root `main.dart` demo app, committed `google-services.json`, `test/widget_test.dart` failing stub.
4. **Delete dead code twin:** `features/orders/presentation/subscription_screen.dart` (the live one is `features/subscriptions/…/subscription_screen.dart`, imported by `customer_home_screen.dart:4`); kill the `\vert{}` string bug cargo.
5. **Prune dead deps:** `equatable`, `provider`, `shared_preferences` (all zero-import), then decide which of `CartProvider/LocationProvider/HomeProvider`/`HomeDataProvider`/`AppTheme`/`AppBottomNavBar`/`LivePurityCard`/`SavedAddressesScreen`/`SupportHelpScreen` get real wiring or deletion (they are 100% dead today).
6. **Kill the role-mixing seams:** remove the rider "ENTER PIN & DELIVER CANS" button from the customer `OrderCard` (`order_card.dart:225-247`), the owner console tile from customer profile (`customer_profile_screen.dart:99-111`), and the partner-portal routing inside `login_screen.dart:104-116` — rider/vendor/owner surfaces must not ship in the customer app.
7. **Rewire theming:** replace the two brand palettes (teal `0xFF0D9488` vs green `0xFF16A34A`) with one token set in our `theme.dart`; eliminate the 233 inline `Color(…)` literals; resolve the M2 (`useMaterial3: false`) boot vs dead M3 `AppTheme` conflict.
8. **Fix gradle to our toolchain:** move Groovy files into our KTS/AGP-9 settings; delete the machine path `org.gradle.java.home` line (`gradle.properties:2`); lift compile/targetSdk to `flutter.*` so target ≥ 34/35; normalize signing to key.properties + minify/shrink.
9. **API-hygiene pass needed before any behavior imports:** the geolocator call (`top_bar.dart:62-65` desiredAccuracy) must be reformed for our ^14 pin; re-enable the 4 disabled lints and settle resulting const/style diagnostics; align the geolocator callers with our `core/location_service.dart`.
10. **Test lift-off:** every imported screen arrives with zero tests — plan parity with our ~136/138-test baseline requires authoring controller/payload/state tests for whatever UI is adopted (no donor tests can be inherited except the login flow edge — and its test is red).

---

*All citations are file:line in the donor at commit `76e0eba` (shallow), or `apps/user_app/…` today. Counts are regex sweeps, reproducible.*
