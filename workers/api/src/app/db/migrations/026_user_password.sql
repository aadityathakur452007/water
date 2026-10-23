-- 026_user_password.sql — customer password auth (034).
--
-- Customers sign in with a phone + password. Existing rows keep an empty
-- password_hash and cannot log in until an admin reset; there is no OTP
-- migration or account claim path.
ALTER TABLE users ADD COLUMN password_hash TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN password_updated_at TEXT;
