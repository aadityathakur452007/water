-- 011_port.sql — port wrong-repo Phase-1/Phase-2 gaps onto the Workers schema (ADR-055).
-- Wrong-repo source: water-delivery-app 0003_addresses.sql (house/street/area/
-- pincode/phone/lat/lng) + Slice-1 server vendor profile/slots.
-- Water already has lat/lng/pincode (003) and complaints+verify (004/006 +
-- vendor service §14.3), so this file adds ONLY the missing pieces:
--   addresses += house/street/area/phone (nullable, back-compat)
--   vendor_profile += name/phone/address/hours (server profile;
--     updated_at already exists from 007_ops)
--   vendor_slots (new table: slot toggles)
-- Tickets reuse complaints (no new tables — approved: extend complaints).
--
-- NOTE: vendor_profile already exists from 007_ops (capacity/duty shape), so
-- the profile columns are ALTERs, not a CREATE — a second vendor_profile
-- CREATE would silently no-op and profile_save would 500 on D1.
--
-- APPLY-ONCE NOTE: the ALTERs below fail with "duplicate column name" on
-- re-run (SQLite has no ADD COLUMN IF NOT EXISTS). The CREATE is idempotent.
-- D1: apply once via `wrangler d1 execute shodasha --remote --file=<this file>`;
-- on later full-loop re-runs, expect (and ignore) duplicate-column errors on
-- these lines only. Migrations always apply in numeric order (007 before 011).

ALTER TABLE addresses ADD COLUMN house TEXT;
ALTER TABLE addresses ADD COLUMN street TEXT;
ALTER TABLE addresses ADD COLUMN area TEXT;
ALTER TABLE addresses ADD COLUMN phone TEXT;

ALTER TABLE vendor_profile ADD COLUMN name TEXT NOT NULL DEFAULT '';
ALTER TABLE vendor_profile ADD COLUMN phone TEXT NOT NULL DEFAULT '';
ALTER TABLE vendor_profile ADD COLUMN address TEXT NOT NULL DEFAULT '';
ALTER TABLE vendor_profile ADD COLUMN hours TEXT NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS vendor_slots (
    user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    slot_key TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (user_id, slot_key)
);
