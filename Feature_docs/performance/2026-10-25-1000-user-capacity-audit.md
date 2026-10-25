# Shodasha at 1,000 users — capacity audit, bottlenecks, and benchmark plan

**Date:** 2026-10-25  
**Status:** Read-only audit. No application code, migration, infrastructure, or production data changed.  
**Branch:** `035-premium-ui-states-release` (local only; not pushed)  
**Production baseline:** Worker `water` (`https://water.adityathakur452007.workers.dev`), D1 `shodasha`, 9 users, cron `*/15 * * * *`.  
**Scope:** customer Flutter app (`apps/user_app_donor`), FastAPI-on-Workers backend (`workers/api`), D1, caching/edge, vendor/admin surfaces, observability.  
**Approval gate:** Implementation, migrations, staging deployment, and load tests require explicit owner approval. This document only proposes them.

---

## 1. Method and constraints

### 1.1 What was done

- Read the project protocol (`AGENTS.md`, `Agent.md`, `SKILLS.md`) and the living context (`context/progress-tracker.md`, `flow.md`, `decision.md`, `architecture.md`).
- Loaded the six skills named for this task and read each `SKILL.md`:
  - `web-perf`
  - `workers-best-practices`
  - `workers-profiling`
  - `wrangler`
  - `cloudflare`
  - `mobile-native`
- Confirmed there is no Flutter-, FastAPI-, or SQLite-specific skill in `SKILLS.md`; `performance_engineering` contains only `README.md` and reference docs, with no `SKILL.md`. Those areas were audited from source and primary documentation instead.
- Traced the real production request path: Cloudflare Worker → Python/Pyodide (`src/entry.py`) → FastAPI app (`src/app/main.py`) → D1 (`src/app/db_d1.py`). Local tests use `AsyncSqliteConn` over stdlib SQLite, so local timing is not production timing.
- Read the backend routers, services, repositories, scheduler, middleware, caching, and `wrangler.jsonc`.
- Read the customer Flutter composition root, transport, shell, orders controller/screens, tracking, addresses, and `pubspec.yaml`.
- Inventoried migrations `002`–`028` and every `CREATE INDEX`.
- Fetched and checked primary documentation for Workers, D1, cron, caching, Python Workers, and Flutter rendering.

### 1.2 Production safety

- No load test, write, migration, deployment, or configuration change was made against production.
- No secret was read, printed, or committed.
- No real money moved.
- Production remains at 9 users; the audit is based on source, local fixtures, and official limits, not production load.

### 1.3 Evidence labels

- **Verified**: read directly in source or official documentation.
- **Estimated**: derived from the load model; explicitly labeled.
- **Unverified**: depends on runtime measurement or remote state that was not inspected.

---

## 2. Runtime map

```
Flutter customer app (apps/user_app_donor)
  main.dart
    └─ loadOrCreateDeviceId()                  [blocks first frame]
    └─ ApiClient (Bearer + X-Device-Id)        [single-flight GET, 45s public TTL]
    └─ AuthGate → DonorShell (5 tabs, lazy mount)
         ├─ Home        → catalog + windows + quote
         ├─ Orders      → GET /orders (cursor), GET /orders/{id} (poll 60s→300s)
         ├─ Plans       → GET /subscriptions, pause/resume/skip/cancel
         ├─ Wallet      → GET /ledger/me, GET /billing/dues, returns
         └─ Profile     → GET/PATCH /auth/me, addresses, support

Cloudflare Worker `water` (workers.dev, no custom route)
  src/entry.py
    └─ FastAPI app (src/app/main.py)
         ├─ middleware.py       CORS, body cap, IP throttle (per-isolate dict)
         ├─ api/v1/*.py         auth, catalog, quotes, orders, payments,
         │                      subscriptions, addresses, complaints, admin, vendor
         ├─ services/*.py       order, payment, subscription, dispatch, vendor
         ├─ repositories/*.py   order, payment, ledger, address, admin_read
         └─ jobs/scheduler.py   cron */15: due subscriptions, retention purge
  D1 binding DB → `shodasha`
    └─ one database, single writer, every statement auto-commits
    └─ `D1Conn.commit()` / `rollback()` are no-ops (db_d1.py:111-115)
```

**Critical runtime facts**

| Fact | Evidence |
|---|---|
| Production is Python on Pyodide, not CPython/FastAPI on a VM | `workers/api/wrangler.jsonc:6-9`, `src/entry.py` |
| D1 auto-commits each statement; `commit()`/`rollback()` are no-ops | `workers/api/src/app/db_d1.py:111-115` |
| `WRITE_LOCK` is a no-op on Workers/prod | `workers/api/src/app/db.py:38-39,61` |
| Cron runs every 15 minutes | `workers/api/wrangler.jsonc:37` |
| Logs enabled; traces and issue detection disabled | `workers/api/wrangler.jsonc:39-53` |
| No `routes`, so the Worker runs on `workers.dev` | `workers/api/wrangler.jsonc` (no routes block) |
| Client public-read TTL is 45s; server says 300s | `apps/user_app_donor/lib/core/api_client.dart:127-129`, `workers/api/src/app/api/caching.py:18,36-37` |
| Tracking polls 60s base, backoff to 300s | `apps/user_app_donor/lib/features/orders/orders_controller.dart:819-821,1231-1241` |

---

## 3. Load model: what “1,000 users” can mean

The phrase is ambiguous and changes the answer. Three scenarios are modeled until the owner confirms one.

### 3.1 Fixed assumptions

| Parameter | Value | Basis |
|---|---|---|
| API requests per active session | 20 | Typical 6-minute customer session: catalog, windows, quote, order, detail polls, ledger, subscriptions |
| Session length / think time | 360s | 6 minutes |
| Peak burst multiplier | 2.5× average | Morning/evening delivery windows; conservative |
| D1 statements per request | 4 average | Mix of D1-free catalog/windows and 7–12-query order/payment paths |
| Write-request share | 20% | Creates, cancels, reschedules, payments, subscriptions |
| Rows written per write request | 1.5 | Order + event + ledger/payment rows |
| Read/write ratio | 80/20 | Customer app is read-heavy |
| Peak concurrency | 5% / 10% / 100% | Scenario A / B / C |

### 3.2 Little's Law

For `C` concurrent users and 20 requests per 360s:

```
per-user rate = 20 / 360 = 0.05556 rps
average rps  = C × 0.05556
peak rps     = average rps × 2.5
D1 qps       = rps × 4
row writes/s = rps × 0.20 × 1.5 = rps × 0.30
```

| Scenario | Meaning | Concurrent `C` | Avg rps | Peak rps | D1 qps (avg / peak) | Row writes/s (avg / peak) | Requests/day |
|---|---|---:|---:|---:|---:|---:|---:|
| **A** | 1,000 registered, ~5% concurrent at peak | 50 | 2.78 | 6.94 | 11.1 / 27.8 | 0.83 / 2.08 | ~20,000 if all 1,000 active; ~1,000 at 5% |
| **B** | 1,000 daily active, ~10% concurrent at peak | 100 | 5.56 | 13.89 | 22.2 / 55.6 | 1.67 / 4.17 | 20,000 |
| **C** | 1,000 truly concurrent | 1,000 | 55.56 | 138.89 | 222.2 / 555.6 | 16.67 / 41.67 | up to 4.8M if sustained |

**Sensitivity:** the 4-statements/request assumption is optimistic for expensive paths. At 10 statements/request, C becomes 556 qps average / 1,389 peak; A and B become 27.8/69.4 and 55.6/138.9 qps. The verdict for C does not change; the margin for B narrows.

### 3.3 Request mix used for the model

| Class | Share | Examples | D1 statements (typical) |
|---|---:|---|---:|
| Public catalog/windows | 15% | `GET /catalog`, `GET /windows` | 0 |
| Authed reads | 55% | orders list/detail, subscriptions, ledger, dues | 2–9 |
| Writes | 20% | create/cancel/reschedule, payment intent, subscription action | 6–14 |
| Auth/session | 5% | login, refresh, me | 2–8 |
| Admin/vendor | 5% | route, earnings, dashboard | 5–82 |

The model uses 4 as a blended average. The tail is much heavier; that is why P95/P99, not average, decides the verdict.

---

## 4. Proposed SLOs (to be validated, not current measurements)

| Surface | Metric | Target | Why |
|---|---|---|---|
| Public reads | p50 / p95 / p99 | 80 / 250 / 600 ms | No D1; should be edge-fast |
| Authed reads | p50 / p95 / p99 | 150 / 500 / 1,200 ms | 2–9 D1 queries after fixes |
| Writes | p50 / p95 / p99 | 300 / 900 / 2,000 ms | Multi-statement money paths |
| Login | p50 / p95 / p99 | 400 / 1,000 / 2,000 ms | PBKDF2 100k dominates |
| 5xx rate | monthly | < 0.5% | Customer trust |
| Non-auth 4xx | monthly | < 2% | Validation/UX quality |
| Worker CPU | p95 / p99 per request | 50 / 150 ms | Cost and headroom |
| D1 queries | p95 / p99 per request | 10 / 25 | Prevents N+1 regressions |
| D1 rows read | p95 / p99 per request | 200 / 1,000 | Scan detection |
| D1 rows written | p95 / p99 per request | 5 / 20 | Write amplification |
| Cron | statements / CPU / missed due subs | < 1,000 / < 30s / 0 | Paid invocation cap and delivery correctness |
| Flutter cold start | p95 on mid-range Android | ≤ 2.5s | First impression |
| Flutter frames | janky frames, build/raster p95 | < 5%, ≤ 8 ms each | 60Hz budget |
| Availability | monthly | 99.9% | Proposed; owner must confirm |

These are proposals. The current system has no SLO instrumentation, so none of them can be certified today.

---

## 5. Evidence-based findings

Severity: **P0** = money/data correctness or release-blocking; **P1** = capacity/latency/security before 1,000 users; **P2** = client polish/observability.  
“Gain” and “Impact” are estimates unless marked verified. Confidence is about the finding, not the gain.

### 5.1 P0 — correctness and money

| ID | Finding | Evidence | Impact at 1,000 users | Fix | Expected gain | Conf. | Risk |
|---|---|---|---|---|---|---|---|
| P0-1 | Cancel settlement is 10+ sequential statements with no transaction; D1 `commit()`/`rollback()` are no-ops. A mid-way failure leaves a cancelled order without refund/ledger rows; retry returns `AlreadyCancelled` and cannot repair it. | `order_repo.py:456-547`; `db_d1.py:111-115`; `db.py:38-39` | Every cancellation at scale can lose money or leave the ledger inconsistent; support cannot replay. | Single `conn.batch([...])` (D1 batch is transactional) or a `cancel_pending` state + idempotent compensation + reconciliation job. | Eliminates the partial-cancel class; 100% of cancels atomic (est.). | High | Batch parameter limits; must preserve late-capture/refund semantics. |
| P0-2 | Webhook settlement has no compare-and-set: it reads `payments.status`, then updates unconditionally. Two concurrent/retried webhooks can both clear dues or double-credit. | `payment_repo.py:375-442` | Duplicate provider callbacks are normal at scale; double-cleared dues and double credits create real money loss. | `UPDATE payments SET status='paid' WHERE id=? AND status!='paid'` + rowcount check; put order/ledger updates in the same batch; unique ledger ref. | Idempotent webhook; one credit per provider_ref (est.). | High | Must keep the “late capture on cancelled order → refund” branch. |
| P0-3 | Dues settlement is check-then-act, loops all open orders, and runs a paid-sum query per order. | `payment_repo.py:444-518` | Overshoot under concurrent dues payments; P99 grows with order history. | CAS on intent status + one aggregate paid-sum query + batch. | Fewer queries, no double settle (est. 2–5× on this path). | High | Over-capture/refund path must stay exact. |
| P0-4 | Order transition is read-modify-write with an unconditional `UPDATE`; no state guard. | `order_repo.py:323-357` | Concurrent PoD/vendor/admin actions can lose updates and write duplicate events. | `UPDATE orders SET state=? WHERE id=? AND state=?`; check rowcount; unique event guard. | Prevents lost updates and duplicate events (est.). | High | Legal-transition matrix must be preserved. |
| P0-5 | Subscription cancel zeroes `credit_balance_paise` before writing refund/credit rows. | `subscription_service.py:658-710` (zero at 681) | A later failure loses prepaid credit; customer is owed money with no row. | Batch the whole cancel; write credit/refund rows first, zero the balance last; idempotency key. | Atomic cancel; no lost credit (est.). | High | Prepaid/postpaid branches differ; test both. |
| P0-6 | `switch_to_cod` races a live capture: it checks payment state, then converts, without a guard. | `payment_repo.py:326-371` | COD and captured UPI can both be recorded for one order. | CAS on order/payment status in one batch; refuse if any capture appears. | One payment mode per order (est.). | Medium-high | Race window is narrow but real; needs a concurrency test. |
| P0-7 | Delivery-code reissue “3 per 24h” guard relies on `WRITE_LOCK`, which is a no-op on Workers. Count-then-insert is bypassable. | `db.py:38-39,61`; `order_service.py:415-458` | Unlimited code mints; abuse/support load; security promise broken. | D1 atomic counter/rate row or Durable Object; unique index on `(order_id, window)`. | Enforces 3/24h under concurrency (est.). | High | Adds a write to every reissue; DO is a new dependency. |
| P0-8 | Cron advances `next_run` while generating descriptors, before the scheduler creates the order. If creation fails, the delivery is skipped permanently. | `subscription_service.py:885-894`; `scheduler.py:119-138` | At 1,000 users, any transient D1/order error silently loses a paid delivery. Cron invocation still “succeeds”, so Cloudflare retry does not help. | Create order and advance `next_run` in one batch; or claim with a `next_run` CAS and advance only after success; add a dead-letter/retry table. | Zero silent missed deliveries (est.). | High | Must preserve idempotency key `sub:<id>:<date>`. |
| P0-9 | Cron processes every due subscription in one invocation, sequentially. Paid cap is 1,000 D1 queries/invocation; each sub costs ~10–14. Free cap is 50. | `scheduler.py:119-143`; `subscription_service.py:827-899` | ~70–100 due subs approach/exceed the Paid cap; ~4–5 exceed Free. A morning cluster at 1,000 registered users will hit this. | Cursor + max N subs per tick (e.g., 20–30), every-minute cron, and a backlog metric. | Bounded invocation; no cap failures (est.). | High | Deliveries may be delayed by one tick; choose interval with product. |
| P0-10 | Retention purge chunks use `_PURGE_CHUNK = 500`, above D1’s 100-bound-parameter limit. | `scheduler.py:51,223-224,270-271` | Purge fails once tables exceed 500 rows; retention breaks silently. | Set chunk to 90 (or build multi-row statements under 100 params). | Purge works at scale (verified by limit math). | High | Slower purge; run more often. |
| P0-11 | Missing indexes for hot filters: `ledger_events(ref_type, ref_id)`, `audit_log(created_at)`, `idempotency_keys(created_at)`, `rate_counters(window_start)`, `subscriptions(status, next_run)`, `orders(address_id, state)`. | Migrations `002`–`028`; query sites in ledger/audit/order/subscription repos | Scans grow linearly; N+1 paths get slower exactly when volume rises. | Migration `029` with the six indexes; verify with `EXPLAIN QUERY PLAN`. | Est. 10–100× on affected scans, depending on table size. | Medium-high | Write cost/storage; confirm each index is used. |

### 5.2 P1 — capacity, latency, security

| ID | Finding | Evidence | Impact at 1,000 users | Fix | Expected gain | Conf. | Risk |
|---|---|---|---|---|---|---|---|
| P1-1 | Order detail runs 7 sequential queries and a `PRAGMA table_info('stops')` per call. | `order_service.py:329-391`; `order_repo.py:164,439` | Tracking polls amplify this; at C, ~117 qps just for detail reads. P95 suffers. | Join/batch the detail reads; cache the stops schema per isolate; drop the per-call PRAGMA. | Est. 3–5× fewer round trips; 40–60% lower p95. | Medium | Snapshot/legacy columns must stay compatible. |
| P1-2 | `_ensure_billing_mode` runs a PRAGMA on every subscription read/write. | `subscription_service.py:109-136,257,309,316,836` | One extra query per subscription call; list endpoints multiply it. | Cache the schema flag after first check (schema is migration-static) or gate on migration version. | 1–2 queries saved per call. | High | Must invalidate if a migration adds the column at runtime. |
| P1-3 | `/billing/dues` is N+1: one paid-sum query per open order, plus `_dues_posted` per order. | `payment_service.py:211-231` | Wallet/dues is a frequent read; grows with order history. | One aggregate query for paid sums and dues-posted flags; join. | Est. 3–10× fewer queries for users with many orders. | High | Must preserve COD double-count rule. |
| P1-4 | Vendor route is ~82 queries for 40 stops: two PRAGMAs, per-stop ledger, per-stop paid-sum. | `vendor_service.py:302-366` | Vendor app polls every 60s; 20 vendors ≈ 27 qps of expensive reads. | Batch ledger and paid sums by customer/order; cache schema. | Est. 10–20× fewer queries. | High | Route response must stay byte-compatible. |
| P1-5 | Admin metrics/overview run multiple full-table aggregates; sidebar polls every 60s. | `admin.py:1229-1243,1259+`; `admin_read_repo.py:50-115` | Full scans on every admin session, growing with 1,000 users. | Daily rollup table or 5-minute cache; compute on write/event. | Est. 10–100× on dashboard reads. | Medium | Rollup freshness; backfill job. |
| P1-6 | Login does 6 D1 statements before user lookup and limits 20 attempts/IP/hour using `request.client.host`. | `auth_service.py:42-43,221-251,577-578`; `middleware.py:91` | Shared NAT/CGNAT blocks legitimate users with 429; login burst adds D1 load. | Use `CF-Connecting-IP`; raise/scope the IP limit; combine rate checks into one batch; keep per-phone limit. | Est. 60% fewer D1 calls/login; fewer false 429s. | High | Weaker IP limit could increase credential stuffing; pair with device/phone limits. |
| P1-7 | IP throttle is a per-isolate unbounded dict; no global coordination. | `middleware.py:24,95-102` | Memory growth per isolate (128MB cap); limits are inconsistent across isolates. | Bounded TTL/LRU; D1/DO for auth-critical limits. | Stable memory; consistent limits. | High | D1/DO adds latency to every throttled request; scope to auth only. |
| P1-8 | Client caches public reads for 45s while server says 300s; 429 is retried 3×; stale fallback waits through ~37.5s of retries. | `api_client.dart:127-129,263-293,295-299,355-363`; `caching.py:18,36-37` | Up to 6.7× avoidable public reads; retries worsen overload; stale UI takes too long. | Align TTL to 300s or revalidate with ETag; do not retry 429 for GETs; serve stale immediately on transport failure. | Est. 50–80% fewer catalog/windows calls; faster stale UI. | Medium-high | Stale prices longer; catalog changes rarely. |
| P1-9 | `cached()` emits `public` + `CDN-Cache-Control` even for auth-gated admin config/zones. | `caching.py:36-37`; `admin.py:601,1152` | Latent auth-data leak if a Cache Rule is ever added; currently inert on workers.dev. | Use `private, no-store` for admin; split the helper. | Removes the latent leak. | High | None; admin caching is not needed. |
| P1-10 | `/windows?date=` accepts any date, so cache cardinality is unbounded. | `catalog.py:60-72` | Wasted Worker invocations and client cache entries; abuse vector. | Accept only today..+30 days; reject/normalize others. | Bounded cardinality. | High | Product may want a wider booking horizon. |
| P1-11 | No traces, no SLOs, no D1 query metrics, no staging/canary; `/health` is static. | `wrangler.jsonc:46-53`; repo has no staging config | Capacity cannot be certified; failures are discovered by users. | Enable traces/issue detection in staging, structured logs (route, status, duration, D1 queries/rows), SLO dashboards, staging Worker + D1. | Makes the rest measurable. | High | Log volume/cost; redact PII. |
| P1-12 | Vendor sync flushes a sequential 200-item loop. | `vendor_service.py:766-792`; `vendor.py:70-74` | Long requests and 1,000-query cap risk during backlog sync. | Batch in chunks of 20–50; return per-item results. | Est. 5–10× faster sync. | Medium | Partial-failure reporting must stay per-item. |
| P1-13 | Admin order search has no debounce and uses `phone LIKE '%q%'`; several lists are unbounded. | admin orders/search UI + `admin.py`; `admin_read_repo.py` | Full scans per keystroke; worse as orders grow. | Debounce, prefix/FTS5 search, cursor paging. | Est. 10× fewer search queries. | Medium | FTS5 migration/backfill. |
| P1-14 | Tracking can orphan a 60s poll loop: `startTracking()` runs after `await refreshOrder()` with no `mounted` check; `dispose()` only cancels an already-armed timer. | `tracking_screen.dart:95-103,196`; `orders_controller.dart:1205-1240` | Fast back during a slow refresh leaves a GET loop running after the screen is gone; at 1,000 users this is avoidable battery/D1 load. | `if (!mounted) return;` before `startTracking`, or arm before the await and cancel in `dispose`. | Removes orphan polls (est. 50/min at 5% of 1,000). | High | Low. |

### 5.3 P2 — client and operational polish

| ID | Finding | Evidence | Impact at 1,000 users | Fix | Expected gain | Conf. | Risk |
|---|---|---|---|---|---|---|---|
| P2-1 | Orders list uses `ListView(children: ...)` and maps every order into children; no virtualization. | `my_orders_screen.dart:121-194` | Long histories build all cards; jank on low-end Android. | `CustomScrollView` + `SliverList.builder`; keep sections. | Smoother scroll; lower build time. | High | Section headers/empty states need restructuring. |
| P2-2 | First frame is blocked on `loadOrCreateDeviceId()`; no global error handlers or crash/analytics SDK. | `main.dart:26-29,58-82`; `pubspec.yaml:10-24` | Blank/spinner on slow storage; crashes are invisible. | Render immediately, initialize async; add Sentry/Crashlytics + `FlutterError.onError`/`PlatformDispatcher.onError`. | Faster first paint; crash visibility. | High | SDK size/privacy; choose one. |
| P2-3 | Tracking polls every 60s per open screen (backoff to 300s); code-expiry timer ticks every 30s. | `orders_controller.dart:819-821,1231-1241`; `tracking_screen.dart:127` | At C, ~16.7 detail polls/s × 7 queries; battery and D1 load. | Push/SSE, or poll only when dispatched/assigned; keep backoff. | Est. 50%+ fewer tracking reads. | Medium | Push infrastructure (FCM send is deferred today). |
| P2-4 | Public read cache survives logout and has no entry cap. | `api_client.dart:129,148`; `main.dart:91` | Stale prices across accounts; memory growth over long sessions. | Clear `_readCache` at auth boundary; cap entries/LRU. | No cross-account stale reads. | High | None. |
| P2-5 | Body-cap middleware buffers the whole body before rejecting; CORS has no `max_age`. | `middleware.py:61-68,111-120` | Small DoS surface; extra preflight requests. | Check `Content-Length` first; set `max_age=600`. | Less memory/requests. | High | None. |
| P2-6 | Vendor route and admin sidebar poll every 60s regardless of visibility. | `route_controller.dart:246`; admin shell | Constant background load from idle tabs. | Pause when hidden; 2–5 min cadence; ETag/304. | Est. 50–80% fewer background reads. | High | Freshness expectations. |
| P2-7 | FCM token registration exists but server send is deferred; polling is the substitute. | `api_client.dart:829-845`; `015` note in `flow.md` | Every status change costs a poll; battery and load. | Implement FCM send for order/dispatch updates. | Large reduction in polling. | Medium | Firebase setup/ops. |

### 5.4 Flutter deep-dive (static audit; app/tests not run)

The customer-app audit found **no P0 crash/data-loss defect**; it counted **6 P1, 9 P2, 6 P3**. The highest-value client findings not already in the tables above:

| ID | Finding | Evidence | Impact at 1,000 users | Fix | Expected gain | Conf. | Risk |
|---|---|---|---|---|---|---|---|
| F-1 | Splash waits on an unbounded device-ID load and then a 20s session restore; a device-ID throw leaves a permanent spinner. | `main.dart:59,81,116-120`; `auth_controller.dart:266,653-661`; `auth_gate.dart:43-59,87` | Slow Keystore users see 5–20s of splash; a storage error is a dead app. | Render the branded splash immediately; parallelize secure reads; timeout + retry/error UI; keep the stored session on timeout. | Est. 1–20s faster cold start; fewer forced logins. | High | Must not weaken session security. |
| F-2 | Login hero decodes a 1200×686 asset without `cacheWidth`. | `login_screen.dart:515-518` | ≈3.1MiB RGBA per login; memory spike on low-end devices. | `cacheWidth: 360` or resize the asset. | Est. ~3MiB less peak memory. | High | Low. |
| F-3 | Map picker calls `setState` on every pan/zoom frame. | `map_picker.dart:185-189` | Dropped frames while placing a pin; whole subtree rebuilds. | Throttle to gesture end or use a `ValueNotifier`. | Smoother pan/zoom. | High | Low. |
| F-4 | `IndexedStack` rebuilds every mounted tab on shell `setState`; profile wraps the whole screen in an orders listener. | `donor_shell.dart:406-412,142-146,446-452` | Every tab switch/offline banner rebuilds up to 5 subtrees; profile rebuilds on every orders notify. | Cache built tab bodies; narrow the profile listener to the order count. | Est. 20–40% less shell rebuild cost. | Medium-high | Medium; keep-alive semantics. |
| F-5 | Wallet re-tap triggers ledger + payments; checkout refreshes ledger twice. | `donor_shell.dart:141-145,248,268`; `donor_wallet_screen.dart:57-61,70-72`; `api_client.dart:532-533` | Extra GETs per wallet tap and per checkout; pure waste at scale. | Skip if fresh (<30s) or pull-to-refresh only; one refresh after payment. | Est. 1–2 requests saved per interaction. | High | Low. |
| F-6 | Complaints are a `for` loop inside `ListView(children:)`; server cap is unverified (ADR-126 says uncapped). | `support_screen.dart:233-267,621`; `context/flow.md` ADR-126 | Heavy support users build every card eagerly. | Paginate + `ListView.builder`/sliver; confirm server cap. | Bounded build/memory. | High (client) | Server behavior unverified. |
| F-7 | Release APK is 38.4MB and ships `arm64-v8a` + `armeabi-v7a`; no ABI splits/app bundle. | `android/app/build.gradle.kts:56-66`; release artifact | Every install/update downloads both ABIs. | Enable ABI splits or ship an AAB. | Est. 30–40% smaller per-device download. | High | Low. |
| F-8 | `saveSession` awaits four separate secure-storage writes. | `session_store.dart:32-35` | Every login pays 4 sequential Keystore round trips (~40–200ms). | Store one JSON blob under one key. | Faster login save. | High | Low; migration for old keys. |
| F-9 | Catalog/orders are memory-only; no disk hydration. | `api_client.dart:127-134`; `orders_controller.dart:790` | Offline cold start shows error/empty until reconnect. | Persist last successful catalog/orders with timestamp; hydrate + stale banner. | Usable offline cold start. | High | Medium; stale data must be labeled. |
| F-10 | Any `TimeoutException` marks the global `offline` flag, so a slow-but-alive server looks offline. | `api_client.dart:394-400` | False offline banners; users may stop retrying. | Distinguish timeout from socket failure; add a “slow server” state. | Fewer false offline banners. | Medium | Low. |

The Flutter measurement plan (physical Android, profile/release): `flutter run --profile` + DevTools CPU/memory; `am start -W` ×10 cold starts; timeline for tab switch, orders scroll, map pan, 5-minute tracking; 3G/airplane-mode cold start; `flutter build apk --analyze-size` for ABI splits. No production API calls or load tests.

---

## 6. Capacity verdict per scenario

### A — 1,000 registered, ~50 concurrent at peak

**Throughput:** feasible on Workers Paid. 2.8 rps average / 6.9 peak; ~28 D1 qps peak; ~2.1 row writes/s peak. This is far below D1’s single-writer ceiling.

**What breaks first:** correctness, not throughput. Cancel/webhook/transition races (P0-1..P0-6) are unacceptable at any scale. Cron can also break: if ~8–10% of 1,000 registered users are on a daily plan (~80–100 due), the 10–14 statements/sub approach or exceed the 1,000-query Paid cap in one 15-minute tick. Free is not viable: 10ms CPU cannot run PBKDF2 100k login, and the 50-query cron cap fails at ~4–5 subs.

**Verdict:** **Conditional GO** after P0 fixes + cron paging + indexes. No architecture change needed. Do not launch on Free.

### B — 1,000 DAU, ~100 concurrent at peak

**Throughput:** feasible after P0/P1 fixes. 5.6 rps average / 13.9 peak; ~56 D1 qps peak; ~4.2 row writes/s peak; ~20k requests/day. D1 is not the wall; expensive N+1 endpoints, cron, login throttling, and write serialization are.

**What breaks first:** the 15-minute cron (same math as A), vendor route/admin aggregates if those surfaces grow, and false 429s behind CGNAT. Free plan also exceeds the 100k rows-written/day allowance at this write rate (~144k/day average), so Paid is required.

**Verdict:** **GO only after** P0 + cron paging + N+1 fixes + login/throttle fixes + indexes. Architecture unchanged. Target p95 reads ≤500ms after fixes; measure before promising.

### C — 1,000 truly concurrent

**Throughput:** not certifiable. 55.6 rps average / 139 peak; 222 D1 qps average / 556 peak at 4 statements/request, and 556/1,389 at a realistic 10. The single-writer database, 8–14-statement writes, 7–9-query reads, and 10–14-statement cron all collide at this level. A 1,000-subscription morning tick would need 10k–14k statements, 10–14× the per-invocation cap.

**What breaks first:** D1 write serialization and queueing (P99), then the cron cap, then Worker cost/CPU. Caching public reads does not help the authed/write paths that dominate.

**Verdict:** **NO-GO** without architecture changes: transactional batches, async write queue/Durable Objects, read models/caching for authed reads, cursor-based cron, and likely sharding or a non-D1 read store. This is a multi-week design, not a tuning pass. If C is a real requirement, approve a separate architecture phase; if it is a stress target, use it only to find the knee.

### Bottom line

- **A and B are throughput-feasible** on Paid, but **not safe to scale** until the P0 money/cron defects are fixed.
- **C is not feasible** on the current single-D1, per-request-query architecture.
- The first 1,000-user bottleneck is **not raw D1 throughput**; it is **write-path correctness, cron invocation caps, and N+1 reads**.

---

## 7. Prioritized plan

Effort is rough and assumes one engineer familiar with the repo. All phases require approval; none are started.

### Phase 0 — Measure safely (1–2 days)

1. Create a staging Worker (`water-staging`) and D1 (`shodasha-staging`) with synthetic data; never point load tests at production.
2. Enable traces/issue detection in staging; add structured request logs: route, status, duration, D1 query count, rows read/written, cron outcome.
3. Add a real `/health` that checks D1; keep it cheap.
4. Seed: 1,000 users, 1,000 subscriptions (60% per-delivery, 20% prepaid, 20% postpaid), 10,000 orders over 90 days, 20 vendors, 40 stops/vendor, ledger/payment/audit rows.
5. Run a 1-VU smoke over every route and capture the baseline table.

**Exit:** baseline p50/p95/p99 and D1 queries/request for every route; no production impact.

### Phase 1 — P0 correctness (3–5 days)

1. Convert cancel settlement, webhook settlement, dues settlement, transition, subscription cancel, and switch-to-cod to D1 `batch()` transactions with CAS guards.
2. Fix reissue rate limiting with an atomic counter/DO.
3. Fix cron ordering: create order + advance `next_run` atomically; add cursor/max-N per tick; set purge chunk to 90.
4. Add migration `029` with the six indexes.
5. Add concurrency tests: parallel cancels, duplicate webhooks, parallel transitions, parallel reissues, cron with induced order-creation failure.

**Exit:** all P0 concurrency tests pass on local SQLite and staging D1; zero partial writes; zero missed due subs.

### Phase 2 — P1 hot paths (3–5 days)

1. Order detail: join/batch + schema cache.
2. `/billing/dues`: aggregate query.
3. Vendor route: batch ledger/paid sums.
4. Admin metrics: rollup/cache.
5. Login: `CF-Connecting-IP`, combined rate checks, scoped IP limit; throttle LRU.
6. Client: TTL alignment, no 429 retry for GETs, immediate stale fallback, cache clear on logout.
7. Cache headers: admin `private, no-store`; validate `/windows` dates.
8. Vendor sync: chunked batch.

**Exit:** p95 queries/request ≤10 for reads, ≤25 for writes; p95 latency within SLO; no admin `public` headers.

### Phase 3 — Validate A/B (2–3 days)

1. Run the benchmark plan below at A and B with 2.5× bursts and a 30-minute soak.
2. Record p50/p95/p99, error rate, D1 queries/rows, CPU, cron duration.
3. Compare to SLOs with 20% headroom; fix regressions before declaring GO.
4. Produce a cost estimate at B (requests, CPU-ms, D1 rows).

**Exit:** signed benchmark report; GO/NO-GO for A and B.

### Phase 4 — C architecture (only if C is confirmed; multi-week)

1. Async write queue (Queues/DO) for non-critical writes; keep money paths synchronous and transactional.
2. Read models/caching for authed reads; consider D1 read replication if available and validated.
3. Cursor-based cron with a backlog SLO; possibly split cron by shard.
4. Sharding or a non-D1 read store if measurements show the single writer is the wall.
5. Re-run C; certify only with measured headroom.

**Exit:** C meets SLOs at 1,000 concurrent with 20% headroom, or the requirement is renegotiated.

---

## 8. Benchmark plan

### 8.1 Guardrails

- Target **local `wrangler dev`** or **staging Worker + staging D1** only.
- Production is read-only; no load test, write, migration, or deploy against it.
- Synthetic users/phones only; fake UPI provider; no real money.
- Abort a run if 5xx > 2%, p99 > 5s, or D1 errors appear.
- Keep the seed script and results in `Feature_docs/performance/` (not in app code).

### 8.2 Tooling

- **k6** (constant-arrival-rate, thresholds) preferred; **Locust** (Python) acceptable.
- `wrangler tail` / Workers Logs for server errors; D1 query metrics from structured logs.
- Flutter: `flutter run --profile` on a mid-range Android; DevTools timeline; `flutter drive` for cold start.

### 8.3 Profiles

| Profile | VUs | Pattern | Duration | Purpose |
|---|---:|---|---:|---|
| Smoke | 1 | every route once | 5 min | correctness |
| A | 50 | 6-min session, 20 req, 2-min ramp, 2.5× burst | 30 min | registered-user scale |
| B | 100 | same | 30 min | DAU scale |
| C | 1,000 | 10-min ramp, 2.5× burst | 60 min | concurrency limit |
| Soak | B | steady | 2 h | leaks/backlog |
| Cron | — | 100 / 500 / 1,000 due subs | per run | invocation cap/CPU |
| Webhook race | 100 | same `provider_ref` concurrently | 1 min | idempotency |
| Cancel race | 50 | same order concurrently | 1 min | atomic cancel |
| Reissue race | 20 | same order concurrently | 1 min | 3/24h guard |
| Vendor route | 20 vendors | 40 stops, 60s poll | 10 min | N+1 |
| Admin | 5 | dashboard refresh 60s | 10 min | aggregates |

### 8.4 Measurements to capture

Per route: requests, RPS, p50/p95/p99, 5xx %, D1 queries/request, rows read/written/request, Worker CPU p50/p95, response bytes.  
Per cron: due subs, created, failed, statements, CPU, wall time, `next_run` correctness.  
Flutter: cold start, first frame, build/raster p95, jank %, memory, network calls per session.

### 8.5 Acceptance

- A/B: SLOs met with 20% headroom; 5xx < 0.5%; cron < 1,000 statements and < 30s CPU; zero missed due subs after induced failure.
- C: SLOs met at 1,000 VUs only after Phase 4; otherwise record the knee and renegotiate.
- Any P0 concurrency test failure blocks the run and the release.

---

## 9. Official limits and citations

| Topic | Takeaway used here | Source |
|---|---|---|
| Workers limits | Free 10ms CPU; Paid 30s default / 5min max per request; 128MB; 50/1,000 subrequests | https://developers.cloudflare.com/workers/platform/limits/ |
| Workers pricing | Free 100k requests/day; Paid 10M included, 30M CPU-ms/month | https://developers.cloudflare.com/workers/platform/pricing/ |
| D1 limits | 1,000 queries/invocation Paid, 50 Free; 100 bound parameters/query; 100KB SQL; single writer per database | https://developers.cloudflare.com/d1/platform/limits/ |
| D1 pricing | Free 5M rows read/day, 100k rows written/day; Paid 25B read/month, 50M written/month | https://developers.cloudflare.com/d1/platform/pricing/ |
| D1 batch | `batch()` is transactional; a failed statement aborts the sequence | https://developers.cloudflare.com/d1/worker-api/d1-database/#batch |
| Cron triggers | 30s CPU, 15min wall; automatic retries unless `noRetry()` | https://developers.cloudflare.com/workers/configuration/cron-triggers/ |
| Default cache | HTML/JSON are not cached by default; cache behavior must be configured | https://developers.cloudflare.com/cache/concepts/default-cache-behavior/ |
| Python Workers | Runs on Pyodide; deploy-time snapshot reduces cold start, not per-request interpretation | https://developers.cloudflare.com/workers/languages/python/ |
| Flutter performance | 16ms frame budget at 60Hz (8ms build + 8ms raster); profile mode; lazy lists | https://docs.flutter.dev/perf/best-practices |

**Caveats**

- D1’s “single writer” does not mean one query at a time globally; it means writes to one database are serialized. The planning heuristic of ~1ms/simple query is not a guarantee; measure.
- `workers.dev` has no zone-level Cache Rules; `CDN-Cache-Control` in this repo is inert today. The cache headers are still a latent risk for admin paths if a zone is added later.
- Python Workers’ Pyodide overhead is not measured here; CPU numbers are estimates until profiled.

---

## 10. Open questions (owner decisions)

1. **Which scenario is “1,000 users”?** A (registered), B (DAU), or C (concurrent)? The verdict differs.
2. **Workers plan:** Free or Paid? Paid is required for password login (PBKDF2 100k), cron headroom, and D1 write volume at B.
3. **Peak definition:** what is the busiest hour, and is 2.5× burst realistic? Which delivery windows cluster?
4. **Subscription adoption and due-time clustering:** what % of users will be on daily plans, and do they all fall due in the morning? This drives the cron cap.
5. **Cron delay tolerance:** is a 1–15 minute delay for a due delivery acceptable? A cursor/max-N design needs a product answer.
6. **Is C a real requirement or a stress target?** If real, approve Phase 4 architecture work; if not, use C only to find the knee.
7. **Staging budget:** may we create a staging Worker + D1 and seed synthetic data? This is a deployment action and needs approval.
8. **Production observability:** may we enable traces/issue detection and add structured logs in production? No customer data writes; still a config change.
9. **Migrations 017/018 remote state:** can we run a read-only `wrangler d1 migrations list` / schema check to confirm index availability? Production access is currently read-only by policy.
10. **SLO/error budget:** is 99.9% monthly the right target, and what is the acceptable p95 for order tracking?
11. **Push notifications:** implement FCM send to cut polling, or keep polling as the only status channel?
12. **Retention policy:** how long must ledger/audit/idempotency rows live? This determines purge load and index value.

---

## 11. What was not verified

- No production or staging load test was run; all throughput numbers are modeled.
- No physical Android profile-mode benchmark; Flutter findings are source-level.
- Remote application state of migrations `017`/`018` (and therefore some indexes) is unknown.
- The Workers plan tier is not recorded in the repo; Free-vs-Paid conclusions assume the plan can be chosen.
- Pyodide per-request CPU and D1 p50 latency were not measured; the 4-statements/request blend and 1ms/query heuristic are planning assumptions.
- No vendor/admin live traffic measurement; those findings are source-level.

---

*End of audit. No code or production change was made. Implementation awaits explicit approval.*
