-- 006_aftermath.sql — D3 aftermath slice (subscriptions/returns/complaints/
-- ratings/skips/devices + FCM). SQLite/D1 compatible, idempotent.
--
-- VERIFICATION against 004_orders.sql (2026-09-29): ALL SIX tables already
-- exist there — subscriptions (schedule_type/recurrence/payment_method stored,
-- tier/discount_pct/perks NULL v1), returns (qty/address/status/sla_due),
-- complaints (reason_code/text/photos-NULL-v1/vendor_agree/vendor_note),
-- ratings (once-per-delivered + <=3 shortcut note), skips (sub_id/date/late),
-- device_tokens (per user+device, own-delete). So this file creates NOTHING
-- new: the CREATE TABLE IF NOT EXISTS guards below are intentional no-ops
-- that keep a fresh-DB apply order (002->003->004->005) green, plus the
-- indexes the aftermath queries actually need (owner-scoped lists, skip
-- dedupe). Do NOT add ALTERs here: plain executescript must stay re-runnable
-- on D1 (migrate.py tracks files, not statements).

CREATE TABLE IF NOT EXISTS subscriptions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    address_id TEXT NOT NULL,
    qty INTEGER NOT NULL,
    sku_mix TEXT NOT NULL DEFAULT 'refill',
    window TEXT NOT NULL DEFAULT '',
    next_run TEXT NOT NULL DEFAULT '',
    schedule_type TEXT NOT NULL DEFAULT 'daily',
    recurrence TEXT NOT NULL DEFAULT '',
    payment_method TEXT NOT NULL DEFAULT 'cod',
    tier TEXT,
    discount_pct INTEGER,
    perks TEXT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused')),
    hold_from TEXT,
    hold_to TEXT
);

CREATE TABLE IF NOT EXISTS returns (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    qty INTEGER NOT NULL,
    address_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'requested'
        CHECK (status IN ('requested','picked','refunded','rejected')),
    sla_due TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS complaints (
    id TEXT PRIMARY KEY,
    order_id TEXT NOT NULL REFERENCES orders (id),
    user_id TEXT NOT NULL,
    reason_code TEXT NOT NULL DEFAULT 'other',
    text TEXT NOT NULL DEFAULT '',
    photos TEXT,
    vendor_agree INTEGER,
    vendor_note TEXT,
    status TEXT NOT NULL DEFAULT 'open',
    created_at TEXT NOT NULL,
    resolved_at TEXT
);

CREATE TABLE IF NOT EXISTS ratings (
    order_id TEXT PRIMARY KEY REFERENCES orders (id),
    user_id TEXT NOT NULL,
    stars INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS skips (
    id TEXT PRIMARY KEY,
    sub_id TEXT NOT NULL REFERENCES subscriptions (id),
    date TEXT NOT NULL,
    late INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS device_tokens (
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL,
    PRIMARY KEY (user_id, device_id)
);

-- Aftermath query paths (all IF NOT EXISTS — safe on D1 re-apply).
CREATE INDEX IF NOT EXISTS idx_subs_user ON subscriptions (user_id);
CREATE INDEX IF NOT EXISTS idx_returns_user_created ON returns (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_complaints_user_created ON complaints (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_complaints_order ON complaints (order_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_skips_sub_date ON skips (sub_id, date);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens (user_id);
