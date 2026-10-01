# Progress Tracker

Update this file after every meaningful implementation change.

## Current Phase

**Phase-1 Research COMPLETE (2026-09-29) — 35 markdown files in Feature_docs/**

Series-1 setup done (skills 36 dirs + specify 1.0.13.dev0 + Shodasha context + 20-source index). Series-2 6-group deep research done (A/B/C/D/E/F with thorough article reads). Series-3 synthesis done (user/vendor/feature + flows + pricing + MVP).

## Current Goal

Lock Shodasha scope and research scaffold so Series-2 agents can run the 6-group deep-dive (A-ux-case-studies, B-operations, C-competitors, D-dev-guides, E-bisleri, F-market) in English full deep-dive, then synthesise in Series-3.

## Completed

- 006-auth-flow (2026-10-01, ADR-032, branch 006-auth-flow): research-backed build per Feature_docs/ux-redesign/research-and-checklists.md (Flipkart/Amazon DESIGN.md, Crafty-Bay flow, 2026 perf guides) — branded splash + logo login + pin_code_fields numeric OTP (9.4, v10 rejected on Flutter 3.44), first-run location/notify/address sheet (permission_handler rejected on compileSdk 37; geolocator+FCM used), 3-step checkout with icon delivery chips + table_calendar custom dates, repeat-first history (Bulk/First/Repeat tags + Order-again), cached_network_image removed (no network imagery). `flutter analyze` 0, 65 tests green, APK on shodasha_api36 screenshot-verified end to end. Open: container photo; google-services config for prod push; profile-mode DevTools pass.

- 005-super-admin-panel COMPLETE (2026-10-01, ADR-030/031, branch `005-super-admin-panel`): full super-admin web on the shared Python Workers API — `apps/admin_app/` Next.js 16.3.7 + Tailwind v4 tokens + TanStack Query/Table + Recharts + Geist (light-only, no purple/dark/emoji). 14 pages: Overview (KPI cards + GMV/orders/on-time/payment-split/state charts + alert deep-links), Orders + [orderId] (6-step tracker, bill, assign/reassign/cancel-override, activity), Users + [userId] (block/unblock with typed reason), Vendors + [vendorId] (custody/capacity/strikes/payouts/block/review-hold), Payments (payments+refunds tabs), Ledger (hold-limit flags), Operations (reconciliation/custody/dues/routes-generate), Trust (quality/strikes/complaints resolve actions), Audit (actor/action filters), Config, login (OTP admin gate), root redirect. Auth = BFF cookie: /api/auth/otp (start|verify, role=admin gate) sets HttpOnly `sh_session` 30m + `sh_refresh` 7d; `src/proxy.ts` (Next 16 gate) guards /admin/*; reads via GET /api/proxy, writes via POST /api/admin-actions — cookie forwarded server-side, token never in JS. Backend additive (ADR-031): `admin_read_repo.py` + 9 routes (metrics/overview, users + detail, vendors/{id}/detail, suspend/unsuspend with session revocation + admin protection + audit, payments, refunds, ledger) + additive filters on orders/audit; `_bearer()` accepts sh_session cookie fallback. 153 pytest green (8 new; overview test de-dated after UTC rollover broke fixed-date seeds), `npm run build` 19 routes green, lint clean, live smoke proxy→worker→D1 verified. Open/uncommitted: all panel work sits UNCOMMITTED and the checkout is currently on 005-home-ux — commit onto 005-super-admin-panel; Cloudflare Pages deploy (API_URL env); optional cleanup of the `smoke-admin-token-123` session row in workers/api/data/shodasha.db; worker dev-run needs `SHODASHA_DB_PATH=./data/shodasha.db` (db.py ignores DATABASE_PATH).

- 005-home-ux storefront + real checkout (2026-10-01, ADR-029, branch 005-home-ux): Alternative-A corrected spec built — photo cards + search/chips/address-bar home, detail buy-box (tap notes, delivery-type once/daily/alternate/weekly, related SKU), live windows/quotes/orders/subs/intent wiring, Razorpay-or-upi-link UPI, server-ID confirmation with Track primary, OSM pin picker (lat/lng required), bill wa.me share. Catalog locked 2 SKUs (28/30). `flutter analyze` 0 issues, 63 tests green, debug APK installed on shodasha_api36 (API 36) and screenshot-verified. Open: container photo asset; authed-session checkout vs guest UNAUTH copy; webhook secret for live paid-verify.

- Android 36 local run ready (2026-09-30, ADR-028): `platforms/android-36` + build-tools 36.0.0 were already installed (Flutter 3.44.9 targets compileSdk/targetSdk 36; doctor's "android-37.0" is just the highest platform). Installed `system-images;android-36;google_apis;x86_64` 7.0.0, created AVD `shodasha_api36` (pixel_7), booted to API 36 / Android 16, `flutter build apk --debug` green (77s), `adb install -r` Success, MainActivity resumed in foreground (targetSdk=36 verified). No project code changed. Re-run: rebuild debug APK + `adb -s emulator-5554 install -r app-debug.apk`.

- F5 user-app shell + 4 tabs done (2026-09-29, branch 004-user-app-build, ADR-027): `lib/core/` theme/api_client/session_store/auth_impls + `lib/features/{shell,addresses,subscriptions,support,profile}/` — 4-tab NavigationBar (Home=booking, Orders, Support=WhatsApp+FAQ+complaints 11-codes-no-photo, Profile=ledger/returns/language/logout), addresses+subscriptions routed from Profile. Locked palette applied (black #111 primaries incl. restyled F2–F4 CTAs, blue #0284C7 links/active only). Repaired landed F3/F4: orders_controller Color import, booking COD test input, search-test load(), lints — nothing discarded. Assets logo.png+20l.jpg registered; orders tel:/wa.me live via url_launcher. `flutter analyze` 0 issues, 56 tests green (F2 14 + F3 + F4 + theme smoke). Open: F1 real Firebase verifier + l10n consolidation + real OrdersRepository; F3 booking-confirm POST /orders wiring (ApiClient + idempotency keys ready).

- F2 user-app auth done (2026-09-29, branch 004-user-app-build, ADR-026): `lib/features/auth/` — phone_screen (focus-loss errors, disabled-until-valid), otp_screen (6-box+paste, masked, 60s resend, 5-attempt force-resend, expired path), auth_controller (ChangeNotifier on SessionStore/AuthApi/PhoneVerifier seams + local Hindi strings w/ TODO), auth_gate (splash→home/login, guest-browse safe). `test/auth_validation_test.dart` 14 green, `flutter analyze` clean. No pubspec edit (F1 owns it). Open: F1 real Firebase/Secure-Storage/l10n wiring; F3 home + booking-commit/profile gates + new-device banner. Uncommitted.

- Slice-4 backend COMPLETE (2026-09-29, ADR-025): Razorpay Orders REST live in test mode (order created, Rs 1, no money), hardening (headers/CORS/body-cap/throttle + 8 tests), scheduler jobs + CLI, 10-step E2E on fakes. 145 green, 72 paths live. Still dormant: webhook secret, agency VPA, Maps key, WhatsApp provider, service account.

- Credentials wired (2026-09-29, ADR-024): Firebase project live in RealVerifier (garbage→401 real path), Razorpay test keys in local .env (fake provider active until UPI_PROVIDER=real), admin seeded + verified, Google-sign-in-without-phone fails loudly toward phone OTP. 127 green, 72 paths live. Secrets in gitignored .env only; data/ ignored. Still needed: webhook secret, agency VPA, service-account JSON (optional), Maps key, WhatsApp provider.

- Slice-3 backend COMPLETE (2026-09-29, branch 002-backend-foundation, ADR-023): payments (fake/real UPI adapter, webhook HMAC, refunds claim-lock, dues/invoices), vendor ops (duty/routes/triple/PoD/sync/earnings/complaint-verify), subs/returns/complaints/ratings/devices/FCM fakes, zones/dispatch/admin (assign, routes-generate, ledger adjust, reconcile, queues, config, metrics). 127 pytest green, migrations 002–007 idempotent, 72 paths live. Keys guide: `Feature_docs/backend/api-keys-guide.md`. Next: provider ids + Flutter apps.

- Slice-2 backend COMPLETE (2026-09-29, branch 002-backend-foundation, ADR-022): auth (Firebase adapter fake+real skeleton, sessions w/ family rotation, suspend restrictions, seed script), addresses (owner-scoped CRUD, zone stub), orders (state machine, idempotent create/cancel/reschedule, ledger+refunds). 74 pytest green, migrations 002–004 idempotent, 16 paths live. Next: slice-3 payments + vendor ops (needs Firebase project ID + admin phone).

- C1 slice-2 auth done (2026-09-29, branch 002-backend-foundation, ADR-021): 9 files — `adapters/firebase.py` (RealVerifier, 502-no-project/401-bad-token), `repositories/user_repo.py` + `session_repo.py` (sha256 token hashes, rotation+burned reuse), `services/auth_service.py` (in-memory rate limits, LOG-ONLY integrity, suspended restrictions), `api/auth_deps.py` (get_current_user/require_active_user/require_role), `api/v1/auth.py` (otp/start+verify, refresh, logout, me), `db/migrations/002_auth.sql` (users/sessions/burned + family_id), `scripts/seed_admin.py` (one-time, refuses when admin exists), `tests/test_auth.py` (29 passed + 2 xfailed on integrator's `set_test_connection` hook, pending). Integrator notes: mount auth router under /v1; add `set_test_connection` to deps.py; C3 order router tests need Bearer (header stub retired).


- Slice-1 backend COMPLETE (2026-09-29, branch 002-backend-foundation, ADR-020): `workers/api/` FastAPI — core (config/errors/deps/health), pricing service + catalog/quote routes, stdlib-sqlite db + config repo + Firebase stub, 20 pytest green, uvicorn boot verified live (health/catalog/quote 5600/15000/20600). Next: slice-2 auth + orders (needs Firebase project ids).

- B2 slice-1 catalog/quotes done (2026-09-29, branch 002-backend-foundation): `workers/api/app/schemas/catalog.py` (SkuOut/CatalogOut/QuoteIn/QuoteOut DTOs), `services/pricing.py` (pure paise math + sha256 quote_hash), `api/v1/catalog.py` (GET /catalog, /windows 30-min slots 8–20 ex-Sun, /serviceability), `api/v1/quotes.py` (POST /quotes 200 + 15-min TTL, N>10 → 422 OVER_LIMIT), `tests/test_quotes.py` (12 passed; full suite 20 passed with B1). Aligned to landed B1 interfaces (get_settings via app.api.deps, AppError subclass pattern). Validation boundary → 400 VALIDATION per B1 handler (see decision log).

- Backend locked (2026-09-29, ADR-012): Python on Cloudflare Workers + D1 SQLite for auth/users/orders/jars. See context/architecture.md Stack + Auth/Backend sections.
- Security spec done (2026-09-29, ADR-013): FastAPI + Firebase Auth OTP (FCM push-only) threat model + edge cases + prod checklist → `Feature_docs/security/security-threat-model-and-edge-cases.md` (ssdlc skill: STRIDE/OWASP, SEC-A/I/P/F/C + EC-O/G/S/V/R, home≤5/office≤30/tanker stop, skip-today, device caps, quote lock, idempotency, admin audit).
- API contract v1 (ADR-014..017) + audit run-1 (ADR-018): contract covers zones/caps/settlement/3-purse/custody/suspend/strikes/quality + no-photo reason-code system; audit patched 16 logic flaws + 25 traceability gaps (report: `Feature_docs/security/api-contract-audit.md`). Awaiting approval + §8/OPEN external facts.

- Group-D research done (R-D, 2026-09-29): D1-octal (reconstructed — page 403-blocked), D2-goteso-triapp, D3-appinop-ai-iot, D4-customer-journey + _group-D-summary (unified tri-app checklist, canonical order-state machine proposal, MVP vs v2 split) in Feature_docs/research/D-dev-guides/; D4 slug truncation resolved to closest live match, noted honestly.

- Skills install kicked off (specify-cli mandated per ADR-006; Skills.py run deferred to setup series).
- Shodasha scope locked — 20L refill Rs 28 / Jar+Container Rs 30, repeat-order home, Rs 150 jar exchange deposit, arrival window (no live dot), pause, WhatsApp help, UPI+COD, 3 surfaces (2x Flutter Android + Next.js super-admin web).
- Context bootstrap: project-overview.md rewritten for Shodasha; Feature_docs/ scaffold at root. Series-2 six-group deep research follows, then Series-3 synthesis.
- Group F research done (R-F, 2026-09-29): F1 method-only (30 zones/10 cities, 20L separate cut, dual bare+delivered reporting — no findings yet) + F2 Delhi QC claims (Rs72→Rs98, 78%→95%, all UNVERIFIED + internal 2026 volume inconsistency 3.24M vs 7.4M) → `Feature_docs/research/F-market/` (3 files).
- Group A research done (R-A, 2026-09-29): A1 full (reorder/window/quote-lock/dispatch), A2 partial+mirrors (WTP 51%, deposit→sale, taste+convenience learning), A3 BLOCKED-404 with secondary-index fallback, A5 full (OTP/calendar/rewards/admin) + summary (comparison table, 5 flows, top-8 UX rules) → `Feature_docs/research/A-ux-case-studies/` (5 files). See ADR-008.
- Group C research done (R-C, 2026-09-29): C1 CanCan WhatsApp-only, C2 Rekart blueprint, C3 Paniwale pricing, C5 JalSeva architecture (README + 8 source files verbatim) + `_group-C-summary.md` (matrix, copy-vs-differentiate) → `Feature_docs/research/C-competitors/` (5 files). See ADR-008.
- Group E research done (R-E, 2026-09-29): E1 FAQs + E2 deposit page + `_group-E-summary.md` (Rs150 rulebook, hold/resume, 10-day return, 8-8 Sun-closed — adopt 1:1, COD-diverge, wallet-v2) → `Feature_docs/research/E-bisleri/` (3 files). See decision log Bisleri adoption entry.
- SYN-2 synthesis done (2026-09-29): `Feature_docs/synthesis/vendor-requirements.md` (VR-01…VR-14 with source/priority/acceptance, v1/v2 split) + `pricing-deposit-model.md` (deposit (N-E)*150 + Rs3 cap, Rs28/30 vs Rs72→98 UNVERIFIED gap, Paniwale-tier translation, wallet-v2 vs UPI+COD-v1, RWA/office/buffer/hours/return/dispute constants, survey gate) from B (all 5) + C2 + D2/D3 + E-summary + project-overview.

## Next Up

1. User review of Feature_docs/synthesis/ (user-requirements 25x, vendor 14x, features 37x, flows, pricing, MVP) — approve before any Flutter/Next.js scaffolding.
2. Local survey to lock Rs28/30 + Rs150 deposit (market numbers UNVERIFIED) + A3 primary recovery retry.
3. Phase-2 design-first: sitemap + user-flows skill + folder-structure for 2x Flutter + Next.js admin — needs explicit approval gate per Agent.md.

## Open Questions

- Python framework on Workers? (pure-Python Flask-style vs FastAPI ASGI adapter — confirm before scaffolding workers/api/; fallback JS Hono if beta blocks).
- Firebase project ids + session TTLs + first-admin seed — needed for auth API spec (ADR-013/016).
- Market price verification (Rs 28–30 local refill vs Rs 98 quick-commerce average) — confirm via local survey before locking pricing.
- A3 primary recovery (Medium article 404, no archive hit) — retry via signed-in browser (browseros-neo) or author contact before Series-3 synthesis; until then cite as secondary-index only.

## Architecture Decisions

See `context/decision.md` for full decision records.
