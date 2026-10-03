# 016 Vendor Dashboard (mobile-first, production-ready) — Feature Spec

- **Date**: 2026-10-03
- **Branch**: `016-vendor-dashboard` (from `main` @ 015 merge f006067)
- **Status**: DRAFT — awaiting explicit user approval (no app/backend code written)
- **Inputs**: `Feature_docs/synthesis/vendor-requirements.md` (VR-01/02/03/09/12), `pricing-deposit-model.md` (Rs 150 once-only ADR-059, Rs 3 cap), `Feature_docs/backend/api-contract.md` (§§ 4.7/9/11/12), `Feature_docs/vendor-app/spec.md` (§3–§6), `context/flow.md` (vendor call map), `workers/api/src/app/services/vendor_service.py`, `apps/vendor_app/lib/features/{route,stops,sync,earnings}/` + `core/money.dart`, `apps/vendor_app/pubspec.yaml`
- **Skills loaded**: `impeccable` (Operate — scanability beats expression, one primary per screen) · `hallmark` (audit mode — honest copy, no invented balances) · `redesign-existing-projects` (diagnose before fixing, existing stack) · `mobile-native` (48dp targets, safe areas, no hover UI) · `security-audit` (guidance — owner-scoping, IDOR, least privilege) · `high-end-visual-design` (layout rhythm ONLY — locked tokens stay: white/black/blue, r8, 48dp)
- **Spec-kit**: `specs/` absent → `specify init .` runs at plan stage (after approval), specs kept here in `Feature_docs/vendor-dashboard/`

---

## 1. What this is (one screen, nothing more)

A **single dashboard section at the top of the existing Route tab** (`route_screen.dart:151`) — not a new tab, not a new route. It answers four questions top-to-bottom (§3):

| # | Question | Data (server truth) | Exists today? |
|---|----------|---------------------|---------------|
| (a) | Today: users / jars / to-collect (UPI vs COD split) | computed client-side from `today_route` stops (payment_mode + total already joined) | NO — route shows take-X/expect-Y + done/N only (`route_controller.dart:79-90`) |
| (b) | Stop list: name + address + qty + payment badge + status | `RouteStop` + badge (`route_screen.dart:262-290`, `stop_detail_screen.dart:150-166`) | YES (015) — reused verbatim |
| (c) | Money: collected today, pending payout (display-only) | `GET /vendor/earnings` (`earnings_controller.dart:40`) | YES but separate tab — dashboard inlines the two numbers, no new fetch shape |
| (d) | Can ledger: held / pending per customer | `GET /vendor/customers` grouped stops — **no ledger join today** | PARTIAL — needs additive `held`/`dues` fields on the existing response |

One primary CTA per state (existing actions, surfaced in the dashboard header, never duplicated):

| State | CTA | Existing path |
|-------|-----|---------------|
| off-duty / empty route | Start route (→ duty on + load) | `DutyController.setDuty` → `POST /vendor/duty` |
| stops pending | Triple (→ open first pending stop) | `StopsController.commitTriple` + Idempotency-Key |
| triple done, PoD open | PoD (→ OTP sheet on current stop) | `StopsController.completePod` |
| outbox non-empty / offline | Sync (→ one-tap retry) | `SyncController.syncNow` → `POST /vendor/sync` |

## 2. DNA extracted from the 5 inspiration images (layout ONLY, never colours)

All five share one shell: **ONE banner + ONE hero card + ONE primary CTA per screen**. Applied with locked Shodasha tokens (`theme.dart:7-18` — bg white, ink #111 primaries, blue #0284C7 links/active only, r8, 48dp):

- Banner → today's summary strip (a): "Aaj: N grahak · M jars · Collect Rs X (UPI Rs U / COD Rs C)" — text-only section header (existing route rhythm `route_screen.dart:172-205`), no teal, no pills.
- Hero card → money card (c): bordered container, cash/UPI/collected/pending via `rupees()` (`money.dart:5-12`), read-only note "payout admin clear ke baad".
- Primary CTA → single black `ElevatedButton` (theme `theme.dart:74-86`), one per state, full-width 48dp.
- **Rejected**: 5-tab pill nav (shell already 4-tab `vendor_shell.dart:210-250` — do not add tabs), fake ETA/stock numbers (hallmark honest-copy: loading skeleton / honest empty / error+retry only), yellow CTAs (ours stay black).

## 3. Ranked issue list (missing vs images + §3–§4, each with file:line)

1. **No (a) today-totals strip** — `route_controller.dart:79-90` holds takeFulls/expectEmpties/pendingSync but no users-count, jars-total, collect-split. All inputs already on `RouteStop` (paymentMode/totalPaise/paymentStatus `route_controller.dart:44-46`). Pure client aggregate, zero backend change.
2. **`placed_pool` is globally unscoped (isolation gap)** — `vendor_service.py:149-160` returns ALL `placed` orders with no vendor/zone filter; any authed vendor reads every placed order's address/pincode. Must be zone-scoped (`vendor_zones` ∩ `order_zone`) or removed from dashboard scope. Regression test required.
3. **No (d) per-customer ledger** — `today_customers` (`vendor_service.py:400-424`) joins users (name/phone) but never `ledger` (held/dues). Needs additive fields on the same response (no new endpoint): `held`, `dues` per customer from `ledger_repo.get`.
4. **Money (c) lives in a separate tab** — `earnings_screen.dart:69-151` + `earnings_controller.dart:35-58` work, but the dashboard needs the two numbers inline. Reuse: dashboard calls the same `ApiClient.earnings()` (`api_client.dart:333-340`), no new shape.
5. **No single "today" aggregate endpoint — deliberate** — (a) derives from `today_route` stops already fetched; (c) reuses `earnings`. No new endpoint (ponytail: prove existing carry it — they do, except issue 3's additive fields).
6. **Region rule unwritten** — `dispatch_service.py:110-121` (`order_zone` pincode cluster) + `dispatch_service.py:188-195` (`least_loaded_vendor` via `vendor_zones`) + `subscription_service.py:293-329` (`next_run` due scan) + `dispatch_service.py:319-376` (`generate_routes`) already define attach-by-zone. Dashboard spec only needs to name the rule (§5), not build geo.
7. **Deposit display already correct** — `money.dart:16-20` container-only once-only (ADR-059); vendor never invents deposit. No change.

## 4. Feature list: BUILD vs REJECT (one line each)

- **BUILD (a) TodayStrip widget** — pure client fold over loaded `RouteStop`s (users=distinct stops' customers, jars=Σfulls, collect UPI/COD split by paymentMode, paid excluded via isPaid `route_controller.dart:48-49`). Why: §3(a) is the top question, zero backend cost.
- **BUILD (d) ledger fields on `GET /vendor/customers`** — additive `held_paise`, `dues_paise` per customer (server `ledger_repo.get`, owner-scoped by construction since customers derive from `_owned` stops). Why: only gap that existing endpoints cannot carry; same route, same authz, additive keys.
- **BUILD dashboard composition in Route tab** — TodayStrip + existing stop cards + inline money row + per-customer ledger rows; one CTA per state. Why: §3 one-screen order, reuses `ApiClient.send`, `RouteStop.fromJson`, `syncBatch`.
- **BUILD zone-scope fix for `GET /vendor/placed`** — filter by vendor's zones (`vendor_zones` JOIN `order_zone` pincode match); unzoned orders stay `placed` + `needs_dispatch` (contract §9.1) visible to admin only. Why: closes the cross-vendor read; regression test proves it.
- **BUILD widget tests** — badge + totals (targeted: UPI/COD/Paid badge text, TodayStrip sums, never "Rs 0" for missing totals). Why: §6 verification bar.
- **REJECT new tab / new route** — shell is 4-tab by ADR-056; dashboard is a Route-tab section. Why: do not add tabs per brief.
- **REJECT new backend tables** — `vendor_zones`, `zones`, `ledger`, `routes/stops` cover region + money + isolation. Why: no new geo service/tables without proof (none found).
- **REJECT new endpoints** — `today_route?date=` + `earnings` + `customers` (+2 additive fields) + zone-scoped `placed` carry everything. Why: shortest diff that works.
- **REJECT new Flutter packages** — `pubspec.yaml:30-42` covers http/uuid/secure-storage/prefs/geolocator/pin; skeleton uses existing `blueTint` boxes (`route_screen.dart:96-110`). Why: no new deps without checking (checked — none needed).
- **REJECT client money math** — all paise server-side, `rupees()` display only. Why: contract §0 + ADR-059.
- **REJECT ETA / stock predictions** — hallmark honest-copy: only server counts or honest empty. Why: no invented metrics.
- **REJECT auto-assign on Pull** — approved simple Pull stays (assign runs via `dispatch_service.assign_order` / admin `generate_routes`). Why: needs geo/zones decision, out of dashboard scope.

## 5. Region rule (minimal, reuses existing — no new geo/tables)

**Rule**: a user attaches to a vendor iff the user's order address pincode ∈ `zones.pincodes` for a zone the vendor serves (`vendor_zones.vendor_id = session.user`), evaluated by the existing `order_zone()` (`dispatch_service.py:110-121`); capacity via `least_loaded_vendor()` (`dispatch_service.py:188-195`); daily sheets via `generate_routes()` from due subscriptions (`subscription_service.py:293-329` `next_run <= date`, `dispatch_service.py:319-376`). Unknown zone → `placed` + admin queue, user sees "assigning rider…" (contract §9.1). Dashboard work: apply this rule to scope `placed_pool`; nothing else.

## 6. Isolation proof (every endpoint, regression test)

| Endpoint | Scope predicate (server) | Proof |
|----------|--------------------------|-------|
| `GET /vendor/routes/today` | `routes WHERE vendor_id = session.user AND date` (`vendor_service.py:119-122`) | vendor A cannot name vendor B's route id — empty route shape, no oracle |
| `GET /vendor/stops/{id}` | `_owned_stop` JOIN `routes` `WHERE s.id AND r.vendor_id` (`vendor_service.py:480-493`) | not-yours → 404 same-as-missing (contract §3 IDOR rule) |
| `POST triple / POST pod / POST sync` | all funnel through `_owned_stop` (`vendor_service.py:194,246,292-302`) | cross-vendor triple → 404 before any ledger write |
| `GET /vendor/earnings` | `stops JOIN routes WHERE r.vendor_id AND r.date` (`vendor_service.py:307-311`) | sums only own route |
| `GET /vendor/customers`, `GET /vendor/complaints` | `JOIN routes … r.vendor_id` (`vendor_service.py:402-409,428-437`) | grouped/queued own stops only |
| `GET /vendor/placed` (FIX) | ADD `AND order_zone IN (vendor's zones)` | **new regression test**: seed 2 vendors/2 zones/2 placed orders → vendor A sees only zone-A order; unzoned order invisible to both |

## 7. Request/response per contract (no new shapes except 2 additive keys)

- Vendor polls `GET /vendor/routes/today?date=` + `GET /vendor/placed` (zone-scoped) — existing `ApiClient.todayRoute()` / `placedPool()` (`api_client.dart:281-296`).
- Triple/sync carry `Idempotency-Key` (`api_client.dart:303-331`); 401/403 → `onUnauthorized` → logout (`main.dart:73-79`); offline → outbox `vendor.outbox.v1` + one-tap retry (`sync_controller.dart:54,129-159`).
- `GET /vendor/customers` response: each customer gains `held_paise: int`, `dues_paise: int` (server-computed, 0-default, never null-money confusion). App renders via `rupees()`, hides zero/non-applicable honestly.
- Never silent zeros: loading skeleton (`route_screen.dart:96-110` pattern), honest empty (`route_screen.dart:111-120` pattern), error + retry (`route_screen.dart:121-147` pattern).

## 8. ASCII wireframe — the ONE dashboard (Route tab top, 360dp, light-only)

```
┌─ AppBar: "Aaj ka route" ─────────────┐
│ [search]            [Sync baaki (N)] │  ← existing
├─ DASHBOARD ──────────────────────────┤
│ ┌─ TODAY STRIP (a) ────────────────┐ │
│ │ Aaj: 12 grahak · 24 jars         │ │
│ │ Collect Rs 1,240                 │ │
│ │   UPI Rs 400 · COD Rs 840        │ │  ← client fold, rupees() only
│ │ Done 5/12 · Sync baaki (2)       │ │
│ └──────────────────────────────────┘ │
│ ┌─ ONE PRIMARY CTA (state) ────────┐ │
│ │ [ Start route / Triple / PoD /   │ │  ← black, 48dp, one visible
│ │   Sync — one per state ]         │ │
│ └──────────────────────────────────┘ │
│ ┌─ MONEY (c, display-only) ────────┐ │
│ │ Jama Rs 860 (Cash 460+UPI 400)   │ │
│ │ Baaki Rs 380 · hold: Rs 0        │ │
│ │ "payout admin clear ke baad"     │ │  ← earnings() reuse
│ └──────────────────────────────────┘ │
│ ┌─ CAN LEDGER (d, per customer) ───┐ │
│ │ Ramesh — 2 held · Rs 150 deposit │ │
│ │ Sita — 0 held · Rs 86 baaki      │ │  ← customers + held/dues
│ └──────────────────────────────────┘ │
│ ── STOPS (b, existing cards) ─────── │
│ [seq] Name · 2 jars · UPI·Collect  │ │  ← badge reuse, unchanged
│ [seq] Name · 1 jar · COD·Paid      │ │
│ ── SKIP (existing, greyed) ───────── │
└──────────────────────────────────────┘
 States: skeleton → loaded | empty ("Aaj koi stop nahi") |
         offline/error + [Dobara try karein]. 48dp targets,
 safe-area padding, no hover UI, ellipsis>2 lines.
```

## 9. Verification (minimum resources, maximum task)

- `workers/api` pytest green (incl. NEW zone-scoped placed regression test + customers ledger-fields test).
- `vendor_app` `flutter analyze` 0 + `flutter test` green (incl. NEW targeted widget test: badge UPI/COD/Paid + TodayStrip totals incl. paid-exclusion + no-"Rs 0").
- `apps/user_app`, windows gen files, `.gitignore`, untracked junk (`.freebuff/ .idea/ .utim_tmp/`) untouched.
- Context sync on completion: `progress-tracker.md` + `flow.md` + `decision.md` (append-only ADR-064).

## 10. Open items for approval gate (see clarifying questions in session)

Region-rule edge (unzoned placed visibility), customers ledger zero-display, money-row vs Earnings-tab duplication, TodayStrip paid-order accounting, `placed` limit default.
