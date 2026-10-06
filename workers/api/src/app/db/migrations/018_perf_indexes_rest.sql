-- 018_perf_indexes_rest.sql — Phase 8 §8.1 indexes, group 2 (ADR-090).
-- Apply AFTER 017 is landed and measured (D1 single-writer: one index =
-- one writer txn; spec order). Deliberately NOT indexed (spec §8.1):
-- sessions token/refresh hashes (UNIQUE-covered), ledger PK, users phone,
-- ledger/order events (covered), zone-pincode instr()/LIKE (schema fix later).
--
-- APPLY-ONCE NOTE (like 011): all IF NOT EXISTS (idempotent re-run safe),
-- EXCEPT the UNIQUE vendor-period index: if prod already holds duplicate
-- (vendor_id, period) rows it fails LOUDLY at apply time (never silently).
-- Check `SELECT vendor_id, period, COUNT(*) FROM payouts GROUP BY 1, 2
-- HAVING COUNT(*) > 1` before applying; dedupe first if any rows return.
-- D1: apply once via `wrangler d1 execute shodasha --remote --file=<this file>`.
-- Ships unapplied like 014/015/016 did — D1 applies are owner-run.
-- Migrations always apply in numeric order (017 before 018).

CREATE INDEX IF NOT EXISTS idx_orders_state_created ON orders (state, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments (status);
CREATE INDEX IF NOT EXISTS idx_ledger_dues ON ledger (dues);
CREATE INDEX IF NOT EXISTS idx_complaints_status_created ON complaints (status, created_at);
CREATE INDEX IF NOT EXISTS idx_quality_status ON quality_incidents (status);
CREATE INDEX IF NOT EXISTS idx_payouts_status ON payouts (status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payouts_vendor_period ON payouts (vendor_id, period);
CREATE INDEX IF NOT EXISTS idx_vendor_zones_zone ON vendor_zones (zone_id);
CREATE INDEX IF NOT EXISTS idx_sessions_device_created ON sessions (device_fp, created_at);
