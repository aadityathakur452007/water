-- 014_access_codes.sql — generalized access-code auth (028, spec §6).
-- ONE codes table serving vendor+admin (fallback path: 027 unmerged, so the
-- vendor-only 013 shape is NOT assumed). New flows use ONLY this table;
-- code_login keeps a best-effort read fallback to legacy vendor_access_codes
-- when present so 027-seeded DBs keep working through the transition.
-- Lifecycle: active → expired (expires_at) / revoked (revoked_at timestamp,
-- never DELETE). last_used_at tracks last successful code_login.
-- expected_role: 'vendor' | 'admin' (users role=user never get codes — they
-- use POST /v1/auth/user/register; enforced in admin.py, not CHECK, so the
-- rule stays a service decision with a 422, not a DB error).
-- The door defaults CLOSED (access_code_login_enabled = 0, fail-closed).
-- Idempotent: CREATEs + index + flag seed are IF NOT EXISTS / OR IGNORE.
-- The sessions ALTER is apply-once (SQLite has no ADD COLUMN IF NOT EXISTS,
-- same caveat as 011_port.sql): on later full-loop re-runs expect (and
-- ignore) a duplicate-column error on that line only. session_repo tolerates
-- a missing column at runtime (pre-014 DBs backfill the cap in refresh()).

CREATE TABLE IF NOT EXISTS access_codes (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    code_hash TEXT NOT NULL, -- sha256 hex of the access code; never the code
    masked_hint TEXT NOT NULL DEFAULT '', -- last-2 chars + •• (e.g. ••9Q)
    expected_role TEXT NOT NULL DEFAULT 'vendor', -- 'vendor' | 'admin'
    expires_at TEXT NOT NULL,
    revoked_at TEXT,
    last_used_at TEXT,
    created_by TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_access_codes_user ON access_codes(user_id);

INSERT OR IGNORE INTO config(key, value) VALUES ('access_code_login_enabled', '0');

-- Absolute 30-day session cap (spec B3): checked in refresh() before rotate.
-- NULL on pre-014 rows → backfilled in code at refresh time as
-- min(refresh_expires_at, created_at + 30d), never renewed on rotation.
ALTER TABLE sessions ADD COLUMN session_expires_at TEXT;
