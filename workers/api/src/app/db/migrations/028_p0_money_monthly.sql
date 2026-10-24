-- 028_p0_money_monthly.sql — P0 money fixes + real monthly billing.
--
-- Additive except the refunds rebuild needed to let a subscription-level
-- refund exist without an order (order_id was NOT NULL). Existing refund rows
-- are copied verbatim; claim/done endpoints keep using the same columns.
--
-- Apply once (SQLite has no ADD COLUMN IF NOT EXISTS). D1:
--   wrangler d1 execute shodasha --remote --file=028_p0_money_monthly.sql
--
-- Money is integer paise. All refs are unique so a retry can never double
-- credit, double debit, or double refund.

ALTER TABLE subscriptions ADD COLUMN billing_status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE subscriptions ADD COLUMN credit_balance_paise INTEGER NOT NULL DEFAULT 0;
-- Refund destination collected at cancel time, so a prepaid balance refund is
-- actionable even when no jar return exists to carry the UPI ID.
ALTER TABLE subscriptions ADD COLUMN refund_upi TEXT NOT NULL DEFAULT '';

-- Dues intents no longer abuse payments.order_id with the synthetic
-- 'dues:<user_id>' value (which violated the orders FK and 500'd live).
CREATE TABLE IF NOT EXISTS dues_intents (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    amount INTEGER NOT NULL, -- paise, frozen at intent time
    provider_ref TEXT UNIQUE, -- Razorpay order id; NULL while pending
    provider_link TEXT,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'link_sent', 'paid', 'failed')),
    created_at TEXT NOT NULL,
    verified_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_dues_intents_user ON dues_intents (user_id, created_at DESC);

-- One prepaid top-up. One open (pending/link_sent) charge per subscription so
-- a double tap cannot mint two Razorpay orders.
CREATE TABLE IF NOT EXISTS subscription_charges (
    id TEXT PRIMARY KEY,
    subscription_id TEXT NOT NULL REFERENCES subscriptions (id),
    user_id TEXT NOT NULL,
    amount INTEGER NOT NULL, -- paise, 30-day water estimate
    provider_ref TEXT UNIQUE,
    provider_link TEXT,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'link_sent', 'paid', 'failed')),
    created_at TEXT NOT NULL,
    verified_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_sub_charges_sub ON subscription_charges (subscription_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_sub_charge_open
    ON subscription_charges (subscription_id)
    WHERE status IN ('pending', 'link_sent');

-- Signed credit ledger. subscriptions.credit_balance_paise is the cached sum;
-- UNIQUE(subscription_id, ref) makes every charge/order/refund idempotent.
CREATE TABLE IF NOT EXISTS subscription_credit_entries (
    id TEXT PRIMARY KEY,
    subscription_id TEXT NOT NULL REFERENCES subscriptions (id),
    user_id TEXT NOT NULL,
    delta INTEGER NOT NULL, -- +topup / -order / +order_refund / -cancel_refund
    kind TEXT NOT NULL
        CHECK (kind IN ('topup', 'order', 'order_refund', 'cancel_refund', 'adjust')),
    ref TEXT NOT NULL,
    created_at TEXT NOT NULL,
    UNIQUE (subscription_id, ref)
);
CREATE INDEX IF NOT EXISTS idx_sub_credit_sub ON subscription_credit_entries (subscription_id, created_at);

-- Refunds: order_id becomes nullable; subscription_id binds a plan refund.
-- Dropping/renaming is safe: no table references refunds and every copied
-- order_id still exists.
DROP TABLE IF EXISTS refunds_v2;
CREATE TABLE refunds_v2 (
    id TEXT PRIMARY KEY,
    order_id TEXT REFERENCES orders (id),
    subscription_id TEXT REFERENCES subscriptions (id),
    payment_id TEXT,
    amount INTEGER NOT NULL DEFAULT 0,
    method TEXT NOT NULL DEFAULT 'upi',
    upi_id TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'claimed', 'done', 'failed')),
    claimed_by TEXT,
    claimed_at TEXT,
    attempts INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    done_at TEXT,
    UNIQUE (payment_id)
);
INSERT INTO refunds_v2 (id, order_id, subscription_id, payment_id, amount, method, upi_id,
                        status, claimed_by, claimed_at, attempts, created_at, done_at)
SELECT id, order_id, NULL, payment_id, amount, method, '',
       status, claimed_by, claimed_at, attempts, created_at, done_at
FROM refunds;
DROP TABLE refunds;
ALTER TABLE refunds_v2 RENAME TO refunds;
CREATE INDEX IF NOT EXISTS idx_refunds_order ON refunds (order_id);
CREATE INDEX IF NOT EXISTS idx_refunds_subscription ON refunds (subscription_id);
