# Phase 2 — Core business logic (dispatch pipeline, payment truth, refunds, duty)

- **Goal**: orders can actually move `placed → delivered`; money writes are exact, attributed, and reconcilable.
- **Workstreams**: W2a dispatch pipeline (backend) · W2b payment truth (backend) · W2c vendor duty/repool (backend+app copy) — parallel-safe (dispatch_service, payment paths, duty path are disjoint; shared `write_audit` helper is append-only).
- **Depends on**: Phase 1 role gates (vendor accept must be vendor-scoped from day one).

## 2.1 Dispatch mid-pipeline endpoints [P0-1] (Track A F-000, VERIFIED)

- **Evidence**: `order_repo.py:38-53` LEGAL has `accepted/picked/packed/dispatched`, but endpoint grep for accept/pick/pack/dispatch hits only comments/`return pickup`. Sole forward edge `assign_order` requires `packed` (`dispatch_service.py:282-284`) which nothing produces; scheduler never transitions (`scheduler.py` zero `transition/cancel_settle/assign`). Orders strand at `placed`; suite green because no test walks placed→delivered.
- **Fix**: add vendor-scoped `POST /vendor/stops?` — NO. Correct per architecture: assignment is admin/dispatch (`admin.py` assign/reassign/generate). Add the missing pieces:
  1. `POST /v1/admin/orders/{id}/accept` + `/reject` (admin/dispatcher; accept requires `placed`, sets `accepted` + audit).
  2. `POST /v1/vendor/placed/{order_id}/accept` (vendor self-assign from zone-scoped pool → creates route+stop via `route_for_vendor`, capacity+zone checked, audit `vendor.accept`). This is the vendor "Pull" made real (see 2.5).
  3. `POST /v1/admin/orders/{id}/pack` (accepted→picked→packed as one dispatcher action with actor + audit; keeps single-touch ops).
  4. Dispatch = existing assign (packed→assigned) + `POST /v1/admin/routes/{id}/dispatch` (assigned→dispatched for all pending stops, audit per stop).
- **State diagram**: placed → accepted → picked → packed → assigned → dispatched → delivered/failed (Track A mermaid is the contract).
- **Tests**: full placed→delivered walk (accept→pack→assign→dispatch→triple→cash→PoD) incl. 409s on illegal jumps; zone/capacity rejections; audit rows per transition.

## 2.2 Dues UPI intent link [P0-4] (Track B P0-3)

- **Evidence**: `payment_service.py:130-131` builds bare `upi://pay?pa={vpa}&am={dues}` with no intent row; `apply_webhook:178-179` 404s unknown refs. The only dues-pay button (`subscription_screen.dart:424-431`) leads nowhere server-side.
- **Fix**: dues-pay creates a real intent row (new `intent_for_dues(customer_id, amount)` reusing intent machinery: scoped idem key, `provider_ref`, `link_sent` on a synthetic dues-invoice) OR the button is removed and dues collect only via vendor cash / checkout-time UPI. Decision: intent-row (keeps UPI dues viable). Webhook then settles it like any intent.
- **Tests**: dues link → intent row → signed webhook → dues cleared; unknown-ref webhook still 404.

## 2.3 Overpay / partial-refund / refund governance [P1] (Track B P1-1, P1-2, F9–F10)

- **Evidence**: `mark_paid_cash` `>=` absorbs excess (`payment_repo.py:220`); `cancel_settle` refunds full `order.total` even for `partial_dues` (`order_repo.py:309-314`); refund claim/complete has zero `write_audit` and `complete_refund` discards actor (`payment_service.py:99-104`); actual cash movement on `done` is status-flip only (UNVERIFIED provider payout).
- **Fix**: reject `amount > remaining` (remaining = total − paid_sum) with 422 OVERPAY (explicit over-tender flow later, not silently); cancel refunds `paid_sum`, not total; `write_audit` on claim/complete with actor (maker-checker: claimer ≠ completer enforced); document `done` = status settlement (provider payout out of scope, noted).
- **Tests**: overpay 422 + zero rows; partial-cancel refunds partial; claim→complete by different admin ok, same admin 409/422; audit rows present.

## 2.4 Day-close from payments [P1] (Track B P1-3)

- **Evidence**: `admin.py:715-725` sums `stops.triple` JSON instead of `payments` rows → typos/offline edits diverge from money truth; close is advisory only.
- **Fix**: reconciliation aggregates from `payments` (paid/partial by method + period) with triple-sums kept as a cross-check column (`triple_cash` vs `payments_cash`, mismatch flagged, not blocking).
- **Tests**: seeded triple-typo diverges → mismatch flag; payments-path sums exact.

## 2.5 cod-confirm caller + reschedule idempotency [P1/P2] (Track B P1-4, P2-3)

- **Evidence**: `POST /orders/{id}/cod-confirm` has zero UI callers (grep hits backend tests only); COD dues survive via `mark_paid_cash` carry (`payment_repo.py:228-232`). Reschedule client sends Idempotency-Key but server ignores it (`orders.py:99-106` takes no header); retry double-applies window moves. `POST /subscriptions` has no key at all → double-tap mints duplicates (`checkout_service.dart:59-69`).
- **Fix**: wire cod-confirm into checkout COD path (one call after order create) OR delete the endpoint (decide at build; record in ADR — carrying branch is load-bearing either way, prove with test). Honor Idempotency-Key on reschedule (scoped key like triple) + add key to subscription create (client already mints per sheet-open; subscribe endpoint validates).
- **Tests**: double-tap sub → single row; reschedule retry same key → single apply; cod-confirm path covered or endpoint gone.

## 2.6 Duty-off repool wiring [P1] (Track E §4)

- **Evidence**: `VendorService.duty` only flips `on_duty` (`vendor_service.py:99-122`); `auto_repool` exists solely as admin endpoint (`admin.py:201-203` → `dispatch_service.py:451-469` pending→failed + event). Duty-off confirm copy promises "Baki stops ruk jayenge" (`duty_screen.dart:101-102`) — describes a repool that never fires; pending stops strand.
- **Fix**: duty(off) calls `auto_repool(vendor_id)` in the same service flow (audit `vendor.duty_off` with repooled count); copy stays truthful.
- **Tests**: duty-off with pending stops → stops `failed` + order events + audit; duty-on unaffected.

## 2.7 PoD offline honesty [P1] (Track E §3)

- **Evidence**: `completePod` only sets a "Sync me queue" notice on network fail — never enqueues (`stops_controller.dart:127-164` vs `TripleSheet:176-183` which does); `PodSheet` has no outbox wiring.
- **Fix**: EITHER enqueue PoD like triple (with OTP replay safety: server dedupe on `(stop, otp)` + attempt-cap awareness) OR change notice to honest "internet par hi PoD hoga" + disable offline. Decision: enqueue (matches offline-first contract), with server-side replay treating same-OTP retry as same outcome.
- **Tests**: offline PoD → queued → sync completes delivery; duplicate replay → single transition.

## 2.8 Exit criteria

- [ ] Placed→delivered walk green end-to-end (test + device run)
- [ ] Dues UPI settles; overpay rejected; refunds audited + maker-checker enforced
- [ ] Day-close reads payments with triple cross-check
- [ ] Duty-off repools; PoD offline honest; cod-confirm resolved (wired or deleted)
