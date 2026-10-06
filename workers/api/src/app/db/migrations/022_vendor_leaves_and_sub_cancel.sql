-- 022_vendor_leaves_and_sub_cancel.sql — Vendor leaves & subscription cancellation proration

ALTER TABLE subscriptions ADD COLUMN canceled_at TEXT DEFAULT NULL;
ALTER TABLE subscriptions ADD COLUMN cancel_reason TEXT NOT NULL DEFAULT '';
ALTER TABLE subscriptions ADD COLUMN refund_amount_paise INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS vendor_leaves (
    id TEXT PRIMARY KEY,
    vendor_id TEXT NOT NULL REFERENCES users(id),
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    reason TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    cover_vendor_id TEXT REFERENCES users(id),
    created_at TEXT NOT NULL,
    reviewed_at TEXT,
    reviewed_by TEXT REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_vendor_leaves_vendor ON vendor_leaves (vendor_id);
CREATE INDEX IF NOT EXISTS idx_vendor_leaves_dates ON vendor_leaves (start_date, end_date, status);
