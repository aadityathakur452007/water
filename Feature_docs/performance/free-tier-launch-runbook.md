# Free-tier launch runbook — pilot operations

**Status:** **APPROVED by the owner on 2026-10-26 (G0)** as the companion to the Free-tier launch-readiness spec. **Execution result (2026-10-26): NO-GO on Free.** G1 and G7 were executed, G2/G3/G4 failed, and G5 was not started. Production was rolled back to `511879dc`; migration 029 remains. The runbook is retained as the record of the executed gates and the Paid upgrade path.

**Spec:** `2026-10-26-free-tier-launch-readiness-spec.md`
**Parent evidence:** `2026-10-25-1000-user-capacity-audit.md`, `2026-10-25-phase0-results.md`, `2026-10-26-phase2-results.md`, `2026-10-26-phase3-ab-validation-spec.md`
**Production:** `water` / `shodasha` — **read-only** after the G2 rollback. No load test, write, migration, or deploy without explicit approval. Migration 029 is applied; the active code is the pre-G1 version `511879dc`.
**Owner:** daily checklist, alert response, pilot communications, upgrade decision.
**Agent:** docs and read-only probes only when asked; never writes production.

---

## 0. Read this first

This runbook supports three possible outcomes:

| Outcome | What runs | What must be true |
|---|---|---|
| **A. Read-only canary** | `/health` + public GETs at low rate | G0, G1, G2, G5, G7 pass |
| **B. Transactional pilot** | Login/register, COD orders, reads, cancel/reschedule, vendor PoD; no UPI, no new subscriptions | All gates pass, including separately approved G3 and G4 |
| **C. NO-GO** | Nothing customer-facing | G2/G3/G5 fails, or the envelope is not accepted |

**Default until evidence exists: NO-GO for a transactional pilot.** Free is a temporary low-traffic bridge, not a 1,000-user capacity target.

### Hard safety rules

1. **No production writes.** No login, registration, order, payment, admin, vendor, cron trigger, or SQL write against `water` / `shodasha` in this phase.
2. **No load test against production.** The only production traffic is the read-only probes in §3 and the external uptime monitor.
3. **No secrets anywhere.** Never print, commit, or paste tokens, passwords, phones, UPI ids, raw headers, client IPs, or raw `wrangler tail` dumps. Raw tails go outside the repo and are deleted after sanitized parsing.
4. **No traces.** Production `observability.traces.enabled` stays `false`. Do not enable traces for a pilot incident.
5. **No config drift without approval.** Changing `OBS_LOG_SAMPLE_RATE`, cron, bindings, or vars requires a deploy and separate approval.
6. **No D1 restore without approval.** Time Travel is 7 days on Free; a restore can lose writes made after the restore point.
7. **Stop beats diagnose.** On a customer-facing `1102`/`1101`, pause the pilot first, then investigate.
8. **The Worker has no application kill switch.** Rollback is the fastest safe stop.

---

## 1. Gate status

Fill this in only from recorded evidence. Do not mark a gate green from memory.

| Gate | Requirement | Status | Evidence |
|---|---|---|---|
| **G0** | Spec approved by owner | **Passed** | Owner approval 2026-10-26 |
| **G1** | Production backup + migration 029 + Phase 1A/1B/2 deploy | **Completed, rolled back** | Backup 96,430 bytes / SHA256 `CB7A399F…5B900A`; 029 applied (19 statements, 10.30 ms; 28 records); deploy `f3778132`; rolled back to `511879dc` |
| **G2** | Read-only production smoke | **FAILED** | 20 probes: 18×200, 1×503 `exceededResources`/1102, 1×500 `scriptThrewException`; catalog/windows 200 |
| **G3** | Free auth proof (staging) | **FAILED** | 1 registration + 5 logins all 200; CPU p99 **1,269.746 ms** vs ≤8 ms; wall 1.70–4.68 s |
| **G4** | Free cron proof (staging) | **FAILED** | 0-due `db_roundtrips=19`; 3-due `db_roundtrips=46` vs ≤45; 3 processed / 3 created / 0 failed; next tick 0 due |
| **G5** | Alerts configured and tested | **Not started** | No pilot possible after G2/G3/G4 failed; owner email destination unnamed |
| **G6** | Pilot envelope accepted | **Accepted** | Owner approval 2026-10-26 |
| **G7** | Rollback ready | **Passed** | Pre-G1 version `511879dc` recorded; rollback executed; `/health`, catalog, windows re-verified 200 |

Gate rules (from spec §8):

- **G2 fails** → read-only canary is NO-GO; upgrade to Paid.
- **G3 fails** → transactional pilot is NO-GO; read-only canary may still proceed. Login/registration stay closed.
- **G4 fails** → transactional pilot only with subscriptions disabled; no auto-delivery promise. If the cron tick itself `1102`s, treat it as a Free CPU failure.
- **G5 or G7 fails** → no pilot.
- **G6 fails** → no pilot.

---

## 2. Pre-flight after G1 approval

Run from `workers/api`. These commands are read-only except where marked **G1 (approved)**. Do not run the deploy or migration from this runbook without the separate G1 approval.

### 2.1 Record the deployed version

```powershell
npx wrangler whoami
npx wrangler deployments list --name water
```

Record:

- Account name and Worker `water`.
- Active version ID and creation time (UTC).
- Previous version ID (for rollback).
- Deployed commit SHA (`git rev-parse HEAD`) and whether the working tree is clean.

### 2.2 Confirm schema and config

```powershell
npx wrangler d1 migrations list shodasha --remote
npx wrangler d1 execute shodasha --remote `
  --command "SELECT COUNT(*) AS migrations FROM d1_migrations"
```

Expected: no migrations to apply, count **29**. If the count is 28, stop; the deploy is incomplete.

Confirm in `wrangler.jsonc` production:

- `APP_ENV=prod`
- `crons: ["*/15 * * * *"]`
- `observability.logs.enabled=true`, `head_sampling_rate=1`, `invocation_logs=true`
- `observability.traces.enabled=false`
- App log sample `OBS_LOG_SAMPLE_RATE` at its recorded value (default `0.05`); 4xx/5xx/slow always log.

### 2.3 Confirm the read-only surface

```powershell
curl.exe -sS -i https://water.adityathakur452007.workers.dev/health
curl.exe -sS -o NUL -w "catalog %{http_code} %{time_total}s`n" `
  https://water.adityathakur452007.workers.dev/v1/catalog
curl.exe -sS -o NUL -w "windows %{http_code} %{time_total}s`n" `
  https://water.adityathakur452007.workers.dev/v1/windows
```

Expected: `/health` returns `200` with exactly `{"status":"ok"}` and `Cache-Control: no-store`; catalog/windows return `200`. If any is 5xx or `1102`/`1101`, do not start the pilot.

### 2.4 Record D1 baseline

Read-only counts (no phones, tokens, or UPI ids):

```powershell
npx wrangler d1 execute shodasha --remote `
  --command "SELECT (SELECT COUNT(*) FROM users) AS users, (SELECT COUNT(*) FROM orders) AS orders, (SELECT COUNT(*) FROM subscriptions) AS subs, (SELECT COUNT(*) FROM stops) AS stops"
```

Record the counts and database size from the D1 dashboard. Do not re-seed production.

---

## 3. Read-only production smoke (G2)

Authorized scope: `/health` plus public GETs. **No auth, no writes, no load test.**

### 3.1 Twenty health probes over ten minutes

```powershell
$out = Join-Path $env:TEMP "shodasha-health-$(Get-Date -Format yyyyMMddTHHmmssZ).csv"
1..20 | ForEach-Object {
  $r = curl.exe -sS -o NUL -w "%{http_code},%{time_total}" `
    https://water.adityathakur452007.workers.dev/health
  "$(Get-Date -Format o),$r" | Add-Content $out
  if ($_ -lt 20) { Start-Sleep -Seconds 30 }
}
Import-Csv $out -Header ts,code,seconds |
  Group-Object code |
  Select-Object Name,Count
```

**Pass:** all 20 are `200`, no `503`, no `1102`/`1101`. `/health` caches per isolate for 5 s, so 30 s spacing avoids reading the same cached result.

If a probe fails, capture only the status and body prefix (no headers):

```powershell
curl.exe -sS https://water.adityathakur452007.workers.dev/health
```

Record the timestamp (UTC), status, body, and trace id if the body includes one. Do not paste request headers or IPs.

### 3.2 Public GETs

```powershell
curl.exe -sS -o NUL -w "catalog %{http_code} %{time_total}s`n" `
  https://water.adityathakur452007.workers.dev/v1/catalog
curl.exe -sS -o NUL -w "windows %{http_code} %{time_total}s`n" `
  https://water.adityathakur452007.workers.dev/v1/windows
```

**Pass:** both `200` with the expected shape. `/v1/windows` with no query parameters returns today’s windows; do not add a phone, token, or pincode from a real user.

### 3.3 Probe budget

The smoke is 20 health probes + 2 public GETs. The external monitor adds ~288 requests/day at a 5-minute interval. Total probe traffic is <500 requests/day, negligible against 100,000.

### 3.4 G2 result

| Field | Value |
|---|---|
| Date/time UTC | 2026-10-26, 08:53:34–09:03:58 (20 probes at 30 s) |
| Worker version ID | `f3778132-fcd4-4ee2-9ccc-f1de9984b12f` |
| Health 200 / 503 / 1102 / 1101 | **18 / 1 / 1 / 0** |
| Health 500 | **1** (`scriptThrewException`) |
| Catalog status | 200 |
| Windows status | 200 |
| Decision | **FAIL** |

Failure timestamps: 503 at `08:53:34Z` (`exceededResources`, code 1102, CPU 2,020,000 µs); 500 at `08:54:39Z` (`scriptThrewException`, CPU 2,190 µs). The production deployment was rolled back to `511879dc` after this result; `/health`, `/v1/catalog`, and `/v1/windows` returned 200 on the rollback target.

**G2 fails** → Free read-only canary is NO-GO. Record it and recommend Workers Paid.

---

## 4. Alerts and monitoring (G5)

### 4.1 What must be monitored

| Signal | Source | Warn | Critical |
|---|---|---:|---:|
| Requests/day | Workers metrics | 5,000 | 8,000 |
| D1 rows written/day | D1 metrics | 5,000 | 8,000 |
| CPU p99 | Workers metrics | 5 ms | 8 ms |
| D1 round trips/invocation | Structured logs `db_roundtrips` | 40 | 45 |
| D1 size | D1 dashboard | 250 MB | 400 MB |
| Workers Log events/day | Workers Logs | 100,000 | 160,000 |
| 5xx rate | Workers metrics / logs | 0.5% / 15 min | 2% / 5 min |
| `/health` non-200 | External monitor | 1 in 15 min | 2 consecutive |
| Cron failed invocation | Cron log summary | 1 tick | 2 consecutive |
| Auth `1102`/`1101` | Logs | any | any |
| D1 error/overloaded | Logs / dashboard | any | any |

The 50%/80% rule applies to the lower of the Free hard limit and the pilot cap. The pilot cap is the number in the table.

**Metric note:** use **`db_roundtrips`** for the Free 50-query cap. `db_queries` counts statements inside a batch and is a CPU/latency diagnostic. A batch of 16 statements is one round trip but 16 `db_queries`.

### 4.2 Cloudflare Alerts setup

1. Dashboard → **Observability → Alerts**.
2. Verify the owner email destination and send a test notification. **Do not claim an alert exists until the test email arrives.**
3. Review **Platform Notifications** for the Workers and D1 notifications available on the Free plan. Enable the ones that map to the signals in §4.1. Do not enable anything that requires a paid plan.
4. Open **Monitors** and check whether the Workers/D1 datasets are selectable on this Free account.
   - If yes: create threshold monitors for the §4.1 signals. Record monitor name, dataset, query, threshold, and destination.
   - If no: use the external uptime monitor plus the daily checklist. Record “Monitors unavailable on Free” as the reason; do not fabricate a monitor.
5. Leave **traces off**. Do not change log sampling or deploy a config change to make alerts work without separate approval.

**Free-plan caveat:** Cloudflare Alerts can deliver email on all plans, but Workers/D1 SQL API dataset availability for Monitors on Free must be verified in the dashboard. The fallback is not optional: an external `/health` uptime monitor plus the daily checklist.

### 4.3 External uptime monitor (fallback and primary health alert)

Use any external monitor the owner already trusts (for example, a hosted uptime service):

- URL: `https://water.adityathakur452007.workers.dev/health`
- Method: `GET`
- Interval: 5 minutes
- Alert after: 2 consecutive failures
- Timeout: 10 s
- Destination: owner email (and phone/SMS if the service supports it)
- Expected response: `200`; treat any `503` or body containing `1102`/`1101` as a failure

Send a test alert before launch. Record the monitor name, interval, and test result. Do not point the monitor at auth, order, admin, or vendor routes.

### 4.4 Log checks

Workers Logs retention is 3 days on Free. Use the dashboard filters; do not run a sustained `wrangler tail` against production. For a short diagnosis window:

```powershell
$tail = Join-Path $env:TEMP "shodasha-tail-$(Get-Date -Format yyyyMMddTHHmmssZ).jsonl"
npx wrangler tail water --format json *> $tail
```

Stop with `Ctrl+C` after a few minutes. Keep only `route`, `status`, `duration_ms`, `db_queries`, `db_roundtrips`, `db_rows_read`, `db_rows_written`, `trace_id`, `env`. Drop headers, IPs, tokens, phones, bodies, and query strings. Delete the raw JSONL after writing the sanitized summary outside the repo.

---

## 5. Daily owner checklist (10 minutes)

Run once per day during the pilot, at roughly the same time. Record the numbers in §8. Use UTC for the day boundary so it matches Cloudflare metrics.

1. `/health`: any non-200, `503`, `1102`, or `1101` in the last 24 h?
2. Requests today vs the **10,000** pilot cap; 5,000 warn / 8,000 critical?
3. D1 rows written today vs the **10,000** pilot cap.
4. CPU p50/p95/p99; any invocation status “Exceeded resources”?
5. D1 round trips per invocation (p99/max); any route ≥40?
6. 5xx rate and top failing routes.
7. Cron: last tick summary, due backlog, `due_failed`, duration, `db_roundtrips`.
8. Auth: login/register failures — only if G3 passed.
9. D1 size and growth trend.
10. Workers Log events/day; if ≥100k, plan to lower `OBS_LOG_SAMPLE_RATE` (config change + deploy, separate approval).

**Decision each day:** continue / pause invites / pause pilot / upgrade. Record it. “No data” is not a pass.

---

## 6. Incident playbooks

### 6.1 `1102` / `1101` on `/health`, auth, cron, or an order path

1. **Pause the pilot** (stop invites; tell pilot users the service is paused).
2. Record UTC time, route, status, body prefix, and trace id. No headers or IPs.
3. Check Workers metrics for CPU and invocation status; check Cloudflare status.
4. If a deploy immediately preceded it, roll back (§7). If not, the Free 10 ms CPU ceiling is the likely cause.
5. Do not retry a login burst or a load test to “confirm.” One repeat probe is enough.
6. Decision: **NO-GO for the affected path**; recommend Workers Paid and Phase 3P.

### 6.2 5xx spike or `/health` 503 twice consecutively

1. Pause the pilot.
2. Check D1 status and the D1 dashboard for errors/overload.
3. Check the last deploy time and version ID.
4. Roll back if deploy-related; otherwise inspect the failing route’s logs (sanitized).
5. Re-run the §3 smoke after recovery.
6. Record the incident and the decision.

### 6.3 D1 error / writes failing repeatedly

1. Stop writes: pause the pilot and tell users not to retry payments or orders.
2. Do not attempt a D1 restore without owner approval.
3. Check D1 size, rows written today, and Time Travel bookmark.
4. If writes are failing because of the daily row limit, the pilot is over for the day; record it and plan the upgrade.
5. If data may be inconsistent, preserve the bookmark and escalate before any restore.

### 6.4 Auth failures (only if G3 passed)

1. Pause login/registration; keep read-only canary if it is healthy.
2. Check for `1102`/`1101` on `/v1/auth/*` and CPU p99.
3. If CPU-bound, do not retry a burst; disable auth for the pilot and upgrade.
4. Record status, route, timestamp, and trace id. Never record passwords or tokens.

### 6.5 Cron failed invocation

1. Check the cron log summary and Cloudflare errors.
2. If one tick failed, wait for the next tick and confirm recovery; do not manually trigger a burst.
3. If two consecutive ticks fail, pause subscriptions operationally (no new auto-delivery promises) and investigate.
4. Disabling the cron trigger is a config change + deploy; it needs separate approval. Rollback is the stop mechanism if the failure is deploy-related.
5. If the tick itself `1102`s, treat it as a Free CPU failure: transactional pilot is NO-GO.

### 6.6 Money-path inconsistency (double charge, missing order, wrong state)

1. Pause the pilot immediately; stop new orders and payments.
2. Preserve evidence: order id, timestamps, state transitions, trace ids. No tokens, phones, or raw bodies.
3. Do not “fix” data with ad-hoc SQL. Preserve the D1 bookmark and escalate.
4. UPI is out of scope for the Free pilot; if a UPI path was used, that is an out-of-envelope event.
5. Owner decides on user communication and whether a restore is needed. Restore requires explicit approval.

### 6.7 Request or row-write volume ≥80% of the pilot cap

1. Pause new invites.
2. Identify the top routes and write paths from logs/metrics.
3. Do not raise the cap silently. The pilot cap exists to preserve burst headroom below the Free hard limit.
4. Decide: throttle operationally (pause features), or upgrade to Paid.

### 6.8 Log volume ≥160k events/day

1. Lower `OBS_LOG_SAMPLE_RATE` only with approval; it requires a deploy.
2. Keep 4xx/5xx/slow logging; do not silence errors to save quota.
3. Record the old/new value and the version ID.

---

## 7. Rollback

### 7.1 Before any deploy

Record:

- Current version ID and creation time.
- Deployed commit SHA.
- D1 migration count (29).
- D1 bookmark and size.
- Pre-deploy D1 export path, size, and SHA256 (outside the repo).

**G1 backup (read-only export; run only with G1 approval):**

```powershell
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
npx wrangler d1 export shodasha --remote `
  --output "$env:TEMP\shodasha-pre-launch-$stamp.sql"
Get-FileHash "$env:TEMP\shodasha-pre-launch-$stamp.sql" -Algorithm SHA256
```

Record the path, size, and SHA256. Do not commit the export.

### 7.2 Roll back a bad deploy

1. Dashboard → **Workers & Pages → water → Deployments** → select the previous version → **Rollback**.
2. CLI equivalent, only after verifying the version ID:

   ```powershell
   npx wrangler rollback <previous-version-id>
   ```

3. Migration 029 is additive; a code rollback should not require a DB rollback. Do **not** restore D1 unless the migration itself is implicated.
4. Re-run the §3 read-only smoke and record the result.
5. If rollback does not restore service, pause the pilot and escalate to Workers Paid / Cloudflare support.

### 7.3 D1 restore (last resort)

1. Requires explicit owner approval.
2. Prefer Time Travel within the 7-day Free window; otherwise use the pre-deploy export.
3. A restore can lose writes made after the restore point. State that to the owner before proceeding.
4. After restore, verify migration count, row counts, `/health`, and the read-only smoke.
5. Record the bookmark/restore point and the approval.

### 7.4 Communication

- Owner notifies pilot users via the existing WhatsApp/support channel.
- State what is unavailable, what data is safe, and when the next update will come.
- Never include tokens, phone numbers, raw headers, or D1 dumps.

---

## 8. Evidence tables

### 8.1 Gate evidence

| Date (UTC) | Gate/run | Version / commit | Result | Evidence location | Decision |
|---|---|---|---|---|---|
| 2026-10-26 | G1 deploy + migration 029 | `f3778132` / `787446b` | Backup + 029 + deploy OK; rolled back after G2 | Spec §3.2/§8; backup SHA256 in spec §8 | Completed, rolled back |
| 2026-10-26 | G2 read-only smoke | `f3778132` | 18×200, 1×503/1102, 1×500; catalog/windows 200 | §3.4 above; sanitized CSV outside repo | **FAIL** |
| 2026-10-26 | G3 auth probe | staging (pre-G4, cron off) | 6/6 HTTP 200; CPU p99 1,269.746 ms vs ≤8 ms | Table 8.1a | **FAIL** |
| 2026-10-26 | G4 cron probe | staging `93cb3daa` | 3 created / 0 failed / zero missed; `db_roundtrips=46` vs ≤45 | Table 8.1a | **FAIL** |
| 2026-10-26 | G5 alerts tested | — | Not started; no pilot possible | — | Not started |
| 2026-10-26 | G7 rollback ready | `511879dc` | Rollback executed; three production GETs 200 | Spec §3.2 | **PASS** |

#### 8.1a Measured gate detail (sanitized)

**G3 auth (staging, 1 registration + 5 logins, all HTTP 200):**

| CPU bucket (µs) |
|---:|
| 423,518 |
| 432,819 |
| 691,975 |
| 465,223 |
| 1,269,746 |
| 824,734 |

p99 = **1,269,746 µs = 1,269.746 ms**; gate ≤8 ms. Wall time across the six requests was **1.70–4.68 s**; all returned HTTP 200 and none returned `1102`. Synthetic staging user and credentials were deleted; no token or phone is recorded here.

**G4 cron (staging):**

| Tick | Due | Processed | Created | Failed | `db_roundtrips` | Duration | Outcome |
|---|---:|---:|---:|---:|---:|---:|---|
| 0 due | 0 | 0 | 0 | 0 | 19 | 5,896 ms | Ok |
| 3 due | 3 | 3 | 3 | 0 | **46** | 11,497 ms | Ok |
| next tick | 0 | 0 | 0 | 0 | — | — | Ok |

Zero missed: staging orders went 10,006 → 10,009, all three subscriptions advanced to `2026-10-27`, and the next tick saw 0 due. A second 0-due tick in the same window used `db_roundtrips=19` and 1,645 ms (warm). No `1102`. The gate fails only on `db_roundtrips` (46 > 45). Temporary 1-minute cron was removed; staging schedules are empty at version `47dd50cc`.

### 8.2 Daily checklist

| Day | Date (UTC) | Requests | Rows written | CPU p99 | Max roundtrips | 5xx % | Health fails | Cron fails | D1 MB | Log events | Decision |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | | | | | | | | | | | |
| 2 | | | | | | | | | | | |
| 3 | | | | | | | | | | | |
| 4 | | | | | | | | | | | |
| 5 | | | | | | | | | | | |
| 6 | | | | | | | | | | | |
| 7 | | | | | | | | | | | |

### 8.3 Incident log

| Date (UTC) | Signal | Route/scope | Duration | Action | Outcome | Follow-up |
|---|---|---|---|---|---|---|
| | | | | | | |

Sanitized only: no tokens, phones, headers, IPs, or raw bodies.

---

## 9. Approval checklist

- [x] Approve the spec (`2026-10-26-free-tier-launch-readiness-spec.md`) — **G0**, approved 2026-10-26.
- [x] Approve this runbook — approved 2026-10-26.
- [x] Approve the pilot envelope: 50 registered / 10 DAU / 5 concurrent; COD only; no UPI; no new auto-delivery subscriptions; vendor route ≤20 stops — approved 2026-10-26.
- [x] Approve the read-only production probes in §3 — approved 2026-10-26.
- [x] Approve the alert plan in §4 — approved 2026-10-26; owner email destination still to be recorded at G5.
- [x] Approve the staging auth probe (G3) — approved and executed 2026-10-26; **failed**.
- [x] Approve the staging cron probe (G4) — approved and executed 2026-10-26; **failed**.
- [x] Approve the production deploy + migration 029 (G1) — approved and executed 2026-10-26; rolled back after G2.
- [x] Accept the rollback plan in §7 — approved 2026-10-26; exercised 2026-10-26.

**Execution result: NO-GO on Free.** G0 and G6 are approved; G1 and G7 executed; G2, G3, and G4 failed; G5 was not started. Do not run a pilot on Free. The next step is Workers Paid + Phase 3P.

---

## 10. Quick reference

| Item | Value |
|---|---|
| Production Worker | `https://water.adityathakur452007.workers.dev` |
| Production D1 | `shodasha` (`da762aad-1d5c-46eb-992e-acc79505cc95`) |
| Staging Worker | `https://water-staging.adityathakur452007.workers.dev` |
| Staging D1 | `shodasha-staging` (`05772775-a957-4852-8ec3-6b14082d4a62`) |
| Free requests/day | 100,000 |
| Free CPU/request | 10 ms |
| Free D1 queries/invocation | 50 |
| Free D1 rows written/day | 100,000 |
| Free D1 size | 500 MB |
| Free Time Travel | 7 days |
| Free Workers Logs | 200,000 events/day, 3-day retention |
| Pilot request cap | 10,000/day (warn 5,000 / critical 8,000) |
| Pilot write cap | 10,000 rows/day (warn 5,000 / critical 8,000) |
| Pilot CPU p99 | warn 5 ms / critical 8 ms |
| Pilot roundtrips | warn 40 / critical 45 |
| Pilot D1 size | warn 250 MB / critical 400 MB |
| Health check interval | 5 min, alert after 2 failures |
| Cron | `*/15 * * * *` (production; do not trigger manually) |

**Never commit:** tokens, passwords, phone numbers, raw headers, client IPs, `wrangler tail` dumps, D1 exports, or the contents of `data/phase0_tokens.json`.
