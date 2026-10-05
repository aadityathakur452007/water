# Phase 6 — Admin truth + workflows (pagination, export, invented fields, config)

- **Goal**: every admin number is real, complete past page 1, exportable where decisions need it; no invented columns.
- **Workstream**: W6 admin screens (single stream — screens share table/fixture patterns; parallel sub-splits per screen allowed if file-disjoint).
- **Depends on**: Phase 3 shapes (reconciliation/custody), Phase 0 build fix.

## 6.1 Cursor pagination + honest counts [P1] (Tracks D/F)

- **Evidence**: `next_cursor` never followed; "Show all" un-slices fetched rows (`orders.tsx:57-60,169-177`); users/vendors client-paginate one fetch; trust/leaderboard/funnel slice page 1.
- **Fix**: load-more appends on orders/users/ledger/audit (cursor loop, "page N · total M" caption from server totals where available); payments search sends server query; trust counts + leaderboards from count queries.
- **Tests**: 200-row seed — counts match DB; load-more reaches the last row.

## 6.2 Export + config honesty [P2/P3] (Track D)

- Audit export CSV (filtered scope, labeled); orders CSV scope labeled ("filtered page" vs full-book fetch-all option).
- Config save invalidates + shows saved value (fixes `config.tsx:18-27` staleness); per-key unit labels (kill "paise unless noted").
- GMV chart unit caption reconciled with card; on-time window semantics documented against 30-min copy (or copy fixed).

## 6.3 Invented-field removal [P2] (Track D)

- Users Team/workspace/lastActive → sourced or deleted; vendors onDuty/inHand/reviewHold joined live; Analytics "Customers —" wired or removed; dues-tab raw `customer_id` enriched like Dunning.
- Operations duplication resolved: merge into Finance/Dispatch or record each tab's unique decision (ADR).

## 6.4 States + guards + mock fidelity [P2/P3] (Tracks D/F)

- Preview/access loading+retry via `vendor-states` (no `return null` blanks); QualityCheck query states; secondary-query errors surfaced (no silent `undefined`).
- 429-specific copy on mutations (login screens have it — extend); offline banner for NETWORK (admin currently generic string).
- Mock fixtures mirror live exactly (reconciliation/custody rows, `expires_at` 90d default, `masked_hint` `••last2`); mock writes return shape-realistic envelopes, not bare `{ok:true}` where UI reads fields.

## 6.5 Exit criteria

- [ ] No screen under-reports past page 1 without saying so
- [ ] Audit export + labeled CSV scopes; config round-trip honest
- [ ] Zero invented columns; mock==live shapes (contract test)
