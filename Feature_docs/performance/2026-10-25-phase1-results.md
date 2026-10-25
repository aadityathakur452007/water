# Phase 1 results — P0 money/cron correctness and read-path batching

**Date:** 2026-10-25  
**Status:** Phase 1A and Phase 1B implemented locally and verified on SQLite; staging apply blocked by the account's D1 free-tier daily row-write limit; production untouched.  
**Spec:** `2026-10-25-phase1-p0-correctness-spec.md`  
**Audit:** `2026-10-25-1000-user-capacity-audit.md`  
**Phase 0 evidence:** `2026-10-25-phase0-results.md`

## 1. Outcome

Phase 1A fixes all eleven P0 money/cron defects with one D1 `batch()` per
money mutation and SQL compare-and-set guards. Every mutation that used to be a
sequence of independently committed statements is now all-or-nothing, and every
loser of a concurrent race writes nothing.

Local verification is green: **438 passed** (400 before Phase 1A), ruff clean,
and `EXPLAIN QUERY PLAN` proves the hot queries use the new indexes. The
deterministic concurrency tests cover duplicate cancels/webhooks/dues/transitions,
cancel-vs-webhook in both orders, COD late capture, reissue limits, and induced
batch failures.

The code is ready for staging. Staging is **not** verified yet: applying
migration 029 to `shodasha-staging` was rejected by Cloudflare with error code
`7500` (D1 free-tier daily row-write limit) at 2026-10-25 11:44 UTC. The
database is unchanged. No bypass was attempted. The apply must be retried after
the quota resets at midnight UTC, then the Worker deploy and atomicity smoke can
run.

Phase 1B (vendor-route and dues N+1 batching) was approved after Phase 1A and
implemented in the same local release as a separate commit; see §9. It changes
no schema and no money mutation.

## 2. What shipped

| P0 | Change | Key file |
|---|---|---|
| P0-1 Cancel | One `cancel_settle` batch: order CAS sets `mutation_token`; real payments are claimed with `refund_id IS NULL`, prepaid credit with `credit:<token>`; stop-code clear, cancel event, and deposit reversal are token-guarded; the cancel refund is derived from the rows actually claimed (`payment_id=order_id`); `_outcome` prefers that refund | `repositories/order_repo.py` |
| P0-2 Webhook | One `apply_webhook` batch: payment CAS `status!='paid'` sets `settlement_token`; SQL-branched order update marks paid only when live and non-COD, otherwise queues exactly one refund; a refunded capture resets a stale `link_sent` order to `unpaid`; service strips `settlement_token`/`mutation_token`/`refund_id`, lifts `duplicate` to the top level for dues, and preserves `_refund_queued` | `repositories/payment_repo.py`, `services/payment_service.py` |
| P0-3 Dues | One `settle_dues_intent` batch: intent CAS; per-order guarded allocation, status update, and link failure; guarded ledger clear; refund remainder derived in SQL using the exact intent clear (`ref_type='dues' AND ref_id=<intent>`), not a `LIKE` prefix that would double-count per-order clears; unique open intent replays or returns 409 | `repositories/payment_repo.py` |
| P0-4 Transition | One CAS batch: `UPDATE orders ... WHERE state=?` sets the token, then the event and postpaid dues are token-guarded; the loser gets 409 with no duplicate row | `repositories/order_repo.py` |
| P0-5 Subscription cancel | One batch guarded by `canceled_at IS NULL`: return, credit, and refund rows are written first, `credit_balance_paise` is zeroed last, and any failure rolls back the whole batch; `build_restore_order_credit_stmts` is shared with order credit restore | `services/subscription_service.py` |
| P0-6 COD switch | One CAS batch rejects cancelled/rejected orders and captured `paid`/`partial` payments, fails open links, and converts in place; a late UPI capture is refunded by the webhook COD guard | `repositories/payment_repo.py` |
| P0-7 Reissue | New `delivery_code_reissues` table with PK `(order_id, seq)`, sliding 24h count, and up to three PK-conflict retries; stop update and audit are written only when the `(order_id, seq)` insert succeeded; the order must be `dispatched`; rows older than 48h are purged | `services/order_service.py`, `jobs/scheduler.py` |
| P0-8 Cron ordering | `process_due` no longer advances generated descriptors. `run_due_subscriptions` creates the order and settles prepaid credit first, then advances via `advance_due` CAS (`next_run` must still equal the processed date). Failure leaves the plan due with `due_attempts`, `due_last_error`, and `due_retry_at` | `services/subscription_service.py`, `jobs/scheduler.py` |
| P0-9 Cron bounds | `_DUE_LIMIT=60`, ordered by `next_run, id`, with `due_backlog` reported; retry backoff grows 15m → 24h and caps at 24h; paused auto-resume is guarded by `status='paused'` | `jobs/scheduler.py` |
| P0-10 Purge | `_PURGE_CHUNK=90` bound parameters everywhere (D1 cap is 100 per statement), including the money-audit scan; reissue purge added | `jobs/scheduler.py` |
| P0-11 Indexes | Seven hot-path indexes plus the reissue index and unique open-dues-intent index; `EXPLAIN QUERY PLAN` asserts the named index for each hot query | `db/migrations/029_p0_correctness.sql`, `tests/test_indexes.py` |
| D1 hardening | `D1BatchError` with statement index; per-result success checks for `execute`/`batch`; result-count and rowcount validation; dict/object result and `meta` handling; `AsyncSqliteConn.batch` uses `BEGIN IMMEDIATE` and rolls back on exception | `db_d1.py` |
| Cron metrics | `cron_tick` summary adds `db_queries`, `db_roundtrips`, `duration_ms`, and `due_backlog` alongside `processed`/`created`/`failed`/`low_balance`/`resumed` | `jobs/scheduler.py` |

Migration `029_p0_correctness.sql` is additive: `orders.mutation_token`,
`payments.settlement_token`, `payments.refund_id`,
`dues_intents.settlement_token`, `subscriptions.due_attempts`/`due_last_error`/`due_retry_at`,
`delivery_code_reissues`, the unique open-dues-intent index, and the hot-path
indexes. Old code ignores every addition, so a code rollback is safe after the
migration.

## 3. Verification

- Full backend suite: **438 passed in 19.56s** (`results/phase1a-pytest.txt`).
- Ruff on every changed source/test file: **All checks passed**
  (`results/phase1a-ruff.txt`).
- Every explicit test migration list that builds a database now includes `029`.

### 3.1 New tests

| File | Tests | What they prove |
|---|---|---|
| `tests/test_p0_atomicity.py` | 13 | Cancel mid-batch failure leaves no trace; two cancels produce one event/reversal/refund; cancel after a webhook refund claim does not refund twice; duplicate webhook produces one payment/clear; webhook vs cancel in both orders produces exactly one refund per payment; COD late capture refunds and keeps the order unpaid; duplicate dues allocates once; dues after cancel refunds the unallocated remainder; two transitions produce one event/postpaid row; subscription cancel failure leaves credit untouched; prepaid/postpaid cancel refunds only collected credit; reissue 3/24h plus reset; reissue PK-conflict retry |
| `tests/test_d1_batch.py` | 9 | Rowcounts preserved; one roundtrip per batch; failure reports the statement index; short result lists fail; dict results and `meta` handled; `execute` read/write failures raise; SQLite batch rolls back; outer transaction stays open; 90-parameter chunk stays under D1's limit |
| `tests/test_indexes.py` | 9 | All nine Phase 1A indexes exist; each of eight hot queries uses its named index |
| `tests/test_scheduler.py` | 12 | Due replay is idempotent; creation failure leaves `next_run` and retries; advance failure replays the same order; 100 due subscriptions drain 60/40/0 over three ticks; held-range plans do not consume the page; backoff caps at 24h; 500+ audit rows purge in chunks and replay clean; `cron_tick` reports roundtrips and backlog |

### 3.2 Index proof

`tests/test_indexes.py` runs `EXPLAIN QUERY PLAN` against a database built from
migrations 002–029. Each plan must contain `USING INDEX` or
`USING COVERING INDEX` **and** the expected index name:

- `idx_ledger_events_ref` — dues lookup by `(ref_type, ref_id)`
- `idx_audit_created` — audit retention delete
- `idx_idem_created` — idempotency retention delete
- `idx_rate_window` — rate-counter retention delete
- `idx_subs_status_next_run` — due page ordered by `next_run, id`
- `idx_orders_address_state` — orders by address and state
- `idx_payments_refund` — one-refund-path lookup
- `idx_reissues_order_created` — reissue count in the 24h window

## 4. Staging pre-flight (read-only)

Against `shodasha-staging` / D1 `05772775-a957-4852-8ec3-6b14082d4a62`:

| Check | Result |
|---|---|
| Applied migrations | **27**, latest `028_p0_money_monthly.sql` |
| Users | **1,021** |
| Orders | **10,000** |
| Open dues intents (`pending`/`link_sent`) | **0** — the unique-index cleanup would touch zero rows |
| Database size | **13,991,936 bytes** |

No write was made by the pre-flight.

## 5. Staging blocker

Command:

```powershell
cd workers/api
npx wrangler d1 migrations apply shodasha-staging --remote --env staging
```

Result at **2026-10-25 11:44 UTC**:

```
Your account has exceeded D1's free tier daily row write limit.
Upgrade to a paid plan or wait until tomorrow (midnight UTC)
(code: 7500)
```

The migration was **not** applied. A follow-up read-only query confirmed the
database is unchanged: **27 migrations**, latest `028`, 1,021 users, 10,000
orders. No bypass, partial apply, or manual DDL was attempted.

The free-tier daily row-write cap is a second platform blocker, separate from
the 10 ms Workers CPU ceiling recorded in ADR-140. The migration itself is also
still unverified on D1; local SQLite does not model D1 latency or row
accounting.

**Retry after 2026-10-26 00:00 UTC.** Then verify the new columns, table, and
indexes, record pre/post row counts, deploy `water-staging` with cron disabled,
and run the synthetic atomicity smoke from the spec (seed tokens only, no real
provider calls, no secrets in logs).

## 6. What is not done

- Migration 029 is **not** applied to staging; the staging acceptance criterion
  is not met.
- `water-staging` has **not** been redeployed with Phase 1A code.
- The staging atomicity smoke has **not** run.
- Phase 1B read-path batching is implemented locally (§9) but has **not** been
  staging-verified.
- Production `water` / D1 `shodasha` remain untouched: no migration, deploy,
  write, or load test.
- No real subscription-adoption data exists; the seed billing mix is synthetic.

## 7. Rollback

- **Code rollback:** safe after 029. Old code ignores the new columns, table,
  and indexes.
- **Migration rollback:** not recommended; dropping the columns/table loses
  retry and reissue state. If required, it is a separate owner-approved
  operation with a backup.
- **Cron tuning:** lower `_DUE_LIMIT` and redeploy; no schema change.

## 8. Artifacts

- `Feature_docs/performance/results/phase1a-pytest.txt`
- `Feature_docs/performance/results/phase1a-ruff.txt`
- Spec: `Feature_docs/performance/2026-10-25-phase1-p0-correctness-spec.md`
- Migration: `workers/api/src/app/db/migrations/029_p0_correctness.sql`
- Tests: `workers/api/tests/test_p0_atomicity.py`, `test_d1_batch.py`,
  `test_indexes.py`, `test_scheduler.py`

## 9. Phase 1B addendum — read-path N+1 batching (2026-10-25, ADR-142)

Approved after Phase 1A: two read paths only, no migration, no API shape change,
no write-path change.

| Path | Before (Phase 0) | After (service level) | Change |
|---|---|---|---|
| `GET /v1/vendor/routes/today` | **85 statements / 162 rows** at the endpoint for 40 stops | **6 queries / 6 roundtrips / 42 rows** for a 40-stop route | 1 ledger `held` aggregate + 1 payments `paid` aggregate replace 2 reads per stop |
| `GET /v1/billing/dues` | **15 statements / 14 rows** for ~6 open orders | **4 queries / 4 roundtrips / 40 rows** for 40 open orders | 1 paid-sum aggregate + 1 dues-posted aggregate replace 2 reads per open order |

Implementation:

- `LedgerRepo.held_for_customers(ids)` — `SELECT customer_id, held FROM ledger
  WHERE customer_id IN (...)`, missing customer → `0`.
- `PaymentRepo.paid_sums_for_orders(ids)` — `SUM(amount)` grouped by order,
  status `paid`/`partial`, missing order → `0`.
- `PaymentRepo.dues_posted_for_orders(ids)` — `DISTINCT ref_id` from
  `ledger_events` where `ref_type='order'`, `kind='dues'`, `d_dues>0`.
- Ids are deduped and empty ids dropped; an empty list skips the query. Chunks
  of 90 keep every statement under D1's 100-bound-parameter cap.
- `today_route` keeps the address-snapshot overlay and the `held > 3`
  hold-block rule; `get_dues` keeps line order and the COD double-count guard.
- Single-order helpers (`paid_sum_for_order`, `_dues_posted`, `get_invoice`,
  `cod_confirm`) are untouched.

Verification:

- Targeted `test_vendor.py` + `test_payments.py`: **54 passed**.
- Full backend suite: **443 passed in 23.00s**.
- Ruff on every changed source/test file: **All checks passed**.
- New tests: per-customer/per-order map parity, query count equal for 1 vs 40
  stops, 95-customer chunk/dedupe, dues query count equal for 1 vs 40 open
  orders, and a 95-order chunk test asserting exactly 6 dues statements
  (1 ledger + 1 orders + 2 paid chunks + 2 posted chunks).
- Measured with the observability `RequestMetrics` on seeded SQLite. Local
  SQLite still does not model D1 network latency or row accounting, so staging
  remains the proof.

Not included: `_stop_field_cols` schema caching, `settle_dues_intent`
allocation loop, admin/order-detail N+1, read `batch()`, any write-path change.

Artifacts: `workers/api/src/app/repositories/{ledger_repo,payment_repo}.py`,
`workers/api/src/app/services/{vendor_service,payment_service}.py`,
`workers/api/tests/{test_vendor,test_payments}.py`.
