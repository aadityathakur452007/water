-- 017_perf_indexes_core.sql — Phase 8 §8.1 hot-path indexes, group 1 (ADR-090).
-- Covers the highest-churn reads: today_route (route+seq), stop joins
-- (order/customer/return), routes-by-vendor-day, audit actor/action scans.
--
-- APPLY-ONCE NOTE (like 011): every statement is CREATE INDEX IF NOT EXISTS
-- (idempotent re-run safe). D1 single-writer note: land this file first,
-- re-measure hot-path query counts (today_route, preview), then apply 018.
-- D1: apply once via `wrangler d1 execute shodasha --remote --file=<this file>`.
-- Ships unapplied like 014/015/016 did — D1 applies are owner-run.
-- Migrations always apply in numeric order.

CREATE INDEX IF NOT EXISTS idx_stops_route_seq ON stops (route_id, seq);
CREATE INDEX IF NOT EXISTS idx_stops_order ON stops (order_id);
CREATE INDEX IF NOT EXISTS idx_stops_customer ON stops (customer_id);
CREATE INDEX IF NOT EXISTS idx_stops_return ON stops (return_id);
CREATE INDEX IF NOT EXISTS idx_routes_vendor_date ON routes (vendor_id, date);
CREATE INDEX IF NOT EXISTS idx_audit_actor_created ON audit_log (actor, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_action_entity ON audit_log (action, entity);
