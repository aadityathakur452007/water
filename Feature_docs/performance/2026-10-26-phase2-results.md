# Phase 2 results — P1 hot paths

**Date:** 2026-10-26  
**Status:** Implemented and verified locally. Backend **459 passed**, Flutter **75 passed**, both analyzers clean. No migration, no money-path change, no staging deploy yet; production untouched.  
**Spec:** `2026-10-26-phase2-p1-hot-paths-spec.md`  
**Audit:** `2026-10-25-1000-user-capacity-audit.md`  
**Prior evidence:** `2026-10-25-phase0-results.md`, `2026-10-25-phase1-results.md`

## 1. Outcome

Phase 2 removes the per-request waste the audit measured on the reads and auth
paths. Steady-state costs:

| Path | Before | After | Proof |
|---|---|---|---|
| Order detail (assigned/dispatched) | 7 statements + 1 stops `PRAGMA` = 8 | 4 statements, 0 `PRAGMA` | `test_order_detail_statements_flat_with_event_count` |
| Vendor route | 6 statements + 2 `PRAGMA`s = 8 | 6 statements, 0 `PRAGMA` steady state | `test_today_route_query_count_independent_of_stop_count` |
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

## 4. Deferred

- **Vendor sync chunked batching (P2-12).** D1 `batch()` is all-or-nothing, so
  batching multiple items would turn one bad stop into a whole-chunk rollback.
  Only the PRAGMA-removal slice shipped. Measure a 100-item flush on staging
  before designing the statement-builder rewrite.
- **Admin rollup table.** A 60 s cache is enough for a dashboard; a rollup needs
  a migration, cron writes, and a backfill.
- **`batch()` for authed reads.** The Phase 1B decision stands.
- **Staging deploy and A/B/C measurement.** The Free-plan 10 ms CPU ceiling still
  blocks a meaningful benchmark; this phase is code-ready for Phase 3.

## 5. Rollout

No migration. Rollback is a code revert. Each slice is independently revertable.
Production remains untouched until a separate explicit gate after staging
verification.
