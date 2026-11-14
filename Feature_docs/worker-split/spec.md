# Worker Split — `water` / `water-ops` / `water-admin`

Status: **APPROVED — steps 1–2 implemented and deployed; step 5 (customer-only `water`) pending client cutover.**
Date: 2026-11-14
Owner: Aditya
Protocol: `Agent.md` (Spec → Clarify → Approve → Implement)

---

## 0. TL;DR

Split the single Python Worker `water` into three Workers that share one D1 database:

| Worker | Surfaces | Public URL |
|---|---|---|
| `water` | customer (Flutter donor app) + cron | `https://water.adityathakur452007.workers.dev` |
| `water-ops` | vendor + rider (one shared Worker) | `https://water-ops.adityathakur452007.workers.dev` |
| `water-admin` | admin web BFF | `https://water-admin.adityathakur452007.workers.dev` |

The split is **additive and zero-downtime**: routes keep identical paths, D1 schema does not change, and `water` continues serving every route until clients have moved.

**Reality check that the spec is built around:** splitting Workers does **not** raise the Free-tier 10 ms CPU limit per request, does **not** multiply the 100k requests/day account quota, and does **not** make D1 faster. It buys isolation, smaller bundles/cold starts per surface, per-surface logs and secrets, and independent deploys. The CPU ceiling stays. Section 14 defines a measurement gate before/after so we can prove whether this helped.

---

## 1. Goals

1. Customer, ops and admin traffic no longer share one Worker bundle or one request pool.
2. A customer request can never reach an admin/vendor/rider handler (404 on the wrong host), even if the role check were bypassed.
3. Admin/vendor secrets are not present on the customer Worker (and vice versa).
4. Every surface stays on Cloudflare Python Workers + the existing FastAPI code; no rewrite, no external host.
5. Database load goes **down**, not up: no new background loops, one cron owner, request-scoped caches on the hottest reads.
6. Old and new APKs can coexist during cutover; rollback is a URL/binding change, not a data migration.

## 2. Non-goals

- Raising the 10 ms CPU limit or the 100k/day account quota.
- Rewriting to TypeScript.
- Changing any route path, request body, response shape, or D1 schema.
- Fixing the pre-existing Free-tier NO-GO declared in ADR-147/148. That remains open.
- Reworking business logic, dispatch, pricing, ledger, or auth semantics.

---

## 3. Verified current state (baseline for this spec)

| Item | Fact | Source |
|---|---|---|
| Worker | one Python Worker `water`, Pyodide + FastAPI | `workers/api/wrangler.jsonc` |
| Entry | `src/entry.py`, module-level `app = create_app()`; `scheduled()` cron `*/15` | `workers/api/src/entry.py` |
| App factory | `create_app()` mounts **all** routers, then `app = create_app()` again at module bottom | `workers/api/src/app/main.py` |
| Routes | ~154 handlers; admin 67, vendor 27, rider 4, orders 8, payments 13, catalog 4 (+leads), auth 11 | `workers/api/src/app/api/v1/*.py` |
| Auth | opaque random tokens stored in D1; `get_current_user` does one `sessions JOIN users` query **per authenticated request** | `app/services/auth_service.py`, `app/repositories/session_repo.py`, `app/api/auth_deps.py` |
| Suspension rule | user row re-read on every request on purpose | `app/api/auth_deps.py` docstring |
| DB | one D1 `shodasha`, id `da762aad-1d5c-46eb-992e-acc79505cc95` | `wrangler.jsonc` |
| Admin web | `shodasha-admin` (TanStack Start), service binding `WATER_API` → `water`, build var `API_URL` | `apps/admin_app/wrangler.jsonc`, `src/server/admin-api.ts` |
| Admin web also hosts vendor portal | calls `/v1/auth/vendor/login` and `/v1/vendor/*` through the same `WATER_API` binding | `src/server/vendor-api.ts`, `vendor-session.ts` |
| Flutter | donor/vendor/rider all default to `https://water.adityathakur452007.workers.dev` | `apps/*/lib/core/api_client.dart`, `.github/workflows/release.yml` |
| Donor client cache | already has 300 s TTL read cache + single-flight | `apps/user_app_donor/lib/core/api_client.dart` (ADR-035) |
| Vendor/rider client cache | none | same files |
| Existing server caches | `health` 5 s; `/v1/admin/metrics` 60 s; catalog/windows ETag + `Cache-Control` only (Worker still runs on revalidation) | `app/api/health.py`, `app/api/v1/admin.py`, `app/api/caching.py` |
| Request DB metrics | `db_queries`, `db_roundtrips`, `db_rows_read`, `db_rows_written` already counted per request | `app/core/observability.py` |
| Tests | 44 files, 470 tests, all use `create_app()` | `workers/api/tests/` |
| Deploy auth | local Wrangler OAuth is logged in as `adityathakur452007@gmail.com` with `workers_scripts (write)` + `d1 (write)` | `npx wrangler whoami`, 2026-11-14 |

**Deploy credentials are already solved.** The pasted `cfat_…` tokens are not needed and should be revoked; `wrangler` OAuth already has the required scopes. No token will be placed in the repo or chat.

---

## 4. Target topology

```
                    ┌──────────────────────────────────────────┐
 Flutter donor ───► │ water          (customer + cron owner)   │
                    │ /v1/auth/user/*, catalog, quotes,        │
                    │ orders, addresses, payments, webhooks,   │
                    │ subscriptions, returns, complaints,      │
                    │ ratings, devices, leads, /health         │
                    └──────────────────┬───────────────────────┘
                                       │
                    ┌──────────────────▼───────────────────────┐
 Flutter vendor ───►│ water-ops      (vendor + rider)          │
 Flutter rider  ───►│ /v1/auth/vendor/*, /v1/auth/rider/*,     │
                    │ /v1/vendor/*, /v1/rider/*,               │
                    │ returns pickup, /health                  │
                    └──────────────────┬───────────────────────┘
                                       │
                    ┌──────────────────▼───────────────────────┐
 Admin web BFF ───► │ water-admin    (admin)                   │
 (server-side)      │ /v1/auth/admin/*, /v1/admin/*,           │
                    │ refunds claim/done/failed, /health       │
                    └──────────────────┬───────────────────────┘
                                       │
                              ┌────────▼────────┐
                              │ D1 `shodasha`   │
                              │ (single source) │
                              └─────────────────┘
```

- All three bind the **same** D1 database and can validate the **same** sessions (tokens are D1 rows, not signed per Worker).
- Only `water` has `triggers.crons` (`*/15`). `water-ops` and `water-admin` have no `scheduled()` handler and no cron trigger, so subscription/reminder jobs cannot double-run.
- Worker names must be exactly `water-ops` and `water-admin` so the workers.dev hostnames above exist automatically. No custom domain or DNS change required.

---

## 5. Route ownership matrix

Routes keep their existing paths. Only the Worker that mounts them changes.

### 5.1 Customer — `water`

| Module | Routes |
|---|---|
| `api/health.py` | `GET /health` |
| `api/v1/auth.py` → `shared` | `POST /v1/auth/refresh`, `POST /v1/auth/logout`, `GET /v1/auth/me`, `PATCH /v1/auth/me` |
| `api/v1/auth.py` → `customer` | `POST /v1/auth/otp/start` (410), `POST /v1/auth/demo`, `POST /v1/auth/user/register`, `POST /v1/auth/user/login` |
| `api/v1/catalog.py` | `/v1/catalog`, `/v1/windows`, `/v1/serviceability`, `POST /v1/leads` |
| `api/v1/quotes.py` | `/v1/quotes` |
| `api/v1/addresses.py` | `/v1/addresses*` |
| `api/v1/orders.py` | `/v1/orders*` |
| `api/v1/payments.py` → `router` | `/v1/payments/*`, `/v1/webhooks/upi`, `/v1/orders/{id}/cod-confirm`, `/v1/orders/{id}/switch-to-cod`, `/v1/billing/dues`, `/v1/ledger/me`, `/v1/invoices/{id}` |
| `api/v1/subscriptions.py` | `/v1/subscriptions*` |
| `api/v1/returns.py` → `router` | `POST /v1/returns`, `GET /v1/returns` |
| `api/v1/complaints.py` | `POST /v1/complaints`, `GET /v1/complaints` |
| `api/v1/ratings.py` | `POST /v1/orders/{id}/rating` |
| `api/v1/devices.py` | `POST /v1/devices`, `DELETE /v1/devices` |

### 5.2 Ops — `water-ops`

| Module | Routes |
|---|---|
| `api/health.py` | `GET /health` |
| `api/v1/auth.py` → `shared` | refresh / logout / me |
| `api/v1/auth.py` → `ops` | `POST /v1/auth/vendor/login`, `POST /v1/auth/rider/login` |
| `api/v1/vendor.py` | all 27 `/v1/vendor/*` routes (fleet, route, stops, complaint verify, quality check, returns visibility) |
| `api/v1/rider.py` | all 4 `/v1/rider/*` routes |
| `api/v1/returns.py` → `ops` | `POST /v1/returns/{id}/pickup` |

### 5.3 Admin — `water-admin`

| Module | Routes |
|---|---|
| `api/health.py` | `GET /health` |
| `api/v1/auth.py` → `shared` | refresh / logout / me |
| `api/v1/auth.py` → `admin` | `POST /v1/auth/admin/login` |
| `api/v1/admin.py` | all 67 `/v1/admin/*` routes |
| `api/v1/payments.py` → `admin` | `POST /v1/refunds/{id}/claim`, `/done`, `/failed` |

### 5.4 Shared / duplicated on purpose

- `/health` on all three.
- `/v1/auth/refresh`, `/v1/auth/logout`, `/v1/auth/me` on all three because every surface issues and rotates its own sessions but uses the same D1 `sessions` table. `PATCH /auth/me` is harmless on all three (owner-scoped).

### 5.5 Surface purity

Any route not in the lists above must return **404** on the wrong host. This is the isolation property the split exists for, and it is tested in section 13.

---

## 6. Backend changes

### 6.1 Extract the app factory — no double init

Current `app/main.py` builds a full app at import, and `entry.py` builds another. Each Worker would pay that cost twice on every cold start.

**Change:**

- New `workers/api/src/app/factory.py` — move the body of `create_app()` here, with a surface parameter:
  ```python
  SURFACES = ("all", "customer", "ops", "admin")
  def create_app(surface: str = "all") -> FastAPI: ...
  ```
  - `surface="all"` reproduces today's exact route set. **All 470 tests and local dev keep working unchanged.**
  - Each surface mounts only its tuples from section 5.
- `workers/api/src/app/main.py` becomes a 2-line compatibility shim:
  ```python
  from app.factory import create_app
  app = create_app()          # local uvicorn only; entries import app.factory
  ```
  This keeps `uvicorn app.main:app` and all docs working.
- `entry.py`, `entry_ops.py`, `entry_admin.py` import from `app.factory`, so importing an entry never builds the "all" app.

### 6.2 Split `auth.py` routers (same file, no logic move)

Define four routers in `app/api/v1/auth.py` and move each decorator onto the correct one:

| Router | Routes |
|---|---|
| `shared_router` | refresh, logout, me GET/PATCH |
| `customer_router` | otp/start, demo, user/register, user/login |
| `ops_router` | vendor/login, rider/login |
| `admin_router` | admin/login |

Keep a module-level aggregate for backward compatibility, because two tests mount it directly (`tests/test_access_code_auth.py:107`, `tests/test_demo.py:118`):

```python
router = APIRouter(tags=["auth"])
for r in (shared_router, customer_router, ops_router, admin_router):
    router.include_router(r)
```

No DTO, service call, or status code changes.

### 6.3 Split `payments.py` and `returns.py` routers

Same technique, same file, same paths:

- `payments.py`: `router` keeps the customer + webhook routes; new `admin_router` holds the three refund routes currently guarded by `require_role("admin")`.
- `returns.py`: `router` keeps create/list; new `ops_router` holds `/{return_id}/pickup`.

This physically removes admin money writes from the customer bundle and vendor pickup from the customer bundle, without duplicating or rewriting handlers. Role checks stay in place as defence in depth.

### 6.4 Entrypoints

| File | Change |
|---|---|
| `src/entry.py` | `app = create_app("customer")`; keep `scheduled()` |
| `src/entry_ops.py` | copy of fetch bridge, `app = create_app("ops")`; no `scheduled()` |
| `src/entry_admin.py` | copy of fetch bridge, `app = create_app("admin")`; no `scheduled()` |

All three keep `set_worker_env(self.env)` and the `gc.collect(1)` finally block.

### 6.5 What does not change

- No route path, payload, error envelope, or response shape changes.
- No D1 migration. No new table. No data backfill.
- No change to tokens, password hashing, rate limiting, dispatch, ledger, or pricing.
- `app.core.worker_env`, middleware, and CORS behavior stay as-is.

---

## 7. Wrangler configuration

### 7.1 Files

```
workers/api/
├── wrangler.jsonc          # water (customer) — unchanged name + cron
├── wrangler.ops.jsonc      # water-ops
└── wrangler.admin.jsonc    # water-admin
```

Both new files are copies of `wrangler.jsonc` with:

| Key | `water` | `water-ops` | `water-admin` |
|---|---|---|---|
| `name` | `water` | `water-ops` | `water-admin` |
| `main` | `src/entry.py` | `src/entry_ops.py` | `src/entry_admin.py` |
| `compatibility_date` | same | same | same |
| `compatibility_flags` | same | same | same |
| `d1_databases` | same id + migrations dir | same id + migrations dir | same id + migrations dir |
| `triggers.crons` | `["*/15 * * * *"]` | **absent** | **absent** |
| `vars.APP_ENV` | `prod` | `prod` | `prod` |
| `vars.FIREBASE_PROJECT_ID` | present | present | present |
| `observability.enabled` | (add) `true` | `true` | `true` |

`vars` comments must state that all three configs point at the same D1 id and must be changed together.

### 7.2 Deploy scripts

`workers/api/package.json`:

```json
"deploy": "uv run pywrangler deploy",
"deploy:ops": "uv run pywrangler deploy --config wrangler.ops.jsonc",
"deploy:admin": "uv run pywrangler deploy --config wrangler.admin.jsonc",
"dev:ops": "uv run pywrangler dev --config wrangler.ops.jsonc",
"dev:admin": "uv run pywrangler dev --config wrangler.admin.jsonc"
```

`pywrangler` proxies unknown flags to Wrangler (verified: `pywrangler deploy --help` forwards to `npx wrangler deploy`).

### 7.3 Migrations

One owner: run migrations only through `wrangler.jsonc` / `water`.

```
uv run pywrangler d1 migrations apply shodasha --remote
```

D1 tracks applied migrations, so a second caller would be a no-op, but keeping one owner avoids drift.

---

## 8. Environment variables and secrets

D1 binding is available to all three. Secrets are per Worker and must be set on each Worker that needs them.

| Name | Kind | `water` | `water-ops` | `water-admin` |
|---|---|---|---|---|
| `DB` (D1) | binding | yes | yes | yes |
| `APP_ENV` | var | `prod` | `prod` | `prod` |
| `FIREBASE_PROJECT_ID` | var (public) | yes | yes | yes |
| `OBS_LOG_SAMPLE_RATE` | var | yes | yes | yes |
| `OBS_SLOW_MS` | var | yes | yes | yes |
| `THROTTLE_ANON_PER_MIN` | var | optional | — | — |
| `SERVICEABLE_PREFIXES` | var | yes | — | — |
| `UPI_KEY_ID` | secret | yes | — | — |
| `UPI_KEY_SECRET` | secret | yes | — | — |
| `UPI_WEBHOOK_SECRET` | secret | yes | — | — |
| `AGENCY_UPI_VPA` | secret | yes | — | — |
| `FAST2SMS_API_KEY` / `_SENDER_ID` / `_ENTITY_ID` | secret/var | yes | — | — |
| `TEXTBEE_API_KEY` / `_DEVICE_ID` | secret/var | yes | — | — |
| `DEV_AUTH` | secret | never prod | never prod | never prod |

No new secret is introduced. No secret is copied between Workers unless the matrix says so.

Commands (one per worker that needs it):

```
npx wrangler secret put UPI_KEY_ID          --config wrangler.jsonc
npx wrangler secret put UPI_KEY_SECRET      --config wrangler.jsonc
npx wrangler secret put UPI_WEBHOOK_SECRET  --config wrangler.jsonc
npx wrangler secret put AGENCY_UPI_VPA      --config wrangler.jsonc
```

Ops and admin need **no** new secrets for v1.

---

## 9. Admin web app (`shodasha-admin`)

The admin Worker hosts both the admin dashboard and the vendor portal, so it needs two upstreams.

### 9.1 `apps/admin_app/wrangler.jsonc`

```jsonc
"services": [
  { "binding": "WATER_API", "service": "water-admin" },
  { "binding": "OPS_API",   "service": "water-ops"   }
]
```

- Keep the binding name `WATER_API` for admin calls so the diff stays small; only its target changes.
- Add `OPS_API` for vendor portal calls.

### 9.2 Build variables (Cloudflare dashboard)

| Variable | Value |
|---|---|
| `API_URL` | `https://water-admin.adityathakur452007.workers.dev` |
| `OPS_API_URL` | `https://water-ops.adityathakur452007.workers.dev` |

Local dev keeps the `http://127.0.0.1:8000` fallback for both.

### 9.3 Code changes

| File | Change |
|---|---|
| `src/server/admin-api.ts` | `bindingFetch(path, init, bindingName = "WATER_API")`; admin calls pass default; `apiUrl()` stays admin URL |
| `src/server/admin-session.ts` | `apiUrl()` reads `API_URL` (unchanged name, new production value) |
| `src/server/vendor-api.ts` | call `bindingFetch(..., "OPS_API")`; fall back to `opsApiUrl()` |
| `src/server/vendor-session.ts` | login/refresh via ops URL/binding, not `callWorkerPublic` |
| new helper in `admin-api.ts` | `callOpsPublic(path, body)` mirroring `callWorkerPublic` |

No UI, route, or cookie changes. Cookie names and device ids stay the same.

### 9.4 Deploy order

Workers Builds deploys this app on push. The binding change and the two build variables must be updated in the same cutover step (section 11, step 4). If the new bindings are wrong, revert `wrangler.jsonc` and the variables and redeploy; `water` still serves everything until step 5.

---

## 10. Flutter apps and CI

### 10.1 Base URLs

| App | Default `SHODASHA_API_BASE` |
|---|---|
| `apps/user_app_donor` | unchanged: `https://water.adityathakur452007.workers.dev` |
| `apps/vendor_app` | `https://water-ops.adityathakur452007.workers.dev` |
| `apps/rider_app` | `https://water-ops.adityathakur452007.workers.dev` |

Only the default host changes; URL building, headers, refresh logic, and read cache stay untouched.

### 10.2 CI

`.github/workflows/release.yml` lines 72-83:

- vendor and rider `defines` → `--dart-define=SHODASHA_API_BASE=https://water-ops.adityathakur452007.workers.dev`
- donor stays on `water`.

Vendor/rider APKs must be rebuilt and redistributed before step 5. Old installs keep working while `water` still mounts ops routes.

### 10.3 Client caching

The donor app already has a 300 s TTL read cache (ADR-035). No change needed.

Vendor/rider have none. Add the same small TTL cache only for **public/reference GETs** used by their screens (route discovery is the hot one). Do not cache auth, stop mutations, or money reads. This is a follow-up item, not a blocker for the split.

---

## 11. Caching and D1 protection

The split does not reduce query count by itself. These are the changes that do.

### 11.1 Per-request query budget

Free tier allows **50 D1 queries per invocation**. Current request metrics already log `db_queries` and `db_roundtrips`.

- Add a test helper that asserts `db_queries <= 10` for the hot endpoints: `GET /v1/catalog`, `GET /v1/orders`, `GET /v1/vendor/route`, `GET /v1/admin/metrics`, `GET /v1/auth/me`.
- In production, log a warning when `db_queries > 25`; never fail the request.

### 11.2 Session lookup cache (biggest CPU win)

Every authenticated request currently performs one `sessions JOIN users` D1 read.

**Change:** in `app/api/auth_deps.py`, memoize the resolved session user for **10 seconds** per isolate, keyed by `sha256(token)`, capped at 4096 entries.

- Admin sessions: **not cached** (`role == "admin"` bypasses the memo) so admin revocation stays immediate and admin traffic is low.
- User/vendor/rider sessions: 10 s staleness ceiling for suspension and logout.
- `POST /auth/logout` evicts the entry in the current isolate.
- Env override `AUTH_SESSION_CACHE_TTL_S` (default `10`, `0` disables). Tests set `0` except the cache test itself.

This is a deliberate, documented weakening of the current "suspension re-read on EVERY request" rule from 0 s to ≤10 s. It must be recorded in `context/decision.md` if approved.

### 11.3 Public read memo (catalog / windows / serviceability)

`app/api/caching.py` currently emits `Cache-Control` + `ETag`, but the Worker still executes on every revalidation, and workers.dev has no zone-level Cache Rule.

**Change:** add a tiny per-isolate TTL memo (same shape as `health.py`) and wrap the three handlers:

| Route | TTL | Key |
|---|---|---|
| `GET /v1/catalog` | 300 s | `catalog` |
| `GET /v1/windows` | 300 s | `windows:{date}:{pincode}` (bounded cardinality already enforced) |
| `GET /v1/serviceability` | 300 s | `serviceability:{pincode}` |

Result: repeat reads cost a dict lookup instead of D1/settings work. ETag behavior stays.

### 11.4 Existing caches kept

- `/v1/admin/metrics`: 60 s per-isolate cache already exists — unchanged.
- `/health`: 5 s per-isolate cache already exists — unchanged.
- Donor app: 300 s read cache + single-flight — unchanged.

### 11.5 Things we will **not** do

- No second database, no read replica, no external cache service (all cost money or add a failure mode).
- No cross-Worker shared cache. Workers have no shared memory; pretending otherwise would be wrong.
- No cron on ops/admin.
- No background polling added on any surface.

### 11.6 Per-surface consequences to watch

- Three Workers mean three rate-limit silos: the in-memory anon throttle is per isolate per Worker. The auth rate limiter already uses D1 counters, so auth limits remain global.
- Cold starts multiply from one pool to three. Smaller per-surface bundles partly offset this.

---

## 12. Rollout — zero downtime, reversible

| Step | Action | State after |
|---|---|---|
| 0 | **Measure baseline**: `exceededCpu` count, p50/p99 CPU, D1 rows read, 5xx rate over 24 h. Save to `Feature_docs/worker-split/baseline.md`. | Known baseline |
| 1 | Implement factory/routers/entries/scripts, run all tests. **Do not redeploy `water`** — the currently live version keeps serving every route. | `water` unchanged |
| 2 | Deploy `water-ops` and `water-admin` (additive; no client points at them yet). Smoke `/health` + wrong-surface 404s. | 3 Workers live, clients still on `water` |
| 3 | Update admin web bindings + `API_URL`/`OPS_API_URL`, redeploy admin. Verify admin login, dashboard, vendor portal. | Admin web on new Workers |
| 4 | Build vendor/rider APKs against `water-ops`, distribute. Verify login, route, pickup, quality check. | Ops clients moved |
| 5 | Flip `water` to `create_app("customer")`, deploy. Verify admin/ops routes now 404 on `water` and still work on their hosts. | Full isolation |
| 6 | Measure again for 24-72 h, compare to baseline, record results. | Decision data |

Steps 1-4 are pure addition. Only step 5 removes routes from `water`.

---

## 13. Rollback

| Failure point | Rollback | Time |
|---|---|---|
| Step 2 (new Workers broken) | Delete/ignore them; nothing points there yet | 0 |
| Step 3 (admin web broken) | Revert `wrangler.jsonc` bindings + `API_URL`; redeploy admin. Or point `WATER_API` back to `water` | minutes |
| Step 4 (APKs broken) | Re-publish previous APKs (still point at `water`) | app-store/APK |
| Step 5 (isolation breaks a client) | Deploy `water` with `create_app("all")` again; old URLs work immediately | one deploy |
| D1 incident | No schema change was made; nothing to reverse | — |

Because all three Workers share the same code and DB, there is no data rollback scenario.

---

## 14. Acceptance criteria

### 14.1 Backend tests

- [ ] All existing 470 tests pass with `create_app()` (surface `all`).
- [ ] New `tests/test_surfaces.py`:
  - [ ] `create_app("customer")`: `/v1/catalog` 200; `/v1/vendor/...` 404; `/v1/admin/orders` 404; `/v1/auth/admin/login` 404.
  - [ ] `create_app("ops")`: `/v1/vendor/...` 401 (auth required, not 404); `/v1/rider/...` 401; `/v1/catalog` 404; `/v1/admin/orders` 404.
  - [ ] `create_app("admin")`: `/v1/admin/orders` 401; `/v1/refunds/x/claim` 401; `/v1/catalog` 404; `/v1/vendor/...` 404.
  - [ ] `create_app("all")` mounts the union.
- [ ] `tests/test_session_cache.py`: second identical authenticated request performs 0 session queries; TTL expiry re-queries; logout evicts; admin is never cached.
- [ ] `tests/test_query_budget.py`: hot endpoints stay within the section 11.1 budget.
- [ ] `ruff` clean, no new type errors.

### 14.2 Post-deploy smoke (manual, documented in results)

- [ ] `GET /health` 200 on all three hosts.
- [ ] Donor: login, catalog, windows, place order, view orders.
- [ ] Vendor: login, route, stop update, return pickup, quality check.
- [ ] Rider: login, route.
- [ ] Admin web: login, dashboard load, one read, one write, vendor portal login.
- [ ] Wrong-surface probe: `water` returns 404 for `/v1/admin/orders` and `/v1/vendor/route`; `water-admin` returns 404 for `/v1/catalog`.
- [ ] Razorpay webhook still reaches `POST https://water.../v1/webhooks/upi` (no config change).

### 14.3 Performance gate

Compare 24-72 h after step 5 against step 0:

| Metric | Pass | Investigate | Abort/rollback |
|---|---|---|---|
| `exceededCpu` rate | lower than baseline | equal | higher |
| p99 CPU per surface | lower | equal | higher |
| D1 rows read/day | lower | equal | higher |
| 5xx rate | lower | equal | higher |

If the split makes any metric worse, step 5 is reverted and the result is recorded. The split must not be presented as a CPU fix unless this table shows it.

---

## 15. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Admin app vendor portal breaks (wrong binding) | Medium | Admin can't manage vendors | Step 3 verification + revert binding |
| Vendor/rider APKs not updated before step 5 | Medium | Ops blocked | Only narrow `water` after APK distribution confirmed |
| 3× cold starts increase 1102 errors | Medium | Login still flaky | Measure; keep `water` surface `all` as fallback |
| Session cache allows ≤10 s stale suspension | Low | Policy deviation | Admin excluded; env-tunable; documented |
| Cron accidentally duplicated | Low | Duplicate subscription orders | ops/admin configs have no `triggers`; test asserts no `scheduled` handler |
| Config drift between three `wrangler` files (D1 id) | Low | Wrong DB | Comment + deploy checklist + `wrangler d1 list` check |
| 100k/day account quota | Certain if traffic grows | All Workers stop together | Not solvable by split; tracked separately |
| Secrets set on wrong Worker | Low | Feature silently disabled | Section 8 matrix + post-deploy smoke |

---

## 16. Out of scope (explicitly)

- Raising CPU limits, upgrading to Workers Paid, rewriting to TypeScript.
- Fixing the 10 ms ceiling (ADR-147/148 remain open; this spec does not close them).
- Changing auth semantics (rider login shape, OTP retirement, access codes).
- Splitting D1, adding read replicas, or moving money paths.
- Admin UI feature work.
- Revoking the pasted tokens (security task, tracked separately; recommended now).

---

## 17. Open questions (answer before approval)

1. **Session cache staleness** — approve a 10 s per-isolate session cache for user/vendor/rider (admin never cached), accepting up to 10 s delay before a suspension/logout takes effect on another isolate? Alternative: keep zero staleness and accept the current per-request D1 read.
2. **Staging Workers** — create `water-ops-staging` / `water-admin-staging` first (extra Workers, same D1 unless a staging DB is used), or go production-only with the staged cutover in section 12?
3. **Cutover confirmation** — confirm you can rebuild and redistribute vendor + rider APKs before step 5, and that you will update the admin app's Cloudflare build variables (`API_URL`, `OPS_API_URL`) in the same window.

---

## 18. Implementation task list (after approval)

1. `app/factory.py` + `app/main.py` shim; verify all 470 tests.
2. Split auth/payments/returns routers; add `test_surfaces.py`.
3. Add `entry_ops.py`, `entry_admin.py`; `wrangler.ops.jsonc`, `wrangler.admin.jsonc`; deploy scripts.
4. Add session memo + public read memo + query-budget tests.
5. Deploy `water` (surface all), then `water-ops`, `water-admin`; smoke.
6. Update admin app bindings/URLs; deploy; smoke.
7. Update vendor/rider defaults + CI; rebuild APKs.
8. Flip `water` to customer-only; wrong-surface probes; measure for 24-72 h.
9. Update `context/flow.md`, `context/decision.md`, `context/progress-tracker.md`; write `Feature_docs/worker-split/results.md`.

---

## 19. Approval

Reply with answers to section 17 and an explicit **"approved"** to start implementation. No file outside this spec and the context docs will be modified before that.
