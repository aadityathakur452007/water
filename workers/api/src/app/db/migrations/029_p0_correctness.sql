-- 029_p0_correctness.sql — Phase 1A P0 money/cron correctness.
--
-- Additive only: CAS tokens, one-refund-path marker, cron retry state, a
-- reissue rate-limit table, one open dues intent per user, and hot-path
-- indexes. Old code ignores every new column/table, so a code rollback is
-- safe after this migration.
--
-- Apply once (SQLite has no ADD COLUMN IF NOT EXISTS). D1 migration runner
-- records it; do not re-run manually.
--
-- Pre-flight (read-only):
--   SELECT user_id, COUNT(*) AS open_intents FROM dues_intents
--   WHERE status IN ('pending','link_sent') GROUP BY user_id HAVING COUNT(*) > 1;

-- CAS/guard tokens (nullable; set only inside the owning batch).
ALTER TABLE orders ADD COLUMN mutation_token TEXT;
ALTER TABLE payments ADD COLUMN settlement_token TEXT;
ALTER TABLE payments ADD COLUMN refund_id TEXT;
ALTER TABLE dues_intents ADD COLUMN settlement_token TEXT;

-- Cron retry/backoff state.
ALTER TABLE subscriptions ADD COLUMN due_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE subscriptions ADD COLUMN due_last_error TEXT;
ALTER TABLE subscriptions ADD COLUMN due_retry_at TEXT;

-- Reissue rate limit: per-order monotonic sequence, sliding 24h count.
CREATE TABLE IF NOT EXISTS delivery_code_reissues (
    order_id TEXT NOT NULL,
    seq INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (order_id, seq)
);
CREATE INDEX IF NOT EXISTS idx_reissues_order_created
    ON delivery_code_reissues (order_id, created_at);

-- One open dues intent per user. Keep the newest; stale duplicates are
-- unusable anyway. No money moves.
UPDATE dues_intents SET status = 'failed'
WHERE status IN ('pending', 'link_sent')
  AND rowid NOT IN (
      SELECT MAX(rowid) FROM dues_intents
      WHERE status IN ('pending', 'link_sent') GROUP BY user_id
  );
CREATE UNIQUE INDEX IF NOT EXISTS uq_dues_intent_open
    ON dues_intents (user_id) WHERE status IN ('pending', 'link_sent');

-- P0-11 hot filters.
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
