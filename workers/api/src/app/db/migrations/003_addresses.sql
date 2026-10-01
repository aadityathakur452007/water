-- 003_addresses.sql: addresses + zones + vendor_zones + leads (contract §2 / §9.1).
-- Idempotent (IF NOT EXISTS) — safe to apply on local sqlite and D1.
-- NOTE: router mounting in app/main.py is the integrator's job (B1 owns that
-- file); this migration only creates tables.

CREATE TABLE IF NOT EXISTS addresses (
    id TEXT PRIMARY KEY,
    user_id TEXT REFERENCES users,
    type TEXT CHECK(type IN ('home','office')),
    label TEXT,
    lat REAL,
    lng REAL,
    place_id TEXT,
    formatted TEXT,
    landmark TEXT,
    pincode TEXT,
    lift_flag INTEGER,
    serviceable INTEGER,
    created_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_addresses_user ON addresses(user_id);

-- Admin-owned geography (contract §9.1). pincodes: comma-separated cluster;
-- polygon: optional GPS-polygon JSON (fallback matcher, slice-3).
CREATE TABLE IF NOT EXISTS zones (
    id TEXT PRIMARY KEY,
    name TEXT,
    pincodes TEXT,
    polygon TEXT,
    active INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS vendor_zones (
    vendor_id TEXT REFERENCES users,
    zone_id TEXT REFERENCES zones,
    priority INTEGER DEFAULT 0,
    PRIMARY KEY(vendor_id, zone_id)
);

-- Unserviceable-pincode + out-of-zone captures (audit addition).
CREATE TABLE IF NOT EXISTS leads (
    id TEXT PRIMARY KEY,
    phone TEXT,
    pincode TEXT,
    lat REAL,
    lng REAL,
    source TEXT,
    created_at TEXT
);
