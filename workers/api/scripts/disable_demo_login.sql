-- disable_demo_login.sql - close the production demo door.
--
-- The demo door is double-gated: config.demo_login_enabled = 1 plus a matching
-- demo_codes row. Setting the flag to 0 is enough by itself; deleting the codes
-- removes the reusable secrets as well, so a future flag flip cannot reopen the
-- same credentials.
--
-- Runbook:
--   npx wrangler d1 execute shodasha --remote --file scripts/disable_demo_login.sql
-- The demo accounts (demo-user-1, demo-vendor-1) stay for local QA; only the
-- production login path is closed.

INSERT OR REPLACE INTO config (key, value, effective_from, updated_by, updated_at)
VALUES ('demo_login_enabled', '0', datetime('now'), 'closeout_20261024', datetime('now'));

DELETE FROM demo_codes;

-- Expected: demo_login_enabled=0 and demo_codes=0.
SELECT 'demo_login_enabled' AS check_name, value
  FROM config
 WHERE key = 'demo_login_enabled'
UNION ALL
SELECT 'demo_codes', COUNT(*) FROM demo_codes;
