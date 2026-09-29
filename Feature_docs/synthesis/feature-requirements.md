# Shodasha Mineral Waters — Unified Feature Requirements (SYN-3)

**Date:** 2026-09-29
**Inputs:** `Feature_docs/research/*/_group-*-summary.md` (6 files: A, B, C, D, E, F) + `context/project-overview.md` + `context/architecture.md`
**Scope anchors (locked inputs, NOT validated prices):** 20L Refill Rs 28 / 20L Jar+Container Rs 30 · Rs 150/jar refundable deposit · cap-missing Rs 3/jar · 30-min arrival window (no live dot MVP) · hours 8AM–8PM ex-Sun/holidays · lift rule gate/2nd-floor · 3-day dispute window · 10-working-day return pickup SLA
**Surfaces:** User app = Flutter Android · Vendor app = Flutter Android · Super Admin = Next.js React web
**Source codes:** A1/A2/A3/A5 · B1/B2/B3/B4 · C1/C2/C3/C5 (C4 unassigned) · D1/D2/D3/D4 · E1/E2 · F1/F2

> Pricing/market figures from F1/F2 and vendor claims (B/C/D) are **unverified source claims** — do not lock constants off them (see Risks + `mvp-scope-v1.md` verification checklist).

## Canonical order-state machine (from D §2 — proposed for Series-3 approval)

Payment is a **separate field** (`unpaid | link_sent | paid_upi | paid_cash | partial_dues`), not an order state.

```
[*] --> placed : POST /api/orders (idempotency key)
placed --> accepted : vendor accepts
placed --> rejected : vendor rejects
rejected --> [*]
placed --> cancelled : user cancels pre-dispatch
accepted --> picked : driver picks up
picked --> packed : packed / loaded
packed --> assigned : assigned to route/driver
assigned --> dispatched : out for delivery
dispatched --> delivered : PoD (OTP+photo+empties+cash)
dispatched --> failed : no-answer / address issue
failed --> dispatched : reattempt
failed --> cancelled : cancel + release stock
delivered --> [*]
```

Guards: forward-or-cancel only (409 otherwise); `dispatched→delivered` requires valid OTP + empties count; cancel after dispatch needs dispatcher override. Full loop + error branches (400/401/403/409/422/link-expired/offline-queue) in D §3. One open decision: keep D4's assign-after-pack vs assign-before-pick.

## Jar-ledger invariant (from B §2)

`held_jars = fulls_delivered − empties_returned − written_off` (never negative; hold-limit blocks delivery). `deposit_balance = paid − refunded` (Rs 150/jar). Every mutation comes from one **atomic stop event** `{stop_id, fulls_given, empties_back, cash, upi, rider, timestamp}`.

---

## 1. User app (Flutter Android)

| ID | Feature | Description | Sources | MVP / v2 | Dependencies |
|----|---------|-------------|---------|----------|--------------|
| FR-01 | Big BOOK NOW repeat home | Home IS the booking screen: last qty + address + window pre-selected; default 2 jars / next morning; reorder ≤3 taps / <30s design target (instrument, don't assert) | A1, A5, C1, D2, F-A1 | MVP | FR-02, FR-05, FR-09, FR-10 |
| FR-02 | SKU steppers on product cards | Two 20L cards (Refill Rs 28 / Jar+Container Rs 30) with inline −/+ steppers; no separate quantity screen; single-sheet checkout | A3, A1, D2, context/project-overview | MVP | — |
| FR-03 | Empty-exchange stepper + deposit math | "Empty jars with cap to return" stepper (E of N); live `(N−E)×150` + "Rs 150/jar refundable" label; cap-missing Rs 3/jar note; no-deposit/non-Shodasha empties = no refund with reason | E1+E2 (R1–R4), A2, B1–B4, C3, D2 | MVP | FR-02, FR-29 |
| FR-04 | Fixed quote lock | Binding quote = f(address, size) shown before commit; never reprice after; cost changes pre-booking only with re-quote | A1, A2 | MVP | FR-02, FR-03 |
| FR-05 | Arrival-window picker | Predefined vendor-schedule windows inside 8AM–8PM ex-Sun/holidays; must pick preferred date; next-working-day start (no same-day subscription start) | E1+E2 (R8,R16), A1, D2 | MVP | FR-27 |
| FR-06 | One-tap pause / resume link | Pause link under BOOK NOW; date-range hold; auto-resume date; ≥24h resume cutoff; push confirms hold; no support call | A5, E1 (R9–R10), B1–B3, C2, D2 | MVP | FR-28 |
| FR-07 | UPI + COD payment chips + invoice links | UPI + COD selectable at booking (deliberate diverge from Bisleri no-COD R5, log as ADR); invoice payment links via SMS/WhatsApp; UPI-vs-COD split tracked | E2 (R5 diverge), B1–B4, C3, D4, project-overview | MVP | FR-31 |
| FR-08 | WhatsApp help + shareables | In-app WhatsApp help button; wa.me prefilled deep links for help / confirmations / shareable bills; support hours 8AM–8PM ex-Sun | C1, B1–B4, D2, project-overview | MVP | — |
| FR-09 | GPS address + serviceability | Cached address + GPS pin; lift flag (no lift → gate/2nd-floor copy + vendor instruction); landmark; pincode serviceable/not-serviceable check | A1, A5, E1+E2 (R17,R20), C5, D2 | MVP | FR-27 |
| FR-10 | Phone OTP auth, price-visible pre-auth | Dual OTP (mobile API + fallback); taps-not-calls signup tied to customer record; never wall quote/prices behind registration | A5, A1, C5, D2 | MVP | — |
| FR-11 | Status card 4-step tracker + window + rider/call | 4-step progress + 30-min window (e.g. 9–9:30 AM) + rider name + call button; map only near-arrival or never in MVP; concierge status language | A1, D2+D4, C1+C5, project-overview | MVP | FR-36 |
| FR-12 | Quality trust line | Strip: RO+UV, last lab-test date, report link, TDS/shelf proof; copy hierarchy taste → ease → proof → health | A2, A3, E2 (R21) | MVP (static) / v2 lab-report viewer | FR-33 |
| FR-13 | Feedback sheet + complaint → WhatsApp | Post-delivery feedback sheet; complaint routes to WhatsApp + admin inbox; 3-day dispute window enforced | D2+D4, E2 (R18), B2 | MVP | FR-33 |
| FR-14 | History + ledger read-only view | Order history + WhatsApp-shareable bills; read-only held-jars + deposit-balance + dues view (disputes die iff visible) | B1–B4, C2, D2 | MVP | FR-29, FR-31 |
| FR-15 | Push notifications | Confirmation (ID/time/amount) + dispatch + arrival + dues/low-balance reminders; window pushes | A5, D2+D4 | MVP | FR-36 |
| FR-16 | Return-jar request | Profile → Return Jar: qty + address + landmark → Submit; 10-working-day pickup SLA shown; refund to UPI/manual in v1, wallet in v2 | E1 (R11–R13) | MVP (request) / v2 (auto-refund) | FR-29, FR-30 |
| FR-17 | Language Hindi | Hindi UI + bills + support in v1; Gujarati + 8–10-lang expansion in v2 | B2+B3, D2 | MVP = Hindi / v2 = Gujarati+ | — |

## 2. Vendor app (Flutter Android)

| ID | Feature | Description | Sources | MVP / v2 | Dependencies |
|----|---------|-------------|---------|----------|--------------|
| FR-18 | Duty toggle + sequenced stop queue | Current-stop / next-alert home; sequenced stops with address, customer, qty, empties-expected; sunlight-legible big targets; Android-only | A1, C2, D2 | MVP | FR-27 |
| FR-19 | Atomic doorstep triple | Per-stop fulls-given + empties-back + cash/UPI in one screen, 1-tap, 44px targets + bulk mode; cap-missing counter (+Rs 3/jar); lift/gate note | B1–B4 (EPIXS triple), E2 (R4), C2 | MVP | FR-29, FR-36 |
| FR-20 | PoD: OTP + counts + cash (photo v2) | `dispatched→delivered` requires valid OTP + empties count + seal flag; cash entry auto-syncs to admin; runtime edit/cancel at door; photo joins in v2 with object storage (ADR-017, contract §4.7 governs) | D2+D4, B1 | MVP (OTP+counts+cash) / v2 (photo) | FR-36, FR-29 |
| FR-21 | Offline queue + sync | Offline-tolerant stop logging; queued sync on reconnect; per-stop payments post as-taken or on sync | B2+B3+B4, D2 | MVP | FR-19, FR-20 |
| FR-22 | Tri-app state advance + reassign | Advance picked→packed→assigned→dispatched→delivered/failed per stop; symmetric accept/decline + timeout; reassign-at-price (admin tool) | A1, D2+D4, C2 | MVP (advance) / v2 (auto-resequence) | FR-27, FR-36 |
| FR-23 | Internal GPS nav + call customer | Internal GPS navigation (customer live map NOT in MVP); call-customer button; GPS active-job only, record visible to rider | A1, D2, B3 | MVP | FR-18 |
| FR-24 | Earnings + reconciliation + hold-block | Per-shift earnings + cash/UPI per-stop totals; hold-limit block surfacing (e.g. 5+ jars / 3+ days pattern); cash-reconciliation view | B2+B3, D2, C2 | MVP (totals+block) / v2 (payroll) | FR-29, FR-32 |
| FR-25 | Loading-sheet consumption | Per-rider take-X / expect-Y loading numbers consumed from admin-built sheets; load-balanced beats | B3, B1, D2 | MVP | FR-27 |

## 3. Super Admin web (Next.js React)

| ID | Feature | Description | Sources | MVP / v2 | Dependencies |
|----|---------|-------------|---------|----------|--------------|
| FR-26 | Order queue + dispatch | Unassigned-orders view; accept/reject; assign; auto-dispatch; multi-stop route sequencing; rider positions; reassign-at-price; cancel-after-dispatch override | A1, D2, B1–B4 | MVP (list+accept/assign) / v2 (auto-sequencing) | FR-36 |
| FR-27 | Schedule / subscription engine | Standing orders Daily/Alt/Weekly/Custom + N-day/weekday/odd-even; auto-generate next delivery; pause-range handling; auto route-sheet + loading generation | B3, B1+B2+B4, E1 (R6–R7), D2 | MVP (basic+pause) / v2 (full matrix) | FR-06 |
| FR-28 | Jar-asset ledger | Plant→vehicle→customer ledger; per-customer held + deposit-balance + dues + history + low-stock / hold-days alerts; never-negative invariant | B1–B4, A2, D2 | MVP | FR-19, FR-20 |
| FR-29 | Deposit-refund closure + adjustments | Closure flow: return jars → refund → ledger zeroed; admin-only manual breakage/write-off adjust in v1 (logged); automation + breakage rules v2 | B4, B3, E1 (R11–R13), D2 | MVP (manual) / v2 (auto) | FR-28 |
| FR-30 | Billing engine + WhatsApp send | `bill = Σ(jars×rate) + prev_dues + deposit_delta − payments`; WhatsApp bills with own-bank zero-fee UPI QR + arithmetic shown; partials carried, never silently zeroed | B2+B3, E2, D4 | MVP | FR-28 |
| FR-31 | Dues / reminders / reconciliation | Dues carry-forward + friendly Hindi reminders; evening route reconciliation (cash+UPI vs pending + jars-out); day-close, never month-end surprise | B1+B4, D2 | MVP | FR-30 |
| FR-32 | CRM-lite + dispute queues | Profiles; ratings/complaint inbox; 10-day return queue + 3-day dispute queue; quality-proof CMS; custom-pricing hooks v2 | A5, E1+E2, D2 | MVP (inbox+queues) / v2 (pricing/promos) | FR-13, FR-16 |
| FR-33 | Analytics + GST + audit | On-time window adherence, repeat rate, reorder time, deposit disputes, UPI-vs-COD split; GST invoice export; granular permissions + audit log on money/deposit edits (v1 = admin-only edits, logged) | A5, B2–B4, D2+D4, F1 | MVP (basic reports) / v2 (NPS/CSAT, competitor-watch) | FR-30, FR-31 |
| FR-34 | Language + comms admin | Hindi bills/templates v1; Gujarati v2; push/SMS/WhatsApp window + reminder admin | B2+B3 | MVP = Hindi / v2 = Gujarati+ | FR-08, FR-15 |

## 4. Cross-cutting (all three surfaces)

| ID | Feature | Description | Sources | MVP / v2 | Dependencies |
|----|---------|-------------|---------|----------|--------------|
| FR-35 | Tri-app order states + API contract | §-top state machine enforced server-side (409 on illegal); idempotency key on POST; payment separate field; error branches 400/401/403/409/422/OTP/link-expired | D2+D4, C5, A1 | MVP | FR-26, FR-22, FR-11 |
| FR-36 | Roles + data-model reservations | Phone-OTP customer / vendor login / admin roles (server-verified sessions); reserve `wallet_balance, deposit_ledger, empties_declared/returned, caps_missing, hold_range, resume_cutoff, return_sla, dispute_window, rate-override, dealer-tier` fields now | C5, E1+E2, B3, A5 | MVP (fields) / v2 (wallet/rates) | — |
| FR-37 | Offline-first + sunlight + i18n plumbing | Vendor offline queue; big targets; Hindi strings externalised day one | B2–B4, A1 | MVP | FR-21, FR-17 |

### Explicitly v2 (parked — see mvp-scope-v1.md)

Wallet (pay/top-up≥order/withdraw), tier rewards + auto-coupons + anti-abuse, referrals/games, AI suggestions + silent auto-reorder (confirm-first rule), IoT (TDS/sensors), customer live map + ±15-min traffic ETA, route-AI auto-sequencing, per-customer/corporate/RWA + dealer-₹18 tier + society billing, payroll/expenses/P&L (30 reports), cards/wallets/dynamic pricing, lab-report viewer, source/certification badges expansion, NPS/CSAT + promos + B2B portal.

### Traceability note

Every FR above carries its group codes; detail lives in `Feature_docs/research/{A…F}/*.md`. Unverified items (A1 40% lift, A3 primaries, B vendor prices/traction, C1 counters, C3 body, D1 reconstruction + D4 CX stats, F1/F2 all numbers, E retail/DB edge) must not be quoted externally — see verification checklist in `mvp-scope-v1.md`.
