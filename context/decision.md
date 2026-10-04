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
| ADR-070 | 2026-10-04 | 023 restore WATER_API service binding (dropped in 013 cutover) as binding-first transport; edge rejects worker-to-worker HTTPS with opaque 403 | Accepted | apps/admin_app wrangler/server, branch 023-water-api-binding |
| ADR-069 | 2026-10-04 | 021 temporary access-code admin login (config-gated demo door + form mode) while phone OTP is repaired; no Firebase SDK in bundle so client Firebase path can never work as built | Accepted | apps/admin_app server/form, branch 021-admin-demo-door |
| ADR-068 | 2026-10-04 | 020 login passthrough: form shows server message (was discarding it — the bare 'Could not send the code'), fetch failures logged + returned as NETWORK | Accepted | apps/admin_app server/form, branch 020-login-error-passthrough |
| ADR-067 | 2026-10-03 | 019 pasteable login errors: worker message passthrough on start + Copy triage bundle (never secrets) | Accepted | apps/admin_app server/form, branch 019-pasteable-login-errors |
| ADR-066 | 2026-10-03 | 018 admin login: prod diagnosability (apiUrl normalize, status-carrying errors, tail logs) + Firebase naming guard + VITE_PUBLIC trap doc | Accepted | apps/admin_app server/form/wrangler, branch 018-admin-login-observability |
| ADR-064 | 2026-10-03 | 016 vendor dashboard: one-screen Route-tab composition (TodayStrip fold + inline earnings + per-customer held/dues) + zone-scoped placed pool + ledger fields on customers | Accepted | workers/api vendor_service/vendor.py/tests, apps/vendor_app route/customers/shell/tests, Feature_docs/vendor-dashboard/spec.md, branch 016-vendor-dashboard |
| ADR-065 | 2026-10-03 | 017 flow sync A+B+C: PoD OTP to user, vendor cash→money truth, hold flags, quality/duty on tables, admin money writes, user nits, returns end-to-end | Accepted | workers/api vendor/order/dispatch/admin/returns + tests, vendor_app stops/sync/route/shell, user_app orders/subs, admin_app BFF/vendor-detail/finance/dispatch/payments, branch 017-flow-sync |
| ADR-063 | 2026-10-03 | 013 round 2: analytics/finance/dispatch surfaces + ledger adjust + returns tab from PDF/FR research; cutover — new dashboard renamed apps/admin_app_v2 → apps/admin_app, legacy admin + branch 005 deleted, zero backend changes | Accepted | apps/admin_app (TanStack Start), Feature_docs/premium-admin-dashboard/upgrade-roadmap.md, branch 013-premium-admin-dashboard |
| ADR-062 | 2026-10-03 | 015 finish: user orders LIVE wiring + vendor brilliance within tokens + contract proof shapes | Accepted | apps/user_app orders/api/main/tests, apps/vendor_app route/stops/sync/earnings/tests, branch 015-vendor-user-sync |
| ADR-061 | 2026-10-03 | 015 parallel remainder: sub due_today in list + FCM queue_or_log (no sends) + badge test + PoD hint + skeleton (no new deps) | Accepted | workers/api subscription/fcm/scheduler/tests, apps/user_app test, apps/vendor_app stops, branch 015-vendor-user-sync |
| ADR-060 | 2026-10-03 | Vendor-user sync: stop payment/address/total join + placed pool + ledger/me + 4-state + payment badges + sub Due/Paid + Android notify/backup basics | Accepted | workers/api vendor/payments/catalog, apps/user_app orders/shell, apps/vendor_app route/money, android manifests + xml, branch 015-vendor-user-sync |
| ADR-059 | 2026-10-03 | Once-only Rs150 container deposit + Flutter order-contract fix + simplify home to 2 schedule cards + fixed 8-12 + kill search | Accepted | workers/api pricing/order_service/tests, apps/user_app api_client/checkout/home/booking_sheet/confirm + tests, branch 014-deposit-wallet-simplify |
| ADR-058 | 2026-10-02 | Fix user address entry: live Bearer wiring + login-gate + picker auto-locate + selection race | Accepted | apps/user_app main/address_screen/map_picker + test, branch 012-address-auth |
| ADR-057 | 2026-10-02 | UI lift (layout shapes only) from premium grocery reference into 6 user+vendor surfaces | Accepted | apps/user_app booking/auth + test, apps/vendor_app route/stops/customers/support/earnings/inventory/core + tests, branch 010-grocery-ui |
| ADR-056 | 2026-10-02 | Wave-1 UX polish: vendor 4-tab + More, address Stepper, login hero, ink/theme honesty, F1 caps, critical states | Accepted | apps/user_app auth/addresses/booking/orders/theme, apps/vendor_app shell/route/support/duty/sync/inventory, workers/api F1 caps + test |
| ADR-055 | 2026-10-02 | Port wrong-repo Phase-1/Phase-2 gaps (011 migration + address format + location + vendor customers/stock/profile/queue) as Workers rewrite | Accepted | workers/api 011_port.sql + vendor/address slices + tests, apps/user_app location/address/store, apps/vendor_app customers/inventory/profile/support |
| ADR-050 | 2026-10-02 | 007-vendor-app: spec + 10 screens built, analyze 0, 13 tests green, APK on shodasha_api36 | Accepted | apps/vendor_app/, Feature_docs/vendor-app/spec.md, branch 007-vendor-app |
| ADR-051 | 2026-10-02 | Never cast Future (await then cast value); vendor google-services.json stays a user manual step (fail-soft Firebase init) | Accepted | apps/vendor_app/lib/core/api_client.dart, lib/main.dart |
| ADR-052 | 2026-10-02 | Dual-APK release (shared tag, user+vendor assets) + conn hardening (retry/single-flight/401 hook) + triple fence fixes + user_app cast port | Accepted | .github/workflows/, apps/vendor_app/lib/core/, workers/api/{src/app/{api/v1/vendor,services/vendor_service},tests/}, apps/user_app/lib/core/api_client.dart |
| ADR-054 | 2026-10-02 | Hotfix: config/audit_log never existed on prod D1 — 010_config_audit.sql migration + demo fail-closed guard | Accepted | workers/api 010_config_audit.sql, auth_service.demo_login, demo_seed.sql, test_demo.py |
| ADR-053 | 2026-10-02 | Address fix (formatted mapping) + config-gated demo login + D1 demo seed (customer+vendor+order/route) + demo buttons both apps | Accepted | apps/user_app address_screen+demo, apps/vendor_app demo, workers/api 009_demo/auth/demo_seed.sql/seed_demo.py/tests |
| ADR-049 | 2026-10-01 | Phone-as-gateway OTP via TextBee (no DLT, free tier) alongside Fast2SMS seam | Accepted | workers/api/src/app/adapters/sms.py, workers/api/src/app/core/config.py, workers/api/.env.example, workers/api/tests/test_sms_otp.py |
| ADR-048 | 2026-10-01 | Server OTP via Fast2SMS (fake/real seam, default firebase) + APK device-shape 400 fix + precise OTP errors | Accepted | workers/api/src/app/{adapters/sms.py,core/config.py,db/migrations/008_otp.sql,repositories/otp_repo.py,services/auth_service.py,api/v1/auth.py,repositories/user_repo.py}, tests/test_sms_otp.py, apps/user_app/lib/{core/auth_impls.dart,features/auth/auth_controller.dart} |
| ADR-047 | 2026-10-01 | Phase-B completion: facade-type fixes + full test await-ify, 163 green, pushed | Accepted | workers/api/src/app/services/{vendor,subscription,dispatch}_service.py, src/app/jobs/scheduler.py, src/app/api/v1/vendor.py, src/entry.py, workers/api/tests/ |
| ADR-046 | 2026-10-01 | T2 Phase-B: 10 routers on async D1 (auth.py pattern) — get_db_conn, async handlers, await service/repo/execute; payments.py extra-paren fix | Accepted | workers/api/src/app/api/v1/{addresses,admin,complaints,devices,orders,payments,ratings,returns,subscriptions,vendor}.py |
| ADR-045 | 2026-10-01 | T2 Phase-B: 5 services + scheduler jobs on async (auth_service.py pattern); address_service pure-unchanged; scheduler main sync via asyncio.run; purge r[0]→r["name"] for dict-rows | Accepted | workers/api/src/app/services/{dispatch,order,payment,subscription,vendor}_service.py, workers/api/src/app/jobs/scheduler.py |
| ADR-044 | 2026-10-01 | T2 Phase-B: remaining 6 repos on async D1 facade (user_repo.py pattern); executemany→loop, address _table_exists async; seed_admin raw-sqlite untouched | Accepted | workers/api/src/app/repositories/{address,admin_read,config,ledger,order,payment}_repo.py |
| ADR-043 | 2026-10-01 | Hotfix: missing `current_env` accessor 500'd every DB route (uncommitted hunk from ADR-042) | Accepted | workers/api/src/app/core/worker_env.py |
| ADR-042 | 2026-10-01 | T2 Phase-A auth on D1: async facade (D1Conn/AsyncSqliteConn + Rows), user/session repos + auth service/router/deps async, get_db_conn selector, pytest asyncio-auto | Accepted | workers/api/src/app/{db_d1.py,api/{deps,v1/auth,auth_deps},repositories/{user_repo,session_repo},services/auth_service}, tests/, pytest.ini |
| ADR-041 | 2026-10-01 | Worker env bridge (worker_env contextvar set in entry.py; adapters/config read request env first, os.environ second; DEV_AUTH deliberately os-only so the backdoor stays dead in prod) | Accepted | workers/api/src/{entry.py,app/core/worker_env.py,app/{adapters/{upi,firebase},repositories/payment_repo,api/v1/catalog,services/address_service}}, tests/test_worker_env.py |
| ADR-040 | 2026-10-01 | Secrets-focused review (security-audit guidance): no committed secrets/tokens/env; support number → +91 9302190067 in 5 user-visible spots; fixtures/docs keep fictional 98765 range | Accepted | apps/{user_app/lib/{core/api_client,features/{auth/auth_controller,orders/{orders_controller,bill_screen}}},admin_app/src/app/login/page.tsx} |
| ADR-039 | 2026-10-01 | Pure-stdlib RS256 verify (rsa_verify.py, DER+pow) with crypto-first fallback in firebase.py; release APK gets prod SHODASHA_API_BASE + Razorpay defines | Accepted | workers/api/src/app/adapters/{rsa_verify.py,firebase.py}, tests/test_firebase_rsa.py, .github/workflows/release.yml |
| ADR-038 | 2026-10-01 | Admin panel → Cloudflare Worker via @opennextjs/cloudflare 1.20.7 (Pages static-export impossible; next-on-pages deprecated; Next 16 supported; proxy.ts is Web-API-only) | Accepted | apps/admin_app/{wrangler.jsonc,open-next.config.ts,package.json,next.config.ts} |
| ADR-037 | 2026-10-01 | src-first backend layout: app/ moved under src/ (bundler only ships entry dir); conftest.py + seed path fixes; local runs need PYTHONPATH=src | Accepted | workers/api/{src/,conftest.py,scripts/seed_admin.py,tests/} |
| ADR-036 | 2026-10-01 | Cloudflare port T1: wrangler.jsonc + package.json + pyproject.toml + src/entry.py + db.get_d1 seam (name water, D1 binding DB, cron 15m stub) | Accepted | workers/api/{wrangler.jsonc,package.json,pyproject.toml,src/entry.py,app/db.py} |
| ADR-035 | 2026-10-01 | 006 merged to main + CI/release GitHub Workflows: JDK 17 + Flutter 3.44.9 pins, auto-patch tags + APK GitHub Releases | Accepted | .github/workflows/, main branch |
| ADR-034 | 2026-10-01 | (reserved — F-SA2 admin-panel UI upgrade, lives on 005-super-admin-panel line, see stash) | Proposed | apps/admin_app/, workers/api/ |
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

### ADR-066: 018 admin login diagnosability
- **Date**: 2026-10-03
- **Status**: Accepted
- **Context**: Prod admin login failed with bare 'Verification failed' while localhost worked. Diagnosis: (1) Cloudflare vars named VITE_PUBLIC_FIREBASE_* don't match code's VITE_FIREBASE_* (Vite bakes exact names at build) so prod silently took the dev-login path, which a DEV_AUTH-off worker always rejects; (2) malformed API_URL (trailing slash or /v1 suffix) yields non-envelope 404s the old fallback string hid.
- **Decision**: Normalize apiUrl + log host once per isolate; status-carrying error strings + [admin-auth]/[admin-api] tail logs (platform observability already on both workers); prod guard shows config-missing notice instead of a doomed dev attempt; wrangler.jsonc documents the naming trap. Single VITE_FIREBASE_* convention kept (no dual-name fallback).
- **Why**: Turns the next failure into a one-line tail read instead of a guessing game; refuses to fake a login in prod.
- **Consequences**: Needs Cloudflare var rename + rebuild to take effect; user runs npm run check (barred unasked).
- **Affects**: admin-session.ts, admin-api.ts, admin-login-form.tsx, wrangler.jsonc

### ADR-064: 016 vendor dashboard — one-screen composition + zone-scoped pool
- **Date**: 2026-10-03
- **Status**: Accepted
- **Context**: User approved 016 spec (one screen answering today-totals/stop-list/money/can-ledger, one CTA per state, vendor-only isolation, pincode-zone region rule reusing vendor_zones/order_zone/generate_routes/next_run, server paise + rupees() display, once-only deposit untouched).
- **Options considered**: New dashboard tab/route (rejected — 4-tab shell locked ADR-056, dashboard is a Route-tab section); new aggregate endpoint (rejected — (a) folds client-side from today_route stops, (c) reuses earnings, (d) needs only 2 additive keys on customers); per-order Python zone filter reusing order_zone() (rejected — N queries; single SQL EXISTS with identical instr token-match semantics, cited to dispatch_service.order_zone); specify init . (skipped — prompts to merge templates into non-empty root; phases honored via spec + task list instead); held_paise key name (rejected — held is jars not paise; keys are `held` + `dues` mirroring ledger_repo.get).
- **Decision**: RouteScreen gains TodayStrip (summarizeToday pure fold: distinct users, jars, UPI/COD collect with paid-excluded) + one CTA (Sync backlog → Triple first-pending → all-done text) + inline money (earnings controller reuse, flagged-hold note, no invented pending-payout number) + can-ledger rows (customers held/dues, nonzero-only); shell passes earnings + customers controllers. Backend: placed_pool(vendor_id) zone-scoped via zones/vendor_zones instr match (unzoned invisible — admin queue only); today_customers gains held/dues via ledger.get (owner-scoped by construction). Verify: backend 196, vendor 30, both analyzes 0.
- **Why**: Shortest diff that answers all four questions with zero new tabs/endpoints/tables/packages; isolation proven per endpoint + regression test (cross-vendor placed read closed).
- **Consequences**: Untracked/admin_app working-tree changes found mid-task are NOT this branch's (left untouched, reported). Merge + device run still owed.
- **Affects**: workers/api vendor_service.py (placed_pool/customers/today_route customer_id passthrough) + vendor.py + test_vendor.py, vendor_app route_controller/route_screen/shell/customers_controller + dashboard_strip_test + route_screen_test, Feature_docs/vendor-dashboard/spec.md, branch 016-vendor-dashboard

### ADR-065: 017 flow sync — handoff seams closed (Phases A+B+C)
- **Date**: 2026-10-03
- **Status**: Accepted
- **Context**: Audit found 8 breaks, all at handoff seams (cash→ledger, OTP→user, flagged→admin). Spec approved (Feature_docs/flow-sync/spec.md): F1 OTP, F2 cash, F3 hold, F4 quality, F5 duty, F6 admin writes, F7 nits, F8 returns.
- **Options considered**: cash inside triple txn (rejected — triple is jar-custody atomic + version-fenced replay; cash needs payment-row/dues semantics mark_paid_cash already owns; separate endpoint, deterministic stop+amount scope, no client key); auto-post cash on triple (rejected per approval — explicit one-tap); 012 migration for vendor_profile shapes (rejected — first-wins ambiguity makes ALTER unsafe; PRAGMA+conditional-ALTER convergence in ensure_profile instead, truly idempotent); flagged_hold clear endpoint (dropped — no flag store exists, nothing to clear; honest cut); bill prev/payments mapping (dropped — server never sends them and rows are !=0-guarded; comment already honest); held naming unify (dropped — local-only names, mapped once); returns assign route_id-only (chose vendor_id+date via route_for_vendor — better UX, same audit).
- **Decision**: A: delivery_otp on order detail (owner + assigned/dispatched) + user code row; POST /vendor/stops/{id}/cash (owned-stop, deterministic dedupe, in_hand bump, sync cash_amount ride, 409=already-jama); hold_blocked on route+stop (ledger>3). B: quality on table (disagree stays open, cross-vendor 404); duty/in_hand on vendor_profile (ensure convergence, router awaits); admin payouts generate/approve+list, custody confirm, reco close, zones list, capacity/zone/refund UI + BFF PATCH. C: dues pay-link button, reschedule key; returns assign (vendor+date)/pickup (owned-stop, held−/dues+cap)/refund (picked-only, deposit math from settings) + vendor pickup UI + admin assign/refund buttons. Deadlock lesson: never nest WRITE_LOCK — mark_paid_cash takes it itself.
- **Why**: Every seam now has a request/response with owner-scoping + tests; shortest diff per seam, zero new packages, 2 new UI-only tables avoided (duty via convergence, close via audit row).
- **Consequences**: Merge order with 016 matters — both touch vendor.py/vendor_service/route files + decision index (064 vs 065 noted); admin_app .env/README/routeTree + user windows gen noise are NOT this branch (left untouched); admin `npm run check` NOT run (admin AGENTS.md bars unasked validation — user runs it).
- **Affects**: (see index row)

### ADR-063: 013 round 2 — premium surfaces from field research + folder cutover
- **Date**: 2026-10-03
- **Status**: Accepted
- **Context**: Round-1 template admin was live but flat (10 surfaces, no analytics/money/operate depth). PaniBox PDF + Feature_docs/synthesis/feature-requirements.md (FR-26…FR-34) named the real super-admin powers: dispatch funnel + route sheets, day-close leak watch, WhatsApp Hindi dunning (Pure Pani loses ₹18k–70k/mo to unbilled COD), ledger adjust as the only manual money mutation, returns SLA queue, analytics pillars (on-time, fulfilment, repeat, UPI-vs-COD).
- **Decision**: Build analytics/finance/dispatch surfaces + ledger adjust sheet + trust returns tab + orders CSV export + 4-group sidebar (Monitor/Money/People/Operate) using ONLY template components (zero invented design) against existing worker endpoints (zero backend changes; wa.me deep links instead of a WhatsApp provider; dunning enriched client-side from /admin/ledger because /admin/dunning returns bare {customer_id, dues}). Cutover: legacy Next.js apps/admin_app deleted, new dashboard renamed to apps/admin_app so the Cloudflare deploy path is unchanged; old-admin branch 005-super-admin-panel deleted. Parked (needs backend): invoice WhatsApp send, calendar FR-27, CRM-lite aggregates, fleet page, RBAC.
- **Why**: Maximum admin leverage per unit of risk — every new power maps to an endpoint that already exists and is audit-logged server-side; rename keeps deploy config untouched.
- **Consequences**: User runs manual screen verification; production issues get pasted back. Unchanged worker API means zero migration risk on merge.
- **Affects**: apps/admin_app routes/-components/navigation/server, Feature_docs/premium-admin-dashboard/upgrade-roadmap.md, context docs, branch 013-premium-admin-dashboard

### ADR-062: 015 finish — live orders wiring + brilliance within tokens
- **Date**: 2026-10-03
- **Status**: Accepted
- **Context**: Biggest remaining gap was user orders on Stub (never hit backend). Three parallel tracks closed it + vendor brilliance + contract proof.
- **Decision**: `ApiBackedOrdersRepository` over send seam (list/detail/cancel/reschedule/rating, cursor passthrough, NETWORK rethrow) + main swap (Bearer already carried) + state/payment/rider/bill map (unknown→placed, server bill has no prev/payments → honest 0s) + copyWith qty fix + 7 mapping tests; vendor 48dp/ellipsis/honest empty-error-copy (no new deps, tokens unchanged); contract shapes proven (orders list/detail/cancel/reschedule/rating + base64url cursor). Security: placed vendor-gated, ledger/me owner-scoped, devices require_active, orders IDOR-404, no secrets/tables/deps. Verify: backend 194, user batches green, vendor 28, analyzes 0.
- **Why**: Makes user↔backend actually live (request/response per contract) with minimum resources: one repo, zero new packages, zero new endpoints.
- **Consequences**: Device run + merge still owed; real FCM sends need secrets.
- **Affects**: user orders/api/main/tests, vendor route/stops/sync/earnings/tests, branch 015-vendor-user-sync

### ADR-061: 015 parallel remainder (design-safe, no new deps)
- **Date**: 2026-10-03
- **Status**: Accepted
- **Context**: Three parallel tracks closed the 015 remainder: backend (sub dues, FCM, placed test), user (badge test), vendor (PoD hint + skeleton).
- **Decision**: `subscription list` adds `due_today_paise` (qty×rate, paid stays in /billing/dues); `fcm.queue_or_log` durable-row-if-table-else-log (never raises, no sends/secrets); payment-badge widget test (upi/paid stub, no timer hang); PoD collect hint via existing caller values; stop-detail skeleton (no shimmer pkg). Verify: backend 194, user 89, vendor 28, analyzes 0.
- **Why**: Smallest close-out that keeps money truth server-side, push readiness without secrets, and premium states with zero new dependencies.
- **Consequences**: Real FCM sends need service-account secrets + device run; outbox-table migration is a future decision.
- **Affects**: workers/api subscription/fcm/scheduler/tests, user test, vendor stops, branch 015-vendor-user-sync

### ADR-060: Vendor-user sync + payment visibility + Android basics
- **Date**: 2026-10-03
- **Status**: Accepted
- **Context**: User approved 015: pay-per-day + totals, 4 states + mode/money + vendor-collect note, simple Pull placed, Android premium research. Audits proved vendor blind (no payment/total/address), user payment invisible post-order, ledger/me 404, Sunday mismatch, detail 5-chip duplication, no channels/backup rules.
- **Options considered**: Auto-assign placed→vendor on create (rejected — needs geo/zones, simple Pull button approved); monthly prepay wallet now (rejected — pay-per-day + Paid-till-now approved); full FCM wiring now (deferred — backend stub + no vendor messaging dep, in-app note first).
- **Decision**: vendor _stop_out/today_route JOIN orders+addresses; GET /vendor/placed pool; GET /ledger/me wallet truth; Order +paymentMode/Status + tracking badge + bill mode; RouteStop +payment/total/status; money container-only waiver flag; catalog all-days; detail qty-only; POST_NOTIFICATIONS + backup/data-extraction rules both apps. Spec: Feature_docs/vendor-user-sync/spec.md. Verify: backend 193, user 88, vendor 28, analyzes 0.
- **Why**: Smallest sync that makes user-created orders vendor-actionable with money truth, earns trust via visible payment state, and lifts Android to 2026 baseline without new deps.
- **Consequences**: FCM end-to-end, vendor premium skeleton states, dead-dep purge, device run still owed.
- **Affects**: workers/api vendor/payments/catalog, user orders/shell, vendor route/money, android manifests/xml, branch 015-vendor-user-sync

### ADR-059: Once-only container deposit + order-contract fix + home simplify
- **Date**: 2026-10-03
- **Status**: Accepted
- **Context**: User: deposit on every delivery is wrong — only Rs30 container, only once, wallet-held, damage-forfeit, quit-refund; assure via UI wallet message; schedule fixed Subah 8-12; kill search; choose best UX; prove backend 500 via live request; branch from main.
- **Options considered**: Per-jar-every-order deposit (rejected — violates once-only rule, proven by pricing.py:42); wallet table migration now (deferred — ledger deposit_paid/refunded already wallet truth, wallet_balance stays 0 for v2); 3-step checkout + slot chips + calendar kept (rejected — 8+slot+calendar CTAs confuse, fixed 8-12 approved); Sunday skip kept (rejected — all-days approved).
- **Decision**: pricing.compute_quote adds deposit_already_paid_paise (refill 0, container (n_c-min(e,n_c)) only when held<15000); order_service waives + accepts pre-waiver quote to avoid STALE loop; Flutter api_client/checkout_service now send quote_total/rate_version/expires_at (was 400 every order); home kills search/chips, adds 2 schedule cards + wallet-safe strip; booking_sheet shows fixed 8-12 card; nextServiceableDay all-days; confirm adds wallet-safe message. Tests updated to new rule (quotes/orders/e2e/scheduler/app). Verify: backend 193, user 86, analyzes 0.
- **Why**: Fixes 100%-fail checkout at root + implements wallet trust by visibility (Profile shows held money) with smallest diff, no colour change, no new deps.
- **Consequences**: Damage-deduct + quit-refund endpoints still open (ledger holds truth, no UI yet). First device run must verify COD/UPI end-to-end + wallet strip with real ledger.
- **Affects**: workers/api pricing/order_service/tests, apps/user_app api_client/checkout/home/booking_sheet/confirm/tests, branch 014-deposit-wallet-simplify

### ADR-058: Fix user address entry (Bearer wiring + login-gate + auto-locate + race)
- **Date**: 2026-10-02
- **Status**: Accepted
- **Context**: User reported maps/address unusable in the user app and ordered a thorough once-and-done fix. Evidence-first audit proved the load-bearing root cause had nothing to do with maps: `main.dart` never gave the shared `ApiClient` the session token (vendor `main.dart` wires `accessTokenGetter`; user did not), so every authed call went bearer-less into the backend's 401 (`auth_deps.py`). Payload shape, manifest, deps, form, and pin gate were all verified correct first.
- **Options considered**: Two clients vendor-style (rejected — 5 controller rewirings for the same effect; one lazy getter closure does it); trusting the login route result in the gate (rejected — OtpScreen self-pops to first, so the gate re-checks live `isAuthenticated`); backend `is_default` now (deferred per approval — badge stays dead, first-address fallback works); tile-provider swap (rejected — user confirmed tiles render; Delhi-default pin was the real maps defect).
- **Decision**: F1 lazy `accessTokenGetter` on the shared client; F2 `openAddressesGated` + `_LoginGatePage` (no guest escape hatch, back cancels; demo path closes via `isCurrent` listener rule, OTP path via OtpScreen); F3 picker auto-locates on open with pin-first ordering (Delhi = denied/offline fallback + note); F4 `load()` re-adopts persisted selection. 5 regression tests (bearer live-switch, 3 gate cases, restart race). user 87 + vendor 28 green, analyzes 0.
- **Why**: Fixes the actual 401 root cause plus every adjacent dead-end (guest 3-step-fill-then-401, Delhi-pin trap, forgotten selection) in one pass so the complaint cannot recur in a new shape next week.
- **Consequences**: First real-authed address traffic will exercise the server path end to end — watch the first device run. Bare `ApiClient()` fallbacks in profile/support screens left as-is (main always passes controllers; noted trap).
- **Affects**: apps/user_app main.dart + address_screen.dart + map_picker.dart + address_entry_test.dart, branch 012-address-auth (aeecc83)

### ADR-057: UI lift (layout shapes only) from premium grocery reference
- **Date**: 2026-10-02
- **Status**: Accepted
- **Context**: User ordered a layout-shape lift from a read-only premium reference (`flutter_grocery_app` @ 804109e, 59 files — GetX + ScreenUtil + carousel + green/red + Poppins/Cairo + dark-mode) into 6 approved surfaces on a fresh branch `010-grocery-ui` from main (checkout had been on 009-d1-011-fix; main already held ADR-055/056, only the worker-only 011-ALTER fix stayed behind — zero Flutter impact). Skills loaded: hallmark (audit mode), impeccable (Operate), redesign-existing-projects, mobile-native. Design-first gate: reference audit + per-screen lift table + 4 clarifying questions → explicit approval (all 6 surfaces, pill-search exception, 2-col grid now, branch from main, banners/avatars out).
- **Options considered**: Keep home list-cards with inline steppers (rejected by user — 2-col slim grid approved; qty now lives in the buy-box, controller API untouched); pill search vs r8-everywhere (pill approved as the single documented radius exception); grid with inline steppers (rejected — 214px cells cannot fit stepper + deposit info; slim photo+name+price+add, tap opens buy-box); flutter_animate in vendor_app (rejected — hand-rolled `core/cascade.dart` instead, zero new deps); carousel/promo banners + avatars (out — invented content, honest-copy rule); See-all links (out — destinations do not exist; honest counts instead); first_run hero rework (out — sheet flow, not a hero surface; refinement preserves).
- **Decision**: S1 home (greeting overline+title + 48dp mark, pill search + clear, filter-aware section header + honest count, slim 2-col grid with corner 48dp add + flutter_animate stagger ≤300ms easeOut + reduced-motion guard); S2 buy-box (close-over-photo, photo fade+scale 200/250ms, Kitne-jar↔stepper single row, bordered deposit/cap/hours fact row); S3 login (48px top space + staggered hero/chips/CTA entrances; inputs un-animated); S4 route/stop (header rows with counts, bordered stop cards + 48dp seq avatars, bordered ledger fact rows, `core/cascade.dart` one-controller Interval stagger, zero Timers); S5 customers/support/earnings/inventory (tile rows with leading mark + chevron, Vivaad-queue header, section headers + bordered summaries). ScreenUtil `.w/.h/.sp` converted to fixed dp; 36px ref controls scaled UP to 48dp. Verify: user 80 + vendor 26 green, both analyzes 0 after every slice. One test-hygiene edit (flush entrance clock in wave1_ux_test).
- **Why**: Shape and rhythm lift without importing the reference's identity (palette/fonts/dark-mode), stack (GetX/ScreenUtil/carousel), or invented content — every borrowed pattern is re-expressed in ShodashaTheme tokens with Hindi copy, and every rejected affordance (dead search icon, fake See-all) is documented, not silently kept.
- **Consequences**: Home booking now routes qty through the buy-box (BOOK NOW stays disabled at 0 — same controller gate, no logic change). Watch: release-APK screenshot pass on shodasha_api36 still owed; Wave-2 items from ADR-056 unchanged. Push cuts release with all of it.
- **Affects**: apps/user_app booking/home + buy-box + login + test, apps/vendor_app route/stops/customers/support/earnings/inventory/core-cascade + tests, branch 010-grocery-ui (f8bc14e, cdda6d4, 9706b46, d639d32, 362e16f)

### ADR-056: Wave-1 UX polish (4-tab vendor, address Stepper, login hero, honesty, F1 caps)
- **Date**: 2026-10-02
- **Status**: Accepted
- **Context**: User ordered skill-loaded UX pass (hallmark audit + impeccable Operate + redesign-existing-projects + mobile-native + security-audit guidance) with 4 parallel audit agents (user UX, vendor UX, states/a11y/copy, inputs-security). 70+ ranked findings; 1 confirmed security issue (F1 unbounded address fields). Prior explicit approval: 4-tab + More, Wave 1 only, designed hero login. Committed first (008-ux-polish ce75762) so nothing could be lost.
- **Options considered**: 7-tab polish-in-place (rejected — 7 destinations mistap outdoors, approved 4+More); copying wrong-repo forms (rejected — rewrite on Water theme); new tickets tables (already rejected in ADR-055); full 40-item sweep now (rejected — approved Wave 1, rest queued as Wave 2).
- **Decision**: Vendor shell 4 tabs + drawer (Customers/Stock/Sync-log/Profile/WhatsApp/Logout); Route absorbs search + stock header + sync chip; address sheet → 3-step Stepper + save-fail stays open; login/OTP → hero card + trust chips + Step 1/2–2/2 + pin 40px; blue-filled → ink, 3 token classes → theme aliases, ~40 hardcoded literals → tokens; F1 max_length=500 both sides; duty-off confirm, sync/inventory/queue loading+error branches, slot retry, support enable fix. Verify: 191 pytest, user 80, vendor 26 green, both analyzes 0.
- **Why**: Structural declutter (steppers/drawer/sections) over button sprawl; single token source stops the next drift; fail-closed states instead of silent zeros.
- **Consequences**: Wave 2 queued (booking schedule rework, stop Triple/PoD stepper, remaining states/a11y/Hindi-copy sweep). Push cuts release with all of it.
- **Affects**: user auth/addresses/booking/orders/theme + tests, vendor shell/route/support/duty/sync/inventory + tests, workers F1 caps + test

### ADR-055: Port wrong-repo Phase-1/Phase-2 gaps as Workers rewrite (011_port)
- **Date**: 2026-10-02
- **Status**: Accepted
- **Context**: A prior agent did the Phase-1 (vendor-missing/location/address) + Phase-2 (profile/tickets/maps) work in `C:\Users\Hp\water-delivery-app` (Water-ui branch `20261002-1330-phase2`, commits 368ceca/e735c33/01c2377) instead of this repo. Verified: `water.git` main == Water HEAD 5aa7e10 (nothing leaked); all value sits only on Water-ui. User confirmed the work was intended for this repo and approved porting all gaps as a Workers rewrite, customers from route stops, tickets by extending complaints.
- **Options considered**: File-copy from water-delivery-app (rejected — different stacks: TS Hono+SQLite + single apps/user vs Python Workers+D1 + split user_app/vendor_app; copy would not compile); single-app merge (rejected — Water's split is the locked architecture, ADR-004); new tickets tables like wrong-repo 0004 (rejected — complaints + verify_complaint already cover the thread; added only the vendor queue read); ALTER-free migration (impossible — address columns must be added; documented apply-once instead).
- **Decision**: (1) `011_port.sql`: addresses += house/street/area/phone (nullable) + vendor_profile/vendor_slots CREATEs (idempotent); ALTERs documented apply-once (SQLite has no ADD COLUMN IF NOT EXISTS). (2) Backend: address repo/schemas/router carry the 4 fields; VendorService += profile_get/save, slots_get/set (50-cap), today_customers (stops grouped by customer + users name/phone join), vendor_complaints queue; vendor router += profile/slots/customers/complaints routes. (3) user_app: NEW location_service (geolocator+geocoding+permission_handler, Hindi errors, geolocator-14 no-args API), full-format form fields + use-location prefill, SelectedAddressStore + controller selection (Home/checkout/Addresses agree via resolve()). (4) vendor_app: NEW customers/ (list+search+detail) + inventory/ (loading-sheet stock, no new endpoint) + live profile edit + support queue filling the verify-by-id form; 7-tab shell. 190 pytest + user 78 + vendor 23 green, both analyzes 0.
- **Why**: Rewrite (not copy) is the only port that respects the locked stacks; every gap is covered by tests; duplicates avoided (OSM picker, earnings, complaints-verify reused, not rebuilt).
- **Consequences**: USER must apply 011 to D1 once (`wrangler d1 execute shodasha --remote --file=src/app/db/migrations/011_port.sql`; ALTERs error harmlessly on re-run). Push to main cuts a dual-APK release with all of it. Still blocked (unchanged): google-services.json/plist for push, keystore, privacy URL.
- **Affects**: workers/api 011_port.sql + address/vendor slices + test_port_011.py (+011 in test_addresses/test_e2e harnesses), apps/user_app (location_service, address_screen, selected store, pubspec, Info.plist), apps/vendor_app (customers, inventory, profile, support, shell, api_client)

### ADR-054: Hotfix — config/audit_log missing on prod D1 (010_config_audit.sql + demo fail-closed)
- **Date**: 2026-10-02
- **Status**: Accepted
- **Context**: Prod 500 on POST /v1/auth/demo right after ADR-053 landed: `D1_ERROR: no such table: config`. Root cause is NOT commit feb8aa8's code — the `config` + `audit_log` tables are slice-1 tables created only by `db.init_schema()` (local sqlite path); ADR-037 applied migrations 002–007 to D1, and no migration file ever created these two. So `ConfigRepo.get` (used by demo gate, catalog rates, admin config GET/PUT) and `audit_log` writes were landmines on D1 from day one; demo was just the first route to step on one. Reuse of 009 was rejected: 009's `schema_migrations` row already exists on D1, and D1 re-execution of `CREATE TABLE IF NOT EXISTS` inside a tracked file is a no-op there.
- **Options considered**: Reuse 009 (rejected — already applied on D1, silently no-ops); call `init_schema` from the request path (rejected — hides the schema drift, and DDL-in-request on D1 is a smell); `except Exception -> flag=None` guard only, no migration (rejected — leaves admin config routes + rates 500ing).
- **Decision**: (1) `010_config_audit.sql` — same shape as db.py `_SCHEMA`, idempotent, restores schema_migrations integrity. Apply with the other migrations: `for f in src/app/db/migrations/*.sql; do wrangler d1 execute shodasha --remote --file="$f" || break; done` then `wrangler d1 execute shodasha --remote --file=./demo_seed.sql`. (2) `demo_login` wraps the config read in try/except → 401 "Demo login is off." (fail closed — the flag defaults to off anyway, so behavior is unchanged for any DB state). (3) 2 new tests: pre-010 DB (002+009 only, no config table — the exact prod condition) → clean 401 not 500; migrations-only + seed → demo works. 184 pytest green.
- **Why**: Fix the actual schema drift (root cause) for every config/audit_log consumer, plus a one-line fail-closed so the demo door can never 500. Log the runbook in demo_seed.sql so the next D1 change applies migrations first.
- **Consequences**: USER still must run the migration loop + demo_seed.sql on D1 (remote). Until then demo shows 401 (clean), admin Config page will still 500 — the migration is the real fix. Keep `010` in mind for the next fresh-env setup.
- **Affects**: workers/api/src/app/db/migrations/010_config_audit.sql, src/app/services/auth_service.py (demo_login), demo_seed.sql (header runbook), tests/test_demo.py (+2)

### ADR-053: Address fix + demo login + demo seed
- **Date**: 2026-10-02
- **Status**: Accepted
- **Context**: User reported address add/edit broken (no Google key to give) + asked for demo creds + D1 demo data (customer vs vendor) + dummy payment test + new release.
- **Options considered**: Google Maps SDK (rejected — needs billing-enabled API key the user can't provide; OSM pin picker already exists and works); DEV_AUTH in prod (rejected — os-only by design, un-armable from worker vars); always-on demo endpoint (rejected — config flag + hash-only revocable codes instead).
- **Decision**: (1) Address root cause was wire-mapping, not maps: app sent `address_line`/`phone` which the server schema silently drops → saved text came back empty. Fixed `toApi()` to send `formatted` + mock round-trip test. No Google key needed anywhere (OSM tiles + manual home/office form). (2) Demo door: migration 009 `demo_codes` + config-gated `POST /v1/auth/demo` (flag + hash compare + device rate limit + normal session mint) + `demo_seed.sql`/`seed_demo.py` (idempotent fixed ids: demo customer/vendor, address, dispatched Rs-20600 COD order, today route+stop, ledger, flag=1) + 6 backend tests. (3) Demo buttons in both apps (preset fill, server-gated so prod shows a clean error, role-gated per app) + tests. Dummy payment = existing fake UPI/COD path (no keys needed).
- **Why**: Smallest root-cause fixes; demo is revocable (config 0 / delete codes) and provable (E2E script green on scratch DB; vendor demo sheet screenshot-verified).
- **Consequences**: User must run demo_seed.sql on D1 once; creds customer +919000000001/111111, vendor +919000000002/222222. Push to main cuts the release with both APKs.
- **Affects**: user address_screen + auth/demo + tests, vendor auth/demo + tests, workers 009/auth service+router/demo seed + tests

### ADR-052: Dual-APK release + connection hardening + triple fence fixes
- **Date**: 2026-10-02
- **Status**: Accepted
- **Context**: User asked for commented files, a unified release page with both APKs clearly labeled, proof the vendor app talks to the Python backend correctly, senior-level conn optimization, a security pass, and merging 007 to main.
- **Options considered**: Per-app tags/two Releases (rejected — fragments changelog, confuses sideloaders about which pair goes together); sequential single-job builds (rejected — 2× wall time, coupled logs); loosening CORS for mobile (rejected — CORS never affects native HTTP; verified in middleware.py); retrying all POSTs (rejected — PoD/duty have no server dedupe; retry only replay-safe paths).
- **Decision**: release.yml = version job (one shared tag) → matrix build (user+vendor, fail-fast, unique artifact names) → release job (per-app downloads, renamed shodasha-user/shodasha-vendor APKs, SHA256SUMS, file→audience table in body); ci.yml matrix for both apps. Client: replay-safe retry (GET/keyed POST/sync-batch, backoff+jitter, Retry-After honored), GET single-flight, 401/403→forceLogout hook, outbox cleared on logout, https assert, allowBackup=false, 60s sync timeout. Backend: triple requires Idempotency-Key (orders convention), idem-check before version fence, version+1 on commit, same-payload-done replays without 409. Ported await-cast fix to user_app (20 sites) + regression test.
- **Why**: Research-backed (release-matrix practice, AWS/Stripe retry guidance, audit threat model); every change covered by tests (vendor 19, user 67, backend 176 green).
- **Consequences**: First main push cuts a two-APK release. Open backend TODOs (logged, not built): random per-order PoD OTP + attempt cap, server cash-vs-total cross-check, per-key sync results, 401 refresh flow, real keystore.
- **Affects**: workflows, vendor core/auth/sync/main/manifest, workers vendor router+service+tests, user api_client+test

### ADR-051: Never cast Future + fail-soft Firebase init (vendor)
- **Date**: 2026-10-02
- **Status**: Accepted
- **Context**: Route widget test (MockClient) threw `type 'Future<dynamic>' is not a subtype of 'Future<Map<...>>'` — the `send(...) as Future<Map>` pattern (copied from user_app) is a runtime type error on every typed call. Same latent bug exists in user_app's ApiClient (flagged, not fixed — different app, out of scope).
- **Options considered**: `send<T>` generics (rejected — bigger diff across all callers); await-then-cast-value per method (chosen — smallest root fix).
- **Decision**: Every typed ApiClient method is now `async` + casts the awaited value. Firebase init wrapped in try/catch so the APK boots and the login screen renders before the vendor `google-services.json` lands (OTP send surfaces the SMS error path until then).
- **Why**: Fixes the crash class at the root with zero behavior change; fail-soft keeps screenshots/QA possible pre-console-step.
- **Consequences**: 13 tests green including the route-sheet widget test; login screenshot-verified on shodasha_api36.
- **Affects**: `apps/vendor_app/lib/core/api_client.dart`, `lib/main.dart`

### ADR-050: 007-vendor-app (spec → approved → 10 screens built)
- **Date**: 2026-10-02
- **Status**: Accepted
- **Context**: Pasted new-session prompt ordered vendor Android app on branch `007-vendor-app` with RULE 0 + git hygiene + parallel research + design-gate spec.
- **Options considered**: Building app code immediately (rejected — AGENTS.md hard gate Spec→Clarify→Approve→Implement); single-agent research (rejected — brief ordered parallel vendor-domain/API/Flutter-build agents).
- **Decision**: Created `007-vendor-app` from `main` (dirty macOS registrant + .freebuff/.idea/.utim_tmp left untouched); ran 3 parallel research agents; wrote `Feature_docs/vendor-app/spec.md` (screen map, wireframes, endpoint matrix, light-only visual system) and paused for approval.
- **Why**: Keeps fictional-API risk at zero (endpoints/shapes cite live `vendor.py`/`vendor_service.py` + contract §4.7/§9/§11/§12/§14) and preserves design-first compliance.
- **Consequences**: No `apps/vendor_app/` code exists yet; next step is user approval → scaffold → build → analyze/test/APK screenshots.
- **Affects**: branch 007-vendor-app, Feature_docs/vendor-app/spec.md, context sync (this file + progress-tracker + flow)

### ADR-049: Phone-as-gateway OTP via TextBee (no DLT)
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: User cannot get DLT approved (blocks Fast2SMS prod) and refuses Firebase billing. Requested the phone-as-sender pattern. Verified: TextBee (open source, free 300/mo + 50/day, key auth, delivery status) vs SMSGate cloud (free, no caps published, community-run). User's criterion was no-DLT; both qualify — picked TextBee for docs/key-auth/sustainability.
- **Options considered**: SMSGate cloud (kept as fallback); staying Firebase-only (rejected — needs Blaze for real SMS); DLT anyway (blocked).
- **Decision**: `TextBeeProvider` in `adapters/sms.py` (x-api-key, e164 recipients, optional deviceId); `OTP_PROVIDER=textbee`; `TEXTBEE_API_KEY`/`TEXTBEE_DEVICE_ID` settings; service sms branch accepts fast2sms+textbee (caught by a failing test). 176 pytest green.
- **Why**: Same seam, no behavior change until switched; sender is the owner's SIM with zero provider bill.
- **Consequences**: User-side: install TextBee app, link device, hand over API key → `TEXTBEE_API_KEY` secret + `OTP_PROVIDER=textbee` var + redeploy. Watch: gateway phone must stay on/online; free-tier cap; sender is a personal number (dedicated SIM advised).
- **Affects**: sms adapter + config + env example + sms tests

### ADR-048: Server OTP via Fast2SMS + APK verify 400 fix
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: APK verify 400'd (app sent `device` as string, contract needs `{id}` object); all send failures masked as "network problem"; Firebase SMS needs Blaze billing (Sept 2024, verified) which the user refuses. Verified 2026 pricing: Fast2SMS Rs 0.25/SMS from Rs 100 (+GST + Rs 0.025 scrubbing); DLT registration mandatory for all providers.
- **Options considered**: MSG91 SendOTP (rejected — pricier packs, same DLT need); Blaze with cap (rejected by user); test-numbers-only (kept as the QA path, not the build).
- **Decision**: `adapters/sms.py` fake/real seam (`OTP_PROVIDER`, default firebase = zero behavior change); `008_otp.sql` + `OtpRepo` (sha256 only, 5-min TTL, 5 attempts then burn, single-use); service branches + additive `channel` on 202 and optional `phone`/`otp_code` on verify; app sends `device:{id}`, returns channel, skips Firebase on `sms`, distinct sms/server/network errors. 172 backend + 66 app tests green.
- **Why**: Smallest shape that kills the 400 today, unmasks errors, and makes the provider a secret-flip once the user finishes DLT + Rs 100 recharge.
- **Consequences**: User-side still open: DLT entity/header/template (spec file has plain-language steps) + `FAST2SMS_API_KEY` secret + `OTP_PROVIDER=fast2sms` var. Push redeploys `water`; APK needs a release rebuild for the device fix.
- **Affects**: backend sms slice + app auth (see index)

### ADR-047: Phase-B completion — facade-type fixes + tests await-ified, 163 green
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: The three partition workers landed repos/services/routers but left 58 tests red, plus three src-side type bugs my verification caught: `VendorService`/`SubscriptionService` held raw `sqlite3.Connection` while awaiting `execute` on it; `dispatch_service` module functions and scheduler jobs had the same raw-conn shape; `vendor.py` over-awaited the sync in-memory `duty`/`vendor_check_quality`.
- **Options considered**: Service-internal auto-wrap of raw conns (rejected — hides the facade contract; Phase-A requires callers to pass `Conn`, tests wrap like `test_auth` does); wiring cron `scheduled` to `run_all(D1Conn)` now (rejected — D1Conn untested against real D1; comment updated to async-ready instead, wiring deferred); router-by-router rollout (rejected — user approved full Phase-B).
- **Decision**: `__init__`/job signatures take `Conn = D1Conn | AsyncSqliteConn` (vendor, subscription, dispatch, scheduler); dropped the two bogus `await`s in `vendor.py`; converted 7 test files (vendor, aftermath, payments, dispatch_admin, admin_panel, scheduler, e2e: wrap conns, `async def` + `await`, `get_db` overrides → `get_db_conn` + facade). Full suite 163 green, zero RuntimeWarnings, zero `Depends(get_db)` in routers, zero raw-conn hints in services/jobs/repos. Committed + pushed; `water` rebuilds from main.
- **Why**: Fixes the exact prod 500 (`no such table: orders` — sync `:memory:` sqlite on Workers) at the root for every route at once, with zero behavior change locally.
- **Consequences**: Admin panel + user-app routes run on D1 once redeployed. Watch item: first real-traffic check of `/v1/admin/orders` + OTP login. Cron wiring still open (tested-D1 follow-up).
- **Affects**: `workers/api/src/app/services/{vendor_service,subscription_service,dispatch_service}.py`, `workers/api/src/app/jobs/scheduler.py`, `workers/api/src/app/api/v1/vendor.py`, `workers/api/src/entry.py`, `workers/api/tests/{vendor,aftermath,payments,dispatch_admin,admin_panel,scheduler,e2e}.py`

### ADR-046: T2 Phase-B — 10 routers on async D1 (auth.py pattern)
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: Phase-B router partition: 10 routers still injected sync `get_db` while services/repos land as `async def` via parallel workers — every conn-touching handler needed `async def` + `await`.
- **Options considered**: Awaiting pure helpers too (address_service/pricing/_uid/_service constructors — rejected, no conn use, stay sync like auth.py `_service`); converting services/repos/tests/catalog/quotes (rejected — other workers' partitions, untouched); rewriting `sqlite3.OperationalError` guards (rejected — logic-identical; same behavior locally, D1 errors differ but that matches the landed pattern).
- **Decision**: `get_db` → `get_db_conn` import + `Depends` swap (orders.py keeps `get_settings`); all 80 conn-touching handlers `async def` (zero conn-free handlers existed, so none stayed sync); `await` on every service/repo call + `(await conn.execute(...)).fetchone()/fetchall()` paren-wrap; `commit()`/`rollback()`/`WRITE_LOCK` sync; module helpers `_service/_svc/_uid/_require_idem/_now/_cursor/_sla_due/_display/_to_out` sync; conn-touching helpers async (`admin._audit` awaits `write_audit`, `complaints._delivered_at`, `returns._owned_address`); `get_current_user` try/except fallbacks untouched; routes/models/codes/params/logic/noqa identical. One forced fix: `payments.py:refund_done` had an extra `)` (SyntaxError) — removed so compileall passes.
- **Why**: Mechanical mirror of Phase-A auth.py; smallest diff that matches the async service/repo shape with zero behavior change.
- **Consequences**: compileall green on all 10 files; zero `get_db` remnants; zero un-awaited execute/service/repo sites (grep-verified). Full pytest expected red until all Phase-B partitions land (per brief, not run).
- **Affects**: `workers/api/src/app/api/v1/{addresses,admin,complaints,devices,orders,payments,ratings,returns,subscriptions,vendor}.py`

### ADR-045: T2 Phase-B — 5 services + scheduler jobs on async (auth_service.py pattern)
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: Phase-B partition: dispatch/order/payment/subscription/vendor services + scheduler jobs still called repos/`conn.execute` synchronously while repos land as `async def` via the parallel worker — every DB-touching service call needed `await`.
- **Options considered**: Full-file rewrites (rejected — ponytail smallest-diff; scripted mechanical transform + full-diff review instead); converting routers/tests too (rejected — other workers' partitions, untouched); adding `executemany`/facade changes (rejected — db_d1.py not mine); leaving `purge_expired`'s `r[0]` (rejected — KeyError under dict-rows, proven by smoke run).
- **Decision**: `async def` on every method touching a repo, another DB-touching service method, or `conn.execute`; `await` on every such call site with `(await conn.execute(...)).fetchone()/fetchall()` paren-wrap; `commit()`/`rollback()`/`WRITE_LOCK` sync; pure helpers sync (`_now/_today/_parse_*`, money/validation, `pod_otp`, `_haversine_m`, `_stop_out`, in-memory `duty`/`vendor_check_quality`/`seed_quality`); provider `create_intent`/`verify_webhook` + `pricing.compute_quote` sync (adapters/pure, like the auth verifier). `address_service.py` unchanged (pure, zero repo/conn use). Scheduler `main()` stays sync, wraps `AsyncSqliteConn` + `asyncio.run`. One forced fix: purge `r[0]` → `r["name"]` (sqlite3.Row accepts both; dict-rows only the latter).
- **Why**: Mirrors landed Phase-A exactly; behavior/logic/SQL/errors/constants byte-identical apart from async/await and the one indexing fix.
- **Consequences**: compileall green; zero un-awaited repo/execute sites (grep-verified); module importable; `run_all` smoke on migrated :memory: DB green. Full pytest expected red until routers/tests partitions land.
- **Affects**: `workers/api/src/app/services/{dispatch_service,order_service,payment_service,subscription_service,vendor_service}.py`, `workers/api/src/app/jobs/scheduler.py`

### ADR-044: T2 Phase-B — remaining 6 repos on async D1 facade
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: Phase-A (ADR-042) converted only the auth slice (user/session repos); address/admin_read/config/ledger/order/payment repos still took raw `sqlite3.Connection`, so every non-auth DB route still 500s in prod (per-request `:memory:` sqlite, D1 unused).
- **Options considered**: Converting routers/services/tests in the same pass (rejected — owned by other workers' partitions; pytest will stay red until they land, which is expected); adding `executemany` to the facade (rejected — db_d1.py owned by another worker); touching seed_admin.py (rejected — verified raw-sqlite3 only, zero repo imports).
- **Decision**: Mechanical copy of the `user_repo.py` pattern across the 6 files: `Conn = D1Conn | AsyncSqliteConn`, constructor `conn: Conn`, every conn-touching method `async def`, every `execute` awaited, commit/rollback left sync, WRITE_LOCK/SQL/noqa/errors/logic byte-identical. Two forced adaptations: `config.all_rates` `executemany` → awaited `execute` loop (facade has no `executemany`; same INSERT OR IGNORE per key); `address_repo._table_exists(conn)` → `async def` (facade execute is async-only), awaited through `_blocked_by_order/_sub` → `update/delete_owned`. `sqlite3` import kept only where `OperationalError`/`IntegrityError` are caught (address/order/payment); dropped in config/ledger/admin_read (hints only). Pure helpers (`_now`, `_validate`, `_row`, `_page`, etc.) stay sync.
- **Why**: Smallest diff that unblocks the router partition: repos expose the awaited shape services will call, with zero behavior change locally (AsyncSqliteConn wraps the same sqlite).
- **Consequences**: compileall green; zero un-awaited `execute`, zero un-awaited repo-internal calls, zero awaited commit/rollback. Full pytest expected red until routers+services+tests partitions land (not a regression).
- **Affects**: `workers/api/src/app/repositories/{address_repo,admin_read_repo,config_repo,ledger_repo,order_repo,payment_repo}.py`

### ADR-043: Hotfix — `current_env` accessor was never committed (every DB route 500'd)
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: Prod `POST /v1/auth/otp/start` (and every route via `get_db_conn`) 500'd with `ImportError: cannot import name 'current_env' from 'app.core.worker_env'`. HEAD 027c34b (ADR-042) added the import in `deps.py:52` but the 5-line `current_env()` helper existed only as an uncommitted working-copy edit — `worker_env.py` at HEAD had just `set_worker_env` + `env_get`.
- **Options considered**: Rewriting `get_db_conn` to avoid the helper (rejected — the helper is the right seam; the import was already correct, only the definition was missing); broader refactor of the env bridge (rejected — ponytail/design-patterns smallest-fix rule).
- **Decision**: Committed the single 5-line hunk (`current_env()` returning `_current_env.get()`) as `1bc4cb5` and pushed to main; Cloudflare rebuilds `water` from main. Unrelated `GeneratedPluginRegistrant.swift` modification left uncommitted. 163 pytest green before and after.
- **Why**: The import and all callers were already correct — the only defect was the missing definition, so shipping it is the minimal root-cause fix.
- **Consequences**: OTP start/verify + refresh/logout/me run again once the worker redeploys; watch the `water` deploy + retry admin login. Lesson: Phase-B conversions must verify `main` imports resolve (e.g. a cold `python -c` import pass) before pushing.
- **Affects**: `workers/api/src/app/core/worker_env.py`

### ADR-042: T2 Phase-A — auth slice on async D1 facade
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: First DB-touching prod route 500'd (`no such table: users` — per-request `:memory:` sqlite, D1 unused). Phased scope approved: auth slice first (login unblocked; everything else already 500s in prod, so no regression possible).
- **Options considered**: Full 350-site conversion at once (rejected — approved phased); sync facade over D1 (impossible — Workers async-only); rewriting all tests' harnesses (rejected — kept raw conns + AsyncSqliteConn wrapper, only test_auth/test_vendor touched).
- **Decision**: `db_d1.py` (D1Conn via prepare/bind + all()/run(), AsyncSqliteConn wrapper, cursor-compatible Rows with rowcount from D1 meta); user/session repos + auth service/router/auth_deps async; new `get_db_conn` sync selector (D1 in prod, wrapped sqlite locally, double-wrap-safe); pytest asyncio-auto. Non-converted routers keep raw `get_db` (unchanged locally; still 500 in prod until their phase). 163 pytest green.
- **Why**: Minimal-diff crossing: only `execute` gains `await`; commit/rollback/fetch shapes untouched; local/test behavior identical.
- **Consequences**: Push redeploys `water`; otp/verify+refresh+logout+me run on D1 (schema + admin row already live). Phase-B: remaining routers.
- **Affects**: `workers/api/src/app/{db_d1,api/deps,api/v1/auth,api/auth_deps,repositories/*,services/auth_service}`, `tests/test_auth.py`, `tests/test_vendor.py`, `pytest.ini`

### ADR-041: Worker env bridge (vars/secrets were invisible in prod)
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: Login failed with "Auth provider not configured" despite FIREBASE_PROJECT_ID set in wrangler.jsonc. Docs confirm: Python Workers expose vars/secrets on the env object (`self.env`), never `os.environ` — every `os.environ.get` in the codebase returned None in production (rates only worked because of code defaults).
- **Options considered**: Reading `request.scope["env"]` in every route (rejected — touches 14 routers for the same effect); moving everything to wrangler secrets (wrong layer — vars were already correctly placed, just unread).
- **Decision**: `app/core/worker_env.py` (request-scoped ContextVar set once per fetch in `src/entry.py`); `env_get()` checks worker env → os.environ. Applied at the choke points: upi `_setting()` (covers all adapter secrets), Firebase project id, payment VPA, serviceability prefixes. `DEV_AUTH_ENABLED` deliberately left os-only — proven by test to be un-armable from worker vars. 4 bridge tests; full suite 163 green.
- **Why**: One seam, zero behavior change locally/tests, production reads what the platform actually provides.
- **Consequences**: Push redeploys `water`; Firebase project id resolves; login proceeds to real SMS/test-number verification.
- **Affects**: `workers/api/src/{entry.py,app/core/worker_env.py}`, adapters, `tests/test_worker_env.py`

### ADR-040: Secrets-focused review + real support number
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: User asked for a security-skill pass over hardcoded secrets/URLs/env + swapping the placeholder support number for +91 9302190067. Skill loaded: security-audit (guidance mode — rule applied: only concrete boundary+result counts; checklist nits are not findings).
- **Options considered**: Full audit with artifacts (rejected — user asked a focused question, not a full review); rewriting test fixtures to the new number (rejected — churn for zero gain; 98765-range is India's standard fictional prefix and never user-visible).
- **Decision**: Scan verdict — no high/medium findings: `.env`/`.env.local`/`data/`/`.dev.vars` all untracked+gitignored; no Cloudflare tokens in git; committed key material is public-by-design only (Firebase client key, `rzp_test_*` publishable key, D1 id, workers.dev URLs in CI); google-services.json committed per standard practice. One hygiene fix class: 5 user-visible placeholder numbers → +91 9302190067 (kSupportPhone, 2× wa.me share links, auth phone hint, admin login placeholder). Test fixtures + format-doc comments keep 98765.
- **Why**: Smallest diff that removes every user-facing placeholder without touching test semantics or inventing new secret-handling.
- **Consequences**: Next release APK + admin redeploy carry the real number. Informational residual: SHA fingerprints + Firebase authorized domains remain user-side console steps.
- **Affects**: `apps/user_app/lib/{core/api_client.dart,features/auth/auth_controller.dart,features/orders/{orders_controller.dart,bill_screen.dart}}`, `apps/admin_app/src/app/login/page.tsx`

### ADR-039: Pure-stdlib RS256 verify + prod release defines
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: App-login audit found the worker cannot verify Firebase tokens (cryptography banned on Workers) and the release APK points at localhost. PyJWT also skips aud/exp checks when the signature is unverified (proven empirically), so the fallback hand-checks claims.
- **Options considered**: `rsa` PyPI package for RSA math (rejected — extra dep + its own C-risk; `pow()` + `hashlib` is 60 lines stdlib); D1-REST sync facade for repos (deferred to T2, unchanged); embedding Razorpay *secret* in the app (rejected — secret stays server-side; only the publishable `rzp_test_*` key ships, read char-for-char from `.env`).
- **Decision**: `rsa_verify.py` (DER reader → `(n,e)` → PKCS#1 v1.5 + SHA-256 via `pow`, constant-time compare); `firebase.py` uses crypto path when importable, pure fallback otherwise; 6 tests (self-minted keypair, tamper/aud/expiry/garbage/flip-bit). `release.yml` gains `--dart-define=SHODASHA_API_BASE=https://water.adityathakur452007.workers.dev/v1` + publishable Razorpay key. 159 pytest green.
- **Why**: Same checks, same errors on both runtimes; release APK talks to prod with zero hardcoded hosts.
- **Consequences**: Push redeploys `water` with working token verify; app-side Firebase swap still needs `google-services.json` from the user.
- **Affects**: `workers/api/src/app/adapters/{rsa_verify.py,firebase.py}`, `tests/test_firebase_rsa.py`, `.github/workflows/release.yml`

### ADR-038: Admin panel → Cloudflare Worker via OpenNext adapter
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: Panel (Next 16.3.8, BFF routes + HttpOnly cookies + proxy.ts gate) must reach the live `water` worker + D1. Static export impossible (route handlers/cookies/proxy can't export); @cloudflare/next-on-pages is deprecated.
- **Options considered**: Pages static export (rejected — kills BFF + auth); next-on-pages (rejected — deprecated upstream); @opennextjs/cloudflare 1.20.7 on Workers (chosen — supports all Next 16 minors; our proxy.ts is Web-API-only so no Node-runtime issue).
- **Decision**: Adapter + wrangler 4.145 installed; `wrangler.jsonc` (name `shodasha-admin`, `.open-next/worker.js`, nodejs_compat, ASSETS, self-reference); default open-next config (no R2 — admin SSR gains nothing from shared cache); preview/deploy/upload/cf-typegen scripts; `initOpenNextCloudflareForDev()` in next.config; `_headers` + `.open-next` ignore + `.dev.vars.example`. `npm run build` green (14 pages + 4 routes + proxy); adapter build green (worker.js emitted, Node-middleware experimental warning logged as watch item).
- **Why**: Official, maintained path per Cloudflare + OpenNext docs; verified locally before any dashboard step.
- **Consequences**: User creates dashboard Worker `shodasha-admin` (root `apps/admin_app`, build `npx opennextjs-cloudflare build`, deploy `npx opennextjs-cloudflare deploy`) + sets `API_URL` + 3 Firebase web keys (login is dead without them).
- **Affects**: `apps/admin_app/{wrangler.jsonc,open-next.config.ts,package.json,next.config.ts,public/_headers,.gitignore}`

### ADR-037: src-first backend layout (bundler only ships the entry dir)
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: First real deploy failed at API validation: `ModuleNotFoundError: No module named 'app'` — pywrangler uploads only `src/` (entry landed at `/session/metadata/entry.py`), sibling `app/` never shipped.
- **Options considered**: Root-level entry importing `app` (rejected — unverified bundling assumption; official examples are all src-contained); copying app into src (rejected — duplicates source of truth); `git mv app src/app` (chosen — history preserved, matches official layout).
- **Decision**: `app/` → `src/app/`; new root `conftest.py` puts `src/` on `sys.path` for pytest; `scripts/seed_admin.py` + 10 test files' migration paths repointed to `src/app/db/migrations`; local commands gain `PYTHONPATH=src` prefix. 153 pytest green. No import line inside `src/app` changed (`from app.*` still resolves — `src` is the path entry).
- **Why**: Smallest diff that satisfies the verified bundler behavior; official layout, zero speculation.
- **Consequences**: Local run/test invocations change (documented in conftest.py header); `wrangler d1 execute --file` paths unchanged (still `app/db/migrations` relative to `workers/api` — now under src, command updated accordingly).
- **Affects**: `workers/api/src/`, `conftest.py`, `scripts/seed_admin.py`, `tests/`

### ADR-036: Cloudflare port T1 — worker config + entrypoint + D1 seam (official shapes only)
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: User on dashboard "Set up your application" (project `water`, repo aadityathakur452007/water, root `/`, deploy `npx wrangler deploy`): deploying as-is would fail — no wrangler config (autoconfig fails on multi-framework monorepos per docs), wrong root, name-mismatch risk.
- **Options considered**: `npx wrangler deploy` as dashboard deploy cmd (kept as fallback — official Python examples deploy via `uv run pywrangler deploy`, mirrored in package.json `npm run deploy`, which is the configured command); moving `app/` under `src/` (rejected — huge churn on an unverified bundling assumption; `src/entry.py` imports `app.main`, one-line fix if the bundler disagrees); full async-D1 conversion now (rejected — ~130 call sites; split into T2 rather than half-ship).
- **Decision**: `wrangler.jsonc` (name `water` = dashboard project, `src/entry.py`, compat 2026-10-01, `python_workers` + `python_dedicated_snapshot` flags from the official FastAPI example, `d1_databases` binding `DB`→shodasha with placeholder id that fails fast, `vars` only `APP_ENV`, cron `*/15`, observability on); `package.json` (wrangler ^4.114.0, scripts mirror official examples); `pyproject.toml` (fastapi/pydantic-settings/httpx/pyjwt; no uvicorn — Workers ship the ASGI server; no cryptography — C-ext banned); `src/entry.py` (`Default.fetch` → `asgi.fetch(app, request.js_object, self.env)` verbatim from cloudflare/python-workers-examples 03-fastapi, `scheduled(controller, env, ctx)` verbatim from cron example, currently a logged no-op); `db.get_d1(env)` seam (returns `env.DB` or `None`; sqlite path untouched). Every shape copied from official sources, nothing invented. 153 pytest green; wrangler/package/pyproject machine-validated.
- **Why**: Dashboard needs committed config + root `workers/api` before it can succeed; T1 unblocks "Save and Deploy" structurally while T2 (async repos, pure-Python RS256, vars→pydantic confirmation) is now precisely scoped instead of vague.
- **Consequences**: User must run `wrangler d1 create shodasha` (paste id), `wrangler secret put` per key, set dashboard root to `workers/api` + deploy cmd `npm run deploy`. First deploy proves boot/config; DB routes need T2.
- **Affects**: `workers/api/{wrangler.jsonc,package.json,pyproject.toml,src/entry.py,app/db.py}`

### ADR-035: 006 merged to main + CI/release GitHub Workflows (research-backed, no hallucination)
- **Date**: 2026-10-01
- **Status**: Accepted
- **Context**: User ordered: merge the branch into main + GitHub Workflows researched from senior-engineer sources (not hallucinated), compatible Java, compiled APK published to the GitHub Releases page per push with semver tags, auto patch-bump + changelog + APK assets every CI run.
- **Options considered**: Tag-only manual releases (rejected — user explicitly wants auto-patch per main push); JDK 25 in CI to literally mirror local JBR 25.0.3 (rejected — AGP 9.0.1 release notes document JDK 17 as min+default; Gradle 9.1 runs on 17–26 so both work, but 17 is the AGP-tested path and the project's bytecode target is 17, making the APK byte-identical); real keystore signing now (rejected — no keystore exists; debug-signed release installs directly, keystore is a pre-Play TODO); actions/create-release + upload-release-asset v1 (rejected — archived/deprecated; softprops/action-gh-release@v2 is the maintained senior standard with generate_release_notes).
- **Decision**: (1) Committed 006-scoped leftovers (manifest + launcher icons + pubspec) on 006-auth-flow, merged --no-ff into main; 005-super-admin-panel strays left uncommitted (tracked part stashed as "005-super-admin-panel WIP", untracked admin_app etc. untouched). (2) `.github/workflows/ci.yml` (PR + non-main push): checkout v4 + setup-java v4 (temurin 17) + flutter-action v2 (3.44.9, cache) → analyze + test + debug APK → upload-artifact v4, contents:read. (3) `.github/workflows/release.yml` (push to main only, contents:write, non-cancelling concurrency): same verify gates → next patch from latest v* tag (none → start v1.0.1; pubspec 1.0.0+1) → `flutter build apk --release --build-name=X.Y.Z --build-number=run_number` → stage versioned APK + SHA256SUMS → softprops/action-gh-release@v2 with tag_name + generate_release_notes. No pubspec commit (no push-loop); tag pushes can't retrigger (branches:main filter).
- **Why**: Every pin traces to evidence: AGP 9.0.1 compat table (Gradle 9.1.0 / Build-tools 36.0.0 / NDK 28.2 / JDK 17) matches the local wrapper/SDK exactly; flutter-action README documents the flutter-version pin; softprops README documents files/generate_release_notes/tag_name. The JDK-17-vs-25 call is safe because the JDK only runs Gradle — phones run the compiled APK against SDK 36 with bytecode 17 either way.
- **Consequences**: First push of main with these workflows cuts v1.0.1 automatically; every later main push cuts the next patch. Real signing keystore still needed before Play distribution (debug-signed OK for direct download).
- **Affects**: `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `main` branch (merge commit of 006-auth-flow)

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
