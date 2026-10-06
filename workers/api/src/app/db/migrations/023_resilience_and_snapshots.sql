-- 023_resilience_and_snapshots.sql
-- ADR-102: Address snapshot freezing on orders + damaged container tracking + stop failure reasons.

ALTER TABLE orders ADD COLUMN address_snapshot_json TEXT;

ALTER TABLE stops ADD COLUMN failure_reason TEXT;

CREATE TABLE IF NOT EXISTS damaged_containers (
    id TEXT PRIMARY KEY,
    order_id TEXT,
    stop_id TEXT,
    customer_id TEXT,
    vendor_id TEXT,
    qty INTEGER NOT NULL DEFAULT 1,
    condition TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_damaged_containers_customer ON damaged_containers (customer_id);
CREATE INDEX IF NOT EXISTS idx_damaged_containers_vendor ON damaged_containers (vendor_id);
