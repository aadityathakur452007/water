-- 002_auth.sql — C1 users/sessions slice (contract §2 / §4.1 / §14.1).
-- Idempotent (IF NOT EXISTS) — safe to apply on local sqlite and D1.
-- Clocks: ISO-8601 UTC TEXT. All writes parameterized (ssdlc).
-- sessions.family_id: refresh rotation + reuse detection (revoke whole family
-- on burned-token reuse, C7). sessions.created_at: device-cap window (SEC-F01).

CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    phone TEXT UNIQUE,
    firebase_uid TEXT UNIQUE,
    name TEXT,
    role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user','vendor','admin')),
    language TEXT NOT NULL DEFAULT 'hi',
    kyc_status TEXT NOT NULL DEFAULT 'none',
    suspended INTEGER NOT NULL DEFAULT 0,
    suspended_reason TEXT,
    suspended_by TEXT,
    suspended_at TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);

CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    token_hash TEXT UNIQUE NOT NULL,
    refresh_hash TEXT UNIQUE NOT NULL,
    role TEXT NOT NULL DEFAULT 'user',
    device_fp TEXT NOT NULL DEFAULT '',
    family_id TEXT NOT NULL DEFAULT '',
    expires_at TEXT NOT NULL,
    refresh_expires_at TEXT NOT NULL DEFAULT '',
    revoked_at TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_family ON sessions(family_id);

-- Burned refresh tokens: reuse of a rotated token => revoke whole family (C7).
CREATE TABLE IF NOT EXISTS burned_refresh_tokens (
    token_hash TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    created_at TEXT NOT NULL
);
