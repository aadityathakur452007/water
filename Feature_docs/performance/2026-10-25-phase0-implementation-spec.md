# Phase 0 implementation spec — safe measurement layer

**Date:** 2026-10-25  
**Status:** Approved for implementation by owner ("implement phase 0"). Measurement-only; no business-logic changes.  
**Parent audit:** `Feature_docs/performance/2026-10-25-1000-user-capacity-audit.md`  
**Production:** read-only. No load test, write, migration, or deploy against `water` / `shodasha`.

## 1. Goal

Make A (1,000 registered) and B (1,000 DAU) measurable without risking production, and make C (1,000 concurrent) a stress test that finds the knee rather than a launch gate.

Exit evidence:

- Per-route p50/p95/p99, status mix, and D1 statements/rows per request.
- A real `/health` that fails when D1 is unreachable.
- An isolated staging Worker + D1 with deterministic synthetic data.
- A repeatable benchmark harness that refuses production targets.

## 2. Hard constraints

- Free-plan limits are real until the owner upgrades: 10 ms CPU, 50 D1 queries per invocation, 100k rows written/day, 5M rows read/day.
- Worker vars are not visible through `pydantic-settings`; new runtime flags must use `app.core.worker_env.env_get`.
- Logs must never contain Authorization/cookies/tokens, phone numbers, UPI IDs, provider refs, request bodies, query strings, client IPs, or raw user-controlled paths.
- `/health` success body must stay exactly `{"status":"ok"}` (existing contract test).
- No new runtime dependency, migration, or business-rule change.
- Staging only: `water-staging` + `shodasha-staging` (`05772775-a957-4852-8ec3-6b14082d4a62`, APAC).

## 3. Workstreams and file ownership

| Workstream | Files | Owner |
|---|---|---|
| Observability + health | `src/app/core/observability.py`, `src/app/api/health.py`, `src/app/api/deps.py`, `src/app/api/middleware.py`, `src/app/main.py`, `src/app/db_d1.py`, `tests/test_observability.py`, `tests/test_health.py` (additive only) | core |
| Staging config | `wrangler.jsonc`, `.env.example`, `Feature_docs/performance/phase0-runbook.md` | core |
| Synthetic seed | `scripts/seed_phase0.py` (new only) | seed agent |
| Benchmark harness | `scripts/bench_phase0.py`, `tests/test_bench_guard.py` (new only) | benchmark agent |

No agent edits another workstream's files. Existing tests may only be extended, never weakened.

## 4. Structured request log

One JSON object per sampled request, emitted through `logging`:

```json
{
  "event": "http_request",
  "ts": "2026-10-25T08:00:00.123Z",
  "env": "staging",
  "trace_id": "a1b2c3d4e5f60718",
  "method": "GET",
  "route": "/v1/orders/{order_id}",
  "status": 200,
  "duration_ms": 142.7,
  "db_queries": 7,
  "db_roundtrips": 7,
  "db_rows_read": 23,
  "db_rows_written": 0
}
```

Rules:

- `route` is the FastAPI route template after routing. Unmatched requests log `<unmatched>`, never the raw path.
- `method` is allowlisted; `status` is an integer; `duration_ms` is rounded to 0.1 ms.
- `db_queries` counts SQL statements (a batch of N counts N). `db_roundtrips` counts `execute`/`batch` calls. Rows use D1 `meta.rows_read` / `meta.rows_written` when present; otherwise returned rows / changes.
- `trace_id` is accepted from `X-Trace-Id` only if it matches `^[A-Za-z0-9._-]{1,64}$`; otherwise a new 16-hex id is generated. The sanitized id is echoed in the response header.
- Sampling: 5xx and requests slower than `OBS_SLOW_MS` (default 750) always log. Everything else samples deterministically from a hash of `trace_id` at `OBS_LOG_SAMPLE_RATE` (default 0.05; staging 0.1). `0` disables non-error logs; `1` logs all.
- Logging must never raise into the request path.
- Rate-limit logs drop the client IP.

## 5. Health contract

`GET /health`:

- Runs `SELECT 1` through the normal DB dependency, with a 2 s timeout.
- Caches the result per isolate for 5 s to avoid monitor-driven D1 load.
- Success: HTTP 200, body exactly `{"status":"ok"}`, `Cache-Control: no-store`.
- Failure/timeout: HTTP 503, body `{"status":"degraded","checks":{"db":"error"}}`, no exception text, no secrets.
- A failure emits one structured warning with the trace id and duration only.

## 6. Staging configuration

- Worker: `water-staging`; D1: `shodasha-staging`; binding `DB`.
- Vars: `APP_ENV=staging`, `OBS_LOG_SAMPLE_RATE=0.1`, `OBS_SLOW_MS=750`, `THROTTLE_ANON_PER_MIN=100000` (benchmark source IP is single), public `FIREBASE_PROJECT_ID`.
- Cron disabled in staging so synthetic due subscriptions do not mutate the dataset during a run.
- Logs persisted; traces enabled with head sampling 1.0. Remove the unsupported `issue_detection` field that Wrangler 4.152 warns about.
- No secrets in config. Secrets, if ever needed, go through `wrangler secret put --env staging`.

## 7. Synthetic seed

Deterministic, idempotent, synthetic-only IDs/phones/emails. Default shape follows the audit:

- 1,000 customers + 1,000 addresses + 1,000 ledger rows.
- 1,000 subscriptions: 60% per-delivery, 20% monthly prepaid, 20% monthly postpaid.
- 10,000 orders over 90 days, with events; delivered/paid, dispatched, and placed states.
- 20 vendors + profiles + one zone; 20 today routes with 40 stops each.
- Payments for delivered orders; audit rows; one synthetic session per customer/vendor plus one admin.
- Token file is written outside git (`data/phase0_tokens.json`) and never printed. Tokens are random and valid only on the seeded DB.
- Outputs: local SQLite (`data/phase0.db`) or a D1 SQL file (`data/phase0_seed.sql`) plus a summary (`data/phase0_seed_summary.json`).
- All phone numbers use the reserved-looking `+9188888xxxxx` range and `example.invalid` emails; no real PII.

## 8. Benchmark harness

Python 3.13 stdlib only (k6/Locust are not installed). Constant-arrival-rate workers, keep-alive connections, per-route latency buckets.

Profiles:

| Profile | Average rps | Peak rps | Duration | Concurrency |
|---|---|---|---|---|
| A | 2.78 | 6.94 | 10 min | 20 |
| B | 5.56 | 13.9 | 10 min | 40 |
| C (stress) | 55.6 | 139 | 5 min | 200 |

Scenario mix: health, catalog, auth/me, orders list, order detail, billing/dues, vendor route. A 1-VU smoke runs every route once before any load.

Guardrails:

- Refuse any host that is not loopback or does not contain `staging`.
- Refuse if `--base-url` is the production Worker.
- Abort on >2% 5xx or p99 >5 s (record partial results).
- Never sends writes; only GET/HEAD.
- Writes JSON + a Markdown table to `Feature_docs/performance/results/`.

## 9. Acceptance checks

1. `pytest` passes, including new observability/health/guard tests.
2. A request with a phone in the query string produces no phone in logs.
3. A 429/404/500 request is logged even at sample rate 0.
4. `/health` returns the exact legacy body on success and 503 on DB failure.
5. `wrangler deploy --dry-run` passes for default and `--env staging`.
6. Staging D1 migrations apply; staging `/health` returns 200.
7. Seed counts match the requested shape; no real PII.
8. 1-VU smoke over every route captures status + D1 statements/request.
9. A/B runs produce a baseline table; C records the knee, not a GO.

## 10. Rollback

- Code: revert the Phase 0 commit; no schema or data change in production.
- Staging: `wrangler delete --env staging` and `wrangler d1 delete shodasha-staging` only with explicit owner approval.
- Logs: set `OBS_LOG_SAMPLE_RATE=0` (errors still log) or disable `observability.logs` in config.

## 11. Known limitations

- Free plan may reject staging Python Worker invocations at 10 ms CPU; that is a measurement finding, not a code failure.
- Local SQLite latency is not D1 latency; use local for query counts and relative shape, staging for real edge/D1 latency.
- Synthetic traffic cannot predict real subscription adoption; billing mix is an explicit assumption from the audit.
- C remains NO-GO until Phase 4 architecture work; Phase 0 only finds the knee.
