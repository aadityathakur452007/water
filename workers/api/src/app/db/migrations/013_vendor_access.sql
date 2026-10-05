-- 013_vendor_access.sql — vendor access codes (027 vendor RBAC, spec §1c).
-- Admin-issued per-vendor login codes: only sha256 hashes stored, never codes.
-- Lifecycle: active → expired (expires_at) / revoked (revoked_at timestamp,
-- never DELETE). last_used_at tracks the last successful vendor_login.
-- Idempotent (IF NOT EXISTS). Applies after 010 (seeds the config flag).
-- The door defaults CLOSED (vendor_access_enabled = 0, fail-closed like demo).

CREATE TABLE IF NOT EXISTS vendor_access_codes (
    id TEXT PRIMARY KEY,
    vendor_id TEXT NOT NULL REFERENCES users(id),
    code_hash TEXT NOT NULL, -- sha256 hex of the access code; never the code
    masked_hint TEXT NOT NULL DEFAULT '', -- last-2 chars + •• (e.g. ••9Q)
    expires_at TEXT NOT NULL,
    revoked_at TEXT,
    last_used_at TEXT,
    created_by TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_vendor_access_vendor ON vendor_access_codes(vendor_id);

INSERT OR IGNORE INTO config(key, value) VALUES ('vendor_access_enabled', '0');
