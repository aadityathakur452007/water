# Phase 0 results — safe measurement layer

**Date:** 2026-10-25  
**Status:** Implemented, deployed to staging, measured; production untouched.  
**Spec:** `2026-10-25-phase0-implementation-spec.md`  
**Audit:** `2026-10-25-1000-user-capacity-audit.md`  
**Runbook:** `phase0-runbook.md`

## 1. Outcome

Phase 0 shipped the measurement layer: a real DB-backed `/health`, redacted
structured request logs with D1 statement/row counters, an isolated staging
Worker + D1, a deterministic synthetic seed, and a guarded GET-only benchmark
harness.

The layer works. The platform does not. On Workers **Free**, the 10 ms CPU
ceiling kills this Python/FastAPI Worker before application code runs: staging
A/B/C aborted at 27.3% / 16.7% / 55.6% 5xx, and production’s old `/health` also
returns intermittent `1102`. A warm keep-alive connection is fast
(118–194 ms), but cold/isolate startup is 1.5–4 s. **Paid Workers is a launch
prerequisite, independent of the 1,000-user target.**

On a local seeded database the application itself handled both A (2.78 rps,
1,668 requests, p99 34.8 ms) and B (5.56 rps, 3,336 requests, p99 32.8 ms)
with zero errors. The
query-shape data also confirms the audit’s N+1 findings: the vendor route issues
**85 statements / 162 rows** per request for 40 stops, above the Free-plan
50-query cap and far above a healthy target.

## 2. What shipped

| Area | Change | File |
|---|---|---|
| Health | Real `SELECT 1` probe, 2 s timeout, 5 s per-isolate cache, exact success body, 503 degraded body, `no-store` | `workers/api/src/app/api/health.py` |
| Request logs | One redacted JSON line per sampled request; template route, status, duration, trace id, DB counters; 4xx/5xx/slow always log | `workers/api/src/app/core/observability.py` |
| Trace safety | Trace ids sanitized to `^[A-Za-z0-9._-]{1,64}$` before echo/log; malformed ids replaced | `workers/api/src/app/core/errors.py` |
| Middleware | Trace outer to CORS, request timing, metrics reset, log in `finally`, logging never raises | `workers/api/src/app/api/deps.py` |
| D1 counters | `meta.rows_read` / `meta.rows_written` / `changes`; batch = N statements, one roundtrip; no double count | `workers/api/src/app/db_d1.py` |
| Local counters | `AsyncSqliteConn` counts rows for the same log schema | `workers/api/src/app/db_d1.py` |
| Throttle | `THROTTLE_ANON_PER_MIN` override; client IP removed from rate-limit logs | `workers/api/src/app/api/middleware.py` |
| Config | `.env.example` documents `OBS_LOG_SAMPLE_RATE`, `OBS_SLOW_MS`, `THROTTLE_ANON_PER_MIN` | `workers/api/.env.example` |
| Staging | `env.staging`: `water-staging`, D1 `shodasha-staging`, `APP_ENV=staging`, OBS flags, throttle 100000, cron off | `workers/api/wrangler.jsonc` |
| Seed | Deterministic 43,203-row dataset with true UPSERTs, SQL and SQLite modes, tokens/summary output | `workers/api/scripts/seed_phase0.py` |
| Benchmark | GET-only constant-arrival A/B/C + smoke, refuses production, aborts on 5xx/p99, JSON + Markdown | `workers/api/scripts/bench_phase0.py` |
| Tests | 13 observability/health/counter tests, 26 benchmark guard tests, health cache assertions | `workers/api/tests/test_observability.py`, `test_bench_guard.py`, `test_health.py` |
| Docs | Spec, runbook, results, context sync | `Feature_docs/performance/`, `context/` |

No business logic, schema, money path, or production data changed.

## 3. Verification

- Full backend suite: **400 passed** (`python -m pytest -q`, `workers/api`).
- Benchmark guards: **26 passed**; unsafe target, profile C without
  `--allow-stress`, and missing tokens all exit 1 with token-free messages.
- `wrangler deploy --dry-run` passed for default and `--env staging`; staging
  binds only `shodasha-staging`.
- Staging D1 migrations **002–028** applied: 27 migration records.
- Staging seed: **437 SQL queries, 43,203 rows**, D1 reported **168,115 rows
  written including indexes**, DB size 13.99 MB. Do not re-seed casually on
  Free (100k/day).
- Production migration check was read-only:
  `npx wrangler d1 migrations list shodasha --remote` → **“No migrations to apply!”**
- Staging Worker deployed at 100% traffic: `water-staging`, version
  `c53de1d3-0353-4673-b818-3e263d10b7c6`,
  `https://water-staging.adityathakur452007.workers.dev`.
- First staging deploy uploaded a version then failed the workers.dev route step
  with `10007 This Worker does not exist`; a second deploy registered the route.
  The runbook records the retry.
- Live staging `/health`: `200 {"status":"ok"}`, `Cache-Control: no-store`,
  sanitized `x-trace-id`.
- Live staging structured log: `env=staging`, `route=/health`, `status=200`,
  `duration_ms=1055`, `db_queries=1`, `db_roundtrips=1`, `db_rows_read=0`,
  `db_rows_written=0`, trace id `tailcheck001`; no headers, query, body, phone,
  token, or client IP.
- Seeded staging routes returned 200 one at a time: catalog, `auth/me`, orders,
  order detail, dues, vendor route, admin orders. A 1-VU smoke later hit three
  platform `1102` responses; the same routes returned 200 when retried (§4).
- No token, bearer value, phone number, or 64-hex secret appears in the results
  artifacts or runbook.

## 4. Staging benchmark — Workers Free

All runs are GET-only against `water-staging`. The harness aborts after at least
20 requests when 5xx > 2% or p99 > 5 s and still writes the partial result.

| Run | Requests | Achieved rps | 5xx | p50 | p95 | p99 | Outcome |
|---|---:|---:|---:|---:|---:|---:|---|
| smoke | 7 | 1.17 | 42.9% | 270 ms | 4279 ms | 4279 ms | fail |
| A (2.78 rps, 20 conc.) | 22 | 2.81 | 27.3% | 397 ms | 1945 ms | 3264 ms | aborted |
| B (5.56 rps, 40 conc.) | 24 | 4.07 | 16.7% | 598 ms | 1473 ms | 2804 ms | aborted |
| C (55.6 rps, 100 conc.) | 45 | 7.04 | 55.6% | 218 ms | 2105 ms | 5877 ms | aborted |

Per-route A (the run that got furthest):

| Route | Count | 5xx | p50 | p95 | p99 |
|---|---:|---:|---:|---:|---:|
| health | 1 | 0 | 203 ms | 203 ms | 203 ms |
| catalog | 4 | 1 | 241 ms | 418 ms | 418 ms |
| me | 3 | 0 | 397 ms | 545 ms | 545 ms |
| orders | 4 | 0 | 962 ms | 1203 ms | 1203 ms |
| order_detail | 4 | 2 | 272 ms | 830 ms | 830 ms |
| dues | 3 | 1 | 660 ms | 847 ms | 847 ms |
| vendor_route | 3 | 2 | 1945 ms | 3264 ms | 3264 ms |

These are **not** application latency measurements. Every failed response body
was Cloudflare `error code: 1102` (CPU limit) or, after a kill, `1101`; none was
the app’s degraded JSON. The abort point is the runtime ceiling, not a D1 or
query-shape knee.

The abort reason prints the rate at the moment the threshold is crossed
(28.57% / 20.00% / 88.00%); in-flight requests finish into the final overall
rate in the table (27.3% / 16.7% / 55.6%). Both describe the same failures.

## 5. Root cause: Free-plan CPU, not Phase 0 code

Evidence, in order:

1. A 503 body is exactly `error code: 1102`, not
   `{"status":"degraded","checks":{"db":"error"}}`.
2. `wrangler tail` shows
   `SystemError: Cannot enter a promising task from inside another running
   promising task. This is a bug in Pyodide.` at `initPyInstance`, plus 1102
   CPU-limit kills. This is runtime initialization, before route handlers.
3. The known workerd issue is an isolate stuck on `1101` after a CPU-limit kill
   ([workerd #7814](https://github.com/cloudflare/workerd/issues/7814)); the
   1101s cluster after 1102s.
4. Production’s **old, DB-free** `/health` also returns intermittent 1102:
   5 probes = 200, 503 1102, 200, 200, 200 at 1.9–4.2 s. The blocker predates
   this phase and affects the current 9-user production deployment.
5. One warm keep-alive connection to staging: first `/health` 1962 ms, then
   19/19 200 at **118–194 ms**. Warm requests are fine; cold start and CPU
   accounting are the problem.

Workers Free allows **10 ms CPU per request**. Pyodide/Python initialization
alone exceeds it. Paid allows 30 s by default (up to 5 min), which removes this
ceiling. No code change in this repo can make a Python Worker fit 10 ms of CPU
on every cold request.

This is the Phase 0 spec’s expected outcome: a Free-plan CPU rejection is a
**measurement finding**, not a code failure.

## 6. Local application baseline

The same seeded shape (1,021 users, 10,000 orders) on local SQLite, app served
by uvicorn, harness pointed at loopback. This removes the Cloudflare CPU ceiling
and measures the application and query shape, not D1 network latency.

| Run | Requests | Achieved rps | Errors | p50 | p95 | p99 | Result |
|---|---:|---:|---:|---:|---:|---:|---|
| smoke | 7 | 139.0 | 0 | 7.0 ms | 13.0 ms | 13.0 ms | pass |
| A (2.78 rps, 20 conc.) | 1668 | 2.78 | 0 | 11.4 ms | 29.0 ms | 34.8 ms | pass |
| B (5.56 rps, 40 conc.) | 3336 | 5.56 | 0 | 9.8 ms | 25.8 ms | 32.8 ms | pass |

Local A per route:

| Route | Count | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| health | 83 | 5.8 ms | 23.7 ms | 27.2 ms |
| catalog | 250 | 4.5 ms | 22.1 ms | 24.5 ms |
| me | 250 | 11.6 ms | 29.9 ms | 34.1 ms |
| orders | 334 | 7.7 ms | 24.7 ms | 30.3 ms |
| order_detail | 334 | 8.1 ms | 25.1 ms | 29.2 ms |
| dues | 250 | 13.2 ms | 31.9 ms | 37.3 ms |
| vendor_route | 167 | 17.5 ms | 33.2 ms | 37.6 ms |
| **Total** | **1668** | **11.4 ms** | **29.0 ms** | **34.8 ms** |

**Caveat:** local A recorded 1,662 transport reconnects and local B recorded
3,324. The benchmark threads idle ~7 s between requests, while uvicorn’s default
keep-alive is 5 s; the stale socket fails, the harness reconnects, and the
request succeeds. All 1,668 A requests and all 3,336 B requests returned 200.
Treat the latency as “application plus one local reconnect,” not a clean
network measurement. The query counters are unaffected. The runbook now uses
`--timeout-keep-alive 75` for local runs.

Local SQLite is not D1: it has no network roundtrip, no D1 row accounting, and
different concurrency behavior. These numbers prove the app can execute A/B
request rates without application errors; they do not prove D1 can serve them.

## 7. Per-route query shape (local, full sampling)

From one request per route with `OBS_LOG_SAMPLE_RATE=1`:

| Route | Statements | Roundtrips | Rows read | Rows written | Finding |
|---|---:|---:|---:|---:|---|
| `/health` | 1 | 1 | 1 | 0 | `SELECT 1` |
| `/v1/catalog` | 0 | 0 | 0 | 0 | Static settings |
| `/v1/auth/me` | 6 | 6 | 6 | 0 | Session + user reads; trim later |
| `/v1/orders?limit=20` | 2 | 2 | 11 | 0 | Acceptable |
| `/v1/orders/{id}` | 5 | 5 | 24 | 0 | Acceptable |
| `/v1/billing/dues` | 15 | 15 | 14 | 0 | N+1 per open order |
| `/v1/vendor/routes/today` | **85** | **85** | **162** | 0 | **Over Free’s 50-query cap** |

Named N+1s:

- `vendor_service.today_route` (`vendor_service.py:302-366`) runs
  `ledger.get` + `paid_sum_for_order` per stop, plus schema introspection and
  base reads. For 40 stops: 85 statements / 162 rows. This alone exceeds the
  Free-plan 50-queries-per-invocation cap and is the first query-shape fix.
- `payment_service.get_dues` (`payment_service.py:211-231`) runs
  `paid_sum_for_order` and `_dues_posted` per open order. 15 statements for ~6
  open orders.
- `order_detail` is 5 statements, better than the audit’s earlier 7 but still
  includes `PRAGMA table_info('stops')` (`order_repo.py:164,439`).

## 8. What this means for A, B, and C

- **A (1,000 registered) and B (1,000 DAU):** the application handled both
  request rates locally with zero errors, so the remaining A/B blockers are
  platform plan, D1 latency, and the P0 correctness defects — not raw handler
  throughput.
- **C (1,000 concurrent):** still **NO-GO**. The staging C run could not measure
  a concurrency knee because the CPU ceiling failed first (55.6% 5xx at 7 rps).
  C remains a stress target for a later architecture phase, not a launch gate.
- **Free plan:** not viable even at 9 production users. `/health` alone returns
  intermittent 1102. This is the first thing to fix.

## 9. Phase 1 priorities

1. **Upgrade the Worker to Paid when the owner is ready** (owner action, no
   code; not now). Until then, keep measurement to staging/local and do not
   launch A/B. After the upgrade, re-probe production `/health` and staging and
   re-run staging A/B. Paid’s 30 s default removes the 1102/1101 ceiling. Do not
   start A/B load tests against production.
2. **Fix the P0 money/cron defects before any launch:** non-atomic cancel
   (`order_repo.py:456-547`), webhook CAS gap (`payment_repo.py:375-442`),
   order-transition lost updates (`order_repo.py:323-357`), cron advancing
   `next_run` before order creation (`subscription_service.py:885-894`), and
   the purge chunk of 500 over D1’s 100-parameter limit.
3. **Batch the N+1 reads:** vendor route first (85 → target <10 statements),
   then dues. Replace per-stop `ledger.get`/`paid_sum_for_order` with one
   grouped query; cache `_stop_field_cols` per isolate. This also brings the
   vendor route under Free’s 50-query cap, though Free CPU remains fatal.
4. **Page the cron:** process due subscriptions in bounded batches under the
   1,000-queries/invocation Paid cap; advance `next_run` only after the order
   exists.
5. **Re-run staging A/B on Paid**, then decide whether C needs the
   architecture work (read models, async writes, cursor cron, sharding).
6. **Keep the measurement layer on:** structured logs are cheap, redacted, and
   already deployed to **staging**. Production deploy of the same code is a
   separate approved step; it was not performed in Phase 0. Add alerts on 5xx
   rate and `/health` 503 before launch.

## 10. Artifacts and reproduction

Results (`Feature_docs/performance/results/`):

- `phase0-smoke-staging-1.{json,md}`
- `phase0-a-staging-1.{json,md}`, `phase0-b-staging-1.{json,md}`,
  `phase0-c-staging-1.{json,md}`
- `phase0-smoke-local-1.{json,md}`, `phase0-smoke-local-counters.{json,md}`
- `phase0-a-local-1.{json,md}`, `phase0-b-local-1.{json,md}`

Reproduction commands are in `phase0-runbook.md`. The harness refuses any host
that is not loopback or does not contain `staging`, and profile C requires
`--allow-stress`.

## 11. Limits and open questions

- The synthetic billing mix (20% prepaid subscriptions, 3,000 delivered orders,
  6,000 placed) is an assumption; real subscription adoption is unknown.
- Morning is the busiest window (owner: “until 12”), so peak concurrency is
  concentrated there. The benchmark profiles model 2.5x burst, not a
  time-of-day curve.
- Cron delay is “totally tolerable” per the owner, which gives the Phase 1 cron
  paging design room.
- Status remains polling-only; FCM is later and was not measured.
- Local SQLite cannot model D1 network latency or D1 row accounting.
- No production load test, write, migration, or deploy was performed in this
  phase.
