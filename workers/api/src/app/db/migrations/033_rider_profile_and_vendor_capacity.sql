-- 033_rider_profile_and_vendor_capacity.sql
-- Creates rider_profile table for rider duty tracking (ADR-205)
-- Elevates legacy vendor capacity from restrictive 60 jars to mindful baseline (250 jars)

CREATE TABLE IF NOT EXISTS rider_profile (
    user_id TEXT PRIMARY KEY REFERENCES users(id),
    duty_status TEXT NOT NULL DEFAULT 'on_duty',
    duty_on TEXT,
    duty_off TEXT,
    updated_at TEXT
);

UPDATE vendor_profile SET max_jars_per_shift = 250 WHERE max_jars_per_shift = 60;
