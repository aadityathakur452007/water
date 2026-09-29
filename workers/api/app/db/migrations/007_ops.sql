-- 007_ops.sql — D4 dispatch/admin ops tables (contract §9.1 / §11 / §14.1).
-- ONLY the tables missing after 003 (zones/vendor_zones/leads) + 004
-- (orders/stops/routes/ledger/complaints/returns): vendor_profile, strikes,
-- quality_incidents, payouts, depot_stock. Idempotent (IF NOT EXISTS).
-- Money: integer paise. Clocks: ISO-8601 UTC TEXT. All writes parameterized.
-- NOTE: duty/custody live on vendor_profile (on_duty/in_hand) — the §9.1
-- `shifts` table is out of D4 scope; duty reads + custody-zero guard use these
-- columns so no extra table is needed.

CREATE TABLE IF NOT EXISTS vendor_profile (
    user_id TEXT PRIMARY KEY REFERENCES users(id),
    max_stops_per_shift INTEGER NOT NULL DEFAULT 25,
    max_jars_per_shift INTEGER NOT NULL DEFAULT 60,
    per_stop_fee INTEGER NOT NULL DEFAULT 0, -- paise; 0 = salary model (§11)
    active INTEGER NOT NULL DEFAULT 1,
    on_duty INTEGER NOT NULL DEFAULT 0,
    in_hand INTEGER NOT NULL DEFAULT 0, -- paise, agency cash in vendor pocket (§11)
    kyc_note TEXT NOT NULL DEFAULT '',
    review_hold INTEGER NOT NULL DEFAULT 0,
    duty_on TEXT,
    duty_off TEXT,
    updated_at TEXT
);

CREATE TABLE IF NOT EXISTS strikes (
    id TEXT PRIMARY KEY,
    subject_id TEXT NOT NULL REFERENCES users(id),
    kind TEXT NOT NULL DEFAULT 'quality', -- quality|fake_delivery|cash|behavior|payment_default|abuse (§14.1)
    severity INTEGER NOT NULL DEFAULT 1,
    ref_type TEXT NOT NULL DEFAULT '',
    ref_id TEXT NOT NULL DEFAULT '',
    note TEXT NOT NULL DEFAULT '',
    created_by TEXT NOT NULL DEFAULT '',
    cleared_by TEXT,
    cleared_at TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_strikes_subject ON strikes(subject_id, created_at);

CREATE TABLE IF NOT EXISTS quality_incidents (
    id TEXT PRIMARY KEY,
    order_id TEXT NOT NULL REFERENCES orders(id),
    vendor_id TEXT NOT NULL REFERENCES users(id),
    batch_code TEXT NOT NULL DEFAULT '',
    reason_code TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '', -- v1: words, not photos (no object storage)
    vendor_check TEXT NOT NULL DEFAULT '',
    vendor_agree INTEGER, -- door/pickup verification (§14.3)
    vendor_note TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','confirmed','rejected')),
    resolution TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_quality_vendor ON quality_incidents(vendor_id, created_at);

CREATE TABLE IF NOT EXISTS payouts (
    id TEXT PRIMARY KEY,
    vendor_id TEXT NOT NULL REFERENCES users(id),
    period TEXT NOT NULL DEFAULT '',
    stops_done INTEGER NOT NULL DEFAULT 0,
    gross_fee INTEGER NOT NULL DEFAULT 0, -- paise
    deductions INTEGER NOT NULL DEFAULT 0, -- paise (custody recovery lands here, §14.2)
    net INTEGER NOT NULL DEFAULT 0, -- paise
    status TEXT NOT NULL DEFAULT 'pending',
    approved_by TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_payouts_vendor ON payouts(vendor_id, created_at);

CREATE TABLE IF NOT EXISTS depot_stock (
    depot_id TEXT PRIMARY KEY,
    fulls INTEGER NOT NULL DEFAULT 0,
    empties INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT
);
