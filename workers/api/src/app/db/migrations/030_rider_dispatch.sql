-- 030_rider_dispatch.sql — Rider role and stop assignment for doorstep OTP delivery
--
-- Adds stops.rider_id so vendors/admins can assign individual delivery stops to specific riders.
-- When rider_id is NULL, stops are claimable/viewable by all active riders of that vendor.

ALTER TABLE stops ADD COLUMN rider_id TEXT;
CREATE INDEX IF NOT EXISTS idx_stops_rider ON stops (rider_id, status);
