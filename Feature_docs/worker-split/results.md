# Worker Split — Implementation Results

Status: **steps 1–2 complete** (code + two new Workers live). Step 5 (`water` customer-only) pending client cutover.
Date: 2026-11-14
Branch: `045-worker-split-surfaces` (not merged to `main`)
Spec: `Feature_docs/worker-split/spec.md`
ADR: `context/decision.md` ADR-191

---

## 1. What shipped on this branch

| Area | Change |
|---|---|
| App factory | `src/app/factory.py::create_app("all"\|"customer"\|"ops"\|"admin")`. `"all"` preserves the exact pre-split route set. `src/app/main.py` is now a 2-line shim. |
| Entrypoints | `src/entry.py` → `create_app("customer")` + `scheduled()`; new `src/entry_ops.py`, `src/entry_admin.py` (no cron). |
| Routers | `auth.py`: `shared_router` / `customer_router` / `ops_router` / `admin_router` + aggregate `router`. `payments.py`: `router` + `admin_router` (3 refund writes). `returns.py`: `router` + `ops_router` (pickup). Paths and handlers unchanged. |
| Caching | `app/core/memo.py` per-isolate TTL memo. 300 s for catalog / windows / serviceability. 10 s session memo in `auth_deps.py` for user/vendor/rider; admin bypasses; logout evicts; `AUTH_SESSION_CACHE_TTL_S=0` disables. |
| Worker configs | `wrangler.ops.jsonc` (`water-ops`), `wrangler.admin.jsonc` (`water-admin`). Same D1 id, same compatibility flags, **no cron**. |
| Scripts | `package.json`: `deploy:ops`, `deploy:admin`, `dev:ops`, `dev:admin`. |
| Admin BFF | `WATER_API` binding → `water-admin`; new `OPS_API` binding → `water-ops`; `bindingFetch(path, init, bindingName)`; new `callOpsPublic`; `opsApiUrl()`. Vendor portal (`vendor-api.ts`, `vendor-session.ts`) moved to ops. |
| Flutter / CI | Vendor + rider defaults and `release.yml` point at `https://water-ops.adityathakur452007.workers.dev`. Rider CI no longer appends a second `/v1`. Donor unchanged (`water`). |
| Tests | `tests/test_surfaces.py` (surface isolation / wrong-surface 404), `tests/test_caching_045.py` (session + catalog memo), `test_payments.py` / `test_vendor.py` mount the moved routers. |

---

## 2. Verification

| Check | Result |
|---|---|
| `uv run pytest -q` | **512 passed, 1 skipped** |
| `ruff check` on changed files | Clean — all checks passed |
| `wrangler deploy --dry-run --config wrangler.ops.jsonc` | Clean |
| `wrangler deploy --dry-run --config wrangler.admin.jsonc` | Clean |
| `flutter analyze` (vendor) | No issues |
| `flutter analyze` (rider) | No issues |
| `npx tsc --noEmit` (admin) | Only pre-existing errors in unrelated dashboard/fixture files |
| Surface snapshot | customer 43 paths / ops 34 / admin 70 / all 139. Customer has no `/v1/vendor`, `/v1/rider`, `/v1/admin`, `/v1/refunds`, pickup. |

---

## 3. Deployments

| Worker | Version ID | URL | Secrets |
|---|---|---|---|
| `water-ops` | `732212ef-7525-488e-8feb-c35dc87afcd6` | https://water-ops.adityathakur452007.workers.dev | none (only `APP_ENV`, `FIREBASE_PROJECT_ID`, DB) |
| `water-admin` | `adf32d10-2c7b-4f79-9a49-a35b9bc793e2` | https://water-admin.adityathakur452007.workers.dev | none (only `APP_ENV`, `FIREBASE_PROJECT_ID`, DB) |
| `water` | **unchanged** — still the old all-routes build | https://water.adityathakur452007.workers.dev | existing money/OTP secrets remain |

Both new Workers bind D1 `shodasha` (`da762aad-1d5c-46eb-992e-acc79505cc95`). Worker startup time reported ~2.8–2.9 s; watch Free-tier cold start / 1102 after traffic moves.

### Live smoke (2026-11-14)

| Probe | Result |
|---|---|
| `GET water-ops /health` | 200 |
| `GET water-admin /health` | 200 |
| `GET water-ops /v1/catalog` | 404 |
| `GET water-ops /v1/admin/orders` | 404 |
| `POST water-ops /v1/auth/vendor/login` | 400 (validation, route exists) |
| `GET water-admin /v1/catalog` | 404 |
| `GET water-admin /v1/vendor/duty` | 404 |
| `GET water-admin /v1/admin/orders` | 401 (auth required, route exists) |
| `POST water-admin /v1/auth/admin/login` | 400 (validation, route exists) |

Isolation works on the live hosts: routes owned by one surface are absent (404) on the others, and owned routes are reachable (401/400 rather than 404).

---

## 4. Remaining cutover (do in this order)

1. **Admin app**: set Cloudflare build variables `API_URL=https://water-admin.adityathakur452007.workers.dev` and `OPS_API_URL=https://water-ops.adityathakur452007.workers.dev`, then redeploy `shodasha-admin` from `wrangler.jsonc` (bindings `WATER_API` → `water-admin`, `OPS_API` → `water-ops`). Verify admin login/dashboard/one read/one write and vendor portal login.
2. **Vendor + rider APKs**: build from this branch (defaults / CI now point at `water-ops`) and distribute. Verify vendor login, route, stop update, pickup, quality check; rider login and route.
3. **Narrow `water`**: deploy `water` with `create_app("customer")` (`npm run deploy`). Then probe:
   - `water /v1/admin/orders` → 404
   - `water /v1/vendor/duty` → 404
   - donor login, catalog, windows, place order, orders still 200
   - Razorpay webhook still reaches `POST https://water.../v1/webhooks/upi`
4. **Measure 24–72 h** vs baseline: `exceededCpu`, p99 CPU per surface, D1 rows read/day, 5xx rate. Record in this file.

Only step 3 removes routes from `water`; steps 1–2 are additive and can be reverted independently.

---

## 5. Rollback

| Failure | Action |
|---|---|
| Admin app broken after redeploy | Revert `apps/admin_app/wrangler.jsonc` bindings + `API_URL`, redeploy. Or point `WATER_API` back to `water`. |
| New APKs broken | Re-publish previous APKs (they still point at `water`, which still serves every route). |
| `water` customer-only breaks a client | Deploy `water` with `create_app("all")` again. One deploy, no data change. |

No D1 migration was added, so there is nothing to reverse at the database layer.

---

## 6. Notes / watch items

- Session memo relaxes suspension/logout propagation from per-request to ≤10 s per isolate (admin excluded). Tune with `AUTH_SESSION_CACHE_TTL_S`.
- Three Workers = three cold-start pools and three in-memory anon-throttle silos; auth rate limits stay global (D1 counters).
- Splitting Workers does not raise the 10 ms CPU limit or the 100k/day account quota (ADR-147/148 remain open).
- `water-admin` and `water-ops` intentionally have no money secrets; if a future route needs one, add it to that Worker only.
