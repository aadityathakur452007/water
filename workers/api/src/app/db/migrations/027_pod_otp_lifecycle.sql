-- 027_pod_otp_lifecycle.sql — delivery-code expiry (034).
--
-- New stops mint a code at assignment and arm the 24h window at dispatch.
-- Existing dispatched stops have no dispatch timestamp; migration time is the
-- honest backfill. Completed/terminal rows keep no secret.
ALTER TABLE stops ADD COLUMN pod_otp_expires_at TEXT;
CREATE INDEX IF NOT EXISTS idx_stops_pod_expiry ON stops(pod_otp_expires_at);

UPDATE stops
SET pod_otp_expires_at = strftime('%Y-%m-%dT%H:%M:%S+00:00', 'now', '+24 hours')
WHERE status = 'pending'
  AND pod_otp IS NOT NULL
  AND pod_otp_expires_at IS NULL
  AND order_id IN (SELECT id FROM orders WHERE state = 'dispatched');

-- Expired secrets are removed immediately; the timestamp stays as a tombstone
-- so the customer UI can say "expired" and offer a reissue.
UPDATE stops
SET pod_otp = NULL
WHERE pod_otp IS NOT NULL
  AND pod_otp_expires_at IS NOT NULL
  AND pod_otp_expires_at <= strftime('%Y-%m-%dT%H:%M:%S+00:00', 'now');

-- Terminal stops never keep a code.
UPDATE stops
SET pod_otp = NULL, pod_otp_expires_at = NULL, pod_attempts = 0
WHERE status IN ('done', 'failed', 'skipped')
   OR order_id IN (SELECT id FROM orders WHERE state IN ('cancelled', 'rejected', 'failed'));
