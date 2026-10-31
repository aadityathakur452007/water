-- cleanup_demo_20261031.sql — remove the two seeded demo accounts and every
-- row they own from production D1. Explicit allowlist only; real users,
-- the real vendor, the admin, and audit_log are deliberately excluded.
--
-- Runbook:
--   1. Fresh export: npx wrangler d1 export shodasha --remote --output <path>
--   2. Preflight:    npx wrangler d1 execute shodasha --remote --file scripts/cleanup_demo_20261031.sql
--   3. Verify the final SELECT in this file; every demo count must be 0.
--
-- FK-safe order: money/delivery children first, then parents, then users.
-- Idempotent: safe to re-run; missing rows delete zero rows.

PRAGMA foreign_keys = ON;

-- Hard guard: the two allowlisted ids must still have their expected roles.
DROP TABLE IF EXISTS _demo_cleanup_guard_20261031;
CREATE TABLE _demo_cleanup_guard_20261031(ok INTEGER NOT NULL CHECK (ok = 1));
INSERT INTO _demo_cleanup_guard_20261031(ok)
SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
  FROM users
 WHERE (id = 'demo-user-1'   AND role <> 'user')
    OR (id = 'demo-vendor-1' AND role <> 'vendor');
DROP TABLE _demo_cleanup_guard_20261031;

-- Pre-flight evidence.
SELECT id, role, phone
  FROM users
 WHERE id IN ('demo-user-1', 'demo-vendor-1');

-- Subscription children.
DELETE FROM subscription_credit_entries
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1')
    OR subscription_id IN (
         SELECT id FROM subscriptions
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'));
DELETE FROM subscription_charges
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1')
    OR subscription_id IN (
         SELECT id FROM subscriptions
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'));
DELETE FROM skips
 WHERE sub_id IN (
         SELECT id FROM subscriptions
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'));

-- Order money and audit children.
DELETE FROM refunds
 WHERE order_id IN (
         SELECT id FROM orders
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'))
    OR subscription_id IN (
         SELECT id FROM subscriptions
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'));
DELETE FROM payments
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1')
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'));
DELETE FROM dues_intents
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM idempotency_keys
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1')
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'));

-- Delivery children.
DELETE FROM damaged_containers
 WHERE customer_id IN ('demo-user-1', 'demo-vendor-1')
    OR vendor_id IN ('demo-user-1', 'demo-vendor-1')
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'))
    OR stop_id IN (
         SELECT id FROM stops
          WHERE customer_id IN ('demo-user-1', 'demo-vendor-1')
             OR order_id IN (
                  SELECT id FROM orders
                   WHERE user_id IN ('demo-user-1', 'demo-vendor-1')));
DELETE FROM quality_incidents
 WHERE vendor_id IN ('demo-user-1', 'demo-vendor-1')
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'));
DELETE FROM complaints
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1')
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'));
DELETE FROM ratings
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1')
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'));
DELETE FROM order_events
 WHERE order_id IN (
         SELECT id FROM orders
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'));
DELETE FROM stops
 WHERE customer_id IN ('demo-user-1', 'demo-vendor-1')
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'))
    OR return_id IN (
         SELECT id FROM returns
          WHERE user_id IN ('demo-user-1', 'demo-vendor-1'));
DELETE FROM returns
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1');

-- Parents.
DELETE FROM subscriptions
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM orders
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM ledger_events
 WHERE customer_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM ledger
 WHERE customer_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM addresses
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM device_tokens
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM sessions
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM access_codes
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM vendor_access_codes
 WHERE vendor_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM vendor_slots
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM vendor_zones
 WHERE vendor_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM vendor_leaves
 WHERE vendor_id IN ('demo-user-1', 'demo-vendor-1')
    OR cover_vendor_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM vendor_profile
 WHERE user_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM payouts
 WHERE vendor_id IN ('demo-user-1', 'demo-vendor-1');
DELETE FROM routes
 WHERE vendor_id IN ('demo-user-1', 'demo-vendor-1')
    OR id = 'demo-route-1';
DELETE FROM strikes
 WHERE subject_id IN ('demo-user-1', 'demo-vendor-1');

-- Phone-keyed rows that are not FK-linked.
DELETE FROM otp_codes
 WHERE phone IN (SELECT phone FROM users WHERE id IN ('demo-user-1', 'demo-vendor-1'));
DELETE FROM demo_codes
 WHERE phone IN (SELECT phone FROM users WHERE id IN ('demo-user-1', 'demo-vendor-1'));
DELETE FROM leads
 WHERE phone IN (SELECT phone FROM users WHERE id IN ('demo-user-1', 'demo-vendor-1'));

-- The allowlist is role-checked above; audit_log is retained.
DELETE FROM users WHERE id = 'demo-user-1'   AND role = 'user';
DELETE FROM users WHERE id = 'demo-vendor-1' AND role = 'vendor';

-- Verification: every value must be 0.
SELECT
  (SELECT COUNT(*) FROM users
    WHERE id IN ('demo-user-1', 'demo-vendor-1')) AS demo_users,
  (SELECT COUNT(*) FROM orders
    WHERE user_id IN ('demo-user-1', 'demo-vendor-1')) AS demo_orders,
  (SELECT COUNT(*) FROM stops
    WHERE id = 'demo-stop-1'
       OR customer_id IN ('demo-user-1', 'demo-vendor-1')
       OR order_id IN (SELECT id FROM orders
                        WHERE user_id IN ('demo-user-1', 'demo-vendor-1'))) AS demo_stops,
  (SELECT COUNT(*) FROM routes
    WHERE id = 'demo-route-1'
       OR vendor_id IN ('demo-user-1', 'demo-vendor-1')) AS demo_routes,
  (SELECT COUNT(*) FROM sessions
    WHERE user_id IN ('demo-user-1', 'demo-vendor-1')) AS demo_sessions;
