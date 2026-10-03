# 017 Flow Sync — vendor ↔ user ↔ admin ↔ backend handoff repair (spec)

- **Date**: 2026-10-03
- **Branch (planned)**: `017-flow-sync` from `main` — NOTE: 016 work is verified but uncommitted on `016-vendor-dashboard`; see Q1 for merge-vs-stack.
- **Status**: DRAFT — awaiting explicit user approval (no app/backend code written)
- **Source**: audit of 2026-10-03 (vendor feature matrix + sync verdict); all claims cite file:line below.
- **Skills carried**: `security-audit` (guidance — owner-scoping + IDOR-as-404 on every new endpoint) · `impeccable` (Operate — one primary per screen; scanability) · `hallmark` (audit — no invented money/OTP states)
- **Tokens/law**: ShodashaTheme locked (white/ink/blue, r8, 48dp); server paise + `rupees()` display-only; offline outbox + Idempotency-Key preserved; no new packages/tables unless proven (one migration only where proven — F5).

---

## 0. What is broken (load-bearing first — verified, not inferred)

1. **PoD OTP unreachable**: `pod_complete` enforces `delivery_otp` 401 (`vendor_service.py:249-252`), spec says customer reads it from their phone — but `pod_otp|delivery_otp` has **0 hits in `apps/user_app/lib`**. PoD uncompletable by design.
2. **Vendor cash is money-dead**: `PaymentRepo.mark_paid_cash` (`payment_repo.py:211-248`, full/partial + dues reconcile) has **zero callers**; `payments.py:1-100` exposes no cash-post route. Triple cash lands in stop JSON + earnings only; `orders.payment_status` stays `unpaid`, dues never clear, user bill shows dues forever.
3. **`holdBlocked` UI dead**: `RouteStop.holdBlocked` always false — server never emits it (only enforced at create, `order_service.py:40`).
4. **Quality split-brain**: vendor writes in-memory `_QUALITY` (`vendor_service.py:485-494`); admin reads `quality_incidents` table (`007_ops.sql:40-53`, `admin.py:466,475`). Two truths.
5. **Duty evaporates**: `_DUTY` in-memory (`vendor_service.py:106-114`) while `007_ops.sql:10-23` already carries `on_duty/in_hand/duty_on/duty_off` + note `007_ops.sql:6-8` says duty/custody live there. **Schema conflict**: `011_port.sql:22` defines a *different* `vendor_profile` (name/phone/address/hours) — first-applied wins via IF NOT EXISTS; F5 must reconcile.
6. **Admin reads without writes**: payouts approve/clear, capacity PATCH (BFF is GET+POST only, `admin-api.ts:54-66`), zone attach/detach UI, day-close POST, custody write, refunds actions, returns resolve — all absent (admin audit 2026-10-03).
7. **User nits**: dues `pay_link`/`lines` dropped (`subscription_screen.dart:116`), reschedule missing `Idempotency-Key` (contract requires it, `api_client.dart:6`), bill `prev/payments` stay 0 (`orders_controller.dart:454`), `held_jars` vs `held` field-name split (`profile_screen.dart:101` vs `user_shell.dart:111`).
8. **Returns dead end-to-end**: only `POST/GET /returns` + `GET /admin/returns` exist; `assign/pickup/refund` (§4.8) missing in backend, `actions:[]` in admin, no vendor screen.

## 1. Phases (recommendation: A now, B next, C last — see Q2)

- **Phase A (doorstep-unblocking)**: F1 + F2 + F3. Without these, no real delivery can complete and no COD cash is truth.
- **Phase B (trust + admin loop)**: F4 + F5 + F6. Closes quality/duty/payout/capacity/zone/day-close.
- **Phase C (nits + returns)**: F7 + F8. Polish + the one flow needing new backend writes.

## 2. Fixes (request/response per contract, authz per finding)

### F1 — PoD OTP to the user (Phase A)
- **Backend**: `OrderService.detail` (`order_service.py:209`) gains `delivery_otp: str | None` — computed via `pod_otp(order_id, route_date)` reusing `vendor_service.pod_otp`, route date from `stops JOIN routes` (latest route for the order). Included **only** for the owning user (`find_owned` already scopes) and **only** when state ∈ {assigned, dispatched} — hidden before assignment (no stop yet) and after delivered/cancelled/failed (useless, avoids confusion). No new endpoint, additive key.
- **User app**: tracking screen (`tracking_screen.dart:271` 4-step area) shows one honest row when present: `Delivery code: 123456 — rider ko batayein`. Copy Hindi-first (impeccable). No OTP logic client-side — display only.
- **Vendor**: untouched (already enforces + completes).
- **Security**: owner-scoped by construction (`find_owned`); OTP is deterministic server-known, not a secret — exposure equals what the vendor flow already assumes (customer reads it aloud). No oracle change: non-owners never see the order at all (404).
- **Tests**: backend — owner sees OTP when dispatched, hidden when placed/delivered, other user 404; user widget — code row renders iff field present.

### F2 — Vendor cash posts money truth (Phase A)
- **Backend**: NEW `POST /vendor/stops/{id}/cash {amount, idempotency_key?}` → `require_role('vendor')` → `_owned_stop` (404-as-missing, same IDOR rule) → `PaymentService.mark_cash(order_id, amount, vendor_id)` (existing, `payment_service.py:94-95` → `mark_paid_cash`). Response: `{payment, order, ledger}` (existing shape). Cash also bumps `vendor_profile.in_hand` (+amount; `007_ops.sql:17` custody column exists, nothing writes it today) in the same txn; handover-confirm stays Phase B. Replay: same idempotency semantics as triple (scoped key on `POST /v1/vendor/stops/{id}/cash`); double-post beyond total → `mark_paid_cash` raises already-paid (409 via existing `ConflictError`).
  - Why a new endpoint (not inside triple): triple is jar-custody atomic + offline-replayable with version fence; cash needs payment-row + dues-reconcile semantics that `mark_paid_cash` already implements and tests already cover at repo level. One thin route, zero new tables.
- **Vendor app**: after triple success with cash>0, `StopsController` posts cash via `ApiClient.postStopCash` (new method, same `send` seam + Idempotency-Key); notice `Cash jama / post ho gaya`; offline → enqueue into existing outbox item (cash rides the queued triple, posted on sync — `sync_batch` extends per-item cash post after triple apply, per-item results preserved).
- **User app**: untouched — next poll shows `paid_cash`/`partial_dues` via existing badge path (`tracking_screen.dart:378`).
- **Tests**: backend — vendor posts cash for own stop (paid_cash + payment row + dues cleared + in_hand bumped); other vendor 404 with no write; double-post 409 same outcome; sync-batch cash replay no-op. Vendor widget — cash notice renders.

### F3 — `hold_blocked` on stops (Phase A)
- **Backend**: `today_route`/`_owned_stop` compute `hold_blocked: held > 3` via existing `ledger.get(customer)` (same >3 rule as create, `order_service.py:40`); additive bool + existing `hold_reason` Hindi string. Zero new tables; bounded extra reads (stops per route ≤ caps).
- **Vendor app**: untouched — `RouteStop.holdBlocked` + stop-detail/triple-gate copy already render it (`route_screen.dart`, `stop_detail_screen.dart:230-239`, triple disabled `stop_detail_screen.dart:248`).
- **Tests**: backend — held=4 customer → flag true; held=3 → false.

### F4 — Quality single truth (Phase B)
- **Backend**: `vendor_check_quality` moves from `_QUALITY` to `quality_incidents` row (ownership: incident must link via `order_id` to this vendor's stop — same join as complaint verify, `vendor_service.py:460-468` pattern; else 404). Mapping: agree → `status=confirmed`; disagree → stays `open` + `vendor_agree=0` (frozen for 48h triage; satisfies `CHECK(status IN ('open','confirmed','rejected'))`, `007_ops.sql:50`). `seed_quality` seam retires (tests seed the table instead).
- **Admin**: untouched (already reads/writes the table).
- **Tests**: migrate existing quality tests to table seeds + cross-vendor 404.

### F5 — Duty persists + custody truth (Phase B)
- **Backend**: `duty()` reads/writes `vendor_profile.on_duty/duty_on/duty_off` (`007_ops.sql:16,20-21`) instead of `_DUTY`; triple/PoD cash also maintain `in_hand`. **Pre-req**: reconcile `007_ops.sql:10-23` vs `011_port.sql:22` vendor_profile shapes — decision needed in plan (merge columns via new `012_duty_reconcile.sql` keeping IF NOT EXISTS idempotence; exact column union locked at plan, not here).
- **Tests**: duty round-trips across service instances (proves persistence); off-duty sweep unchanged.

### F6 — Admin writes (Phase B, admin_app + workers/api)
- `payouts` approve/clear → `POST /v1/admin/payouts/{id}/approve|clear` (writes `payouts.status/approved_by`, clears `flagged_hold` display source); finance page buttons.
- Capacity PATCH → `PATCH /v1/admin/vendors/{id}/capacity` + BFF PATCH helper (`admin-api.ts` gains `"PATCH"`); vendor-detail edits `max_stops/max_jars/per_stop_fee`.
- Zone attach/detach UI → existing `attach/detach` routes (`admin.py:332`, custody-zero guard kept) surfaced on vendor-detail zones row.
- Day-close POST → `POST /v1/admin/reconciliation/close {route,date}` (writes audit + close marker; additive, no day-close table — audit_log row).
- Custody write → `POST /v1/admin/custody/confirm {vendor_id, amount}` (decrements `in_hand`, audit).
- Refunds actions → approve/reject buttons onto existing `claim/done/failed` routes.
- Returns resolve → `POST /v1/admin/returns/{id}/resolve` (with F8 backend).
- Each: audit_log write (contract §4.11), tests per route.

### F7 — User nits (Phase C, user_app only, no backend)
- Render dues `pay_link`/`lines` (`subscription_screen.dart:116` consumes full shape).
- Reschedule sends `Idempotency-Key` (`api_client.dart:347`, same uuid seam as cancel).
- Bill maps server `prev/payments` (fix `orders_controller.dart:454` zero-stays) or remove the dead fields (one line each — plan decides).
- Unify `held_jars`→`held` (or vice versa) across profile/shell/ledger consumers.

### F8 — Returns end-to-end (Phase C)
- Backend (§4.8): `POST /admin/returns/{id}/assign {route_id|vendor_id}` (queues pickup stop with `stops.return_id`) + vendor `POST /returns/{id}/pickup {empties_collected, caps_missing}` + `POST /admin/returns/{id}/refund {method}` (claim-lock pattern from refunds, C15).
- Vendor app: pickup stop renders in route list (return stops already in schema); triple-sheet variant for pickup counts.
- Admin: resolve/refund buttons (wired in F6) drive these.

## 3. Verify (per phase)
- Backend pytest green + NEW tests per fix (OTP visibility matrix, cash post + 404-no-write + 409 replay + in_hand, hold flag boundary, quality table + isolation, duty persistence, each admin write).
- `flutter analyze` 0 + `flutter test` green both apps; NEW widget tests: OTP row iff present, cash notice, hold-block disables triple (already covered? extend).
- Untouched: windows gen files, `.gitignore`, unrelated junk; 016 branch state resolved per Q1.

## 4. ASCII — the two critical sequences

```
F1 OTP:  User tracking ──GET /orders/{id}──▶ OrderService.detail
         (owner, dispatched) ──stops⋈routes──▶ pod_otp(order,date)
         ──▶ {…, delivery_otp:"123456"} ──▶ "Delivery code — rider ko batayein"
         Vendor PoD ──POST pod {delivery_otp}──▶ 200 delivered (unchanged)

F2 cash: Stop triple ──POST triple──▶ 200 done (unchanged)
         ──POST /vendor/stops/{id}/cash {amount}+Idem-Key──▶ _owned_stop?
         ──▶ mark_paid_cash ──▶ payment row + paid_cash/partial_dues
              + dues reconcile + in_hand+=amount (one txn)
         User poll ──GET /orders/{id}──▶ badge Paid/Due (unchanged path)
```
