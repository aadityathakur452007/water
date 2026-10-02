-- 011_port.sql — port wrong-repo Phase-1/Phase-2 gaps onto the Workers schema (ADR-055).
-- Wrong-repo source: water-delivery-app 0003_addresses.sql (house/street/area/
-- pincode/phone/lat/lng) + 0004_vendor_profile.sql (vendor_profile/slots/tickets).
-- Water already has lat/lng/pincode (003) and complaints+verify (004/006 + vendor
-- service §14.3), so this file adds ONLY the missing pieces:
--   addresses += house/street/area/phone (nullable, back-compat)
--   vendor_profile + vendor_slots (server vendor profile, Slice 1)
-- Tickets reuse complaints (no new tables — approved: extend complaints).
--
-- APPLY-ONCE NOTE: the four ALTERs below fail with "duplicate column name" on
-- re-run (SQLite has no ADD COLUMN IF NOT EXISTS). The CREATEs are idempotent.
-- D1: apply once via `wrangler d1 execute shodasha --remote --file=<this file>`;
-- on later full-loop re-runs, expect (and ignore) duplicate-column errors on
-- these four lines only. Fresh envs should instead take the columns from an
-- updated 003 (TODO: fold into 003 once D1 prod has 011).

ALTER TABLE addresses ADD COLUMN house TEXT;
ALTER TABLE addresses ADD COLUMN street TEXT;
ALTER TABLE addresses ADD COLUMN area TEXT;
ALTER TABLE addresses ADD COLUMN phone TEXT;

CREATE TABLE IF NOT EXISTS vendor_profile (
    user_id TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    name TEXT NOT NULL DEFAULT '',
    phone TEXT NOT NULL DEFAULT '',
    address TEXT NOT NULL DEFAULT '',
    hours TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS vendor_slots (
    user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    slot_key TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (user_id, slot_key)
);
