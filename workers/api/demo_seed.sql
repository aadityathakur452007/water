-- demo_seed.sql — demo accounts + demo order/route for QA (D1 + local).
--
-- What this creates (ALL demo-only, safe to wipe):
--   demo customer  +919000000001 / code 111111  (role user)
--   demo vendor    +919000000002 / code 222222  (role vendor)
--   + one COD order (2 refills, Rs 20600 dues) dispatched to the vendor's
--     TODAY route as stop #1 (pending), ready for triple → PoD → earnings.
--   + config demo_login_enabled = 1 (the demo door; set 0 to close it)
--   + demo_codes rows (sha256 hashes only — codes live in docs, never here)
--
-- Idempotent: every write is INSERT OR REPLACE keyed on fixed demo ids, so
-- re-running never duplicates. Run on D1 with:
--   wrangler d1 execute shodasha --file=./demo_seed.sql
-- or locally with:  python scripts/seed_demo.py
-- Revoke demo access any time with:
--   wrangler d1 execute shodasha --command="UPDATE config SET value='0' WHERE key='demo_login_enabled'"
--   wrangler d1 execute shodasha --command="DELETE FROM demo_codes"

-- 1. accounts ---------------------------------------------------------------
INSERT OR REPLACE INTO users (id, phone, firebase_uid, name, role, language, kyc_status, suspended, created_at)
VALUES
  ('demo-user-1', '+919000000001', NULL, 'Demo Customer', 'user', 'hi', 'none', 0, datetime('now')),
  ('demo-vendor-1', '+919000000002', NULL, 'Demo Vendor', 'vendor', 'hi', 'verified', 0, datetime('now'));

INSERT OR REPLACE INTO vendor_profile (user_id, max_stops_per_shift, max_jars_per_shift, per_stop_fee, active, on_duty, in_hand, kyc_note, review_hold, updated_at)
VALUES ('demo-vendor-1', 25, 60, 0, 1, 0, 0, 'demo seed', 0, datetime('now'));

-- 2. customer address (home, Delhi pin) --------------------------------------
INSERT OR REPLACE INTO addresses (id, user_id, type, label, lat, lng, place_id, formatted, landmark, pincode, lift_flag, serviceable, created_at)
VALUES ('demo-addr-1', 'demo-user-1', 'home', 'Ghar', 28.6139, 77.2090, NULL,
        'Demo House 12, MG Road, New Delhi 110001', 'Near metro gate', '110001', 0, 1, datetime('now'));

-- 3. COD order, dispatched: 2 refills (Rs 56) + deposit (2-1)*150 = Rs 206 --
INSERT OR REPLACE INTO orders (id, user_id, address_id, items, n, e, m, water_bill, deposit_due, cap_charge, total, payment_mode, payment_status, state, window_start, window_end, idempotency_key, payload_hash, quote_hash, quote_rate_version, created_at)
VALUES ('demo-order-1', 'demo-user-1', 'demo-addr-1',
        '[{"sku":"refill","qty":2}]', 2, 1, 0, 5600, 15000, 0, 20600,
        'cod', 'unpaid', 'dispatched',
        date('now') || 'T09:00:00Z', date('now') || 'T09:30:00Z',
        'demo:demo-order-1', '', '', 'v1', datetime('now'));

INSERT OR REPLACE INTO order_events (id, order_id, from_state, to_state, actor_id, actor_role, reason, created_at)
VALUES
  ('demo-ev-1', 'demo-order-1', NULL, 'placed', 'demo-user-1', 'user', 'demo seed', datetime('now')),
  ('demo-ev-2', 'demo-order-1', 'placed', 'accepted', 'seed', 'admin', 'demo seed', datetime('now')),
  ('demo-ev-3', 'demo-order-1', 'accepted', 'picked', 'seed', 'admin', 'demo seed', datetime('now')),
  ('demo-ev-4', 'demo-order-1', 'picked', 'packed', 'seed', 'admin', 'demo seed', datetime('now')),
  ('demo-ev-5', 'demo-order-1', 'packed', 'assigned', 'seed', 'admin', 'demo seed: demo-vendor-1', datetime('now')),
  ('demo-ev-6', 'demo-order-1', 'assigned', 'dispatched', 'seed', 'admin', 'demo seed', datetime('now'));

-- 4. customer ledger: Rs 206 dues, no deposit paid yet (COD at door) --------
INSERT OR REPLACE INTO ledger (customer_id, held, deposit_paid, deposit_refunded, dues, wallet_balance, rate_override)
VALUES ('demo-user-1', 0, 0, 0, 20600, 0, NULL);

-- 5. vendor TODAY route + stop #1 (pending, version 1) -----------------------
INSERT OR REPLACE INTO routes (id, date, vendor_id, zone, status)
VALUES ('demo-route-1', date('now'), 'demo-vendor-1', 'demo-zone', 'open');

INSERT OR REPLACE INTO stops (id, route_id, order_id, return_id, customer_id, seq, fulls_exp, empties_exp, version, triple, status, synced_at)
VALUES ('demo-stop-1', 'demo-route-1', 'demo-order-1', NULL, 'demo-user-1', 1, 2, 1, 1, NULL, 'pending', NULL);

-- 6. demo door: flag on + code hashes (codes: 111111 customer, 222222 vendor)
INSERT OR REPLACE INTO config (key, value, effective_from, updated_by, updated_at)
VALUES ('demo_login_enabled', '1', datetime('now'), 'seed_demo', datetime('now'));

INSERT OR REPLACE INTO demo_codes (phone, code_hash, created_at)
VALUES
  ('+919000000001', 'bcb15f821479b4d5772bd0ca866c00ad5f926e3580720659cc80d39c9d09802a', datetime('now')),
  ('+919000000002', '4cc8f4d609b717356701c57a03e737e5ac8fe885da8c7163d3de47e01849c635', datetime('now'));
