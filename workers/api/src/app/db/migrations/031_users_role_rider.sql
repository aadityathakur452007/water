-- 031_users_role_rider.sql — allow 'rider' in users.role CHECK constraint.
-- SQLite cannot alter CHECK constraints in place; requires table recreate.

PRAGMA foreign_keys=OFF;

CREATE TABLE IF NOT EXISTS users_new (
    id TEXT PRIMARY KEY,
    phone TEXT UNIQUE,
    firebase_uid TEXT UNIQUE,
    name TEXT,
    role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user','vendor','admin','rider')),
    language TEXT NOT NULL DEFAULT 'hi',
    kyc_status TEXT NOT NULL DEFAULT 'none',
    suspended INTEGER NOT NULL DEFAULT 0,
    suspended_reason TEXT,
    suspended_by TEXT,
    suspended_at TEXT,
    created_at TEXT NOT NULL,
    email TEXT NOT NULL DEFAULT '',
    assigned_vendor_id TEXT,
    password_hash TEXT NOT NULL DEFAULT '',
    password_updated_at TEXT
);

INSERT OR REPLACE INTO users_new (
    id, phone, firebase_uid, name, role, language, kyc_status,
    suspended, suspended_reason, suspended_by, suspended_at,
    created_at, email, assigned_vendor_id, password_hash, password_updated_at
)
SELECT 
    id, phone, firebase_uid, name, role, language, kyc_status,
    suspended, suspended_reason, suspended_by, suspended_at,
    created_at,
    COALESCE(email, ''),
    assigned_vendor_id,
    COALESCE(password_hash, ''),
    password_updated_at
FROM users;

DROP TABLE users;

ALTER TABLE users_new RENAME TO users;

CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
