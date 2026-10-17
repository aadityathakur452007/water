-- 012_monthly.sql — monthly billing mode on subscriptions (026).
-- Adds ONLY the missing column; everything else already exists in 004.
--   subscriptions.billing_mode: per_delivery (default) | monthly_prepaid | monthly_postpaid
-- payment_method (upi|cod) already stored; monthly works with either.
--
-- APPLY-ONCE NOTE: ALTER fails with "duplicate column name" on re-run
-- (SQLite has no ADD COLUMN IF NOT EXISTS). All CREATEs stay idempotent.
-- D1: apply once via `wrangler d1 execute shodasha --remote --file=<this file>`;
-- on later full-loop re-runs, expect (and ignore) duplicate-column error here.
-- Service also self-heals via PRAGMA + conditional ALTER (ensure_profile precedent).

ALTER TABLE subscriptions ADD COLUMN billing_mode TEXT NOT NULL DEFAULT 'per_delivery';
