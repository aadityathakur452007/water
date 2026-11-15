-- reset_d1_keep_admin_only.sql
-- Purges all users, vendors, riders, orders, stops, routes, payments, ledger, and customer data
-- Preserving ONLY the single admin account (+917828442476).

PRAGMA foreign_keys = OFF;

DELETE FROM subscription_credit_entries;
DELETE FROM subscription_charges;
DELETE FROM skips;
DELETE FROM subscriptions;

DELETE FROM delivery_code_reissues;
DELETE FROM order_events;
DELETE FROM stops;
DELETE FROM routes;
DELETE FROM refunds;
DELETE FROM payments;
DELETE FROM dues_intents;
DELETE FROM orders;

DELETE FROM returns;
DELETE FROM damaged_containers;
DELETE FROM quality_incidents;
DELETE FROM complaints;
DELETE FROM ratings;
DELETE FROM payouts;

DELETE FROM ledger_events;
DELETE FROM ledger;
DELETE FROM addresses;
DELETE FROM leads;

DELETE FROM vendor_access_codes;
DELETE FROM vendor_leaves;
DELETE FROM vendor_slots;
DELETE FROM vendor_zones;
DELETE FROM vendor_profile;

DELETE FROM otp_codes;
DELETE FROM demo_codes;
DELETE FROM rate_counters;
DELETE FROM idempotency_keys;
DELETE FROM burned_refresh_tokens;
DELETE FROM strikes;
DELETE FROM depot_stock;

-- Keep only admin sessions and device tokens
DELETE FROM device_tokens WHERE user_id NOT IN (SELECT id FROM users WHERE role = 'admin');
DELETE FROM sessions WHERE user_id NOT IN (SELECT id FROM users WHERE role = 'admin');
DELETE FROM access_codes WHERE user_id NOT IN (SELECT id FROM users WHERE role = 'admin');

-- Purge all non-admin users
DELETE FROM users WHERE role != 'admin';

PRAGMA foreign_keys = ON;

SELECT id, name, phone, role FROM users;
