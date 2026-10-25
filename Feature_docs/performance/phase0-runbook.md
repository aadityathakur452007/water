# Phase 0 runbook — staging measurement

**Scope:** measure the API on `water-staging` + `shodasha-staging` only.
Production (`water` / `shodasha`) is read-only: never load-test, write, migrate, or deploy there.

Related documents:

- Audit: `2026-10-25-1000-user-capacity-audit.md`
- Spec: `2026-10-25-phase0-implementation-spec.md`
- Results: `results/`

## 1. Safety rules

- Benchmark scenarios are GET-only. Do not add writes to the harness.
- The harness refuses any host that is not loopback or does not contain `staging`.
  It also refuses the production host explicitly.
- Profile `c` requires `--allow-stress`; it finds the knee, it is not a launch gate.
- Never print, commit, or paste `data/phase0_tokens.json`. The file contains live
  staging session tokens.
- Do not re-seed staging casually. The default seed is ~43k rows but D1 counts
  ~168k row writes including indexes, which exceeds the Free plan's 100k/day.
- No secrets belong in `wrangler.jsonc`. Use `wrangler secret put --env staging`
  only if a staging flow truly needs one.

## 2. Prerequisites

From `workers/api`:

```powershell
npx wrangler whoami
python -m pytest -q
```

The staging environment is defined in `wrangler.jsonc`:

- Worker: `water-staging`
- D1 binding: `DB` → `shodasha-staging` (`05772775-a957-4852-8ec3-6b14082d4a62`)
- `APP_ENV=staging`, `OBS_LOG_SAMPLE_RATE=0.1`, `OBS_SLOW_MS=750`
- `THROTTLE_ANON_PER_MIN=100000` (the benchmark exits from one source IP)
- Cron disabled, logs persisted, traces enabled

## 3. One-time staging setup

Apply migrations:

```powershell
npx wrangler d1 migrations list shodasha-staging --remote --env staging
npx wrangler d1 migrations apply shodasha-staging --remote --env staging
```

Generate the deterministic seed and tokens:

```powershell
python scripts/seed_phase0.py `
  --sql data/phase0_seed.sql `
  --tokens data/phase0_tokens.json `
  --summary data/phase0_seed_summary.json
```

Apply it once:

```powershell
npx wrangler d1 execute shodasha-staging --remote --env staging `
  --file=data/phase0_seed.sql
```

Expected shape: 1,021 users, 1,000 addresses/ledger/subscriptions, 10,000 orders,
24,000 events, 3,000 payments, 800 stops, 1,021 sessions, 100 audit rows.
Record the reported rows written; do not re-run the same day on Free.

Deploy:

```powershell
npx wrangler deploy --env staging
```

If the first deploy uploads a version but ends with
`This Worker does not exist on your account [code: 10007]`, run the same deploy
again. Wrangler can create the version before the workers.dev route exists; the
second deploy registers the route. Confirm:

```powershell
npx wrangler deployments list --env staging
curl.exe -sS -i https://water-staging.adityathakur452007.workers.dev/health
```

Success is `200` with exactly `{"status":"ok"}` and `Cache-Control: no-store`.

## 4. Verify logs and redaction

Tail staging while sending one request:

```powershell
npx wrangler tail --env staging --format json
```

In another terminal:

```powershell
curl.exe -sS -H "X-Trace-Id: runbook-check" `
  https://water-staging.adityathakur452007.workers.dev/health
```

The tail must contain one `shodasha.request` JSON line with:

- `env=staging`
- `route=/health` (a template, never a raw user path)
- `status`, `duration_ms`, `db_queries`, `db_roundtrips`, `db_rows_read`,
  `db_rows_written`
- no `Authorization`, cookie, token, phone, UPI id, query string, body, or client IP

4xx/5xx and slow requests always log; healthy fast requests sample at 0.1.
Set `OBS_LOG_SAMPLE_RATE=0` to silence the healthy path (errors still log).

## 5. Run the benchmark

Always smoke first:

```powershell
python scripts/bench_phase0.py `
  --base-url https://water-staging.adityathakur452007.workers.dev `
  --profile smoke --label staging-smoke
```

A/B:

```powershell
python scripts/bench_phase0.py `
  --base-url https://water-staging.adityathakur452007.workers.dev `
  --profile a --label staging-a
python scripts/bench_phase0.py `
  --base-url https://water-staging.adityathakur452007.workers.dev `
  --profile b --label staging-b
```

C only as a stress probe:

```powershell
python scripts/bench_phase0.py `
  --base-url https://water-staging.adityathakur452007.workers.dev `
  --profile c --allow-stress --label staging-c
```

Results are written to `Feature_docs/performance/results/phase0-<profile>-<UTC>.json`
and a sibling `.md`. The harness aborts after at least 20 requests when 5xx >2%
or overall p99 >5 s, and still writes the partial result.

Local query-shape baseline (no Cloudflare CPU ceiling):

```powershell
python scripts/seed_phase0.py `
  --db data/phase0_local.db `
  --tokens data/phase0_local_tokens.json `
  --summary data/phase0_local_summary.json --fresh

$env:PYTHONPATH="src"
$env:SHODASHA_DB_PATH="data/phase0_local.db"
$env:OBS_LOG_SAMPLE_RATE="1"
python -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8787 `
  --timeout-keep-alive 75
```

Then point the harness at `http://127.0.0.1:8787` with
`--tokens data/phase0_local_tokens.json`. The structured log lines give exact
statement/row counts per route; local SQLite latency is not D1 latency.

Use `--timeout-keep-alive 75` for local A/B. Uvicorn defaults to 5 s, while a
20-thread profile idles each thread ~7 s between requests; without the longer
timeout nearly every request records a stale-socket reconnect in
`retry_count`, which inflates local latency. It does not affect the query
counters.

## 6. Reading the result

- `result=pass`: all requests were 2xx and no abort threshold was crossed.
- `aborted=true` / `result=fail`: read `abort_reason` and the per-route table.
  A partial result is still evidence; keep it.
- `error code: 1102` in a response body means the Worker exceeded CPU, not a
  database failure. On Workers Free the limit is 10 ms per request; this Python
  Worker exceeds it. `1101` after a `1102` is the known workerd/Pyodide
  "isolate stuck after a CPU-limit kill" failure, not an application bug.
- A `503` from our `/health` contract has body
  `{"status":"degraded","checks":{"db":"error"}}`. A `503` with
  `error code: 1102` comes from Cloudflare before the app.

## 7. Rollback

- Code: revert the Phase 0 commit; no production schema or data change.
- Staging Worker: `npx wrangler delete --env staging` only with explicit owner approval.
- Staging D1: `npx wrangler d1 delete shodasha-staging` only with explicit owner approval.
- Logs: set `OBS_LOG_SAMPLE_RATE=0`, or disable `observability.logs` in staging config.

## 8. Known limitations

- Workers Free is 10 ms CPU per request. This app currently returns intermittent
  `1102`/`1101` even for `/health`; A/B/C on staging therefore abort early.
  That is a platform finding, not a benchmark bug.
- Local SQLite does not model D1 network latency or D1 row accounting.
- Synthetic billing mix is an assumption; real subscription adoption is unknown.
- C is a stress probe only. Architecture changes are required before 1,000
  concurrent users can be a launch target.
