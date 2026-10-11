-- 025_payments_user_index.sql — Composite index for GET /v1/payments/me user payment history.
--
-- Optimizes SELECT p.*, o.* FROM payments p LEFT JOIN orders o ON o.id = p.order_id
-- WHERE p.user_id = ? ORDER BY p.created_at DESC LIMIT ?
-- Converts full-table payment scans into O(log N) index seeks in Cloudflare D1 / SQLite.

CREATE INDEX IF NOT EXISTS idx_payments_user_created ON payments (user_id, created_at DESC);
