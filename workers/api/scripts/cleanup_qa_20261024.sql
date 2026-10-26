-- cleanup_qa_20261024.sql - remove only the nine disposable QA customers
-- created during ADR-133 and the 2026-10-24 money verification.
--
-- Scope is an explicit id allowlist. demo-user-1, demo-vendor-1, the admin,
-- and every pre-existing customer are deliberately absent. Do not replace the
-- allowlist with a name/phone pattern: production has real users too.
--
-- Runbook:
--   1. Take a fresh export:  npx wrangler d1 export shodasha --remote --output qa-backup.sql
--   2. Inspect roles:        npx wrangler d1 execute shodasha --remote --command "SELECT id, role FROM users WHERE id IN (...9 ids...)"
--   3. Run this file:        npx wrangler d1 execute shodasha --remote --file scripts/cleanup_qa_20261024.sql
--   4. Verify:               npx wrangler d1 execute shodasha --remote --command "SELECT COUNT(*) FROM users"
--      Expected users total: 9 (admin + demo customer + demo vendor + 6 real users).
--
-- FK-safe order: subscription/order children first, then subscriptions/orders,
-- then user-owned ledger/address/session rows, then the users themselves.
-- audit_log is intentionally retained as the security trail.

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS _qa_cleanup_guard_20261024;
CREATE TABLE IF NOT EXISTS _qa_cleanup_20261024 (id TEXT PRIMARY KEY);
DELETE FROM _qa_cleanup_20261024;
INSERT OR IGNORE INTO _qa_cleanup_20261024(id) VALUES
  ('69af983e97af40f2aeb4e2c2f2b4ba33'),
  ('d784605287334025b751bff39fe7ed77'),
  ('d1fbcbb835304001a65b703a305e0123'),
  ('c81129c8066b48cdbeb538582e94a874'),
  ('1f28b492a81f466a8264b39adb24084e'),
  ('33fd62b3bb5b4e6d93ccf746ef381e32'),
  ('ccc2d063aefc4153af293c1ccffba126'),
  ('7d714fda16a34fb689d9a9c2b1c307a4'),
  ('7e8efe44c7ad4a25a68823927263adc0');

-- Pre-flight evidence. Every existing allowlisted row must say role=user.
SELECT id, role FROM users WHERE id IN (SELECT id FROM _qa_cleanup_20261024);

-- Hard guard: abort before any delete if an existing allowlisted id is staff.
-- Missing ids are fine (idempotent re-runs); zero non-user rows is the pass.
CREATE TABLE _qa_cleanup_guard_20261024 (ok INTEGER NOT NULL CHECK (ok = 1));
INSERT INTO _qa_cleanup_guard_20261024(ok)
SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
  FROM users
 WHERE id IN (SELECT id FROM _qa_cleanup_20261024)
   AND role <> 'user';
DROP TABLE _qa_cleanup_guard_20261024;

-- Subscription children.
DELETE FROM subscription_credit_entries
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024)
    OR subscription_id IN (
         SELECT id FROM subscriptions
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024));
DELETE FROM subscription_charges
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024)
    OR subscription_id IN (
         SELECT id FROM subscriptions
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024));
DELETE FROM skips
 WHERE sub_id IN (
         SELECT id FROM subscriptions
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024));

-- Order/subscription money and audit children.
DELETE FROM refunds
 WHERE order_id IN (
         SELECT id FROM orders
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024))
    OR subscription_id IN (
         SELECT id FROM subscriptions
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024));
DELETE FROM payments
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024)
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024));
DELETE FROM dues_intents
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024);
DELETE FROM idempotency_keys
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024)
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024));

-- Delivery children.
DELETE FROM damaged_containers
 WHERE customer_id IN (SELECT id FROM _qa_cleanup_20261024)
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024))
    OR stop_id IN (
         SELECT id FROM stops
          WHERE customer_id IN (SELECT id FROM _qa_cleanup_20261024));
DELETE FROM quality_incidents
 WHERE vendor_id IN (SELECT id FROM _qa_cleanup_20261024)
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024));
DELETE FROM complaints
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024)
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024));
DELETE FROM ratings
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024)
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024));
DELETE FROM order_events
 WHERE order_id IN (
         SELECT id FROM orders
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024));
DELETE FROM stops
 WHERE customer_id IN (SELECT id FROM _qa_cleanup_20261024)
    OR order_id IN (
         SELECT id FROM orders
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024))
    OR return_id IN (
         SELECT id FROM returns
          WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024));
DELETE FROM returns
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024);

-- Parents.
DELETE FROM subscriptions
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024);
DELETE FROM orders
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024);
DELETE FROM ledger_events
 WHERE customer_id IN (SELECT id FROM _qa_cleanup_20261024);
DELETE FROM ledger
 WHERE customer_id IN (SELECT id FROM _qa_cleanup_20261024);
DELETE FROM addresses
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024);
DELETE FROM device_tokens
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024);
DELETE FROM sessions
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024);
DELETE FROM access_codes
 WHERE user_id IN (SELECT id FROM _qa_cleanup_20261024);
DELETE FROM strikes
 WHERE subject_id IN (SELECT id FROM _qa_cleanup_20261024);

-- Phone-keyed rows that are not FK-linked.
DELETE FROM otp_codes
 WHERE phone IN (SELECT phone FROM users WHERE id IN (SELECT id FROM _qa_cleanup_20261024));
DELETE FROM demo_codes
 WHERE phone IN (SELECT phone FROM users WHERE id IN (SELECT id FROM _qa_cleanup_20261024));
DELETE FROM leads
 WHERE phone IN (SELECT phone FROM users WHERE id IN (SELECT id FROM _qa_cleanup_20261024));

-- The allowlist is customer-only by design. A staff id stays put and the
-- verification count below exposes it instead of silently deleting staff.
DELETE FROM users
 WHERE id IN (SELECT id FROM _qa_cleanup_20261024)
   AND role = 'user';

DROP TABLE IF EXISTS _qa_cleanup_20261024;

-- Verification. Expected: remaining_qa=0, users_total=9, demo_user=1.
SELECT 'remaining_qa' AS check_name, COUNT(*) AS value
  FROM users
 WHERE id IN ('69af983e97af40f2aeb4e2c2f2b4ba33','d784605287334025b751bff39fe7ed77',
              'd1fbcbb835304001a65b703a305e0123','c81129c8066b48cdbeb538582e94a874',
              '1f28b492a81f466a8264b39adb24084e','33fd62b3bb5b4e6d93ccf746ef381e32',
              'ccc2d063aefc4153af293c1ccffba126','7d714fda16a34fb689d9a9c2b1c307a4',
              '7e8efe44c7ad4a25a68823927263adc0')
UNION ALL
SELECT 'users_total', COUNT(*) FROM users
UNION ALL
SELECT 'demo_user', COUNT(*) FROM users WHERE id = 'demo-user-1';
