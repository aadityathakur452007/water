-- 015_pod_otp.sql — random per-stop PoD OTP + attempt counter (Phase 1 §1.6).
--
-- dispatch mints a random 6-digit code per order stop (assign/reassign) and
-- pod_complete verifies against it with a DB-backed attempt counter (lockout
-- after 5 fails). pod_otp NULL = legacy deterministic code
-- (sha256(order:date) % 1e6) for in-flight rows created before this migration.
-- Code tolerates pre-015 DBs (PRAGMA-gated reads, legacy fallback), so this
-- file is apply-once color like 011/014: CREATEs are IF NOT EXISTS-safe, the
-- ALTERs expect (and ignore) a duplicate-column error on re-runs.
-- The code is a short-lived delivery handoff secret disclosed to the customer
-- by design (tracking screen); it is never logged.

ALTER TABLE stops ADD COLUMN pod_otp TEXT;
ALTER TABLE stops ADD COLUMN pod_attempts INTEGER NOT NULL DEFAULT 0;
