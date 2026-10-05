# WATER PLATFORM — MASTER ENGINEERING AUDIT REPORT

- **Date**: 2026-10-04/05 · **Branch**: `028-access-code-auth` · **Mode**: read-only audit (no source edits)
- **Tracks**: A authz+order-machine+sync · B payments · C flutter size/perf/deps/android · D admin reality+KPIs · E vendor experience · F customer UX+frontend perf+states+dead code+observability
- **Skills applied**: `security-audit` (guidance: boundary+result per finding) · `ssdlc` (STRIDE, authz in service) · `performance_engineering` (measure first) · `design-patterns` (architecture map) · `user-flows` (branches drawn) · `ui-checklist` (states) · `mobile-native` (touch/offline truths) · `redesign-existing-projects` (diagnose before fixing)
- **Labels**: VERIFIED (code+test proof) · UNVERIFIED (cannot prove) · BROKEN (confirmed broken) · FIXED (after remediation) · Status per item: DONE / PARTIAL / MISSING / BROKEN
- **Prior audits reused**: 028 five-track audit (S1–S5), 027 vendor-RBAC findings. Re-verified on this branch where stated.

---

## 1. Executive Summary

Money truth (ledger/never-negative/deposit-math/dues/custody/payouts), offline triple+sync fencing, RBAC vs cross-vendor IDOR, and code-only auth (028) are genuinely live and tested. The release-blockers are structural: (a) **admin web does not build** (one bad import — nothing else verifiable until fixed); (b) **orders strand at `placed`** — no accept/pick/pack/dispatch endpoints, assign requires unreachable `packed`; (c) **real money cannot move** in any deployed config (fake UPI default + test key + placeholder VPA) and the fake webhook is fail-open self-fraud; (d) **D1 multi-statement transactions are non-atomic** while tests run on atomic sqlite — half-applied money states are reachable in prod, invisible to CI; (e) **PoD OTP is deterministic and computable**; (f) **vendor unilaterally resolves disputes** it is party to. Daylight P1s: vendor web sessions die every ~30 min (refresh device mismatch), admin shell renders on vendor cookies, admin logout dead, first-page-only pagination everywhere, reconciliation/custody boards mock-only, release APKs signed with debug keys, ~5 MB of unused Flutter deps.

## 2. Baselines (measured this audit)

| Metric | Value | Verdict |
|---|---|---|
| Backend pytest | 241 passed, ~6–12s (`workers/api`) | PASS (sqlite-only; proves logic, not D1/concurrency) |
| User Flutter test / analyze | 99 green / 0 issues | PASS |
| Vendor Flutter test / analyze | 40 green / 0 issues | PASS |
| User release APK (arm64) | **26.05 MB** (was 61.4 MB fat pre-028) | PASS-ish; −5 MB available via dep purge |
| Vendor release APK (arm64) | **18.13 MB** | GOOD, no action |
| Admin `npm run build` | **FAILED** — `[UNRESOLVED_IMPORT] ../../../../-components/vendor-states` in `stops/$stopId/index.tsx:9` (fix: `../../../-components/...`) | BLOCKER |
| Debug APKs | 161.5 / 153.6 MB (not shippable) | n/a |

## 3. Architecture — ACTUAL (not intended)

```
user_app ──Bearer──▶ Workers FastAPI (/v1/*) ──services──▶ repos ──▶ D1 (SQLite edge)
vendor_app ─Bearer──▶ Workers (/v1/vendor/*, /complaints/*/verify, /quality/*/vendor-check)
admin BFF (TanStack Start server fns, HttpOnly sh_session) ──cookie-as-Bearer──▶ Workers (/v1/admin/*)
Public: catalog/windows/serviceability/quotes, /auth/*/login|register|refresh, /webhooks/upi
Auth core: get_current_user (hash→session→per-request user re-read) · require_active_user (susp→403) · require_role (wrong-role OR susp→403)
```

## 4. Authorization matrix (derived from handlers)

| Resource | user own | user others | vendor | admin |
|---|---|---|---|---|
| Own profile GET/PATCH | allow (PATCH active-only) | — | own | all |
| Own orders | allow owner (`find_owned`) | 404 no-oracle | ⚠️ CAN CALL as self (any-role gate — P1 F-002) | queue only |
| Vendor routes/stops/earnings/payouts/customers/complaints | n/a | n/a | own only (`r.vendor_id=?` / `_owned_stop` 404) VERIFIED | all |
| Payouts approve, custody confirm, ledger adjust, write-off, config, audit, suspend, zones, codes | deny 403 | deny | deny 403 VERIFIED | allow + audit |
| Users directory / access codes | deny | deny | deny 403 VERIFIED | allow (vendor+admin targets) |
| Devices | own (`user_id+device_id`) | 404 by construction UNVERIFIED test | own | own session |

Cross-vendor reads/writes: CLOSED (404 + owner scope, tested). Holes are missing role gates on self-scoped user endpoints (vendor POST /orders|/returns|/subscriptions|/upi-intent — F-002 P1) and suspended-write bypass (orders/addresses — F-001 P1).

## 5. P0 BLOCKERS (fix before any release)

| ID | Finding | Evidence |
|---|---|---|
| P0-0 | Admin build fails — unresolved vendor-states import | `stops/$stopId/index.tsx:9` → use `../../../-components/vendor-states` |
| P0-1 | Orders strand at `placed`: no accept/pick/pack/dispatch; assign requires unreachable `packed` | `dispatch_service.py:282-284`; zero endpoints; scheduler never transitions |
| P0-2 | Real money impossible: fake UPI default + blank secrets + `rzp_test_*` key + `shodasha@upi` placeholder | `upi.py:174-178`, `wrangler.jsonc:20-27`, `release.yml:69`, `booking_sheet.dart:276` |
| P0-3 | Fake webhook fail-open: unsigned callback mints `paid_upi` (self-fraud, no auth on route) | `upi.py:96-109`, `payments.py:50-54` |
| P0-4 | Dues UPI pay-link can never settle (no intent row; webhook 404s unknown refs) | `payment_service.py:130-131` vs `payment_repo.py:178-179` |
| P0-5 | D1 txns non-atomic (`commit` no-op) + `WRITE_LOCK` no-op across isolates → half-applied money, concurrent double-apply | `db_d1.py:81-85`, `db.py:7-8,25` |
| P0-6 | Suspended users create/cancel/reschedule orders + mutate addresses | `orders.py:63-106`, `addresses.py:63-92` (get_current_user only) |
| P0-7 | Reconciliation board mock-only: aggregate response vs per-route UI (Finance/Dispatch/Operations dead on live) | `admin.py:577-588` vs `finance/index.tsx:105-124` |
| P0-8 | PoD OTP deterministic `sha256(order:date)%1e6`, computable by holder | `vendor_service.py:66-72` + own TODO |
| P0-9 | Vendor `agree → resolved` unilaterally closes disputes it is party to, no countersign/evidence | `vendor_service.py:599-604` |

## 6. P1 CRITICAL (next)

- Vendor web silent refresh always 401s (device `vendor-web` vs refresh `admin-web`) → session dies ~30m after login. (`auth_service.py:516-517`, `vendor-session.ts:30`, `admin-session.ts:95-98`)
- Dashboard shell renders full admin nav on vendor cookie (presence-only guard). (`dashboard/route.tsx:28-39`)
- Admin logout dead (zero callers; dropdown item has no onClick). (`admin-session.ts:114-126`, `account-switcher.tsx:84-87`)
- Custody shape drift (server `{vendor_id,in_hand}` vs UI needs name/phone/on_duty). (`admin.py:591-596`)
- First-page-only pagination everywhere; funnel/counts/search/CVS under-report past page 1.
- Ledger hold badge `held>10` contradicts code constant `HOLD_BLOCK_LIMIT=3`.
- Overpay silently kept (`>=`); partial-cancel refunds full total; refunds unaudited, no maker-checker; day-close sums `stops.triple` JSON not `payments`.
- Release APKs signed with debug keys; 7 unused user deps (~5 MB: forui/shadcn/gmaps/svg/intl/cupertino/pin_code_fields) + vendor pin_code_fields.
- User ApiClient: no retry/single-flight/401-hook; `deviceId 'pending-device'`; hardcoded booking rates (server never called — client can drift on config change).
- Vendor: no refresh wiring (~30m forced logout); PoD offline impossible despite notice; duty-off doesn't repool (copy claims it does); `partial_dues`/`link_sent` render as full Collect (over-collection); new assignments undiscoverable (no push, no poll); duty switch shows route-presence not duty.
- User support WhatsApp is clipboard fake (primary help entry); no Flutter crash reporting; missing DB indexes (stops/routes/audit_log); unbounded `sync.items`; per-isolate rate limits.

## 7. P2–P4 (condensed; full detail in track outputs, session record)

- P2: Operations≈Finance+Dispatch duplication; users table invents Team/workspace/lastActive; vendors list zeros; UTC-vs-IST day flip; dues cap disagreement; 3 status vocabularies; access UI rides legacy door (admin-role codes unissuable); possible raw-phone render (UNVERIFIED); dead POST_NOTIFICATIONS; razorpay keep-or-drop decision; checkout friction (double schedule, 1-useful-step, silent slot fail, client sub totals, tanker dead CTA, FAQ contradictions); support error swallowed by builder bug; trace_id discarded at display; scheduler full scans; vendor failed-stops invisible; sync rejects stuck; wa.me empty-phone; Pull label over-claims; web stop anonymity; observability gaps (no JSON logs, no RUM, payment visibility = Razorpay dashboard).
- P3/P4: chart unit labels, config no-invalidate + paise ambiguity, audit no-export, trust counts, audit keystroke queries, logo size, R8 off, https-assert asymmetry, 400-message passthrough, JSON on UI thread, icon/tree-shaking healthy, skeletons partial, a11y top-10 (tracker semantics, pay-chip focus, calendar locale, focus-on-error, contrast UNVERIFIED), TODO inventory (19 user), doc-only dead comments.

## 8. Contract matrix (field-level highlights)

- Preview: flat `route` (=whole today_route), payout rows `gross_fee` — frontend adapted, exact types preferred over dual-shape tolerance.
- `today_customers` → `{date, customers}` ✓; placed/complaints → `{data:[]}` ✓; dunning bare `{customer_id,dues}` + client ledger join ✓.
- Mock drift: reconciliation + custody fixtures show rows live never returns; mock writes always `{ok:true}` (no 404/409 semantics); issue `expires_at` null vs live 90d default.
- Missing endpoints: `GET /orders/{id}/tracking`, `POST /leads`, lab-report URL, audit export, single-vendor `quality` list for vendor web (manual id input = crutch).
- `detail.rider` always null; `capacity_left` always null; `restrict` ≡ `suspend` in effect; suspended pay-dues path 403s while copy says pay-or-appeal.

## 9. KPI verdicts

Real and verified: GMV/orders/deposits/dues series, on-time %, payment splits, money totals, dunning (top-200 capped — card vs table can disagree), leaderboards vendor-load (BROKEN live: missing name/on_duty → NaN sort), reconciliation (BROKEN live), trust badge, user detail aggregates, vendor jama/baaki/hold (honest display-only). Beautiful-but-wrong: users Team/workspace/lastActive, vendors onDuty/inHand zeros, Analytics "Customers —", fulfilment ignores in-flight, GMV chart ₹'00 vs card ₹, UTC-day flip at 05:30 IST.

## 10. Sync verdicts

Triple/cash/verify: counterparty learns via poll (user tracking ≤60s, admin ≤15s) VERIFIED. Broken: user own-orders list after checkout (manual only), user ledger (once-per-shell-init, never post-mutation), user complaint list (no refresh trigger), admin operations/config mutations (no invalidation), vendor new-assignment discovery (no push, no poll — manual pull only).

## 11. Dependency graph of fixes (order)

```
authorization (suspend gates, role gates, httpOnly, logout, guards)
  → order state machine (accept/pick/pack/dispatch endpoints)
    → payment (fail-closed webhook, dues intent link, overpay/refund guards, day-close source)
      → vendor order flow (PoD OTP random, verify authority, states UI, refresh wiring, duty repool, notifications)
        → customer ordering (catalog live, support launch, states, tracker)
          → admin analytics truth (reconciliation/custody shapes, pagination, UTC→IST, export)
            → backend perf (indexes, sync cap, D1 atomicity strategy, scheduler bounds, D1 rate counters)
              → flutter lightness (dep purge, signing, R8, retry parity)
                → UX polish + animations (last)
```

## 12. Remediation phases (§40 adapted)

- Phase 0 Safety: branch per workstream, baselines recorded above (this report), P0-0 build fix first (unblocks everything admin).
- Phase 1 Security: F-001/F-002 gates, httpOnly, logout wiring, role-aware guards, webhook fail-closed, PoD OTP random + attempt cap, verify authority downgrade, codes admin-door UI.
- Phase 2 Core business: dispatch mid-pipeline endpoints + vendor accept UI, reschedule idempotency, cod-confirm caller or removal, refund audit+maker-checker, overpay/partial-refund guards, day-close from payments.
- Phase 3 Contracts: tracking endpoint, rider population, leads endpoint, audit export, failed-stop list, quality list for vendor, window/product/instructions on stops, exact types (drop dual-shape).
- Phase 4 Flutter lightness+reliability: dep purge, debug-key signing, R8, retry/single-flight/401 parity, real device id, catalog live, support launch, logo.
- Phase 5 Vendor ops: refresh wiring (or honest re-login), duty repool wiring, PoD offline or honest notice, partial/link_sent UI, failed section, assignment discovery (poll interval or push plan).
- Phase 6 Admin truth: reconciliation/custody shape alignment, cursor pagination, UTC→IST, dues-cap label, invented-field removal, config invalidate, CSV scope labels.
- Phase 7 Customer UX: checkout friction (schedule once, slot-failure loudly, sub server-quote), confirm/track completeness, Hindi/FAQ consistency, a11y top-10.
- Phase 8 Perf: indexes migration, sync cap, scheduler bounds, D1 atomicity strategy (batch API or saga), D1 rate counters, cache headers for static reads.
- Phase 9 Polish: animations only where state-communicating (skeletons, status transitions), dep-graph order respected.
- Phase 10 Verify: pytest + flutter + build + release APK re-measure + security re-sweep + this report's verification matrix filled.

## 13. Verification matrix (fill during remediation)

| Area | Before | After | Evidence | Status |
|---|---|---|---|---|
| Admin build | FAILED (vendor-states import) | GREEN (vite 3675 modules 1.55s + SSR + nitro, 0 unresolved) | Phase 0 build output, commit 97c6971 | FIXED |
| APK user/vendor | 26.05 / 18.13 MB arm64 | | | OPEN |
| Order placed→delivered | strands at placed | | | OPEN |
| UPI real money | impossible | fail-closed in prod (fake refused 502); dues-pay settles end-to-end; real needs owner secrets | Split 2 + Phase 2B: upi.py guards + dues-intent → webhook → cleared (test_phase02_splitb) | PARTIAL (code done, secrets owed) |
| Webhook forgery | self-fraud possible | unsigned/dev-fake callbacks fail closed, zero ledger writes | Split 2: FakeUpiProvider guards + test no-write | FIXED |
| D1 atomicity | torn writes possible | | | OPEN |
| Suspended writes | bypass | 403 + zero rows on 10 write routes, reads stay 200 | Split 1: dep swaps + test_phase01_authz (5) | FIXED |
| PoD OTP | computable | random per-stop (015) + 5-fail lockout + wrong→404 no-oracle | Split 2: vendor_service/dispatch + test_phase01_split2 (6) | FIXED |
| Vendor resolve | unilateral | agree→vendor_confirmed + note≥10; only admin resolves | Split 2: verify_complaint + admin release test | FIXED |
| Reconciliation live | empty | per-route rows + custody identity join live; screens still map old shapes | Split A: recon/custody rework + tests (UI remap owed in Split B) | PARTIAL |
| Vendor session | ~30m death | refresh pinned to vendor-web device (BFF + guard) | Split 1 W1b (build verify owed by owner) | FIXED* |
| Tests | 241 + 99 + 40 green | 256 pytest (+5 authz +10 split2) + 99 + 40 green | pytest 256 green | BASELINED+ |

## 14. UNVERIFIED list (needs device/prod to close)

On-device jank/cold-start/battery/GPS; exact SDK ints; country_flags parent chain; Play review; multi-isolate rate drift; D1 torn-write demonstration; cross-user device scoping test; subs screen state parity; zoom fields; contrast ratios; calendar Hindi; sub launchUrl path; yesterday-Δ edge; raw-phone render in users-columns; window semantics vs 30-min copy; CVE scan of deps.

## 15. Dead code ledger (SAFE TO DELETE / NEEDS VERIFICATION / KEEP)

See Track F §6: delete stale url_launcher comment; verify-then-remove pin_code_fields (both), searchCatalog, Hardcoded vs Caching catalog (keep one as offline fallback), StubOrdersRepository (tests still use); keep SMS seam/OTP/demo endpoints (until 029), InMemorySessionStore (tests), 027 legacy access table (until 027 merges).
