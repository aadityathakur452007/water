# Phase 3 — Backend↔frontend contracts (endpoints, shapes, types, pagination)

- **Goal**: every screen reads a real endpoint that returns the shape the UI renders; no mock-only boards, no dual-shape tolerance, no first-page illusions.
- **Workstreams**: W3a backend reads (admin.py, admin_read_repo, vendor_service selects) · W3b admin UI mapping (screens + fixtures) · W3c Flutter mapping (parsers + missing fields). Parallel-safe: W3a owns worker shapes; W3b/W3c adapt + report drift, never invent.

## 3.1 Reconciliation + custody shape alignment [P0-7/P1] (Track D P0/P1)

- **Evidence**: UI expects per-route rows (`finance/index.tsx:105-124`, `dispatch.tsx:234-247`, `operations.tsx:68-86`) but `GET /v1/admin/reconciliation` returns one aggregate (`admin.py:577-588`) → live "No rows"; mock shows a full board. Custody returns `{vendor_id,in_hand}` only (`admin.py:591-596`) vs UI needs name/phone/on_duty → NaN sorts, ID fallbacks; zero-in-hand vendors invisible live.
- **Fix (backend owns truth)**: `GET /v1/admin/reconciliation?date=` returns per-route rows (route/vendor/stops/delivered/cash/upi/jars_out/empty_returned) + aggregate footer; `GET /v1/admin/custody` joins users+profile (name/phone/on_duty, include zeros with flag). Fixtures updated to the real shapes (mock must mirror live, not flatter it).
- **Tests**: seeded day → rows match hand-computed route sums; UI renders live response (no fixture) in mock-off run.

## 3.2 Vendor stop field completion [P1/P2] (Track E §1)

- **Evidence**: `today_route`/`_owned_stop` select no `window_start`, no items/SKU, no instructions col exists, no customer name/phone (`vendor_service.py:140-148,654-665`); app drops `order_id/order_state/deposit_due/triple` in `fromJson` (`route_controller.dart:60-78`); web stop detail anonymous (address only), no call/navigate.
- **Fix**: stops select gains `window_start`, `items_json` (SKU/qty snapshot at dispatch — new col, backfill NULL), customer name/phone (assigned-vendor need-to-know, accepted per portal precedent); app parses + renders all; web detail gains name/phone/call/navigate. New `instructions` col on orders (nullable, user-editable pre-dispatch) surfaced end-to-end.
- **Tests**: stop payload contains all fields; parsers map 1:1 (no dropped keys — add a shape-parity test).

## 3.3 Missing read endpoints [P1/P2] (Tracks D/E/F)

- `GET /orders/{id}/tracking` (contract promise; `detail` substitution is not a tracking resource) — build or delete the contract line (ADR).
- Vendor `quality` list (web takes manual incident id — crutch) + failed-stop list (repooled `failed` renders as pending — `route_controller.dart:57`).
- `POST /leads` (windows returns `lead_capture:true` into a table nobody writes).
- Audit export (CSV of filtered audit; orders CSV exists but page-scoped — label scope or fetch-all).
- `GET /admin/metrics` vs overview duplication — keep both, document which feeds what (no code).

## 3.4 Pagination truth [P1] (Tracks D/F)

- **Evidence**: no UI follows `next_cursor` — orders "Show all" un-slices fetched rows (`orders.tsx:57-60,169-177`); users/vendors client-paginate one fetch; payments search filters the page; trust/leaderboard/funnel slice page 1. Server supports limit/cursor.
- **Fix**: cursor-follow on orders/users/ledger/audit (load-more appends, count shows "page 1 of …" honestly), server-driven search on payments (send query, don't filter page), trust counts from dedicated count queries (not page filters). No virtualization library until a 200-row render is measured slow (measure first).
- **Tests**: 200-row seed → load-more reaches row 200; counts match DB counts.

## 3.5 Exact types, invalidation, config [P2/P3] (Tracks D/F)

- Drop dual-shape tolerance (`vendor-types.ts:111-112`, preview adapters) — exact server shapes, fail fast on drift (contract test per endpoint shape).
- Missing invalidations: `config.tsx:18-27` save + `operations.tsx:24` generate → add `useInvalidateAdmin` (the only two sites lacking it).
- Config "paise unless noted" → per-key unit labels (money-trap); order-detail bill gains fee/deposit breakup; GMV chart unit vs card unit reconciled with explicit unit caption.
- UTC-day → IST business day for "today"/series (`admin.py:1013-1014`); dues card vs dunning-200 cap labeled; single status legend for the three vocabularies (orders/payments/payouts).
- Ledger badge `held>10` → `>3` to match `HOLD_BLOCK_LIMIT` (or make limit config-driven — decide, ADR).
- Users invented fields (Team/workspace/lastActive) removed or sourced; vendors list joins custody (no zeros); Operations duplication resolved (merge into Finance/Dispatch or justify unique decision per tab).

## 3.6 Exit criteria

- [ ] Zero mock-only boards (every screen renders live response in live mode)
- [ ] Cursor pagination on 4+ screens with count honesty; no client-side counts over page 1 presented as totals
- [ ] Contract shape tests per new/changed endpoint; dual-shape adapters deleted
