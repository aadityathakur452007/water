-- 020_user_email.sql — users.email for name+email+phone signup (no OTP).
--
-- Email is a contact field, never an identity: phone stays the unique login
-- identity (find_by_phone), staff check, and rate-limit key. Nullable shape
-- via NOT NULL DEFAULT '' (same convention as orders.instructions in 016):
-- '' = never given; a set address is never overwritten, only filled once.
-- Apply-once ALTER like 011/014/015/016: re-runs must ignore the
-- duplicate-column error on this line only.

ALTER TABLE users ADD COLUMN email TEXT NOT NULL DEFAULT '';
