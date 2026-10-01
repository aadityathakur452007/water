# Decision Log

> **Purpose**: The "why" file. An **append-only** log of every meaningful decision —
> which library was chosen and why, architecture choices, feature decisions, branch
> decisions, tradeoffs. When anyone (human or AI) wonders "why is it built this way?",
> the answer is here.
>
> **Update rule (MANDATORY)**: Append a new entry for EVERY meaningful decision.
> **Never edit or delete past entries** — that would rewrite history and break the
> log's purpose. Before making a new decision, check this log first (don't decide
> twice).

---

## What counts as a "meaningful decision"? (MANDATORY — log all of these)

- **Library / framework / tool choice** — component library, icon set, state manager, animation lib, styling approach
- **Architecture / pattern choice** — folder structure, data flow, error strategy, server vs client components
- **Feature design decisions** — scope, UX, API shape, data model
- **Branch / workflow decisions** — git flow, release process, deployment target
- **Anything you had to think about for more than ~5 seconds**

---

## How to add a decision

1. Copy the **Template** below into the **Decision Entries** section (newest on top)
2. Fill it in — the **Why** line is the most important part
3. Add a row to the **Decision Index** table
4. If it supersedes an earlier decision, mark the old one as `Superseded by ADR-NNN`

---

## Decision Index

| ID | Date | Decision | Status | Affects |
|----|------|----------|--------|---------|
| ADR-033 | 2026-10-01 | Release-mode validation + emulator rebuild: clean AVD recreate, flutter clean + --release AOT (60.7MB), senior-practice audit (fixed Bकaya typo; no secrets/prints) | Accepted | apps/user_app (release artifact), local AVD |
| ADR-032 | 2026-10-01 | 006-auth-flow: research-backed splash/auth/first-run + stepper checkout + repeat history + pinned packages | Accepted | apps/user_app/{lib/features/{auth,booking,orders,shell},pubspec}, Feature_docs/ux-redesign/ |
| ADR-031 | 2026-10-01 | 005-super-admin-panel backend: additive read/detail/suspend/payments/refunds/ledger endpoints + sh_session cookie fallback in _bearer | Accepted | workers/api/app/{api/v1/admin.py,api/auth_deps.py,repositories/admin_read_repo.py}, tests/test_admin_panel.py |
| ADR-030 | 2026-10-01 | 005-super-admin-panel: Next.js 16 + Tailwind v4 BFF panel — 14 pages, HttpOnly-cookie auth, TanStack Query/Table + Recharts, Geist tokens | Accepted | apps/admin_app/, Feature_docs/super-admin-panel/, branch 005-super-admin-panel |
| ADR-029 | 2026-10-01 | 005-home-ux: storefront home + buy-box detail + delivery-type checkout + OSM pins + Razorpay-or-upi-link + server-ID confirm | Accepted | apps/user_app/lib/{core,features/{booking,addresses,orders,shell}}, pubspec, AndroidManifest |
| ADR-028 | 2026-09-30 | Local run on Android 36: platform-36 already present, added google_apis x86_64 image + shodasha_api36 AVD, debug APK targetSdk 36 installed | Accepted | apps/user_app, local SDK/AVD only |
| ADR-027 | 2026-09-29 | F5 shell+theme+API+4 tabs: Material-not-shadcn, black primaries, typed client on seams | Accepted | apps/user_app/lib/core+features/{shell,addresses,subscriptions,support,profile}/ |
| ADR-026 | 2026-09-29 | F2 user-app auth: seam-based AuthController, Material-mirrored ForUI, local Hindi strings | Accepted | apps/user_app/lib/features/auth/, test/ |
| ADR-025 | 2026-09-29 | Slice-4: Razorpay-real, hardening, scheduler, E2E — 145 green | Accepted | workers/api/, live test keys |
| ADR-024 | 2026-09-29 | Test credentials wired locally: Razorpay test + Firebase project + admin seed | Accepted | workers/api/.env (untracked), live dev DB |
| ADR-023 | 2026-09-29 | Slice-3 complete: payments + vendor + dispatch + admin, all-stubbed | Accepted | workers/api/, slice-4 apps |
| ADR-021 | 2026-09-29 | C1 slice-2 auth: RealVerifier adapter, session families, in-memory limits, LOG-ONLY integrity | Accepted | workers/api/auth, sessions, tests |
| ADR-022 | 2026-09-29 | Slice-2 complete: auth + addresses + orders, 74 tests green | Accepted | workers/api/ |
| ADR-020 | 2026-09-29 | Slice-1 complete: stdlib-sqlite Repository seam + paise + 20 tests green | Accepted | workers/api/ |
| ADR-019 | 2026-09-29 | B2 slice-1: align to landed B1 interfaces; OverLimitError subclass; validation=400 truth | Accepted | workers/api/app/api/v1/, tests |
| ADR-018 | 2026-09-29 | Contract audit run-1: 16 vuln fixes + 25 traceability fixes, 6 simplifications rejected | Accepted | api-contract, context, synthesis |
| ADR-017 | 2026-09-29 | No-photo v1: reason-code complaints + vendor verification protocol | Accepted | api-contract, complaints/quality flows |
| ADR-016 | 2026-09-29 | Trust & safety: suspend ladder + strikes + quality/batch + custody-guarded replacement | Accepted | workers/api/, admin trust board |
| ADR-015 | 2026-09-29 | Multi-vendor zones + capacity + cancellation settlement + 3-purse money model | Accepted | workers/api/, D1 schema, all clients |
| ADR-014 | 2026-09-29 | Backend API contract v1 spec (D1 schema + RBAC + endpoints) | Proposed | workers/api/, Feature_docs/backend/ |
| ADR-013 | 2026-09-29 | FastAPI + Firebase Auth OTP (FCM push only) + security/edge-case spec | Accepted | workers/api/, auth flow, Feature_docs/security/ |
| ADR-012 | 2026-09-29 | Backend: Python on Cloudflare Workers + D1 SQLite for auth/users | Accepted | workers/api/, D1 schema, Flutter apps, Admin web |
| ADR-011 | 2026-09-29 | SYN-2 synthesis: vendor-reqs VR-01…VR-14 + pricing-deposit model accepted as proposed | Proposed | Feature_docs/synthesis/, Series-3 spec lock |
| ADR-010 | 2026-09-29 | Group-B operations research done; jar ledger + billing flows locked for Series-3 | Accepted | Feature_docs/research/B-operations/, Series-3 synthesis |
| ADR-009 | 2026-09-29 | Group-C competitor research done; copy-vs-differentiate locked | Accepted | Feature_docs/research/C-competitors/, Series-3 synthesis |
| ADR-008 | 2026-09-29 | Group-A UX research done; A3 cited secondary-only; top-8 user-app rules | Accepted | Feature_docs/research/A-ux-case-studies/, Series-3 synthesis |
| ADR-007c | 2026-09-29 | Group-D: canonical order-state machine + MVP/v2 split proposed | Proposed | Feature_docs/research/D-dev-guides/, Series-3 synthesis |
| ADR-007b | 2026-09-29 | F-market: all Actowiz figures UNVERIFIED, price lock gated on local survey | Accepted | Feature_docs/research/F-market/, pricing |
| ADR-006 | 2026-09-29 | specify-cli install mandated | Accepted | repo root, SDLC workflow |
| ADR-005 | 2026-09-29 | Feature_docs/ at root in English full deep-dive with browseros-neo reading | Accepted | Feature_docs/, Series-2/3 research |
| ADR-004 | 2026-09-29 | Shodasha 3-surface split (2x Flutter Android + Next.js web super-admin) | Accepted | user app, vendor app, super-admin web |
| ADR-003 | 2026-08-11 | Remove Scaffold.py; canonical trees are the source of truth | Accepted | repo root, folder-structure skill |
| ADR-002 | 2026-08-11 | Add flow.md + decision.md as living context files | Accepted | context/, all docs |
| ADR-001 | YYYY-MM-DD | [One-line decision] | Accepted | [files/features] |

---

## Template

### ADR-NNN: [Short title]
- **Date**: YYYY-MM-DD
- **Status**: Proposed | Accepted | Rejected | Superseded by ADR-NNN
- **Context**: [what triggered this decision — the problem being solved]
- **Options considered**: [alternatives, and why each was rejected]
- **Decision**: [what was chosen]
- **Why**: [the reasoning — this is the important part. Write enough that a future agent
  understands without re-deriving it.]
- **Consequences**: [positive and negative effects, things to watch out for]
- **Affects**: [features / files / branches this touches]

---

## Decision Entries

### ADR-033: Release-mode validation + emulator rebuild (senior-practice pass)
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: User reported the emulator misbehaving; asked for a rebuild + research on senior Flutter release practices (release checklists from Chirag Prajapati, Imran Hossain, Mohamed Yaser, official perf docs) and execution.
- **Options considered**: Patching the sick AVD in place (rejected — repeated process deaths, unknown state); delete + recreate `shodasha_api36` clean (chosen); debug-only verification (rejected — debug lies: AOT/tree-shaking/obfuscation issues hide).
- **Decision**: AVD deleted + recreated (pixel_7, android-36 google_apis x86_64); audit pass — fixed mixed-script `Bकaya` typo, confirmed no prints/secrets/hardcoded hosts (only localhost dev default + OSM/wa.me URLs); `flutter clean` + `flutter build apk --release` green (60.7MB AOT); release APK installed on fresh API-36 emulator, branded login foreground, no crash. Known env quirk: emulator needs ~2-4 min first boot; adb poll loops must null-guard (device appears late).
- **Why**: Release artifact is the only truth senior guides agree on (debug builds hide AOT + asset-packing bugs); a clean AVD removes all stale-state doubt about what the user sees.
- **Consequences**: Keep launching the emulator from Android Studio Device Manager for persistence across sessions; profile-mode DevTools pass still open.
- **Affects**: `apps/user_app/lib/features/booking/booking_controller.dart` (typo), `build/.../app-release.apk` (untracked output), local AVD

### ADR-032: 006-auth-flow (research-backed auth-first-run + stepper checkout + repeat history)
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: User-ordered research (DESIGN.md of Flipkart/Amazon, Crafty-Bay Flutter flow, 2026 Flutter perf guides) + per-screen checklists (`Feature_docs/ux-redesign/research-and-checklists.md`), then approved build: branded first-run, stepper checkout with calendar delivery, repeat-first history.
- **Options considered**: Full custom OTP boxes kept (rejected — `pin_code_fields` 9.4 gives autofill/paste/error-shake maintained upstream; v10 REJECTED — needs Flutter 3.47/material_ui, we are 3.44); permission_handler for permissions (REJECTED — v13 demands compileSdk 37, Flutter 3.44 pins 36; geolocator + firebase_messaging.requestPermission cover both with zero new native code); cached_network_image (REMOVED — no network imagery; flutter_map caches own tiles, product art is local); bespoke calendar (rejected — table_calendar 3.2.1).
- **Decision**: Branded splash (logo+trust, animate entry) + logo-headed login + MaterialPinField numeric OTP (6, autofill, paste, error-shake, same controller seams); first-run sheet (location → notification → address-pin, once per install via SharedPreferences, denied paths never dead-end); checkout is 3-step (Address → Schedule → Pay) with icon delivery chips + table_calendar multi-date (≤6) for custom recurrence; orders get Bulk badge + First/Repeat tags (timestamps required, else untagged) + Order-again one-tap reorder; perf P1–P8 (cacheWidth art, const, scoped setState, no Opacity animation). `flutter analyze` 0, 65 tests green, debug APK on API-36 emulator screenshot-verified (login → guest → home + first-run sheet → clean home).
- **Why**: Every screen traces to a read source (Flipkart density/blue-header, Amazon a11y/haptics discipline, Crafty-Bay screen order, official perf docs); differentiation kept (repeat-first, windows not dates-as-promises, deposit honesty).
- **Consequences**: Custom recurrence capped at 6 dates (64-char contract field); first-run flag is per-install (reinstall re-asks — acceptable v1); FCM permission via firebase_messaging needs a real google-services config for production push (stub-safe today).
- **Affects**: `apps/user_app/lib/features/{auth/{auth_gate,phone_screen,otp_screen,first_run_screen},booking/{booking_controller,booking_sheet,product_detail_sheet},orders/{orders_controller,orders_screen},shell/user_shell.dart}`, `pubspec.yaml`, `test/checkout_payload_test.dart`, `Feature_docs/ux-redesign/research-and-checklists.md`

### ADR-031: 005-super-admin-panel backend — additive panel endpoints + cookie-bearer fallback
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: Approved spec (`Feature_docs/super-admin-panel/spec.md` — "Approved — build it", live Workers API, all 14 pages) needs super-admin powers: ALL orders/users/vendors cross-account, stats dashboard (orders created, GMV, money to vendors/users, deposits, dues, UPI-vs-COD, on-time %), block/unblock users + vendors with instant session revocation, audit/server-log viewer, payments/refunds/ledger pages. Contract §0 (ADR-014/018) forbids breaking API changes; backend is the existing Python Workers API + D1 (ADR-012/020).
- **Options considered**: parallel `/v1/admin2` router (rejected — splits admin authz surface and discovery); reshaping existing `GET /admin/orders` / `GET /admin/metrics` responses (rejected — contract break); Python-side GraphQL/aggregate layer (rejected — new paradigm for nothing); additive endpoints + additive optional query params (chosen).
- **Decision**: New read-only `app/repositories/admin_read_repo.py` (daily_series, on_time_series, money_totals, users_page, user_detail, vendor_detail, payments_page, refunds_page, ledger_page; rowid-cursor paging `_page()`). `app/api/v1/admin.py` +9 routes: `GET /admin/metrics/overview?days=`, `GET /admin/users?query=&role=&suspended=&limit=&cursor=`, `GET /admin/users/{id}/detail`, `GET /admin/vendors/{id}/detail`, `POST /admin/users/{id}/suspend` (`SuspendIn{reason≥3, level: restrict|suspend}` — suspend revokes the user's sessions instantly, admin accounts → 400, audit `user.suspend`), `POST /admin/users/{id}/unsuspend` (audit `user.unsuspend`), `GET /admin/payments?status=&method=`, `GET /admin/refunds?status=`, `GET /admin/ledger`; additive optional params on `GET /admin/orders` (payment_status, query, cursor) and `GET /admin/audit` (actor_id, action) — every existing response shape unchanged. `app/api/auth_deps.py:_bearer()` now accepts the `sh_session` cookie as Bearer fallback (Bearer still first) so the admin web authenticates via HttpOnly cookie with no token in JS. Money stays integer paise on the wire; the panel only formats. Validation errors stay 400 VALIDATION per the central handler (project truth, not 422). 8 new router tests in `tests/test_admin_panel.py` (authz 403, overview aggregates, search/role filter, user+vendor detail, suspend restrict/suspend + revocation + audit + admin-protection + unsuspend, payments/refunds/ledger cursor paging) — full suite 153 green.
- **Why**: Additive-only keeps every existing client (Flutter user app, vendor door, prior tests) byte-compatible while delivering the panel's full power set; the cookie fallback closes the web-surface auth gap without weakening the mobile Bearer path; revocation-on-suspend makes ADR-016's ladder instantly effective.
- **Consequences**: Overview date buckets use the real UTC clock — tests must seed relative dates (fixed-date seeds rot at day rollover; `test_overview_kpis_and_series` was fixed for exactly that failure). Rowid cursor paging assumes append-mostly tables (standard admin-page tradeoff). `restrict` level only flags — COD-only enforcement remains dispatch-side.
- **Affects**: `workers/api/app/repositories/admin_read_repo.py`, `workers/api/app/api/v1/admin.py`, `workers/api/app/api/auth_deps.py`, `workers/api/tests/test_admin_panel.py`

### ADR-030: 005-super-admin-panel — Next.js 16 + Tailwind v4 BFF panel (stack + libraries)
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: User ordered the super-admin panel (branch `005-super-admin-panel`) in Next.js + React, hosted on Cloudflare Pages, sharing the Python Workers backend; hard constraints: API contract must not break, no AI slop (no purple gradients, no dark mode, no emoji), premium libraries per stitch-design-taste DESIGN.md, senior-crafted dashboard UX — don't hand-roll what good libraries already do.
- **Options considered**: Vite SPA (rejected — loses file routes + the server-side BFF proxy that keeps tokens out of the browser); browser→Workers direct calls + CORS (rejected — exposes origin/token to JS, adds CORS surface for zero gain); Mantine/Chakra/MUI (banned by Agent.md); HeroUI as base (banned as default); full shadcn/ui kit (rejected — the panel's needs are data-dense tables/charts over a token set; ~15 hand-rolled primitives in `shared/ui` are smaller and fully owned); hand-rolled SVG charts (rejected — user explicitly demanded a real chart library); ECharts (heavier, canvas-imperative; Recharts chosen for React composition + existing install).
- **Decision**: `apps/admin_app/` — next 16.3.7 + react 19.2.8 (Next 16 convention: the gate is `src/proxy.ts` with `export default function proxy`, middleware.ts is deprecated), Tailwind v4 via `@theme` tokens in `globals.css` (single visual source of truth: canvas #F9FAFB, surface white, ink #18181B, steel #71717A, accent water-blue #0369A1, good/warn/bad green/amber/red-700, radius-16 cards, whisper shadow, LIGHT-ONLY), Geist Sans + Geist Mono (mono tabular for every money figure and ID), @tanstack/react-query ^5 (server state + invalidation), @tanstack/react-table ^9 (dense tables), recharts ^3 (GMV/orders, payment split, on-time, states charts), lucide-react icons, clsx + tailwind-merge. Auth: `/login` → POST `/api/auth/otp` (action start|verify, role=admin gate) → BFF sets HttpOnly `sh_session` (30m) + `sh_refresh` (7d); `src/proxy.ts` gates `/admin/*` + `/login`; reads via `GET /api/proxy` (admin /v1 paths only), writes via `POST /api/admin-actions` — cookie forwarded server-side, the Workers URL never reaches the browser (`API_URL` server-only; `NEXT_PUBLIC_API_MODE=mock` sentinel → fixtures for offline UI work). Feature-first: `features/{shell,dashboard,orders,users,vendors}` + `shared/ui` primitives (Card/Stat/Badge/StateBadge/PaymentBadge/PageHeader/Skeleton*/Empty/Error, danger ConfirmAction with typed reason) + `lib/{api,format,types}` (paise→₹, num, pct, dateTime, phoneMasked). Motion: skeleton shimmer (no spinners), staggered `.rise`, prefers-reduced-motion honored. 14 pages (13 admin + login) + 4 BFF routes; `npm run build` 19 routes green, lint clean; live smoke verified end-to-end (browser proxy → uvicorn worker → D1).
- **Why**: The BFF-cookie pattern is the only shape satisfying "web panel + shared API + no contract break + secrets hygiene" at once: the backend needed zero auth changes beyond the cookie fallback (ADR-031), and the browser never holds an access token. Token-driven Tailwind v4 plus Query/Table/Recharts gives the senior look and correct data behavior without owning a component framework.
- **Consequences**: Cloudflare Pages deploy needs `API_URL` env wiring (`.env.example` added) since the BFF calls the worker server-side; Next 16's proxy.ts rename means pre-16 middleware snippets don't apply; dev run needs the worker up first (`cd workers/api && SHODASHA_DB_PATH=./data/shodasha.db python -m uvicorn app.main:app --port 8000` — db.py reads SHODASHA_DB_PATH, not DATABASE_PATH) then `npm run dev` (port 3100) and admin-phone OTP login.
- **Affects**: `apps/admin_app/**` (new app), `Feature_docs/super-admin-panel/spec.md`, branch `005-super-admin-panel`

### ADR-029: 005-home-ux storefront + real checkout (Alternative A, corrected)
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: User UX review: text-list home, no product detail, text-only address (maps blank without key), stub checkout (UPI chip flipped a flag, fake ORD- id, WhatsApp-copy as post-purchase primary), no one-time-vs-recurring question at buy time. Guardrails read (.agents/design-basics/guardrails.md): light mode, black text, blue buttons, no purple, no gradients, no emojis.
- **Options considered**: Purple-gradient premium (rejected by user — reads AI); Google Maps with key (rejected — no key; OSM now, one-file swap later); feeding all UPI through Razorpay gateway (rejected — backend UPI_PROVIDER=fake returns FAKE-* refs; gateway only for real `order_` refs, FAKE-* opens upi:// link); third priced tap-SKU (rejected — user locked 2 SKUs, tap = detail copy).
- **Decision**: Storefront home (address bar, search, chips, photo cards, sticky book bar); detail buy-box sheet (facts, tap note, stepper, delivery-type Ek-baar/Roz/alternate/weekly, related SKU, BUY); checkout pulls GET /windows slots, live POST /quotes → POST /orders + Idempotency-Key with one STALE_QUOTE retry, recurring → POST /subscriptions; Razorpay gateway (test key_id via --dart-define, secret stays server-side) with GET /orders/{id} paid-verify, never client-callback trust; confirmation shows server-minted id + Track primary + sub shortcut; WhatsApp demoted to bill-share wa.me link; OSM drag-pin picker (flutter_map, lat/lng required since backend rejects 0,0); deps flutter_map 8.3.2/latlong2/geolocator 14.1.1/razorpay_flutter 1.4.7 + location permissions. `flutter analyze` 0, 63 tests green, debug APK on API-36 emulator verified via screenshot.
- **Why**: Every complaint traced to a contract endpoint that already existed (quotes/orders/subs/windows/intent) — the app just never called them; smallest diff that makes money move for real.
- **Consequences**: Container card reuses 20l.jpg crop until a real container photo lands; subscription create needs an authed session (guest checkout hits UNAUTH → login prompt, honest dead-end-free copy pending F1 Firebase wiring).
- **Affects**: `apps/user_app/lib/core/api_client.dart` (+6 methods), `features/booking/` (catalog/detail/checkout-service/sheet/confirm/home rewrite), `features/addresses/` (lat/lng + map_picker), `features/orders/bill_screen.dart`, `features/shell/user_shell.dart`, `main.dart`, `pubspec.yaml`, `AndroidManifest.xml`

### ADR-028: Run user app on Android 36 emulator (no project code change)
- **Date**: 2026-09-30
- **Status**: Accepted
- **Context**: User reported only Android 37 installed while the app targets Android 36. Inspection showed `platforms/android-36` + `build-tools/36.0.0` + NDK 28.2.13676358 were already installed (Flutter 3.44.9 expects compileSdk/targetSdk 36); `flutter doctor` reporting "Platform android-37.0" just reflects the highest installed platform. What was actually missing: no system-image, no AVD, no device connected.
- **Options considered**: Physical phone via USB debugging (rejected — user chose emulator); Play-Store image (rejected — larger, unneeded; google_maps_flutter works on google_apis); `flutter install` release default (rejected — no release APK/signing; debug APK chosen).
- **Decision**: Installed `system-images;android-36;google_apis;x86_64` (7.0.0) via new `android sdk install` CLI (old sdkmanager splits `;` args in PowerShell), created AVD `shodasha_api36` (pixel_7) via avdmanager with JAVA_HOME=Android Studio jbr, cold-launched detached via emulator.exe, built `flutter build apk --debug` (77s, targetSdk 36 verified via dumpsys), installed via `adb install -r` and launched via monkey; MainActivity resumed (pid verified).
- **Why**: Zero project-code change — the SDK already matched Flutter's expected 36; only the runnable (image/AVD/device) was missing. google_apis x86_64 is the smallest stable image for this Windows host.
- **Consequences**: Emulator `shodasha_api36` persists in `~/.android/avd`; re-run after code changes is `flutter build apk --debug` + `adb -s emulator-5554 install -r app-debug.apk`. Do NOT uninstall platform-37 — coexistence is harmless.
- **Affects**: local SDK/AVD only (`~/.android/avd/shodasha_api36*`, `sdk/system-images/android-36/...`); `apps/user_app/build/.../app-debug.apk` (untracked build output)

### ADR-027: F5 shell + theme + typed API + Addresses/Subscriptions/Support/Profile
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: F5 brief (branch 004-user-app-build) approved 11-screen build: bottom-nav shell (Home/Orders/Support/Profile) + addresses + subscriptions + support + profile on the locked design language (white #FFFFFF, black #111 primaries, water blue #0284C7 links-only). F1's deps landed in pubspec meanwhile (firebase_auth, url_launcher, uuid, shadcn_flutter); F3/F4 booking+orders landed mid-task with a compile error (OrdersTokens used `Color` under a foundation-only import) and 2 red tests.
- **Options considered**: shadcn_flutter widgets (rejected — pubspec dep exists but screens are already Material across F2–F4; swapping = rewrite + new regression surface for zero user-visible gain; tokens keep the swap config-only); purple seed theme (rejected — locked palette); black-primary buttons keep F2–F4 token classes untouched (chosen — 5 str_replace edits, one value each).
- **Decision**: `core/theme.dart` (Material ThemeData: black ElevatedButton primaries, blue TextButton links, NavigationBar blue-active, hairline borders r8, 48dp); `core/api_client.dart` (typed client per contract §3/§4: Bearer + X-Device-Id, Idempotency-Key, ApiException{code,status,retryAfter}, NETWORK on offline/5xx); `core/session_store.dart` (SecureSessionStore on flutter_secure_storage + persisted device UUID); `core/auth_impls.dart` (ApiBackedAuthApi on §4.1 + StubPhoneVerifier dev-OTP 123456 behind F2's unchanged seams); `features/shell/user_shell.dart` (IndexedStack NavigationBar, tab enum stable for tests/deep links); Addresses (§4.3 gates: pincode regex, delete-confirm, 409 edit-blocked message), Subscriptions (§4.5: pause range end>start cross-validation, resume ≥24h pre-check, late-skip → vendor-call dialog), Support (§4.7: 11 reason codes, ≤500 chars, NO photo field per ADR-017, 422 window-expired → WhatsApp path not a dead end, status open→progress→resolved), Profile (§4.6 ledger read-only, /returns 10-day SLA, Hindi-default/English-fallback merged maps, logout confirm); repaired F4 (color import, search-test load(), lints) without discarding its work. Assets: public/logo.png + 20l.jpg copied + registered; orders url_launcher tel/wa.me wired (guarded try/catch → SnackBar fallback). `flutter analyze` 0 issues, 56 tests green.
- **Why**: Compiles + verifies today with zero new deps beyond F1's landed set; F2–F4 screens keep their token classes (black-primary is a value edit, not a rewrite); StubPhoneVerifier keeps the full auth flow runnable against staging until F1's Firebase swap, which stays a one-file change behind the seam.
- **Consequences**: Support/Profile/Addresses/Subs hit real endpoints that exist on the Workers API (slice-3 mounted them); StubOrdersRepository still backs Orders until F1 wires real HTTP; booking sheet confirm still stubs POST /orders (F3 TODO now unblocked — ApiClient + idempotency keys ready); real Firebase verifier + l10n consolidation remain F1-owned TODOs.
- **Affects**: `apps/user_app/lib/core/` (4 files), `lib/features/{shell,addresses,subscriptions,support,profile}/` (5 files), repairs in `lib/features/{auth,booking,orders}/`, `test/widget_test.dart`, `pubspec.yaml` assets, `assets/{logo.png,20l.jpg}`

### ADR-026: F2 user-app auth — seam-based controller, no new deps, local strings
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: F2 brief (branch 004-user-app-build) ordered phone+OTP auth on contract §4.1 + flow-1 guest-browse with locked tokens, but pubspec.yaml (F1-owned, do-not-edit) lacks firebase_auth/flutter_secure_storage/forui and lib/l10n + google-services.json are absent.
- **Options considered**: Hard-import firebase_auth/forui as briefed ("assume present") (rejected — breaks `flutter analyze` + compile today); editing pubspec to add deps (rejected — F1 owns it); abstract seams + Material-mirrored ForUI patterns + local strings map (chosen).
- **Decision**: `AuthController` (ChangeNotifier) depends only on in-file `SessionStore`/`AuthApi`/`PhoneVerifier` abstracts (+ `InMemorySessionStore`); Firebase invoked only in user actions; ForUI login/OTP patterns mirrored with Material at identical tokens; Hindi copy in `authStringsHi` with TODO to consolidate into F1's `lib/l10n/strings.dart`; `AuthGate` routes splash→home/login with guest-browse safe. `flutter analyze` clean, 14 tests green.
- **Why**: Compiles and verifies today; F1 plugs real Firebase/Secure Storage/l10n without touching callers; guest-browse keeps prices unwalled per flow 1.
- **Consequences**: F1 must provide real SessionStore/AuthApi/PhoneVerifier impls + l10n consolidation; F3 must wire home + booking-commit/profile auth gates + new-device banner.
- **Affects**: `apps/user_app/lib/features/auth/` (4 files), `apps/user_app/test/auth_validation_test.dart`

### ADR-025: Slice-4 hardening + Razorpay-real + scheduler + E2E
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: 4 parallel builders (E1 Razorpay REST, E2 headers/CORS/throttle, E3 scheduler jobs, E4 full-lifecycle E2E) + integrator pass. Live test credentials available in untracked local `.env` (ADR-024).
- **Options considered**: Real network in pytest (rejected — monkeypatched transport only; live check is a manual wirecheck script, deleted after); per-agent context edits (tolerated once, reviewed).
- **Decision**: RealUpiProvider calls Razorpay Orders REST (test mode) when `UPI_PROVIDER=razorpay`, fake default; centralized `_setting()` (real env > `.env` file > default) after finding adapters blind to `.env`; hermetic tests blank vars instead of deleting; payments provider stays module-global seam (E4's Depends suggestion declined — monkeypatch works, zero churn); scheduler as callable jobs + CLI (no cron infra); E2E covers 10-step lifecycle incl. abuse cases.
- **Why**: Live handshake proved (`order_ThqdP4urO7CtXd` created in test mode, Rs 1, no money); 145/145 green; 72 paths live.
- **Consequences**: Webhook verify still 502 until webhook secret lands; payee lock dormant until agency VPA; Flutter apps are the next build.
- **Affects**: `workers/api/app/adapters/upi.py`, middleware, jobs, tests, live test-mode proof

### ADR-024: Test credentials wired locally (Firebase project + Razorpay test + admin seed)
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: User provided Firebase project (ID + phone/Google sign-in enabled), Razorpay test key pair, and admin phone. Values live in untracked local `.env` only (verified by repo-wide secret scan 2026-09-29: all values present in `.env`, zero hits elsewhere). Instruction: wire now, verify on dummies + live paths, no secrets in git.
- **Options considered**: Committing `.env` for convenience (rejected — secrets hygiene, ssdlc blocking gate); hardcoding in config (rejected — same); local untracked `.env` + `.env.example` placeholders only (chosen).
- **Decision**: `workers/api/.env` (gitignored, verified absent from status) holds test values; config gained optional `upi_*`/`agency_upi_vpa` fields; Google-sign-in tokens without phone claims fail loudly with phone-OTP direction (v1 accounts are phone-keyed); admin seeded live and verified; `data/` added to `.gitignore` (dev DB holds a real phone).
- **Why**: Verification proved the wiring (project picked up, garbage→401 real path, seed row live) while keeping every secret out of version control; payee lock stays dormant until the business VPA arrives rather than enforcing against a guessed value.
- **Consequences**: Webhook verify stays 502 until the webhook secret arrives; payee lock dormant until agency VPA arrives; service-account JSON still pending for cert-independent ops (not needed for verification path).
- **Affects**: local dev only; no committed secrets

### ADR-023: Slice-3 payments + vendor ops + dispatch + admin (all keys stubbed)
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: 4 parallel builders (D1 payments, D2 vendor, D3 subs/returns/complaints/devices, D4 zones/dispatch/admin) on `002-backend-foundation`; integrator renumbered migrations (005 payments/006 aftermath/007 ops), mounted 8 routers, fixed test filename refs, migrated nothing else.
- **Options considered**: Real keys now (rejected — user provides later; adapters shaped for drop-in); Firebase Admin SDK (rejected — native-dep risk on Workers; PyJWT + certs).
- **Decision**: Fake providers (UPI/Auth/FCM) + stub seams (Google/WhatsApp) with full test coverage; keys guide at `Feature_docs/backend/api-keys-guide.md`. Full suite 127 green; migrations 002–007 idempotent; 72 paths live-booted.
- **Why**: Every external boundary is an interface with a fake; real credentials change env only, never code.
- **Consequences**: Backend API functionally complete per contract; remaining: provider selection (UPI/WhatsApp), Firebase/Maps ids, Flutter apps + admin web.
- **Affects**: `workers/api/`, `Feature_docs/backend/api-keys-guide.md`, slice-4

### ADR-022: Slice-2 integration — mounts, migrate runner, Bearer test migration
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: C1/C2/C3 landed disjoint slices; integration needed router mounts, test hook, migration runner, and orders-test auth migration (C1's landing retired the X-User-Id stub → 3 tests 401).
- **Options considered**: `app/db/migrate.py` (rejected — `app.db` is a module, submodule unimportable); per-agent context edits mid-flight (tolerated once — B2/C1 entries reviewed, accurate, kept).
- **Decision**: `app/migrate.py` runner (idempotent via schema_migrations); `set_test_connection` hook in deps.py; orders router tests use dependency-overridden canned Bearer sessions; C3 deviations accepted (refund payment_id=order id, idempotency_keys table, literal 409 replay); pyjwt+cryptography added local-dev-only. Full suite 74 green; 16 paths live-booted.
- **Why**: Minimal unblocking diffs; every deviation evidence-backed and verified.
- **Consequences**: Slice-3 = payments + vendor ops + dispatch; needs Firebase project ID + admin phone + UPI provider.
- **Affects**: `workers/api/`, slice-3 plan

### ADR-021: C1 slice-2 auth — RealVerifier adapter, session families, in-memory limits, LOG-ONLY integrity
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Approved C1 design (6 answers) on branch 002-backend-foundation: Firebase OTP → D1 sessions for user/vendor/admin.
- **Options considered**: firebase-admin SDK (rejected — grpc/native deps risk on Python Workers beta; PyJWT+Google certs is pure-Python); D1 rate counters now (rejected — per approved answer, in-memory + TODO slice-3); blocking Play Integrity (rejected — LOG-ONLY per approved answer); new schemas/auth.py (rejected — DTOs co-located in the router, 9-file slice stays 9).
- **Decision**: `adapters/firebase.py:RealVerifier` (aud+exp+sig; missing project → 502 UPSTREAM_FAIL, bad token → 401 UNAUTH); sha256-hashed opaque tokens (30m access + 7d rotating refresh, family_id + burned table, reuse kills family); suspended GET me → 200 + restrictions, writes via require_active_user/require_role; `scripts/seed_admin.py` refuses once an admin exists; tests assume `app.api.deps.set_test_connection` (2 hook tests xfail until integrator lands it).
- **Why**: Every approved answer is implemented literally; the Adapter + Repository + DI seams keep the Workers move (cert fetch, D1 counters) as isolated swaps; landing `auth_deps` retires the orders/addresses ImportError stubs by design.
- **Consequences**: Integrator must mount the auth router under /v1, add `set_test_connection` to deps.py, and move C3 order router tests to Bearer (3 currently 401 on X-User-Id headers — verified pre-existing green without auth_deps, untouched per instructions).
- **Affects**: `workers/api/app/{adapters/firebase.py,api/auth_deps.py,api/v1/auth.py,repositories/user_repo.py,repositories/session_repo.py,services/auth_service.py,db/migrations/002_auth.sql,scripts/seed_admin.py,tests/test_auth.py}`

### ADR-020: Slice-1 backend complete — stdlib-sqlite Repository as the D1 seam
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: 3 parallel builders (B1 scaffold/core, B2 pricing/routes, B3 db/repo/stub) landed disjoint files on `002-backend-foundation`; parent integrated: full suite 20 passed, uvicorn boot + live /health, /v1/catalog, POST /v1/quotes verified (2 refills + 1 empty → 5600/15000/20600, exactly the pricing-model worked example).
- **Options considered**: SQLAlchemy ORM (rejected — D1 speaks HTTP, not DBAPI; ORM would be thrown away at deploy); Alembic now (rejected — 2 tables, add with auth slice); firebase-admin now (rejected — needs project ids; stub seam with documented swap).
- **Decision**: stdlib `sqlite3` behind a Repository protocol (same SQL runs on D1 in prod); all money integer paise; Firebase as one-file stub adapter; ponytail-minimal file set (~24 files incl. tests).
- **Why**: The Repository seam is the only abstraction that survives the local→Workers move; everything else is the thinnest code that satisfies the contract's slice-1 surface.
- **Consequences**: Slice-2 (auth + orders + D1 migrations) builds on these seams; contract §8 open items (ASGI spike, providers) still gate deployment, not development.
- **Affects**: `workers/api/`, slice-2 plan

### ADR-019: B2 slice-1 catalog/quotes — align to landed B1 interfaces
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Task brief assumed `get_settings` in `app.core.config` + kwarg-style `AppError(code, message, status_code)`. Landed B1 code has `get_settings` in `app.api.deps` (lru-cached `Settings`: `rate_refill_paise`/`rate_container_paise`/`deposit_per_jar_paise`/`cap_charge_paise`/`quote_ttl_minutes`) and `AppError(message, details)` with code/status as class attrs + central envelope handlers (validation → 400 VALIDATION).
- **Options considered**: Import from briefed paths (rejected — ImportError/TypeError, verified by failing tests); duplicate settings/error code in B2 files (rejected — B1 owns them, drift risk); align to real B1 interfaces (chosen).
- **Decision**: Routers use `app.api.deps.get_settings` + real `rate_*` field names; `OverLimitError(AppError)` subclass (`code=OVER_LIMIT`, 422) follows B1's own subclass pattern; `business_hours/holidays/serviceable_prefixes/rate_version` read via getattr-with-default until B1 adds them. Router tests run against B1's real `create_app`, so validation asserts 400 (production truth, matches brief §4 "400 validation auto") not 422.
- **Why**: Broken imports are worse than brief drift; subclassing is B1's own extension mechanism; testing through the real factory verifies the true envelope.
- **Consequences**: B2 files depend on B1 names — renames break loudly (fail fast, intended). B1 main.py already mounts both routers under /v1.
- **Affects**: `workers/api/app/api/v1/catalog.py`, `quotes.py`, `tests/test_quotes.py`

### ADR-018: Contract audit run-1 (security-audit skill, guidance mode + finder teams)
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: User ordered a senior self-review (gaps/overwrites/overcomplications) plus global install of Cloudflare's security-audit skill and a vulnerability pass over the API contract. Installed via `npx skills add … --skill security-audit --global` (copied to `~\.agents\skills\security-audit` for all agents; PromptScript global quirk noted, skill readable and loaded).
- **Options considered**: Full-audit mode with external output dir (rejected — no executable code exists; sandbox runs N/A; findings are contract-logic, evidenced by spec text; report kept in-repo per project convention, deviation logged in the report).
- **Decision**: Ran 3 read-only finder teams (traceability / contract-logic vulns / complexity+ops) + parent adversarial verification; patched all confirmed items; logged rejections with reasons and open external facts. Report: `Feature_docs/security/api-contract-audit.md`.
- **Why**: 16 logic flaws (suspend bypasses, refund races, assignment races, quote replay, idempotency scope, CSRF, refresh race, FCM scoping, GPS spoof, custody integrity, device farms, reassign races, refund double-pay, webhook replay) + 25 traceability gaps (missing endpoints/tables, stale OTP text, ADR-007 triple-use, photo contradictions) were real on re-read; 6 simplification proposals were worse than the status quo on senior review.
- **Consequences**: Contract is now buildable without known logic holes; remaining gates are external facts (§8 + audit OPEN list) + Phase-2 executable re-audit once code exists.
- **Affects**: api-contract §§0–15, schema, synthesis rows, architecture auth, decision index, progress tracker

### ADR-017: No-photo v1 — reason-code complaints + vendor verification protocol
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: No object storage in v1, so every photo in the contract (PoD, complaint, evidence) had to go. User asked for the replacement: reason codes + vendor verification + return policy that works on words.
- **Options considered**: Free-text-only complaints (rejected — untriagable, unreportable); vendor auto-approves all returns (rejected — invites false claims); admin decides everything (rejected — doesn't scale, slow).
- **Decision**: 11-code reason catalog; quantity/deposit disputes auto-resolve from ledger records; quality claims go through vendor door/pickup verification (agree → auto redelivery/refund; disagree → frozen statements + 48h admin triage); sealed-intact = full reversal, opened = quality-path only; ≥3 false claims/90d → abuse strike. PoD/complaint `photos` columns kept NULL in v1, activated with object storage in v2. Overrides FR-20 "photo required" (contract is the authority).
- **Why**: Triage without images needs structure (codes) + a trusted second pair of eyes (vendor at the door) + a bounded escalation (48h admin) + a fraud backstop (abuse strikes). The sealed/opened line answers the hygiene question photos used to dodge.
- **Consequences**: Complaints/quality endpoints + tables updated (§§4.7/4.9/14.3/14.4 + schema); security spec EC-V02..V04 aligned; avatar + PoD photo become v2 object-storage items.
- **Affects**: api-contract §§4.7/4.9/14.3–14.5, complaints + quality_incidents tables, vendor verify task UI

### ADR-016: Trust & safety — suspend ladder, strikes, quality/batch incidents, custody-guarded replacement
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: User asked for super-admin power over misbehaving vendors/users, subscription-cancel money recovery, muddy-water returns, and vendor replacement per zone — plus unthought-of real cases. Research: BIS issues real packaged-water recall orders for failed batches (IS 14543); Indian case files show mid-route swaps, fake-collector UPI fraud, COD impersonation.
- **Options considered**: Auto-remove vendors at strike thresholds (rejected — auto-removal is an abuse/error vector; human confirms); delete-offender accounts (rejected — destroys evidence; suspend preserves); allow vendor personal UPI collection (rejected — enables fake-collector fraud; agency-QR lock chosen); hard GPS block (already rejected in ADR-015).
- **Decision**: Graduated warn→restrict→suspend→terminate with instant session revocation (vendor suspend also kills Firebase user); strikes + 24h quality window (reason-code + vendor verification, ADR-017 — no photos in v1) + free redelivery/refund; batch rule (≥3/7d → under_review + batch hold + user notices); subscription-cancel deposit offset + dues dunning ladder + audited write-off; custody-zero guard on zone detachment; UPI payee lock + per-order OTP + seal check as anti-fraud triple lock.
- **Why**: Every control maps to a documented real failure (recall orders, swap cases, fake collectors); money recovery is event-sourced like §10 so it inherits the no-over/no-under guarantee.
- **Consequences**: D1 gains suspend columns + strikes + quality_incidents; ~10 new admin endpoints (§14.5); admin trust board becomes a Phase-2 build item.
- **Affects**: `workers/api/`, admin trust board UI, vendor/user suspension screens

### ADR-015: Multi-vendor zones + capacity + cancellation settlement + 3-purse money model
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: User challenged the v1 contract: it modelled isolation but not vendor↔user linkage (who serves whom), not per-vendor quantity control, not cancellation billing accuracy, not vendor-vs-user money. Correct — those were missing.
- **Options considered**: Manual admin assignment per order (rejected — doesn't scale past ~20 orders/day); vendor self-pickup pool (rejected — cherry-picking, no load balance, breaks isolation); zone router + deterministic least-loaded assignment + admin override (chosen). Visit fee on late cancel (rejected for v1 — dispute cost > revenue); GPS hard-block on PoD drift (rejected — fails real deliveries; soft-flag chosen).
- **Decision**: Zones own geography; vendors attach to zones with priority + tunable per-vendor caps; deterministic assignment with unassigned SLA queue; users/vendors never address each other (zone router introduces per order). Cancellation settles by state×money-moved matrix with compensating ledger events + refund rows (UNIQUE per payment). Three purses: user (dues/deposit), vendor custody (in_hand must zero at shift close), agency books (deposits carried as liability, not revenue). Per-stop-fee payouts coexist with salary model.
- **Why**: Removes the three production failure modes that kill water-delivery ops: misrouted orders (zones), over/under-charging on cancel (event-sourced settlement), and cash leakage (custody tracking). Every rule is a server invariant, not UI convention.
- **Consequences**: D1 gains zones/vendor_zones/vendor_profile/shifts/refunds/payouts tables; ~12 new endpoints (spec §§9–14); needs payout-model + visit-fee + GPS answers in §8.4 before scaffold.
- **Affects**: `workers/api/`, D1 schema, vendor app (meters/queues), user app (cancel/rider/bill states), admin (zone board, day-close, queues)

### ADR-014: Backend API contract v1 spec (proposed)
- **Date**: 2026-09-29
- **Status**: Proposed
- **Context**: User asked for the API contract first: backend logic + request map + D1 schema with user/vendor/admin restrictions, covering every FR (01..37) + SEC/EC controls, before any app scaffold.
- **Options considered**: Code-first scaffold (rejected — 3 clients share one ledger; contract drift = rewrites); UI-first (rejected — same reason + auth shape unknown); contract-first spec with D1 schema + RBAC matrix + error catalog (chosen).
- **Decision**: Spec at `Feature_docs/backend/api-contract.md`: conventions (envelope, idempotency, cursor paging, rate limits), module map (Layered/Repository/DTO/State-Machine/Adapter/Strategy named), 15-table D1 schema, per-table view matrix, ~45 endpoints (auth/quote/orders/subs/payments/vendor/jars/complaints/devices/admin/webhooks), 2 mermaid sequences, error catalog, prod notes. Server computes all money; clients never send totals/roles.
- **Why**: Every endpoint traces to an FR/VR/UR/SEC/EC id; state machine + ledger invariants + hold-block + over-limit tanker stops + IDOR rules are enforced server-side so Flutter/Next build in parallel against staging mocks.
- **Consequences**: Needs approval + 3 answers (ASGI spike, tunables, UPI provider) before `workers/api/` scaffold; flow.md untouched (spec-only, no code).
- **Affects**: `workers/api/`, D1 schema, all 3 clients, Phase-2 build order

### ADR-013: FastAPI + Firebase Auth OTP (FCM push only) + security spec
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: User locked FastAPI + Firebase for OTP; asked for senior-security threat model covering payments, login/OTP, validation, order limits/tanker, addresses, subscriptions, vendor failures, device-farm fraud, secrets, OWASP, graceful errors, admin observability, prod checklist.
- **Options considered**: FCM-as-OTP-verifier (rejected — FCM is push only; Firebase Auth phone verifies OTPs); D1-only OTP codes (rejected as primary — Firebase Auth is the verifier, D1 keeps users/sessions/audit); skipping spec and scaffolding (rejected — SSDLC requires threat model before code).
- **Decision**: Firebase Auth (phone) verifies OTP → Workers verifies ID token (aud/exp) → D1 sessions; FCM = push only with server-side targeting. Spec written to `Feature_docs/security/security-threat-model-and-edge-cases.md` (SEC-A/I/P/F/C + EC-O/G/S/V/R series, STRIDE/OWASP, prod gates).
- **Why**: Correct primitive per job (Auth vs FCM), keeps zero-trust server checks, and answers every user scenario (home ≤5 / office ≤30 / tanker hard-stop, skip-today vendor list, device cap 3/30d, quote lock, idempotency) with acceptance criteria before build.
- **Consequences**: Phase-2 must wire Firebase project + sender allowlist, Play Integrity, rate limits, and admin audit dashboards; tunables (COD cap, skip cutoff) locked after survey.
- **Affects**: `workers/api/`, auth flow, Flutter Secure Storage, admin observability, Phase-2 spec

### ADR-012: Backend Python on Cloudflare Workers + D1 SQLite for auth/users
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: User locked backend: Cloudflare Workers hosts Python backend, D1 SQLite manages application user login etc. Surfaces: 2x Flutter Android (user/vendor) + Next.js Super Admin web share one API + one DB.
- **Options considered**: Vercel/Next API + Postgres Neon/Supabase (rejected — user has Cloudflare infra, wants edge SQLite ops simplicity); Durable containers / Railway FastAPI (rejected — more ops, cost); Workers JS/Hono + D1 (rejected as primary — team wants Python, keep as fallback if Python beta blocks us).
- **Decision**: One Python Worker (`workers/api/`, pure-Python deps only) exposing /auth /orders /jars /billing /admin → D1 binding (`env.DB`). Auth = Firebase phone OTP → D1 `users/sessions` (the `otp_codes` path in this line is superseded by ADR-013 — Firebase is the verifier); Flutter uses Bearer token, Admin web HttpOnly cookie same API.
- **Why**: Single edge API serves all 3 surfaces; D1 SQLite fits jar ledger + dues relational model at v1 scale with zero DB ops; tech-selection Step 0 classifies this as fullstack product-service (auth+orders+billing) so backend+DB justified — smallest thing that does the job.
- **Consequences**: Python Workers is beta — no native C extensions (no psycopg, bcrypt-C; use pure-Python/hashing via Workers crypto), CPU-time/memory caps, stateless only. D1: 10GB/db, single-writer, batch reconciliation writes. Mitigation: keep deps stdlib+pure-Python, idempotency keys, audit table for money edits. If FastAPI ASGI adapter fails on Workers, fallback to Flask-style handlers or JS Hono port (trigger documented).
- **Affects**: `workers/api/`, D1 schema (users/sessions/otp/jars/orders), Flutter auth clients, Next.js admin middleware, context/architecture.md

### ADR-011: SYN-2 synthesis — vendor requirements + pricing-deposit model (proposed)
- **Date**: 2026-09-29
- **Status**: Proposed
- **Context**: Series-3 needs buildable vendor + pricing contracts from B (all 5) + C2 + D2/D3 + E-summary + project-overview.
- **Options considered**: Full vendor-matrix prose per source (rejected — Series-3 needs atomic IDs with acceptance); atomic VR-01…VR-14 with source/priority/acceptance + v1/v2 split and a separate pricing-deposit model with UNVERIFIED flags + survey gate (chosen).
- **Decision**: Accept `Feature_docs/synthesis/vendor-requirements.md` (VR-01 triple, VR-02 offline, VR-03 ledger never-negative, VR-04 Rs150 + closure, VR-05 Rs3 cap, VR-06 pause/resume ≥24h, VR-07 route+loading sheets, VR-08 WhatsApp + own-bank QR + carry-forward, VR-09 evening reconcile, VR-10 Hindi v1, VR-11 audit, VR-12 hold>3 block, VR-13 breakage v2, VR-14 GPS-lite) and `pricing-deposit-model.md` (deposit (N−E)*150, Rs28/30 vs Rs72→98 UNVERIFIED gap with different-business caveat, Paniwale-tier translation S10/20/30 @28 = 252/476/672 proposed, wallet-v2 vs UPI+COD-v1, RWA 50–200 + office 20–30/floor/mo, 2.5–3 buffer, 8-8 Sun-closed, 10-day return, 3-day dispute, survey gate).
- **Why**: Every rule traces to a fetched source line (E rulebook for deposit/hold/return, B-matrix for ledger/billing/offline, C2 for buffer/RWA/deposit-band, C3 for tiers, D for PoD/state-machine/MVP-split); unverified numbers stay flagged per ADR-007b §06 rule so price lock waits on the local survey.
- **Consequences**: Series-3 must lock offline conflict semantics, skip-one vs pause-all, hold-limit default (3), and run the §8 survey before Rs 28/30 + Rs 150 lock.
- **Affects**: Feature_docs/synthesis/, vendor app + admin spec, pricing lock

### ADR-010: Group-B operations research — jar ledger + billing flows locked
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Series-2 Group B (R-B) deep research over B1 (Rekart), B2 (Pure Pani + RO sub-page), B3 (PaniHisab + Features), B4 (EPIXS) for Shodasha jar/deposit/route/subscription ops. All six URLs fetched full-page via webfetch (+ pricing/blog/compare supplements via search); browseros-neo skill loaded but its browser actions are not exposed in this env, so webfetch/websearch fallback used throughout — noted honestly in each file's Meta.
- **Options considered**: Shallow per-vendor summaries (rejected — Series-3 needs buildable mechanics); carry rival-source claims (Rekart ₹1,500+/mo, English-only; PaniHisab offline) as facts (rejected — labelled (R)/unverified in matrix); full spine extraction with matrix + ledger model + billing flows and explicit unverified lists (chosen).
- **Decision**: Accept 5 files in Feature_docs/research/B-operations/; Series-3 synthesis inherits: atomic doorstep triple per stop (given/empties/cash-UPI, offline-tolerant), per-customer jar ledger (held + Rs 150 deposit balance + dues, never-negative invariant), Rs 150-at-booking + refund-on-closure lifecycle, pause-with-resume schedules + auto loading sheets, WhatsApp bills with own-bank UPI QR + carry-forward dues, evening route reconciliation, Hindi v1; v2: photo proof, per-customer rates, payroll, expenses/P&L, Gujarati.
- **Why**: All four vendors run the identical spine (order→assign→deliver→collect-empty→cash→ledger→billing) and differ only in weight — the kernel above is the intersection, so it is the safest v1 scope; EPIXS supplies the lifecycle/breakage edge cases the SaaS trio omits, PaniHisab the schedule engine + ₹99 price anchor, Pure Pani the QR-ledger + offline pattern, Rekart the daily-reconcile + churn-signal discipline.
- **Consequences**: Series-3 must resolve the unverified list (deposit Rs-value handling per vendor, Rekart price/language single-sourced, Pure Pani traction/settlement, PaniHisab caps/offline, EPIXS demo unexecuted) + local price/deposit survey per §06 rule before locking constants; flow.md untouched (research-only task, no functions/routes changed).
- **Affects**: Feature_docs/research/B-operations/, Series-3 synthesis, user/vendor/super-admin surfaces

### ADR-009: Group-C competitor research — copy-vs-differentiate locked
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Series-2 Group C (R-C) deep research over C1 (CanCan), C2 (Rekart blueprint), C3 (Paniwale), C5 (JalSeva GitHub). C3 site is a JS shell — body recovered from indexed snippets; JalSeva read to source-file level (booking/login/tracking/payments/firebase/gemini/maps/types).
- **Options considered**: Treat CanCan counters and Paniwale snippets as validated facts (rejected — marketing claims / second-hand text); carry them labelled UNVERIFIED with recovery tasks + adopt only the mechanics verified in fetched bodies (chosen).
- **Decision**: Accept 5 files in Feature_docs/research/C-competitors/; Series-3 inherits: copy one-tap repeat + wa.me links (C1), jar discipline 2.5–3/cust + stop flow + wallet-deferred (C2), Rs 150 deposit + Return&Repeat (C3), OTP/3-tap/guards/domain-types (C5); differentiate on published Rs 28/30 pricing, Rs 150 (not 200–300) deposit, window-no-dot, UPI+COD v1.
- **Why**: C1 proves the WhatsApp repeat mechanic live, C2 is the only numeric ops blueprint, C3 the only subscription ladder with Shodasha's exact deposit figure, C5 the only buildable reference — together they cover channel, ops, pricing, and code with no single-source dependency.
- **Consequences**: Series-3 must mystery-shop CanCan wa.me, in-browser confirm Paniwale, and run the local price survey (Rs 28–30 still unvalidated); flow.md gets a competitor-input trace only (research task, no app functions/routes changed).
- **Affects**: Feature_docs/research/C-competitors/, Series-3 synthesis, user/vendor/super-admin surfaces

### ADR-008: Group-A UX case-study research — accepted with A3 secondary-only rule
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Series-2 Group A (R-A) deep research over A1/A2/A3/A5 for Shodasha repeat-order UX, reliability, window-vs-dot. A3 primary unrecoverable (Medium 404 on markdown+text, archive 404, author/title searches no hit).
- **Options considered**: Drop A3 entirely (rejected — PaniBox report §05/§04 preserves its two design rules and Series-3 needs the gap visible); fabricate A3 body from generic UX knowledge (rejected — dishonest); publish A3 doc as secondary-index reconstruction with BLOCKED status + recovery task (chosen).
- **Decision**: Accept 5 files in Feature_docs/research/A-ux-case-studies/; A3 cited downstream ONLY as "secondary index, primary pending"; Series-3 synthesis inherits the top-8 user-app rules (repeat-machine home, quote lock, window-not-dot, inline steppers, deposit-at-booking, OTP-first/price-unwalled, one-tap pause, proof-over-promises) and the unverified-claims inventory.
- **Why**: A1 gives the strongest UX mechanics, A2 the only causal behavioural evidence, A5 the only shipped-system reference — losing A3's traceability over a dead link would be worse than carrying it honestly labelled; explicit evidence grades stop inflated claims (40% capacity, <30s reorder, 100% migration, WTP levels) leaking into the spec.
- **Consequences**: Series-3 must retry A3 via signed-in browser (browseros-neo) or author contact; flow.md untouched (research-only task, no functions/routes changed).
- **Affects**: Feature_docs/research/A-ux-case-studies/, Series-3 synthesis, user/vendor/super-admin surfaces

### ADR-007c: Group-D — canonical order-state machine + MVP/v2 split (proposed)
- **Date**: 2026-09-29
- **Status**: Proposed
- **Context**: Group-D dev-guide research (Octal/Goteso/Appinop/WDS) converged on a tri-app model and an order lifecycle; Series-3 needs one canonical machine to spec against.
- **Options considered**: D4 verbatim order (picked→packed→assigned→dispatched→delivered) vs Goteso accept-first flow; chosen merge: placed→accepted→picked→packed→assigned→dispatched→delivered with cancelled/failed/rejected branches, payment as separate field.
- **Decision**: Propose the merged machine + MVP (repeat, window, UPI/COD, invoice links, OTP/photo PoD, jar ledger) vs v2 (AI auto-reorder confirm-first, IoT parked, route-AI, live customer map) split per _group-D-summary.md.
- **Why**: D2 gives the tri-app structure, D4 the lifecycle/ETA/payment-link evidence, D3 the v2 parking lot; Shodasha scope (arrival window, no live dot, Rs 150 deposit) constrains the MVP slice.
- **Consequences**: Series-3 must lock assign-before-vs-after-pack, pause semantics, deposit edge cases; D1 needs browser re-verification (403-blocked, reconstructed).
- **Affects**: Feature_docs/research/D-dev-guides/, Series-3 synthesis, user/vendor/super-admin surfaces

<!-- Newest decisions go at the top of this section. Keep this section growing — it is
     the living memory of the project. Delete the two example entries below once you
     have real decisions. -->

### ADR-007b: F-market — all Actowiz figures UNVERIFIED, price lock gated on local survey
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Group F research (R-F) read F1 + F2 fully. F1 is a method pre-registration with no findings yet; F2 is vendor marketing with no disclosed methodology, an "illustrative figures" footer disclaimer, and an internal 2026 volume inconsistency (region splits sum to 3.24M vs 7.4M headline).
- **Options considered**: Treat Rs 98 QC average as a pricing anchor (rejected — different product/channel/city, unverified); average Rs 28–30 with Rs 98 (rejected — F1's "separate business" rule forbids blending); quarantine all Actowiz numbers + gate price lock on a local survey (chosen).
- **Decision**: All F1/F2 numbers stay flagged UNVERIFIED per PDF §06; Shodasha pricing locks only after the local price-census + household-willingness survey filed under `Feature_docs/research/F-market/`. Rs 28–30 remains a scope input, not a validated market price.
- **Why**: Averaging or anchoring off unaudited vendor claims would lock a launch price to Delhi quick-commerce data that measures a different business; the survey plan in `_group-F-summary.md` §3 is the cheapest path to a defensible price.
- **Consequences**: Series-3 synthesis must quote the 3.3–3.5× gap only with the "different business" caveat; F1 URL needs a post-window diary-check for published findings.
- **Affects**: Feature_docs/research/F-market/, pricing, Series-3 synthesis

### ADR-007: Bisleri Group-E adoption (deposit/hold 1:1, COD diverge, wallet v2)
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Group-E research (E1 FAQs + E2 deposit page) gives the industry-standard jar rulebook: Rs150/jar refundable deposit, Rs3 cap-missing, empty-with-cap stepper, Daily/Weekly/Custom + 1mo-1yr, hold/resume ≥24h, 10-day return + wallet refund, 8am-8pm Sun-closed, gate/2nd-floor, 3-day dispute, no-COD/wallet-only.
- **Options considered**: Copy Bisleri prepaid-only (rejected — Shodasha Rs28/30 local market needs COD); ignore Bisleri rules (rejected — deposit/hold/return discipline prevents jar leakage); adopted split below.
- **Decision**: Adopt 1:1 — empty stepper + (N−E)×150 note, Rs3 cap charge, hold range + ≥24h resume, 10-day return SLA, lift/gate note, hours + 3-day dispute, offers-void-on-cancel. Diverge — keep UPI+COD in Phase-1 (Bisleri no-COD noted as reference). Defer — Bisleri Wallet to v2 (keep ledger fields now).
- **Why**: Jar-asset protection and pause/return UX are proven by the market leader; COD is a local-market necessity, wallet is overhead Phase-1 doesn't need — so copy the discipline, not the payment constraint.
- **Consequences**: Booking card needs live deposit math; vendor handover needs cap counter; admin needs 10-day return + 3-day dispute queues + deposit ledger; wallet v2 is a migration not rewrite.
- **Affects**: user app booking/hold/return, vendor handover, super-admin billing/disputes, Feature_docs/research/E-bisleri/

### ADR-006: specify-cli install mandated
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Series-1 setup needs a spec-driven SDLC (specify → plan → tasks → implement) after community skills bootstrap. Agent.md already requires `specify init` after Skills.py.
- **Options considered**: Manual specs in markdown only (no executable SDLC commands, drifts); specify-cli via uv from spec-kit (chosen).
- **Decision**: Mandate `uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@latest` then `specify init .` after Skills.py run.
- **Why**: Unlocks speckit.* SDLC commands for Series-2/3 research-to-build handoff; single standard spec flow across user/vendor/super-admin surfaces.
- **Consequences**: Setup series must run Skills.py first, then specify install; agents must use speckit commands once available.
- **Affects**: repo root, SDLC workflow, all future feature specs

### ADR-005: Feature_docs/ at root in English full deep-dive with browseros-neo reading
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: User approved Feature_docs/ at root, English, full deep-dive for Series-1/2/3 research (6 groups A–F + synthesis). Research sources are live web pages needing logged-in/JS-capable reading.
- **Options considered**: Hindi/mixed notes in context/ only (rejected — user explicitly approved English root folder); shallow summaries (rejected — deep-dive needed for build); plain fetch scraping (rejected — weak on dynamic pages).
- **Decision**: Research lives in `Feature_docs/` at root in English, full deep-dive; live web reading via browseros-neo skill.
- **Why**: User approval is explicit on location, language, and depth; browseros-neo is the dedicated signed-in agent browser, so it handles dynamic/login pages better than raw fetch.
- **Consequences**: Series-2 agents must load browseros-neo before web research; all group outputs in English under Feature_docs/research/.
- **Affects**: Feature_docs/, Series-2/3 research, browseros-neo usage

### ADR-004: Shodasha 3-surface split (2x Flutter Android + Next.js web super-admin)
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Shodasha needs customer ordering, delivery fulfilment, and back-office oversight. Research (PaniBox report F1–F8) shows repeat-order UX, jar-exchange tracking, and WhatsApp/UPI ops span three distinct actors.
- **Options considered**: Single Flutter app with roles (rejected — mixes customer simplicity with driver ops, bloats repeat-order path); all-web PWA (rejected — Android native preferred for GPS/offline delivery); chosen split below.
- **Decision**: Three surfaces — Flutter Android user app (repeat order, Rs 28/30 SKUs, Rs 150 exchange, window, pause, WhatsApp, UPI/COD) + Flutter Android vendor/delivery app (stops, empties in/out, cash collected) + Next.js React Super Admin website (orders, jars, billing, disputes).
- **Why**: Each actor gets the minimal surface it needs: one-tap repeat stays clean for users, drivers get per-stop ops, admin gets oversight — matches tri-app pattern (Octal/Goteso guides D1–D2) and keeps dependency boundaries clean.
- **Consequences**: Shared domain (SKUs, deposits, windows) must stay consistent across three codebases; Series-2/3 research must tag findings per surface.
- **Affects**: user app, vendor app, super-admin web, Feature_docs/ synthesis

### ADR-003: Remove Scaffold.py — canonical trees are the source of truth
- **Date**: 2026-08-11
- **Status**: Accepted
- **Context**: Scaffold.py generated a folder skeleton, but `npm install` / create-app already provides boilerplate. The generator produced a generic tree that ignored per-project needs and duplicated what the `folder-structure` skill already defines.
- **Options considered**: Keep Scaffold.py but improve it (extra maintenance, still redundant with the skill); remove it and rely on the canonical trees (chosen).
- **Decision**: Delete Scaffold.py. The `folder-structure` skill (`.agents/folder-structure/SKILL.md`) is the single source of truth; agents materialize its canonical trees by hand, creating only folders the product needs.
- **Why**: One source of truth instead of two. The skill's trees are the "senior engineer" hierarchy — feature-first frontend, controller-service-repository backend. Remove the Python dependency from the workflow.
- **Consequences**: Agents must create folders manually — the skill's Step 2 shows how. All docs updated (Agent.md, SKILLS.md, README.md, .agents/AGENTS.md).
- **Affects**: repo root, `.agents/folder-structure/SKILL.md`, all docs referencing it

### ADR-002: Add `flow.md` + `decision.md` as living context files
- **Date**: 2026-08-11
- **Status**: Accepted
- **Context**: Agents couldn't understand the project instantly and didn't update context properly. `progress-tracker.md` alone didn't capture HOW the app works (function call maps, user flows) or WHY decisions were made.
- **Options considered**: Fold this info into existing files (overloaded, no single "how/why" home); new dedicated files (chosen).
- **Decision**: Create `context/flow.md` (Mermaid call maps, user flows, request/response, routes) and `context/decision.md` (append-only ADR log). Both are updated on EVERY task, alongside `progress-tracker.md`.
- **Why**: Reading the three files (progress-tracker + flow + decision) gives state, structure, and rationale instantly. Decision log prevents re-deciding and preserves reasoning.
- **Consequences**: Agents must keep diagrams in sync; stale diagrams are treated as bugs. Sync protocol is enforced via AGENTS.md + Agent.md.
- **Affects**: `context/`, `AGENTS.md`, `Agent.md`, `SKILLS.md`, `.agents/AGENTS.md`, `ai-workflow-rules.md`

### ADR-001: Choose Next.js 16 + TypeScript
- **Date**: YYYY-MM-DD
- **Status**: Accepted
- **Context**: Need an SSR-capable framework with strong typing for a multi-page product.
- **Options considered**: React + Vite (no SSR, worse SEO), Astro (less dynamic for app routes), SvelteKit (smaller ecosystem for the team).
- **Decision**: Next.js 16 + TypeScript.
- **Why**: SSR/SSG out of the box, App Router supports the feature-first layout, TypeScript strict mode is a hard requirement, largest ecosystem.
- **Consequences**: Must default to server components; avoid heavy client bundles.
- **Affects**: entire app

### ADR-002: [Example — component library choice]
- **Date**: YYYY-MM-DD
- **Status**: Accepted
- **Context**: Need form controls and modals for the [feature] section.
- **Options considered**: HeroUI (too heavy to default), MUI (banned), custom (slow).
- **Decision**: Pull the [X] components from Astryx, animate with [Y].
- **Why**: Matches the design language in `ui-context.md`; copy-paste ownership preferred per `DESIGN.md`.
- **Consequences**: [things to watch out for]
- **Affects**: `features/<feature>/components/`
