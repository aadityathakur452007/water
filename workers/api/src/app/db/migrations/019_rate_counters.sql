-- 019_rate_counters.sql — Phase 8 §8.4 D1-backed rate counters (ADR-090).
-- Per-key sliding-window counts shared across Worker isolates (the in-memory
-- L1 in auth_service/middleware stays as fast-path; this table is the source
-- of truth). Keys are server-derived only (phone/IP/device_fp from the
-- session or socket — never client-supplied identity, ssdlc).
--
-- APPLY-ONCE NOTE: CREATE TABLE IF NOT EXISTS (idempotent re-run safe).
-- Rows are short-lived (window starts); purge_expired deletes windows older
-- than 2h. D1: apply once via `wrangler d1 execute shodasha --remote
-- --file=<this file>`. Ships unapplied like 014/015/016 did — owner-run.
-- Migrations always apply in numeric order.

CREATE TABLE IF NOT EXISTS rate_counters (
    key TEXT NOT NULL,
    window_start TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (key, window_start)
);
CREATE INDEX IF NOT EXISTS idx_rate_counters_key ON rate_counters (key, window_start);
