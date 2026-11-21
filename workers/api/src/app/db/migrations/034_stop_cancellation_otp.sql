-- 034_stop_cancellation_otp.sql
-- Supports rider stop cancellation with vendor-issued cancellation OTP.

ALTER TABLE stops ADD COLUMN cancel_otp TEXT;
ALTER TABLE stops ADD COLUMN cancel_otp_created_at TEXT;
