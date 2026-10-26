# Phase 3 runbook — A/B validation on staging

**Status:** Spec approved 2026-10-26. Plan only: do not run until Workers Paid is active on the account and the remaining prep approvals (harness, login, write probe, cron window) are granted.
**Spec:** `2026-10-26-phase3-ab-validation-spec.md`
**Parent audit:** `2026-10-25-1000-user-capacity-audit.md`
**Production:** read-only. No command in this runbook may target `water` or `shodasha`.

## 1. Safety rules

1. Target `water-staging` + `shodasha-staging` only. The harness refuses any host that is not loopback or does not contain `staging`, and refuses the production host explicitly.
2. No real money. The write probe uses COD create/cancel/reschedule only. It must refuse `/v1/payments/*`, `/v1/webhooks/*`, and every provider path.
3. No secrets in commands, logs, SQL, or commits. `data/phase0_tokens.json` is read-only and is never printed.
4. Raw `wrangler tail` output contains request headers and IPs. Write it outside the repo, parse it, then delete it. Commit only sanitized aggregates.
5. Abort a run if 5xx > 2% after at least 20 requests, overall p99 > 5 s, or D1 errors appear. The harness writes a partial result.
6. Stop immediately on `1102` / `1101` on a Paid Worker. Do not retry blindly; capture the trace and investigate.
7. Cron is off by default. Enable it only for the cron window and disable it immediately after.
8. Back up staging D1 before the write and cron probes. A restore needs explicit owner approval.
9. No production migration, deploy, write, or load test. Phase 3 does not change that.

## 2. Pre-flight

Run from `workers/api`.

### 2.1 Account and plan

```powershell
npx wrangler whoami
npx wrangler deployments list --env staging
```

Record:

- Account and Worker name.
- Active version ID and creation time.
- **Workers Paid confirmed** (dashboard -> Workers & Pages -> plan; the plan is account-level and applies to staging). If Free, stop; the run is invalid.

### 2.2 Code and schema

```powershell
git rev-parse HEAD
git status --short
npx wrangler d1 migrations list shodasha-staging --remote --env staging
npx wrangler d1 execute shodasha-staging --remote --env staging `
  --command "SELECT COUNT(*) AS migrations FROM d1_migrations"
```

Expected:

- Commit SHA recorded. Working tree clean, or every dirty file listed in the report.
- "No migrations to apply!" and migration count **29** (Phase 1A applied; Phase 2 adds none).

### 2.3 Health and config

```powershell
curl.exe -sS -i https://water-staging.adityathakur452007.workers.dev/health
```

Expected: `200` with exactly `{"status":"ok"}` and `Cache-Control: no-store`.

Confirm in `wrangler.jsonc` staging:

- `APP_ENV=staging`
- `OBS_LOG_SAMPLE_RATE=0.1` (raise to `1` for the run window)
- `OBS_SLOW_MS=750`
- `THROTTLE_ANON_PER_MIN=100000`
- `crons: []`

Record the exact values in the report. Do not print secret values.

### 2.4 Data and tokens

```powershell
Test-Path data/phase0_tokens.json
```

Read-only counts (staging only; no phones, tokens, or UPI ids):

```powershell
npx wrangler d1 execute shodasha-staging --remote --env staging `
  --command "SELECT (SELECT COUNT(*) FROM users) AS users, (SELECT COUNT(*) FROM orders) AS orders, (SELECT COUNT(*) FROM subscriptions) AS subs, (SELECT COUNT(*) FROM stops) AS stops"
```

Record the counts. Do not re-seed unless the counts are wrong; the seed exceeds the Free daily write limit.

### 2.5 Backup

```powershell
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
npx wrangler d1 export shodasha-staging --remote --env staging `
  --output "$env:TEMP\shodasha-staging-pre-phase3-$stamp.sql"
```

Record the path, size, and SHA256. Keep it outside the repo. If the export fails, stop.

### 2.6 Log sampling

For the run window, set staging `OBS_LOG_SAMPLE_RATE=1`, deploy, and record the new version:

```powershell
npx wrangler deploy --env staging
```

This changes only a var, not the code. Restore `0.1` after the last run and deploy again. If log volume is a problem, keep `0.1` and state in the report that D1 query percentiles are sampled; do not silently mix rates.

### 2.7 Harness readiness

After the harness change is approved and committed locally:

```powershell
python -m pytest -q tests/test_bench_guard.py
python scripts/bench_phase0.py --help
```

The harness must prove:

- It refuses the production host.
- It refuses `--allow-writes` unless the target contains `staging`.
- It refuses provider paths in write mode.
- It writes a partial result on abort.
- It never serializes bearer tokens, passwords, or credential files.

### 2.8 Login credentials

The Phase 0 seed leaves `users.password_hash` empty, so the seeded tokens cannot log in. Prepare 90 dedicated synthetic users before the login probe.

```powershell
python scripts/prep_phase3_logins.py `
  --count 90 `
  --sql "$env:TEMP\phase3-logins-$stamp.sql" `
  --credentials "$env:TEMP\phase3-login-credentials-$stamp.json"
```

The script must:

- use `app.core.passwords.hash_password` (PBKDF2-HMAC-SHA256, 100k, 16-byte salt, 32-byte key);
- insert users with `load3-login-<runid>-<n>` ids and synthetic phones;
- write passwords only to the temp credentials file;
- print counts, never passwords or hashes.

Inspect the SQL: only `INSERT INTO users` rows, no real phones, no tokens. Apply it once:

```powershell
npx wrangler d1 execute shodasha-staging --remote --env staging `
  --file "$env:TEMP\phase3-logins-$stamp.sql"
```

Verify with the harness smoke mode (status only; no token output):

```powershell
python scripts/bench_phase0.py `
  --base-url https://water-staging.adityathakur452007.workers.dev `
  --profile login --rate 0.1 --duration 10 `
  --credentials "$env:TEMP\phase3-login-credentials-$stamp.json" `
  --label phase3-login-smoke
```

If the prep script is not approved, the login probe is skipped and the login SLO is **not certified**. Do not use seeded tokens as a substitute.

## 3. Run order

Do not run A/B before the smoke and probes pass.

| # | Run | Duration | Purpose |
|---:|---|---:|---|
| 1 | Smoke | 5 min | Every route once; correctness |
| 2 | Login probe | 10 min | 90 logins; login SLO/CPU |
| 3 | Write probe | 10 min | 1.11 writes/s (0.37 create / 0.37 cancel / 0.37 reschedule); write SLO/D1 rows |
| 4 | A | 30 min | 50 concurrent; 2.5x burst |
| 5 | B | 30 min | 100 concurrent; 2.5x burst |
| 6 | Soak | 30 min | B average; stability |
| 7 | Cron 60 | one tick | per-tick CPU/statements |
| 8 | Cron 500/1,000 | drain window | backlog, zero missed |
| 9 | C (optional) | 60 min | knee only; not a gate |

Between runs, wait for the tail to flush and record the run ID. Do not overlap runs.

## 4. Tail and metrics capture

Start tail before each run in a separate terminal:

```powershell
$run = "phase3-a-$stamp"
npx wrangler tail --env staging --format json *> "$env:TEMP\phase3-tail-$run.jsonl"
```

Send a canary request with a known trace id:

```powershell
curl.exe -sS -H "X-Trace-Id: $run-canary" `
  https://water-staging.adityathakur452007.workers.dev/health
```

Stop tail with `Ctrl+C` after the run. Parse the JSONL outside the repo:

- Keep: `route`, `status`, `duration_ms`, `db_queries`, `db_roundtrips`, `db_rows_read`, `db_rows_written`, `trace_id`, `env`.
- Drop: headers, IPs, tokens, phones, bodies, query strings.
- Delete the raw JSONL after the sanitized aggregate is written.

CPU:

- Open Cloudflare dashboard -> Workers & Pages -> `water-staging` -> Metrics.
- Set the window to the run start/end (UTC).
- Record CPU p50/p95/p99. If p95 is unavailable, record p99 and mark p95 as not captured.
- Do not substitute local CPU or wall time for Worker CPU.

D1:

- Query counts and rows come from the structured logs.
- Record the D1 database size and bookmark before/after the write and cron probes.
- If `wrangler d1 insights` is available, record the query text hash and rows read; do not paste SQL with literals.

## 5. Smoke

```powershell
python scripts/bench_phase0.py `
  --base-url https://water-staging.adityathakur452007.workers.dev `
  --profile smoke --label phase3-smoke
```

Expected: every route 2xx (or the documented 4xx for a deliberate edge case), no 5xx, no 429. If the smoke fails, stop.

## 6. Login probe

Use the 90 dedicated synthetic users from §2.8, one login each, paced at 9/min. Do not exceed the 100/hr IP ceiling.

```powershell
python scripts/bench_phase0.py `
  --base-url https://water-staging.adityathakur452007.workers.dev `
  --profile login --rate 0.15 --duration 600 `
  --credentials "$env:TEMP\phase3-login-credentials-$stamp.json" `
  --label phase3-login
```

Record p50/p95/p99, 5xx, D1 queries, and CPU. A `429` means the probe pacing or user selection is wrong; fix and re-run, do not count it as capacity.

## 7. Write probe

```powershell
python scripts/bench_phase0.py `
  --base-url https://water-staging.adityathakur452007.workers.dev `
  --profile write --rate 1.11 --duration 600 `
  --tokens data/phase0_tokens.json --allow-writes --label phase3-write
```

Rules:

- One idempotency key per logical write; same key on retry; never reuse across payloads.
- COD create, cancel, reschedule only. No UPI intent, no webhook, no dues intent, no subscription intent.
- Split the 1.11/s: 0.37 create, 0.37 cancel, 0.37 reschedule. Each create adds one quote read; report it separately.
- A create is quote + order; the quote is counted as an authed read, not a write.
- Use only the probe-owned pool for cancel/reschedule (created in setup, prefix `load3-w-<runid>-pool-`); never cancel or reschedule seeded Phase 0 orders. Do not reuse an order after a terminal state.
- A `409 STATE_CONFLICT` from a deliberate cancel/reschedule race is recorded as an expected state conflict, not a 5xx.
- Prefix every synthetic order with `load3-w-<runid>-`.
- Record created/cancelled/rescheduled counts, quote count, and D1 rows written.

After the probe, verify one order end-to-end with a read (detail + list) and confirm no payment row was created.

## 8. Run A

```powershell
python scripts/bench_phase0.py `
  --base-url https://water-staging.adityathakur452007.workers.dev `
  --profile phase3-a --label phase3-a
```

The profile runs: 2 min warm-up at 0.70 rps, 10 min at 2.78 rps, 5 min at 6.94 rps, 10 min at 2.78 rps, 3 min ramp-down.

Record per-route and overall p50/p95/p99, 5xx, 4xx, D1 queries/roundtrips/rows, bytes. Exclude warm-up and ramp-down from the SLO table; report them separately.

## 9. Run B

```powershell
python scripts/bench_phase0.py `
  --base-url https://water-staging.adityathakur452007.workers.dev `
  --profile phase3-b --label phase3-b
```

Same timeline at 1.39 / 5.56 / 13.89 / 5.56 rps.

Do not start B until A's report is complete and A is GO or the failure is understood.

## 10. Soak

```powershell
python scripts/bench_phase0.py `
  --base-url https://water-staging.adityathakur452007.workers.dev `
  --profile phase3-soak --label phase3-soak
```

30 min at 5.56 rps, read/auth mix. Compare the first and last 10 minutes: p99 drift, 5xx drift, D1 latency, isolate recycling. A steady p99 increase or a growing error rate is a NO-GO even if the average is inside the gate.

## 11. Cron probe

### 11.1 Prepare the cohort

Use synthetic users/subs only, prefixed `load3-cron-<runid>-`. First record the **baseline** due count, then size the generating cohort so the total generating due count is exactly 60 / 500 / 1,000 (low-balance/pending subs are reported separately). Leave all other subs untouched.

```powershell
npx wrangler d1 execute shodasha-staging --remote --env staging `
  --command "SELECT COUNT(*) AS due FROM subscriptions WHERE status='active' AND canceled_at IS NULL AND next_run <> '' AND next_run <= date('now') AND (due_retry_at IS NULL OR due_retry_at <= datetime('now'))"
```

If the baseline is already at or above the target, record it and choose a larger target or wait for the baseline to drain; do not delete other subscriptions. Use active, funded, non-Sunday subs so the cohort generates; verify `processed` reaches the 60-row page. Low-balance and pending-payment subs are reported separately. Do not paste phone numbers or tokens.

### 11.2 One-page tick (60 due)

1. Enable `crons: ["*/15 * * * *"]` in staging `wrangler.jsonc`, deploy, record the version.
2. Start tail.
3. Wait for the next tick (note the UTC time).
4. Confirm the log line `due_subscriptions date=... progress=... created=... failed=...` and the `cron_tick` outcome.
5. Record statements, CPU, wall time, created/failed, backlog, and `next_run` advancement. If Cloudflare cannot separate cron CPU from HTTP CPU, record wall time and mark CPU **not captured**; the cron CPU gate is then not certified.
6. Disable cron (`crons: []`), deploy, verify.

### 11.3 500 / 1,000 backlog

If approved, repeat with the larger cohort and a `*/5` staging schedule for the drain window. Measure each tick; do not let cron run unattended.

For every tick, assert:

- `created + failed` matches `processed`; `low_balance` and `resumed` are reported separately (they are not in `processed`).
- No duplicate order for the same `sub:<id>:<date>` idempotency key.
- `next_run` advanced only after a successful create.
- A failed create leaves the sub due and backs off; the next tick replays the same key.
- The backlog decreases by the processed count.

Report the drain time at the production `*/15` schedule: `ticks x 15 min`, not the `*/5` test schedule. A 1,000-sub cohort at 60/tick is ~17 ticks (~4.25 h), which is within the owner's "delay tolerable" decision; state it explicitly.

### 11.4 After the cron window

- Disable cron and deploy.
- Re-check the due count and the created orders.
- Record the final backlog and any failures.
- Leave the synthetic orders in staging unless cleanup is explicitly approved.

## 12. C stress probe (optional)

Only with explicit owner approval for that run:

```powershell
python scripts/bench_phase0.py `
  --base-url https://water-staging.adityathakur452007.workers.dev `
  --profile phase3-c --allow-stress --label phase3-c
```

C finds the knee; it is not a launch gate. Record the first failure mode and the rps at which it appears. Do not use C to claim A/B certification. If the Python thread harness cannot sustain 1,000 VUs without client-side exhaustion, switch to k6 and record the tool change; do not report a client limit as a server limit.

## 13. Abort and recovery

Abort the run if:

- 5xx > 2% after at least 20 requests.
- Overall p99 > 5 s.
- D1 errors or `7500` quota errors.
- `429 RATE_LIMITED` in a read run.
- `1102` / `1101` on a Paid Worker.
- A P0 concurrency test fails.

Actions:

1. `Ctrl+C` the harness. It writes a partial result.
2. Stop tail.
3. Record the UTC time, run ID, last trace ID, and the failing route.
4. Do not retry until the cause is understood.
5. If the Worker is stuck, redeploy the same version; do not change code mid-run.
6. If staging data is corrupted, stop and ask the owner before restoring the backup.

## 14. Evidence packaging

Write to `Feature_docs/performance/results/`:

- `phase3-<profile>-<UTC>.json` and `.md` from the harness.
- `phase3-<runid>-summary.md` with sanitized tables.
- `phase3-<runid>-report.md` with the GO/NO-GO, cost estimate, and limitations.

The report must include:

- Run ID, UTC start/end, commit SHA, Worker version, migration count, Paid confirmation.
- Per-run and per-route p50/p95/p99, 5xx, 4xx, D1 queries/roundtrips/rows, CPU, bytes.
- Cron table: cohort, due, created, failed, missed, statements, CPU, wall, backlog.
- Cost estimate at B with assumptions.
- What was not measured: real adoption, production traffic, CDN cache, monthly availability, Flutter device performance.
- Owner signature and date.

Delete raw tail files. Do not commit tokens, headers, IPs, phones, UPI ids, or provider references.

## 15. Cleanup and rollback

After the last run:

1. Restore `OBS_LOG_SAMPLE_RATE=0.1`.
2. Set `crons: []`.
3. Deploy staging and verify `/health` 200 exact.
4. Record the final version ID.
5. Leave synthetic rows in staging; record counts. Cleanup requires a separate approval and a fresh backup.
6. Delete raw tail files.
7. Keep the pre-run D1 export until the report is signed.

Rollback:

- Harness code: revert the Phase 3 commit; the Worker code is unchanged.
- Staging vars/cron: restore the previous `wrangler.jsonc` values and deploy.
- Staging data: restore the pre-run export only with owner approval.
- Production: no action; it was never touched.

## 16. Failure signatures

| Signature | Meaning | Action |
|---|---|---|
| `error code: 1102` | Worker exceeded CPU | Stop; confirm plan; profile before retry |
| `error code: 1101` | Isolate stuck after a CPU kill | Stop; redeploy; do not retry blindly |
| `7500` | D1 daily row-write limit | Stop; wait for quota reset or upgrade |
| `429 RATE_LIMITED` in a read run | Harness pacing or IP limit | Fix the run design; do not count as capacity |
| `503` with `{"status":"degraded"}` | App health check failed on D1 | Stop; inspect D1 |
| `409 STATE_CONFLICT` in write probe | Expected state conflict | Record separately; not a 5xx |
| p99 > 5 s | Abort threshold | Stop; capture trace; investigate |
| 5xx > 2% | Abort threshold | Stop; capture trace; investigate |
