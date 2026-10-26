# Phase 1 implementation spec — P0 money/cron correctness

**Date:** 2026-10-25  
**Status:** **APPROVED (Phase 1A only) and implemented locally on 2026-10-25. Staging apply is blocked by the account's D1 free-tier daily row-write limit (`7500`); production is untouched.** Phase 1B is deferred to a separate release. Evidence: `2026-10-25-phase1-results.md`.  
**Parent audit:** `Feature_docs/performance/2026-10-25-1000-user-capacity-audit.md`  
**Phase 0 evidence:** `Feature_docs/performance/2026-10-25-phase0-results.md`  
**Production:** read-only. No load test, write, migration, or deploy against `water` / `shodasha` without a separate explicit approval.

## 1. Goal

Make the money paths atomic and the cron path lossless before any scaling work. The audit’s verdict is that A/B are throughput-feasible on Workers Paid but **unsafe until the P0 defects are fixed**; C is a later architecture problem.

Exit evidence:

- Every money mutation is one D1 `batch()` transaction with a compare-and-set (CAS) guard.
- Duplicate/concurrent webhooks, cancels, transitions, dues settlements, reissues, and COD switches produce exactly one money outcome.
- A failed cron order creation leaves `next_run` due; a successful creation advances it. No silent missed delivery.
- Cron work per tick is bounded and measurable.
- Migration 029 is additive, verified on staging, and production remains untouched until a separate gate.
- Full backend suite + new concurrency/rollback tests pass; ruff clean.

## 2. Scope

### Phase 1A — P0 correctness (this approval)

| ID | Defect | Fix in this phase |
|---|---|---|
| P0-1 | Cancel settlement is 10+ sequential statements; D1 `commit()`/`rollback()` are no-ops | One batch, order CAS token, refund allocation marker |
| P0-2 | Webhook settlement has no CAS; duplicate callbacks can double-credit/refund | Payment CAS token, SQL-branched refund/order update, one refund path per payment |
| P0-3 | Dues settlement is check-then-act; N+1 paid-sum reads | Intent CAS token, precomputed allocations, refund derived from rows actually written |
| P0-4 | Order transition is read-modify-write with no state guard | Order CAS token, event + postpaid dues in the same batch |
| P0-5 | Subscription cancel zeroes credit before writing refund/credit rows | `canceled_at IS NULL` CAS; credit/refund rows first, zero last, one batch |
| P0-6 | `switch_to_cod` races a live capture | Conditional order CAS + COD webhook guard |
| P0-7 | Reissue “3 per 24h” relies on a no-op `WRITE_LOCK` | `delivery_code_reissues` table with per-order sequence; sliding 24h count |
| P0-8 | Cron advances `next_run` before the order exists | Create/settle first, advance only after success; replay-safe |
| P0-9 | Cron processes every due subscription in one tick | `LIMIT 60` page, `ORDER BY next_run, id`, backlog count, retry backoff |
| P0-10 | Purge chunks use 500 bound parameters (D1 cap = 100) | Chunk size 90 everywhere |
| P0-11 | Six hot filters lack indexes | Migration 029 indexes + `EXPLAIN QUERY PLAN` proof |

### Phase 1B — N+1 batching (optional in the same release)

- `vendor_service.today_route`: replace 2 queries per stop (ledger `held` + paid sum) with 2 chunked aggregate queries per route.
- `payment_service.get_dues`: replace 2 queries per open order (paid sum + dues-posted) with 2 chunked aggregate queries per user.
- Target: vendor route ≤ 4 DB roundtrips for 40 stops (from 85 statements / 162 rows); dues ≤ 3 roundtrips for ~6 open orders (from 15 statements / 14 rows).

**Recommendation:** ship 1A first; treat 1B as a separate commit/release after 1A is verified, so a money regression cannot be confused with a read-path change. The approval question at the end asks which scope to authorize.

### Non-goals

- No FCM/WhatsApp sending, status streaming, or client polling changes.
- No Durable Objects, queues, or architecture change.
- No Paid-plan purchase or production load test.
- No change to pricing, order state matrix, refund claim/done flow, or customer-visible copy.
- No production migration/deploy in this approval.

## 3. Platform facts this design relies on

1. **D1 `batch()` is a SQL transaction.** If any statement fails, the sequence aborts/rolls back. Source: <https://developers.cloudflare.com/d1/worker-api/d1-database/#batch>.
2. **A `batch()` call counts as one query against the 1,000-queries-per-invocation limit**, not one per statement. The 100-bound-parameter limit still applies to each statement. Source: <https://developers.cloudflare.com/d1/platform/limits/>.
3. Therefore the cron cap is best measured by `db_roundtrips` (one per `execute`/`batch`), not `db_queries` (statements). The existing Phase 0 log schema already records both; no schema change is needed.
4. `WRITE_LOCK` is a local/test lock only. It is a no-op on Workers, so every invariant below must be enforced in SQL, not in Python.
5. `D1Conn.commit()` / `rollback()` are no-ops. A mutation is atomic only if it is one `batch()`.

## 4. Money invariants (must hold under concurrency)

- **I-1 One cancel outcome per order.** A second cancel never writes a second event, deposit reversal, credit restore, or refund.
- **I-2 One settlement per payment/intent.** A duplicate provider callback returns the stored outcome; it never clears dues or credits twice.
- **I-3 One refund path per payment.** A payment row is claimed by at most one refund (`payments.refund_id` set once). A late capture on a cancelled/COD/already-paid order queues exactly one refund.
- **I-4 Refund amounts come from rows actually written**, not from a pre-read total, so a concurrent state change converts an unallocated amount into a refund instead of losing it.
- **I-5 One state transition per read state.** A concurrent transition loses cleanly with 409; no duplicate event or postpaid dues.
- **I-6 Subscription cancel never loses prepaid credit.** Credit/refund rows are written before the balance is zeroed; a failure rolls back the whole batch.
- **I-7 Reissue limit is 3 per rolling 24h per order**, even across isolates.
- **I-8 A due subscription advances only after its order exists and (for prepaid) its credit debit succeeded.** A failure leaves it due with backoff; replay is idempotent on `sub:<id>:<date>`.

## 5. Migration 029 — additive schema

File: `workers/api/src/app/db/migrations/029_p0_correctness.sql`

Apply-once. D1 migration runner records it; do not re-run manually. All changes are additive; old code ignores them, so code rollback is safe after the migration.

```sql
-- CAS/guard tokens (nullable; set only inside the owning batch)
ALTER TABLE orders ADD COLUMN mutation_token TEXT;
ALTER TABLE payments ADD COLUMN settlement_token TEXT;
ALTER TABLE payments ADD COLUMN refund_id TEXT;          -- one refund path per payment
ALTER TABLE dues_intents ADD COLUMN settlement_token TEXT;

-- Cron retry/backoff state
ALTER TABLE subscriptions ADD COLUMN due_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE subscriptions ADD COLUMN due_last_error TEXT;
ALTER TABLE subscriptions ADD COLUMN due_retry_at TEXT;

-- Reissue rate limit: per-order monotonic sequence, sliding 24h count
CREATE TABLE IF NOT EXISTS delivery_code_reissues (
    order_id TEXT NOT NULL,
    seq INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (order_id, seq)
);
CREATE INDEX IF NOT EXISTS idx_reissues_order_created
    ON delivery_code_reissues (order_id, created_at);

-- One open dues intent per user (prevents two concurrent settlements for one user)
UPDATE dues_intents SET status = 'failed'
WHERE status IN ('pending', 'link_sent')
  AND rowid NOT IN (
      SELECT MAX(rowid) FROM dues_intents
      WHERE status IN ('pending', 'link_sent') GROUP BY user_id
  );
CREATE UNIQUE INDEX IF NOT EXISTS uq_dues_intent_open
    ON dues_intents (user_id) WHERE status IN ('pending', 'link_sent');

-- P0-11 hot filters
CREATE INDEX IF NOT EXISTS idx_ledger_events_ref
    ON ledger_events (ref_type, ref_id);
CREATE INDEX IF NOT EXISTS idx_audit_created
    ON audit_log (created_at);
CREATE INDEX IF NOT EXISTS idx_idem_created
    ON idempotency_keys (created_at);
CREATE INDEX IF NOT EXISTS idx_rate_window
    ON rate_counters (window_start);
CREATE INDEX IF NOT EXISTS idx_subs_status_next_run
    ON subscriptions (status, next_run);
CREATE INDEX IF NOT EXISTS idx_orders_address_state
    ON orders (address_id, state);
CREATE INDEX IF NOT EXISTS idx_payments_refund
    ON payments (refund_id);
```

Pre-flight (read-only, before applying to staging/production):

```sql
SELECT user_id, COUNT(*) AS open_intents
FROM dues_intents
WHERE status IN ('pending', 'link_sent')
GROUP BY user_id HAVING COUNT(*) > 1;
```

The cleanup marks all but the newest open intent per user as `failed`. No money moves; a stale open intent is unusable anyway. Record the count before/after in the migration evidence.

**Test harness:** add `029_p0_correctness.sql` to every explicit migration list that builds orders/payments/subscriptions/scheduler schema: `test_p0_money.py`, `test_phase02_splitb.py`, `test_admin_panel.py`, `test_aftermath.py`, `test_monthly_billing.py`, `test_sub_cancel.py`, `test_scheduler.py`. `test_payments.py` and `test_demo.py` need the file added to their loaders if they exercise the changed repos. Do not weaken existing tests.

Implemented: all **19** test files that load `028_p0_money_monthly.sql` also load `029_p0_correctness.sql`; no test was weakened.

## 6. Design per defect

### 6.1 P0-1 — atomic cancel settlement

File: `src/app/repositories/order_repo.py` (`cancel_settle`, `_clear_stop_codes`, `_outcome`), `src/app/services/subscription_service.py` (`restore_order_credit` builder).

**Read phase (no writes):** order, legal-transition/override checks, paid payments, credit payments, subscription state, stop column set. Compute the refund candidates and the credit-restore flag.

**Write phase — one batch, first statement is the CAS:**

1. `UPDATE orders SET state='cancelled', payment_status='unpaid', mutation_token=? WHERE id=? AND state=?`
2. Claim real-money payments: `UPDATE payments SET refund_id=? WHERE order_id=? AND status IN ('paid','partial') AND provider_ref NOT LIKE 'subcredit:%' AND refund_id IS NULL AND EXISTS (SELECT 1 FROM orders WHERE id=? AND mutation_token=?)`.
3. Claim credit payments separately: same update with `provider_ref LIKE 'subcredit:%'` and a `credit:<cancel_id>` marker.
4. Fail open links: `UPDATE payments SET status='failed' WHERE order_id=? AND status='link_sent' AND EXISTS (order token)`.
5. Clear stop codes (only the columns that exist) guarded by the order token.
6. Insert the cancel event guarded by the order token.
7. Deposit reversal via `LedgerRepo.build_event_stmts(..., guard=order_token)`.
8. Credit restore statements guarded by the order token **and** `subscriptions.canceled_at IS NULL AND billing_status != 'canceled'`; the balance is recomputed from `SUM(subscription_credit_entries.delta)`, never `balance = balance - amount`.
9. Insert the cancel refund row (`payment_id = order_id`, unique) with amount derived from `SUM(payments.amount) WHERE refund_id=<cancel_id>` plus the conditional credit amount if the plan is already cancelled. Use `HAVING` so a zero refund writes no row.
10. Commit.

**After the batch:** check statement 1 `rowcount`. If `1`, return `_outcome(fresh)`. If `0`, re-read: `cancelled` → `AlreadyCancelledError` with the same outcome; otherwise `ConflictError`. No compensating writes ran because every later statement is guarded by the token.

**Why the token:** a loser batch’s CAS writes no token, so its event/ledger/refund statements are no-ops. A concurrent webhook can still claim a payment; the `refund_id IS NULL` claim makes exactly one path own it.

**Refactor:** `restore_order_credit` becomes a thin wrapper over a `build_restore_order_credit_stmts(order_id, guard)` helper, so cancel can include the statements in its batch. Keep the public method for compatibility/tests.

**Invariant proof (tests):** mid-batch failure leaves state/ledger/refund unchanged; second cancel writes nothing; a payment claimed by a webhook first is not refunded again by cancel.

### 6.2 P0-2 — CAS webhook + one refund path per payment

File: `src/app/repositories/payment_repo.py` (`apply_webhook`), `src/app/services/payment_service.py` (`webhook_ingest`).

**Read phase:** `find_by_provider_ref`, amount checks against the payment intent and frozen order total. If `status == 'paid'`, return the existing row as `_duplicate` (no batch).

**Write phase — one batch, first statement is the CAS:**

1. `UPDATE payments SET status='paid', verified_at=?, settlement_token=? WHERE id=? AND status!='paid'`
2. `UPDATE payments SET refund_id=<webhook_refund_id> WHERE id=? AND refund_id IS NULL AND EXISTS (payment settlement_token=?)`
3. Refund insert guarded by the claim: `INSERT OR IGNORE INTO refunds(... payment_id=<payment.id> ...) SELECT ... WHERE EXISTS (SELECT 1 FROM payments WHERE id=? AND refund_id=<webhook_refund_id>)`. The `UNIQUE(payment_id)` is the final guard.
4. Order update, SQL-branched on the current order state:
   `UPDATE orders SET payment_status='paid_upi' WHERE id=? AND state NOT IN ('cancelled','rejected') AND payment_mode!='cod' AND payment_status NOT IN ('paid_upi','paid_cash') AND EXISTS (payment settlement_token=?)`.
5. Ledger dues clear only if step 4 applies and `_dues_posted`: `LedgerRepo.build_event_stmts(..., d_dues=-min(dues, amount), ref=f"payment:{payment.id}", guard=payment_token)`.
6. Commit.

The refund conditions are expressed in SQL, not in a Python branch: a capture is refund-worthy if the order is `cancelled`/`rejected`, **or** `payment_mode='cod'`, **or** `payment_status IN ('paid_upi','paid_cash')`. Exactly one of “refund” and “mark paid” applies at batch time. This closes the cancel-vs-webhook race: if cancel wins, the webhook queues its own refund; if the webhook wins, cancel’s payment claim sees `refund_id` already set and does not refund twice.

**Response:** `_duplicate` / `_refund_queued` flags preserved. Strip `settlement_token` and `refund_id` from API responses; they are internal.

**COD guard:** a UPI capture on a COD order is a duplicate payment and is refunded, never recorded as the order’s payment mode. This is the second half of P0-6.

### 6.3 P0-3 — atomic dues settlement

File: `src/app/repositories/payment_repo.py` (`settle_dues_intent`).

**Read phase:** fresh intent, amount check, ledger dues, open orders, paid sums (one aggregate query after Phase 1B; N+1 before). Compute each order’s `alloc`, the ledger clear amount, and the expected remainder.

**Write phase — one batch, first statement is the CAS:**

1. `UPDATE dues_intents SET status='paid', verified_at=?, settlement_token=? WHERE id=? AND status!='paid'`
2. For each open order: `INSERT INTO payments(... provider_ref='dues:<intent>:<order>' ...) SELECT ... WHERE EXISTS (SELECT 1 FROM orders WHERE id=? AND state NOT IN ('cancelled','rejected') AND payment_status IN ('unpaid','link_sent','partial_dues')) AND EXISTS (payment token)`.
3. Update the order’s `payment_status` guarded by the inserted payment / order state.
4. Fail the order’s `link_sent` payment guarded by the inserted payment.
5. Ledger clear for posted dues, guarded by the payment/order state.
6. Refund the remainder **derived in SQL**: `intent.amount - SUM(payments.amount WHERE provider_ref LIKE 'dues:<intent>:%') - SUM(-ledger_events.d_dues WHERE ref_type='dues' AND ref_id LIKE '<intent>%')`. Insert only if `> 0`, with `payment_id='dues:<intent>'` (unique).
7. Commit.

**Why:** if an order is cancelled between read and batch, its allocation is skipped, and the SQL refund formula automatically refunds the unallocated amount. No pre-read remainder is trusted. The unique open-intent index prevents two concurrent settlements for one user.

**Duplicate:** if the CAS rowcount is 0, re-read; `paid` → `_duplicate`; otherwise conflict. Dependents are guarded by the loser’s token, so no double allocation.

### 6.4 P0-4 — CAS order transition

File: `src/app/repositories/order_repo.py` (`transition`, `_post_postpaid_dues`).

**Read phase:** order, legal-transition/override checks. If `to_state == 'delivered'`, read the subscription, paid sum, and whether dues were already posted; build the postpaid ledger statements.

**Write phase — one batch:**

1. `UPDATE orders SET state=?, mutation_token=? WHERE id=? AND state=?`
2. Insert the transition event guarded by the token.
3. Postpaid dues ledger statements guarded by the token.
4. Commit.

After the batch, `rowcount == 0` → re-read and raise `ConflictError` (the current state no longer permits the transition). The legal matrix and override roles are unchanged.

**Invariant:** two concurrent PoD/admin transitions produce one event and one dues post; the loser gets 409.

### 6.5 P0-5 — atomic subscription cancel

File: `src/app/services/subscription_service.py` (`cancel`).

**Read phase:** owned subscription, prepaid/postpaid branch, held jars, return SLA, whether `returns.upi_id` exists.

**Write phase — one batch:**

1. `UPDATE subscriptions SET status='paused', canceled_at=?, cancel_reason=?, refund_amount_paise=?, billing_status='canceled', refund_upi=? WHERE id=? AND canceled_at IS NULL`
2. Insert the `returns` row guarded by `canceled_at=?` (fallback statement if `upi_id` is missing).
3. Insert the credit/refund rows first: `subscription_credit_entries` (`ref='cancel:<sub_id>'`, unique), `refunds` (`payment_id='subcancel:<sub_id>'`, unique).
4. Zero the balance last: `UPDATE subscriptions SET credit_balance_paise=0 WHERE id=? AND canceled_at=?`.
5. Commit.

`rowcount == 0` → already cancelled → `SubValidationError`. A later failure rolls back the whole batch, so credit is never zeroed without the refund row. Prepaid and postpaid branches both tested.

### 6.6 P0-6 — `switch_to_cod` race

Files: `src/app/repositories/payment_repo.py` (`switch_to_cod`), `src/app/services/payment_service.py` (`switch_to_cod`), plus the P0-2 COD webhook guard.

**Write phase — one batch:**

1. `UPDATE orders SET payment_mode='cod', payment_status='unpaid' WHERE id=? AND user_id=? AND payment_mode!='cod' AND payment_status NOT IN ('paid_upi','paid_cash','partial_dues') AND NOT EXISTS (SELECT 1 FROM payments WHERE order_id=? AND status IN ('paid','partial'))`
2. `UPDATE payments SET status='failed' WHERE order_id=? AND status='link_sent' AND EXISTS (SELECT 1 FROM orders WHERE id=? AND payment_mode='cod')`
3. Commit.

If the CAS rowcount is 0: re-read; already COD → return it (idempotent); captured/paid → `ConflictError`; otherwise conflict. The COD dues posting stays in `cod_confirm` (idempotent on `_dues_posted`); a UPI capture that arrives after conversion is refunded by the P0-2 COD guard, so COD and UPI can never both be the recorded payment mode.

### 6.7 P0-7 — atomic reissue limit

Files: `src/app/services/order_service.py` (`reissue_delivery_code`), `src/app/jobs/scheduler.py` (purge).

**Algorithm:**

1. Read the order/stop state and the rolling count: `SELECT COUNT(*) FROM delivery_code_reissues WHERE order_id=? AND created_at >= now-24h`.
2. If count ≥ 3 → `RateLimitedError` (429).
3. Compute `seq = MAX(seq)+1` for the order (or 1).
4. One batch:
   - `INSERT INTO delivery_code_reissues(order_id, seq, created_at) SELECT ?, ?, ? WHERE EXISTS (SELECT 1 FROM stops WHERE id=? AND status='pending')`
   - Update the stop’s code/expiry/attempts guarded by the inserted `(order_id, seq)`.
   - Insert the audit row guarded by the same `(order_id, seq)`.
5. Commit. A `PRIMARY KEY(order_id, seq)` conflict means another request won that sequence; retry the count/seq step (bounded, 3 attempts). After retries, return 429/409 “try again”.
6. If the stop is no longer pending, the insert selects 0 rows; return the existing 404/409 without consuming a slot.

Purge `delivery_code_reissues` older than 48h in `purge_delivery_codes` (time-range delete, no IN list).

**Why not a Durable Object:** one new table, no new binding/runtime dependency, and the PK gives the same atomic guarantee. A DO is a later option if reissue contention ever justifies it.

### 6.8 P0-8 — cron advances only after success

Files: `src/app/services/subscription_service.py` (`process_due`, `advance_due`, `record_due_failure`), `src/app/jobs/scheduler.py` (`run_due_subscriptions`).

**Change:** `process_due` stops advancing `next_run` for generated descriptors. It still advances skipped Sundays and auto-resumes paused plans. `run_due_subscriptions`:

1. `due = process_due(today, limit=_DUE_LIMIT)`.
2. For each descriptor:
   - `OrderService.create(..., key='sub:<sub_id>:<date>')`.
   - If `monthly_prepaid`, `settle_prepaid_order(...)`.
   - On success (including `IdempotentReplayError`): `advance_due(sub_id, expected_next_run=date, today)`.
   - On failure: `record_due_failure(sub_id, code, message)` and continue; do not advance.
3. `advance_due` is a CAS: `UPDATE subscriptions SET next_run=?, due_attempts=0, due_last_error=NULL, due_retry_at=NULL WHERE id=? AND next_run=?`. If rowcount 0, another tick advanced it; harmless.
4. `record_due_failure` increments `due_attempts`, stores a 200-char error, and sets `due_retry_at = now + min(15min * 2^(attempts-1), 24h)`.
5. `process_due` filters `(due_retry_at IS NULL OR due_retry_at <= now)` so a failing sub backs off instead of starving the page.

**Residual:** if the order is created and the advance fails, the next tick replays the order (`IdempotentReplayError`) and advances. No duplicate order, no missed delivery. If prepaid settlement fails, the order exists but stays due; the next tick retries the idempotent debit before advancing. Document this in the runbook.

### 6.9 P0-9 — bounded cron page

Files: `src/app/jobs/scheduler.py`, `src/app/services/subscription_service.py`.

- `_DUE_LIMIT = 60` (literal; no new config).
- Due select: `... AND next_run <= ? AND (due_retry_at IS NULL OR due_retry_at <= ?) AND NOT (hold_from IS NOT NULL AND hold_to IS NOT NULL AND hold_from <= next_run AND next_run <= hold_to) ORDER BY next_run, id LIMIT ?`.
- Add a backlog count with the same filters; return it in the summary.
- One page per tick. Keep `crons: ["*/15 * * * *"]`. At 60/tick that is 240 subs/hour; a 100-sub midnight cluster drains in 2 ticks (≤30 min). The owner has said cron delay is tolerable; this avoids a cron-frequency change and extra purge/reminder load.
- `process_due` still limits auto-resumes to `_DUE_LIMIT` and advances skipped Sundays.
- Summary/log: `due_backlog`, `processed`, `created`, `failed`, `low_balance`, `resumed`, `db_queries`, `db_roundtrips`, `duration_ms`.

**Budget check:** with batches counting as one query, ~10–13 roundtrips per sub. 60 × 13 = 780, plus reminders/purge ~50, under the Paid 1,000 cap. If a staging/local 60-sub run exceeds 900 roundtrips, lower `_DUE_LIMIT` to 40 before release.

**Free plan:** 50 queries/invocation still fails at ~4 subs. This phase does not make Free viable; Paid remains required for launch.

### 6.10 P0-10 — purge chunk 90

File: `src/app/jobs/scheduler.py`.

- `_PURGE_CHUNK = 90`.
- Applies to `_delete_chunked` and the money-row probe (`rowid IN (...)` with 1 + N params).
- Add a regression test with 500+ expired rows: purge completes, no “too many SQL variables”, second run deletes 0.

### 6.11 P0-11 — indexes + proof

Migration 029 adds the six indexes listed in §5 plus `idx_payments_refund` for the new refund claim.

Verification (local + staging):

```sql
EXPLAIN QUERY PLAN
SELECT 1 FROM ledger_events WHERE ref_type='order' AND ref_id=? AND kind='dues' AND d_dues>0 LIMIT 1;
EXPLAIN QUERY PLAN
SELECT rowid FROM audit_log WHERE created_at < ?;
EXPLAIN QUERY PLAN
DELETE FROM idempotency_keys WHERE created_at < ?;
EXPLAIN QUERY PLAN
DELETE FROM rate_counters WHERE window_start < ?;
EXPLAIN QUERY PLAN
SELECT * FROM subscriptions WHERE status='active' AND canceled_at IS NULL AND next_run <= ? ORDER BY next_run, id LIMIT 60;
EXPLAIN QUERY PLAN
SELECT id FROM orders WHERE address_id=? AND state=?;
```

Record the plan output in the results doc. If an index is not used, drop it before release (write cost is real).

## 7. D1 batch hardening (prerequisite)

File: `src/app/db_d1.py`, `tests/test_d1_batch.py` (new).

- `D1Conn.batch` must inspect each result’s `success` flag. If `False`, raise an error with the statement index and sanitized message; never zip/return a partial batch. The JS API returns per-statement `success`; the Python binding may raise instead, so handle both.
- `D1Conn.execute` does the same for `run()` results.
- `AsyncSqliteConn.batch` wraps the sequence in `BEGIN IMMEDIATE` when not already in a transaction, rolls back on exception, and leaves the commit to the caller. This makes local tests match D1’s all-or-nothing contract.
- Tests: fake D1 binding that fails statement N → no partial writes; fake success → rowcounts preserved; 90-param chunk test; batch counts as one roundtrip in `record_db`.

**Why first:** every fix below depends on a failed batch actually rolling back. Today the suite only exercises `AsyncSqliteConn`; the D1 failure path is untested.

## 8. Phase 1B — N+1 batching (optional)

### 8.1 Vendor route

File: `src/app/services/vendor_service.py` (`today_route`, lines ~302-366).

After the stop rows are fetched:

- Collect `customer_id`s; one query: `SELECT customer_id, held FROM ledger WHERE customer_id IN (?,...)` (chunk 90). Map `held`; default 0.
- Collect `order_id`s; one query: `SELECT order_id, COALESCE(SUM(amount),0) AS paid FROM payments WHERE order_id IN (?,...) AND status IN ('paid','partial') GROUP BY order_id` (chunk 90). Map `paid_sum`; default 0.
- Keep the address-snapshot overlay and `hold_blocked` logic unchanged.

Expected: 2–4 roundtrips for a 40-stop route instead of 80+.

### 8.2 Dues

File: `src/app/services/payment_service.py` (`get_dues`, lines ~211-231).

- One paid-sum aggregate for all open order ids (chunk 90).
- One `SELECT DISTINCT ref_id FROM ledger_events WHERE ref_type='order' AND kind='dues' AND d_dues>0 AND ref_id IN (?,...)` (chunk 90) to replace `_dues_posted` per order.
- Compute `lines`, `order_due`, and `dues` from the maps. The `pay_link`/provider logic is unchanged.

Expected: 2–3 roundtrips instead of 2N+1.

### 8.3 Guardrails

- Chunk size 90 (D1’s 100-bound-parameter limit).
- No behavior change to `paid_sum_for_order`/`_dues_posted` for single-order callers.
- Query-count regression test using `start_metrics()`/`current_metrics()` around the service call: assert the roundtrip count is independent of N for N=1 vs N=40.

## 9. Tests

### 9.1 New deterministic atomicity tests

File: `tests/test_p0_atomicity.py` (new).

| Test | Assertion |
|---|---|
| Cancel mid-batch failure | Order stays in the original state; no event, ledger, credit, or refund row |
| Two cancels, same from-state | One cancel event, one deposit reversal, one refund; loser gets `AlreadyCancelled`/409 |
| Cancel after webhook refund claim | Cancel does not refund the already-claimed payment again |
| Webhook duplicate (same `provider_ref`) | One paid payment, one order update, one ledger clear, second returns `_duplicate` |
| Webhook vs cancel (both orders) | Exactly one refund per payment; order ends cancelled; no `paid_upi` on a cancelled order |
| Webhook on COD order | Capture recorded + refund queued; order stays COD/unpaid |
| Dues duplicate intent | One set of allocation payments; second returns `_duplicate` |
| Dues + concurrent order cancel | Unallocated amount is refunded; no payment on the cancelled order |
| Two transitions | One event, one state change, one postpaid dues row; loser 409 |
| Subscription cancel failure | Credit balance unchanged; no refund/credit rows |
| Prepaid + postpaid cancel | Prepaid refunds only collected credit; postpaid refunds 0 |
| Reissue 4 attempts | 3 succeed, 4th 429; 24h later one succeeds |
| Reissue concurrent | PK conflict retries; never more than 3 rows in the window |

**Concurrency method:** because `WRITE_LOCK` serializes local SQLite, use two complementary tests:

1. **Deterministic interleaving:** run the winning batch, then run the loser’s read+batch against the updated DB. This proves the SQL guards without relying on timing.
2. **File-backed race (best effort):** two connections to a WAL SQLite file, `WRITE_LOCK` monkeypatched to a no-op, `asyncio.gather` on both operations. Assert one winner and no double rows. Mark `@pytest.mark.slow`; skip if the platform cannot open WAL. The deterministic test is the release gate.

### 9.2 Cron tests

File: `tests/test_scheduler.py` / `tests/test_p0_money.py`.

- Order creation failure (monkeypatch `OrderService.create` to raise): `next_run` unchanged, `failed` recorded, retry_at set; next tick with the failure removed creates exactly one order and advances.
- Advance failure after create: next tick replays the same `sub:<id>:<date>` and advances; one order total.
- 100 due subs, limit 60: first tick creates 60, second creates 40; third creates 0.
- Held-range sub does not consume the page.
- `due_attempts` backoff grows and caps at 24h.
- Purge 500+ audit rows succeeds; second run deletes 0.
- `cron_tick` summary includes `db_roundtrips` and `due_backlog`.

### 9.3 D1 and index tests

- `tests/test_d1_batch.py`: success/failure/rowcount/roundtrip counting.
- `tests/test_indexes.py`: `EXPLAIN QUERY PLAN` contains the expected index name for each hot query (skip if the local SQLite version formats differently; assert “USING INDEX” at minimum).

### 9.4 Existing suites

- Full backend: `cd workers/api; $env:PYTHONPATH='src'; python -m pytest -q` — **438 passed** on 2026-10-25 (`results/phase1a-pytest.txt`).
- `ruff check` clean on every changed source/test file (`results/phase1a-ruff.txt`).
- No test was weakened to accommodate the new schema. `029` was added to every explicit migration list.
- New suites: `test_p0_atomicity.py` (13), `test_d1_batch.py` (9), `test_indexes.py` (9), `test_scheduler.py` (12). Details: `2026-10-25-phase1-results.md` §3.

## 10. Observability

- Cron: wrap `cron_tick` in `start_metrics()` / `current_metrics()` / `reset_metrics()`; log one JSON line with the summary above. No secrets, no user phone/UPI/provider refs.
- Money paths: existing request log already records `db_queries`/`db_roundtrips`; the atomic batches should reduce roundtrips and keep statements visible.
- Add a `due_failed` warning log with `sub_id`, `attempts`, `code` (no PII beyond the synthetic/internal sub id). A runbook query for `subscriptions.due_attempts > 0` surfaces stuck plans.
- No new log fields containing tokens, `settlement_token`, `mutation_token`, or `refund_id`.

## 11. Rollout and rollback

### Staging (approved 2026-10-25; apply blocked by D1 quota)

Pre-flight completed read-only: 27 migrations (latest `028`), 1,021 users,
10,000 orders, **0 open dues intents**, 13,991,936 bytes. Applying 029 failed at
2026-10-25 11:44 UTC with Cloudflare code `7500` (free-tier daily row-write
limit); the database is unchanged. Retry after 2026-10-26 00:00 UTC. See
`2026-10-25-phase1-results.md` §5.

1. Apply migration 029 to `shodasha-staging`; record the pre-flight open-intent count.
2. Deploy `water-staging`; cron stays disabled.
3. Run the atomicity smoke: create a synthetic order, cancel it twice, send duplicate signed webhooks, settle dues twice, reissue 4 times, switch to COD after a capture attempt. Use the existing seed tokens; no real provider calls.
4. Run a local 100-due-sub cron test and record `db_roundtrips`.
5. Record query counts for vendor route/dues before/after if 1B is included.

### Production (separate explicit approval)

1. Read-only pre-flight: `npx wrangler d1 migrations list shodasha --remote` and the duplicate-open-intent query.
2. Apply migration 029 **before** deploying code (additive; old code ignores the new columns/table).
3. Deploy the Worker.
4. Smoke: `/health`, catalog, one synthetic cancel/webhook path on a disposable user only if the owner authorizes a write; otherwise verify the read paths and cron log.
5. Never load-test production.

### Rollback

- Code rollback is safe: 029 is additive; old code ignores `mutation_token`, `settlement_token`, `refund_id`, `due_*`, `delivery_code_reissues`, and the new indexes.
- Migration rollback is not recommended; dropping columns/tables loses retry/audit state. If required, it is a separate owner-approved operation with a backup.
- If the cron page size proves too high, lower `_DUE_LIMIT` and redeploy; no schema change.

## 12. Acceptance criteria

- All P0-1..P0-11 fixes implemented with one-batch mutations and CAS guards.
- Deterministic concurrency tests pass; no double refund/credit/event/transition/reissue.
- Induced cron order-creation failure: zero missed deliveries after retry; `next_run` correct.
- Purge works at 500+ rows; 90-param chunks everywhere.
- Migration 029 applies cleanly to staging; `EXPLAIN QUERY PLAN` shows the six indexes used.
- Full backend suite passes; ruff clean; no test weakened.
- Staging smoke has no 5xx from the app and no secrets in logs. **Open:** blocked by the D1 quota; see §11.
- Production remains untouched until the separate gate.
- Context files updated (`progress-tracker.md`, `flow.md`, `decision.md`).

Local criteria are met. The staging apply, staging deploy, and staging smoke
criteria remain open because of the D1 free-tier row-write limit.

## 13. Approval decisions (resolved 2026-10-25)

The owner approved **Phase 1A only** and every recommended option:

1. **Schema:** migration 029 approved as specified — tokens, `payments.refund_id`, `delivery_code_reissues`, `due_*`, unique open dues intent, indexes. The cleanup marks stale duplicate intents `failed`; no money moves.
2. **Scope:** 1A only. Phase 1B N+1 batching is deferred to a separate commit/release after 1A verification.
3. **Cron page size:** keep `*/15`, process 60 due subscriptions per tick, ordered by `next_run, id`; report `due_backlog`. Cron delay is tolerable.
4. **Retry policy:** 15m → 24h exponential backoff, no dead-letter table; stuck plans surface via `due_attempts > 0` and warning logs.
5. **Reissue limit:** `delivery_code_reissues` table, not a Durable Object.
6. **Refund allocation:** `payments.refund_id` is the one-refund-path marker; a late capture creates its own refund row. The cancel response keeps the cancel refund; late-capture refunds appear in the refunds admin list.
7. **Production gate:** staging verification first, then a separate explicit approval for the production migration + deploy.

## 14. File ownership and sequence

| Step | Files | Gate |
|---|---|---|
| 0 | `db_d1.py`, `tests/test_d1_batch.py` | Batch failure rolls back; tests pass |
| 1 | `029_p0_correctness.sql`, test migration lists | Migration applies to a fresh local DB + staging |
| 2 | `order_repo.py`, `subscription_service.py` (cancel/restore) | P0-1/P0-5 tests |
| 3 | `payment_repo.py`, `payment_service.py` | P0-2/P0-3/P0-6 tests |
| 4 | `order_repo.py` (transition), `order_service.py` (reissue) | P0-4/P0-7 tests |
| 5 | `jobs/scheduler.py`, `subscription_service.py` (cron) | P0-8/P0-9/P0-10 tests |
| 6 | Index verification | P0-11 plans recorded |
| 7 | Optional 1B: `vendor_service.py`, `payment_service.py` | Query-count regression |
| 8 | Docs/context sync | Spec results + ADR |

No agent edits another step’s files without the lead’s merge. Existing tests may be extended, never weakened.

## 15. Effort

Rough: 3–5 engineer-days for 1A (including tests and staging verification), 0.5–1 day for 1B. The critical path is the atomicity tests, not the SQL.

---

**Approval:** Phase 1A was approved by the owner on 2026-10-25. Implementation
is complete locally; staging verification is blocked by the D1 free-tier
row-write limit until 2026-10-26 00:00 UTC. Production migration/deploy still
requires a separate explicit approval.
