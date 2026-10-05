# Phase 8 — Performance (indexes, bounds, atomicity strategy, scheduler, caching)

- **Goal**: hot paths indexed and bounded; money writes atomic-or-compensated on D1; background work O(bounded); static reads cached.
- **Workstream**: W8 backend perf (migrations, services, scheduler, middleware). Single stream (migration order + lock semantics need one owner).
- **Depends on**: Phase 2 (sync/accept shapes affect batch design).

## 8.1 Missing indexes [P1] (Track S2 §8, verified absent)

- Add (measure each on staging-sized seed before/after):
  `idx_stops_route_seq (route_id, seq)` · `idx_stops_order (order_id)` · `idx_stops_customer (customer_id)` · `idx_stops_return (return_id)` · `idx_routes_vendor_date (vendor_id, date)` · `idx_audit_actor_created (actor, created_at)` · `idx_audit_action_entity (action, entity)` · `idx_orders_state_created (state, created_at DESC)` · `idx_payments_status (status)` · `idx_ledger_dues (dues)` · `idx_complaints_status_created` · `idx_quality_status` · `idx_payouts_status` · `UNIQUE idx_payouts_vendor_period` · `idx_vendor_zones_zone (zone_id)` · `idx_sessions_device_created (device_fp, created_at)`.
- Do NOT add: sessions token/refresh hashes (UNIQUE-covered), ledger PK, users phone, ledger/order events (covered). Zone-pincode `instr()` + `LIKE %q%` stay unindexed by design (schema fix later, not here).
- D1 note: each index costs a write on the single writer — land 1–7 first, measure, then rest. Migration idempotent (`IF NOT EXISTS`), apply-once note like 011.

## 8.2 Bounds [P1/P2] (Tracks S2, F)

- `SyncIn.items: Field(max_length=200)` + documented paging (client chunks 100); per-item lock churn measured; consider single-batch endpoint only if D1 batch API available (see 8.3).
- `placed` router `limit` validated (`ge/le`); vendor_complaints/payouts 200-caps + cursors; purge `IN`-list chunked (delete in batches of 500, lock released between).
- Scheduler: `collect_reminders` paged (no full-ledger load), `run_due_subscriptions` batch-bounded with progress log, purge chunked. Cron stays */15.

## 8.3 D1 atomicity strategy [P0-5] (Track B P0-4, S2 §3)

- **Evidence**: `D1Conn.commit/rollback` no-ops (`db_d1.py:81-85`); `WRITE_LOCK` thread-local no-op (`db.py:7-8,25`). Triple/cash/webhook/payout multi-statement "txns" half-apply in prod; concurrent same-key commits interleave; tests on sqlite cannot see it.
- **Fix options** (decide with spike, ADR): (a) D1 batch API single-round-trip per op (preferred if pywrangler binding exposes it); (b) saga/compensation (ledger event + reconciler job that heals partial writes — pairs with day-close cross-check 2.4); (c) narrow critical sections + deterministic dedupe as the idempotency floor (already partially true for cash/triple).
- Minimum regardless: torn-write detector test (kill mid-op harness) + documented windows per money path + `in_hand` bump folded into the SAME batch as cash post (today: two txns `vendor_service.py:322-334`).
- **Tests**: concurrent same-key triple/cash → single effect; torn-write harness green under chosen strategy.

## 8.4 Rate limits to D1 [P2] (S2 §5, F §4)

- Move auth + throttle counters to D1-backed (per existing TODOs): `otp/start-verify`, register phone/IP, code-login device, refresh user. Keep in-memory as L1 with D1 as source of truth (or D1-only if latency acceptable — measure).
- Add `Retry-After` on auth 429s (middleware has it; auth path doesn't); observability: log + metric on limit hits (pairs with Phase 10 alerting).

## 8.5 Caching [P3] (S2 §6, F §3)

- `Cache-Control: public, max-age=300` (+ ETag) on `/catalog`, `/windows`, `/serviceability`, `/admin/config`, `/admin/zones`; BFF honors (drop blanket `no-store` for these paths only). Everything else stays no-store (admin data correctness first).
- Recharts 90-day guard: downsample or cap range (measure render cost first — no virtualization library until proven slow).

## 8.6 Exit criteria

- [ ] Index migration applied; hot-path query counts re-measured (today_route, preview, money_totals, dunning) with before/after in report §13
- [ ] All unbounded inputs capped; purge chunked; scheduler bounded
- [ ] Atomicity strategy implemented + torn-write/concurrency tests green
- [ ] D1 rate counters live with Retry-After + hit logging
