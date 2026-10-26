# Phase 2 results — P1 hot paths

**Date:** 2026-10-26  
**Status:** Implemented and verified locally; **staging verified on 2026-10-26** (Worker `70e86bc9-4caf-4bdd-ae2a-ffacf6830895`, no migration, cron off). Backend **459 passed**, Flutter **75 passed**, both analyzers clean. Production untouched and still gated.

**Spec:** `2026-10-26-phase2-p1-hot-paths-spec.md`  
**Audit:** `2026-10-25-1000-user-capacity-audit.md`  
**Prior evidence:** `2026-10-25-phase0-results.md`, `2026-10-25-phase1-results.md`

## 1. Outcome

Phase 2 removes the per-request waste the audit measured on the reads and auth
paths. Steady-state costs:

| Path | Before | After | Proof |
|---|---|---|---|
| Order detail (assigned/dispatched) | 7 statements + 1 stops `PRAGMA` = 8 | 4 statements (service) / 5 endpoint incl. auth, 0 `PRAGMA` | `test_order_detail_statements_flat_with_event_count` |
| Vendor route | 6 statements + 2 `PRAGMA`s = 8 | 4 statements (service) / 5 endpoint incl. auth, 0 `PRAGMA` steady state | `test_today_route_query_count_independent_of_stop_count` |
| Vendor PoD / sync item | 1–3 `PRAGMA`s per stop | 0 after the first probe | `_pod_lifecycle` / `pod_complete` use `stop_columns` |
| Subscription read/write | 1 `PRAGMA` per call | 0 after the first call | `test_billing_mode_probe_once_per_isolate` |
| Login pre-lookup | 4 statements / 2 round trips | 2 statements / 1 round trip | `test_login_checks_are_one_batch` |
| Admin metrics | 3–4 full aggregates per call | ≤1 aggregate pass per 60 s per isolate per key | `test_admin_overview_cached_within_ttl` |
| Anon throttle map | unbounded | ≤2,048 keys | `test_throttle_map_bounded_and_prunes_expired` |

No response shape changed. No money mutation, CAS guard, refund path, cron path,
or state matrix was touched.

## 2. What shipped

| Slice | Change | Key files |
|---|---|---|
| 2A | `stop_columns` / `order_columns` per-isolate schema cache; order-detail rider + stops-ahead folded into one join; vendor `_has_pod_cols`, `_pod_lifecycle`, `_stop_field_cols`, and the inline `pod_complete` probe use the cache; `_ensure_billing_mode` probes once and re-probes only after ALTERs | `db_schema.py` (new), `order_repo.py`, `order_service.py`, `vendor_service.py`, `subscription_service.py`, `conftest.py` |
| 2B | `cached(private=True)` emits `Cache-Control: private, no-store` with no ETag/CDN header; `/admin/config` and `/admin/zones` use it; `/admin/metrics` and `/admin/metrics/overview` use a 60 s TTL cache with `private, no-store`; `/v1/windows` clamps past dates and rejects > today+30 with 400 `VALIDATION` | `caching.py`, `admin.py`, `catalog.py` |
| 2C | `client_ip()` prefers `CF-Connecting-IP`; login does one multi-row UPSERT + one `IN (...)` SELECT in one D1 batch; IP ceiling 100/hr, phone 5/15 min unchanged; throttle prunes expired keys and evicts to 2,048 | `middleware.py`, `auth_service.py`, `api/v1/auth.py` |
| 2D | Public-read TTL 300 s fresh / 20 min stale; GET 429 never retried; cacheable GETs attempt once and serve stale on 429/5xx/transport failure; `clearReadCache()` at the auth boundary; `mounted` guard before `startTracking` | `api_client.dart`, `main.dart`, `tracking_screen.dart` |

## 3. Verification

- Full backend suite: **459 passed in 15.03 s**.
- Ruff on every changed backend file: **All checks passed**. The repo-wide run
  still reports 43 pre-existing errors in untouched files.
- Flutter: **75 passed**; `flutter analyze`: **No issues found**.
- New backend tests: **16** in `workers/api/tests/test_phase2_hot_paths.py`.
- New Flutter tests: **8** in `apps/user_app_donor/test/api_client_cache_test.dart`
  (7 cache/429/stale unit tests + 1 tracking-dispose widget test).
- Existing `tests/test_vendor.py::test_today_route_query_count_independent_of_stop_count`
  now warms the schema cache and asserts the steady-state count is 4.

### 3.1 Notes

- The schema cache is safe because migrations are static for an isolate's
  lifetime. It holds only column names, never request or user data. A failed
  probe returns an empty set and retries on the next call, preserving the old
  tolerant behavior for pre-migration DBs.
- The metrics cache holds only global aggregates (orders by state, users by
  role, dues total, quality count, daily series). Keys are bounded by `days`
  1–90 plus `"metrics"`, so the map cannot grow past 91 entries.
- `cached(private=True)` deliberately skips ETag/304: a `no-store` client will
  not retain a copy to revalidate.
- Login's per-phone cap remains the primary credential-stuffing guard; 100/hr
  per IP keeps shared NAT usable. The IP value is used only as a key and is
  never logged.
- The `duration.zero` Flutter tests prove the stale path without sleeping for a
  real TTL; request counts prove no hidden retry.

### 3.2 Staging verification (2026-10-26)

`water-staging` was deployed at version `70e86bc9-4caf-4bdd-ae2a-ffacf6830895`
(100% traffic, 2026-10-26 06:17 UTC). No migration was applied — `wrangler d1
migrations list` reports "No migrations to apply!" — cron stays off, and
production was not touched.

The smoke used a curl-compatible User-Agent: Cloudflare's bot rules return 403
for the default Python-urllib UA, and the Free-plan isolate returns
intermittent 503/1102 on cold start, so each GET retried transient
503/transport failures.

| Check | Result |
|---|---|
| `GET /health` | 200 `{"status":"ok"}`, `Cache-Control: no-store` |
| `GET /v1/catalog` | 200 `public, max-age=300`, ETag + CDN-Cache-Control present |
| `GET /v1/windows?date=today` | 200 |
| `GET /v1/windows?date=today-5` | 200, `date` clamped to today |
| `GET /v1/windows?date=today+30` | 200, `date` = 2026-11-25 |
| `GET /v1/windows?date=today+31` | 400 `VALIDATION` |
| `GET /v1/admin/config`, `/admin/zones`, `/admin/metrics`, `/admin/metrics/overview` | 200 `Cache-Control: private, no-store`, no ETag/CDN header |
| `GET /v1/orders?limit=50` + `GET /v1/orders/{id}` | 200, 10 orders, detail shape intact |
| `GET /v1/vendor/routes/today?date=2026-10-25` | 200, 41 stops |

`wrangler tail --env staging --format json` was used with trace ids that the
10% sampler always logs. Counts are endpoint-level and include the one auth
statement; the service-level counts in §1 exclude it.

| Path | First request on a cold isolate | Warm steady state |
|---|---|---|
| Order detail (dispatched `load-order-001082`) | 6 statements / 6 round trips / 61 rows | **5 / 5 / 44 rows** (4 service + auth; the extra cold statement is the cached `stop_columns` probe) |
| Vendor route (41 stops) | 7 / 7 / 3,298 rows | **5 / 5 / 3,257 rows** (4 service + auth; cold adds the two cached schema probes) |
| `GET /admin/metrics` | 5 / 5 / 13,050 rows | **1 / 1 / 2 rows** on 11 observed cache hits (auth only; 0 aggregate queries), 157-172 ms |

The metrics hits prove the 60 s cache works per isolate. No cross-isolate hit
is expected or claimed; a different isolate pays the first aggregate pass
again.

These are correctness and query-count checks, not a capacity certification.
The Free-plan 10 ms CPU ceiling still causes cold starts and intermittent
503/1102, so the A/B/C benchmark remains blocked. Raw tail dumps contain
request headers and IPs; they were parsed outside the repo and are not
committed. No tokens, phones, UPI ids, or secrets were printed.

## 4. Deferred

- **Vendor sync chunked batching (P2-12).** D1 `batch()` is all-or-nothing, so
  batching multiple items would turn one bad stop into a whole-chunk rollback.
  Only the PRAGMA-removal slice shipped. Measure a 100-item flush on staging
  before designing the statement-builder rewrite.
- **Admin rollup table.** A 60 s cache is enough for a dashboard; a rollup needs
  a migration, cron writes, and a backfill.
- **`batch()` for authed reads.** The Phase 1B decision stands.
- **A/B/C measurement.** Staging is deployed and the smoke/query counts are
  captured, but the Free-plan 10 ms CPU ceiling still blocks a meaningful
  benchmark; this phase is code-ready for Phase 3.

## 5. Rollout

Staging is deployed and verified; Phase 2 itself adds no migration. Rollback is
a code revert, and each slice is independently revertable.

The production release is **cumulative**, because Phase 2 sits on top of the
Phase 1A/1B code that requires schema 029:

1. Take a fresh D1 `shodasha` backup.
2. Apply Phase 1A migration `029` (production is at 028).
3. Deploy the Phase 1A/1B/2 Worker code.
4. Run the production smoke (read-only routes; no load test).

Production remains untouched until a separate explicit owner gate authorizes
that sequence. Staging evidence does not authorize production.
