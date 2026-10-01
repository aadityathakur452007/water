-- 005_payments.sql — D1 payments slice (SQLite/D1 compatible).
-- ONLY the missing table: 004 already has orders/ledger/refunds/idempotency_keys.
-- Do NOT recreate existing tables. Money integer paise, clocks ISO-8601 UTC TEXT.
-- C16: UNIQUE(provider_ref) — duplicate webhook delivery returns existing, never
-- a second credit. Retention: payments/refunds 30d then purge (contract §0).

CREATE TABLE IF NOT EXISTS payments (
    id TEXT PRIMARY KEY,
    order_id TEXT NOT NULL REFERENCES orders (id),
    user_id TEXT NOT NULL,
    amount INTEGER NOT NULL DEFAULT 0, -- paise, must equal orders.total
    method TEXT NOT NULL DEFAULT 'upi' CHECK (method IN ('upi','cod')),
    provider_ref TEXT UNIQUE, -- UPI ref / cash: cash:{order}:{rand}; NULL allowed pre-intent
    status TEXT NOT NULL DEFAULT 'link_sent'
        CHECK (status IN ('link_sent','paid','partial','failed')),
    created_at TEXT NOT NULL,
    verified_at TEXT -- set when provider/cash confirms money moved
);
CREATE INDEX IF NOT EXISTS idx_payments_order ON payments (order_id);
