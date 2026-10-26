# Phase 2 implementation spec — P1 hot paths

**Date:** 2026-10-26  
**Status:** **APPROVED and implemented locally on 2026-10-26. Backend and Flutter gates are green; no migration, no money-path change, no staging deploy yet, production untouched.** Evidence: `2026-10-26-phase2-results.md`.  
**Parent audit:** `Feature_docs/performance/2026-10-25-1000-user-capacity-audit.md` (§5.2, §7)  
**Prior evidence:** `2026-10-25-phase0-results.md`, `2026-10-25-phase1-results.md`  
**Production:** read-only. No load test, write, migration, or deploy against `water` / `shodasha` without a separate explicit approval. Staging work only.

## 1. Goal

Cut avoidable D1 work on the reads and auth paths that dominate at A/B, and remove the latent admin cache leak. Phase 2 does **not** certify capacity: the Free-plan 10 ms CPU ceiling still blocks a meaningful A/B benchmark (Phase 3). This phase makes the code cheap enough that Phase 3 measures traffic, not waste.

Exit criteria inherited from the audit §7:

- p95 D1 queries per request ≤ 10 for reads, ≤ 25 for writes.
- No admin response emits `public` / `CDN-Cache-Control`.
- No new migration, no money-path change, no production deploy.

## 2. Verified baseline (2026-10-26)

| Item | Current code | Statements / round trips |
|---|---|---|
| Order detail | `order_service.detail` + `order_repo.stop_delivery_state` | 7 statements + 1 `PRAGMA table_info('stops')` = 8 sequential round trips worst case |
| Subscription read/write | `subscription_service._ensure_billing_mode` | 1 `PRAGMA` per call, every call |
| Vendor route | `vendor_service.today_route` + `_stop_field_cols` | 6 statements (Phase 1B) + 2 `PRAGMA`s = 8 |
| Vendor PoD / sync item | `_has_pod_cols`, `_pod_lifecycle`, inline `PRAGMA` in `pod_complete` | 3 `PRAGMA`s per completed stop |
| Admin `/admin/metrics` | `admin.py:1229` | 4 full-table aggregates per call |
| Admin `/admin/metrics/overview` | `admin.py:1259` + `admin_read_repo` | 3 full-table aggregates per call |
| Admin `/admin/config`, `/admin/zones` | `cached()` | `Cache-Control: public` + `CDN-Cache-Control: public` |
| `/v1/windows?date=` | `catalog.py:60` | any date accepted → unbounded cache cardinality |
| Login | `auth_service.user_login` + `_limit_check` | 2 sequential checks = 4 D1 statements + 2 round trips before user lookup; IP from `request.client.host` |
| Anon throttle | `middleware.py:25` | per-isolate unbounded dict |
| Flutter public reads | `api_client.dart:127` | 45 s fresh / 5 min stale; GET 429 retried 3×; stale only after retries; cache survives logout |
| Vendor sync | `vendor_service.sync_batch` | sequential per-item loop, ~12–15 round trips/item |

## 3. Scope

### 2A — Read path + schema cache (backend)

| ID | Audit | Change |
|---|---|---|
| P2-1 | P1-1 | Fold the assigned/dispatched rider lookup and `stops_ahead` into one join; drop the per-call stops `PRAGMA`. |
| P2-2 | P1-2, P1-4 | Add `app/db_schema.py`: per-isolate cached column sets for `stops` and `orders`. Use it in `order_repo`, `vendor_service` (`_has_pod_cols`, `_pod_lifecycle`, `_stop_field_cols`, `pod_complete`). Cache `_ensure_billing_mode` behind a per-isolate ready flag. |

### 2B — Admin + headers + windows (backend)

| ID | Audit | Change |
|---|---|---|
| P2-3 | P1-5 | 60 s per-isolate TTL cache for `/admin/metrics` and `/admin/metrics/overview`; bounded key set. |
| P2-4 | P1-9 | `cached(..., private=True)` → `Cache-Control: private, no-store`, no CDN header, no ETag; use on `/admin/config` and `/admin/zones`. |
| P2-5 | P1-10 | `/v1/windows`: clamp past dates to today; reject dates beyond today + 30 days with 400 `VALIDATION` (the project's `ValidationError` mapping). |

### 2C — Auth edge (backend)

| ID | Audit | Change |
|---|---|---|
| P2-6 | P1-6 | `client_ip(request)` helper: prefer `CF-Connecting-IP`, fall back to `request.client.host`. Use in `/auth/user/login`, `/auth/user/register`, and the anon throttle. Never log the IP. |
| P2-7 | P1-6 | One multi-row UPSERT + one `IN (...)` SELECT for the phone + IP login checks → 2 statements, 1 round trip. Raise the IP ceiling from 20/hr to 100/hr (per-phone 5/15 min unchanged). |
| P2-8 | P1-7 | Bound `_throttle_hits` at 2,048 keys: prune expired entries, then evict oldest-inserted. |

### 2D — Flutter client

| ID | Audit | Change |
|---|---|---|
| P2-9 | P1-8 | Align cache TTL to the server: 300 s fresh, 20 min max stale. Never retry a 429 on GET. Cacheable GETs attempt once and fall back to stale immediately on 429/5xx/transport failure. |
| P2-10 | P1-8 | `clearReadCache()` and call it at the auth boundary next to `clearInflight()`. |
| P2-11 | P1-14 | `if (!mounted) return;` after `await refreshOrder(...)` before `startTracking(...)`. |

### Deferred (not in this approval)

| ID | Audit | Why deferred |
|---|---|---|
| P2-12 | P1-12 | Vendor sync chunked batching. The audit wants chunks of 20–50 with per-item results, but D1 `batch()` is all-or-nothing; batching multiple items would turn one bad stop into a whole-chunk rollback. The safe slice (P2-2 PRAGMA removal) ships now; full batching needs its own statement-builder design + money-path tests. Measure a 100-item flush on staging first. |

### Non-goals

- No migration, no schema change, no production deploy.
- No change to any money mutation, CAS guard, refund path, cron, or state matrix.
- No `batch()` for authed reads (Phase 1B decision kept).
- No admin rollup table (cache only; rollup needs a migration + backfill).
- No `settle_dues_intent` allocation rewrite, no admin/order-detail N+1 work.
- No FCM/push, no status streaming, no polling-interval change.
- No pricing, copy, or customer-visible behavior change.

## 4. Design per item

### 4.1 P2-1 — order detail join

`detail()` keeps its three independent reads (`find_owned`, `events`, `stop_delivery_state`) and replaces the three assigned/dispatched queries with one:

```sql
SELECT s.id, s.route_id, s.seq, r.vendor_id,
       (SELECT COUNT(*) FROM stops x
         WHERE x.route_id = s.route_id AND x.status = 'pending' AND x.seq < s.seq) AS ahead,
       u.name, u.phone, p.name AS prof_name, p.phone AS prof_phone
  FROM stops s
  JOIN routes r ON r.id = s.route_id
  JOIN users u ON u.id = r.vendor_id
  LEFT JOIN vendor_profile p ON p.user_id = r.vendor_id
 WHERE s.order_id = ? AND s.status = 'pending'
```

- `JOIN users` (not `LEFT JOIN`) preserves today's "no vendor user → no rider block" behavior.
- The broad `except Exception: pass` stays: a legacy/partial schema must not fail order detail.
- Response shape is unchanged; `rider`, `stops_ahead`, `events`, `bill`, `tracker` keys stay identical.
- Worst case 4 statements / 4 round trips (from 7 + PRAGMA). Typical non-assigned detail: 3.

### 4.2 P2-2 — per-isolate schema cache

New `workers/api/src/app/db_schema.py`:

```python
async def stop_columns(conn) -> frozenset[str]
async def order_columns(conn) -> frozenset[str]
def reset_schema_cache() -> None   # tests only
```

- Probe once per isolate with `SELECT name FROM pragma_table_info('<table>')`; table names are hard-coded literals.
- Cache only on a successful probe. A failed probe returns `frozenset()` and is retried on the next call, matching today's tolerant behavior.
- No lock: two concurrent first calls probe twice and write the same value.
- `_ensure_billing_mode` keeps its own `_billing_ready` flag in `subscription_service.py`: probe → ALTER missing columns → re-probe once → set ready only when all four columns are present. First call costs 1–2 probes; later calls cost 0. `reset_billing_mode_cache()` for tests.
- Test isolation: add an autouse fixture in `workers/api/conftest.py` that calls `reset_schema_cache()` and `reset_billing_mode_cache()` before each test. Without it, a `:memory:` DB built from a 004-only harness could inherit a column set from a previous test.

### 4.3 P2-3 — admin metrics cache

Module-level in `admin.py`:

```python
_METRICS_TTL_S = 60
_metrics_cache: dict[str, tuple[float, dict]] = {}
```

- Keys: `"metrics"` and `f"overview:{days}"`. `days` is bounded 1–90, so the map is bounded at 91 entries; prune expired entries on write.
- `build()` runs only on a miss. A miss is one full aggregate pass; a hit is zero statements.
- Both routes set `Cache-Control: private, no-store` via an injected `Response`.
- Freshness: ≤60 s stale for admin analytics. Acceptable for a dashboard; no money decision reads these numbers.

### 4.4 P2-4 — private cache headers

`cached(body, request=None, max_age_s=300, private=False)`:

- `private=True` → `{"Cache-Control": "private, no-store"}`, no `CDN-Cache-Control`, no ETag/304.
- `private=False` → unchanged public behavior.
- Call sites: `/admin/zones` (`admin.py:601`) and `/admin/config` (`admin.py:1152`) pass `private=True`. Catalog/windows/serviceability stay public.

### 4.5 P2-5 — `/windows` horizon

- `WINDOW_HORIZON_DAYS = 30`.
- `date` earlier than today → normalize to today (no error; absorbs client timezone skew).
- `date` later than today + 30 → `ValidationError("Choose a delivery date within the next 30 days.", {"date": ...})` → 400 `VALIDATION` (matches the project's error mapping; FastAPI's own malformed-date 422 still applies).
- Validate the input date; `_next_serviceable_day` may still roll forward over holidays. Cache cardinality is bounded by 31 input dates.
- `pincode` handling unchanged.

### 4.6 P2-6 — client IP

New `client_ip(request)` in `app/api/middleware.py`:

```python
def client_ip(request: Request) -> str:
    cf = (request.headers.get("cf-connecting-ip") or "").strip()
    if cf:
        return cf[:45]
    host = request.client.host if request.client and request.client.host else ""
    return host or "unknown"
```

- Cloudflare overwrites `CF-Connecting-IP` on Workers; the fallback covers local/test.
- Used by `/auth/user/login`, `/auth/user/register`, and `throttle_middleware`.
- The value is only used as a rate-limit key; it is never logged (Phase 0 redaction contract).

### 4.7 P2-7 — combined login checks

Replace two sequential `_limit_check` calls with `_limit_checks(checks)`:

1. Run the L1 check for every key first (instant deny, no D1 write).
2. One `batch()`:
   - one multi-row `INSERT ... VALUES (?,?,1),(?,?,1) ON CONFLICT(key, window_start) DO UPDATE SET count = count + 1`
   - one `SELECT key, count FROM rate_counters WHERE key IN (?,?)`
3. Evaluate each count; over-limit raises `RateLimitedError` with that key's retry window.

- 2 statements / 1 round trip (from 4 statements / 2 round trips).
- D1 failure / pre-019 table → debug log, L1 still enforced (same fail-open contract).
- Limits: `LOGIN_PHONE_LIMIT = (5, 900)` unchanged; `LOGIN_IP_LIMIT = (100, 3600)` (was 20). The per-phone cap is the primary credential-stuffing guard; 100/hr/IP keeps a shared NAT usable while still bounding one IP. Device cap (`DEVICE_CAP`) is unchanged.
- Same helper can later serve OTP/access-code paths; this phase only switches login.

### 4.8 P2-8 — bounded throttle

- `_THROTTLE_MAX_KEYS = 2048`.
- On inserting a **new** key: drop keys whose newest hit is older than the 60 s window, then evict oldest-inserted until at or under the cap.
- Existing sliding-window semantics and `Retry-After` math stay unchanged; `reset_throttle()` stays.
- Worst case memory: 2,048 × 120 timestamps ≈ 2 MB per isolate.

### 4.9 P2-9 — Flutter cache + retry

`apps/user_app_donor/lib/core/api_client.dart`:

- `_readCacheTtl` 45 s → 300 s (matches `CACHE_MAX_AGE_S`).
- `_readCacheMaxAge` 5 min → 20 min (matches `stale-while-revalidate = 4 × 300 s`).
- `send(..., maxAttempts = 3)`; `_sendWithRetry` uses it. The single-flight key includes `maxAttempts` so a one-shot read never joins a retrying call.
- `_cachedMapGet` calls `send(..., maxAttempts: 1)`. On failure, if `allowStale` and the entry is within max age and the error is transport/5xx/**429**, return stale immediately; otherwise rethrow.
- GETs never retry a 429, even outside the cache path: `!(method == 'GET' && e.statusCode == 429)`.
- POST retry rules unchanged (idempotency key or `retryPost`).

### 4.10 P2-10 — clear cache at the auth boundary

- Add `void clearReadCache() => _readCache.clear();`.
- `main.dart._onAuthBoundaryChanged()` calls it next to `clearInflight()` (both login and logout transitions).

### 4.11 P2-11 — tracking orphan poll

`tracking_screen.dart` init callback:

```dart
await widget.controller.refreshOrder(widget.orderId);
if (!mounted) return;
if (_detailLoading) setState(() => _detailLoading = false);
widget.controller.startTracking(widget.orderId);
...
```

No polling starts after the screen is gone. `dispose()` keeps its existing cancel path.

## 5. Tests

### 5.1 Backend (new `tests/test_phase2_hot_paths.py`)

- **Order detail**: statement count independent of event count; rider join parity for an assigned order (name/phone/`stops_ahead`); pre-015 `stops` schema still tolerated after a cache reset.
- **Schema cache**: a counting `Conn` proxy shows 1 probe on first call and 0 on the second; `reset_schema_cache()` restores probing.
- **Billing mode**: first subscription call probes, second does not; a 004-only DB still gets the ALTERs.
- **Admin metrics**: two calls inside the TTL → one aggregate pass; `days=7` and `days=14` use separate entries; both routes return `Cache-Control: private, no-store`.
- **Headers**: `/admin/config` and `/admin/zones` are `private, no-store`; `/v1/catalog` and `/v1/windows` stay `public`.
- **Windows**: today 200; past clamps to today; today+30 200; today+31 400 `VALIDATION`.
- **Login**: `CF-Connecting-IP` drives the IP key (two CF IPs do not share a bucket); the pre-lookup path is 1 batch / 2 statements; the 6th attempt in 15 min on one phone still 429s; a 100/hr IP ceiling is enforced.
- **Throttle**: 2,049 unique keys leave the dict at ≤2,048; expired keys are pruned.
- **Vendor**: `today_route` issues 0 PRAGMAs on the second call; `pod_complete` issues 0 PRAGMAs.

### 5.2 Flutter

- New `test/api_client_cache_test.dart` (reuse the fake transport from `api_client_refresh_test.dart`):
  - 300 s fresh window: a 60 s-old entry is served without a request.
  - GET 429 → exactly 1 request; no retry.
  - Cacheable GET 429/5xx/transport failure with a usable stale entry → stale returned immediately.
  - `clearReadCache()` empties the map.
- `test/state_fixes_test.dart` (or new): disposing `TrackingScreen` during an in-flight refresh never starts a poll timer.
- `flutter analyze` + `flutter test`.

### 5.3 Existing suites

- Full backend suite (`PYTHONPATH=src python -m pytest -q`) and `ruff check`.
- No changes expected to Phase 1A/1B atomicity tests; they are the regression gate.

## 6. Rollout and rollback

- **Staging only.** Deploy `water-staging`, run the smoke routes, verify headers and `/windows` bounds, and capture `db_queries` / `db_roundtrips` deltas from the Phase 0 logs. No writes beyond synthetic fixtures already present.
- **No migration.** Nothing to apply; rollback is a code revert.
- **Production** stays untouched until a separate explicit gate after staging evidence.
- Each slice (2A/2B/2C/2D) is an independent commit; any slice can be reverted alone.
- Flutter ships as a client build; the server changes are backward compatible.

## 7. Acceptance criteria

1. Order detail worst case ≤ 4 statements (from 7 + PRAGMA).
2. `_ensure_billing_mode` and the six stop/order PRAGMA sites cost 0 extra queries after the first call per isolate.
3. Vendor route stays ≤ 6 statements with 0 PRAGMAs.
4. `/admin/metrics` and `/admin/metrics/overview` run at most one aggregate pass per 60 s per isolate per key.
5. `/admin/config`, `/admin/zones`, `/admin/metrics`, `/admin/metrics/overview` emit `Cache-Control: private, no-store`; no admin route emits `public` or `CDN-Cache-Control`.
6. `/v1/windows` rejects > today+30 with 400 `VALIDATION` and never returns an unbounded date.
7. Login pre-lookup checks are 2 statements / 1 round trip; `CF-Connecting-IP` is honored; per-phone 5/15 min is unchanged.
8. Throttle map ≤ 2,048 keys.
9. Flutter: 300 s TTL, no GET 429 retry, immediate stale fallback, cache cleared at the auth boundary, no poll after dispose.
10. Backend suite + ruff clean; `flutter analyze` + `flutter test` clean.
11. No migration, no money-path change, no production action.

## 8. Approval decisions (resolved 2026-10-26)

1. **Flutter slice**: included. 2D ships in this phase.
2. **Admin metrics**: 60 s per-isolate TTL cache. No rollup table, no migration.
3. **Login IP ceiling**: raise 20/hr → 100/hr; `CF-Connecting-IP`; per-phone 5/15 min unchanged. No separate failure-only counter.
4. **Vendor sync**: PRAGMA-only slice now (P2-2); full chunked batching deferred pending staging measurement.

Production remains read-only; staging only. Approved for implementation on 2026-10-26; see the results doc for evidence.

## 9. Sequence and effort

| Slice | Files | Effort |
|---|---|---|
| 2A | `db_schema.py` (new), `order_repo.py`, `order_service.py`, `vendor_service.py`, `subscription_service.py`, `conftest.py` | 1 day |
| 2B | `caching.py`, `admin.py`, `catalog.py` | 0.5 day |
| 2C | `middleware.py`, `auth_service.py`, `api/v1/auth.py` | 0.5–1 day |
| 2D | `api_client.dart`, `main.dart`, `tracking_screen.dart`, tests | 0.5–1 day |
| Tests + staging evidence + context sync | — | 1 day |

Order: 2A → 2B → 2C → 2D, each with tests and a local commit. Context files update once at the end (plus ADR for the schema-cache and login-limit decisions).
