-- 009_demo.sql — demo login codes (contract: demo access for QA).
-- Idempotent (IF NOT EXISTS) — safe on local sqlite and D1.
-- Codes are revocable: DELETE FROM demo_codes WHERE phone = ... ;
-- the whole demo door closes via config demo_login_enabled = 0.

CREATE TABLE IF NOT EXISTS demo_codes (
    phone TEXT PRIMARY KEY,
    code_hash TEXT NOT NULL, -- sha256 hex of the demo code; never the code
    created_at TEXT NOT NULL
);
