-- 008_otp.sql — server-generated OTP codes (Fast2SMS slice).
-- Idempotent (IF NOT EXISTS). Only the sha256 of the code is stored, never
-- the plain code (ssdlc: secrets at rest). Rows are single-use: consumed
-- (deleted) on first successful verify; burned after OTP_MAX_ATTEMPTS.
-- Clocks: ISO-8601 UTC TEXT. All writes parameterized.
CREATE TABLE IF NOT EXISTS otp_codes (
    phone TEXT PRIMARY KEY,
    code_hash TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL
);
