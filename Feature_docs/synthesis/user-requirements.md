# User Requirements — Shodasha Mineral Waters Flutter Android User App (v1)

- **Status**: synthesis (SYN-1) — no code
- **Scope**: user app only (Flutter Android). Vendor app + super-admin web appear only as interaction counterparts in `user-flows.md`.
- **Inputs**: `context/project-overview.md` (PO) · `Feature_docs/00-source-index.md` · Group A (`A1, A2, A3, A5`) · `C1-cancan-whatsapp.md` (C1) · `C3-paniwale.md` (C3) · `C5-jalseva-github.md` (C5) · `D4-customer-journey.md` (D4) · Group E (`E1, E2`) · `F-market/_group-F-summary.md` (F1/F2)
- **Pricing caveat**: Rs 28 / Rs 30 / Rs 150 are scope inputs from PO + user reference image. Per F-summary, F2 figures (e.g. Rs 98 QC avg) are UNVERIFIED vendor claims — do not lock pricing off them; local survey gates final price.

## Traceability matrix

| ID | Title | Source(s) | Priority |
|----|-------|-----------|----------|
| UR-01 | Home = repeat booking screen with BOOK NOW | A1, C1, PO | Must |
| UR-02 | Repeat defaults: 2 jars + kal subah (tomorrow morning) | PO, A1, C1, E1 | Must |
| UR-03 | Product card: 20L Refill Rs 28 + stepper | PO, A1, A3 | Must |
| UR-04 | Product card: Jar + Container Rs 30 + stepper | PO, A1, A3 | Must |
| UR-05 | Empty-exchange stepper + Rs 150 deposit note + live math | E1, E2, C3, A2, PO | Must |
| UR-06 | Cap rule: with-cap handover + Rs 3 missing-cap charge | E2 | Must |
| UR-07 | Quote lock before confirm; never reprice after booking | A1, A2 | Must |
| UR-08 | Address + GPS + pincode serviceability check | A1, A5, C5, E1, E2 | Must |
| UR-09 | Delivery window select + 30-min arrival window, no live dot | A1, E1, E2, D4, PO | Must |
| UR-10 | Tracking card: steps + window + rider name + call | A1, A5, D4, PO | Must |
| UR-11 | OTP login (phone-only), quote visible pre-auth | A5, C5, A1 | Must |
| UR-12 | Language: Hindi v1 (Hindi-first, English fallback) | C5, A2 | Must |
| UR-13 | Payment chips: UPI + COD | D4, C5, PO (diverge E2) | Must |
| UR-14 | Firm confirmation: ID + time + amount, WhatsApp-shareable bill | D4, A1, C1, PO | Must |
| UR-15 | One-tap pause auto-delivery | A5, E1, PO | Must |
| UR-16 | Resume ≥24h cutoff + preferred date + auto-resume | E1, A5 | Must |
| UR-17 | WhatsApp help button (home + account + tracking) | C1, C3, E1, PO | Must |
| UR-18 | Order status lifecycle visible to user | D4, A1 | Must |
| UR-19 | Post-delivery feedback / rating | C5, D4 | Should |
| UR-20 | Complaint / dispute ≤3 days via WhatsApp + call | E2, D4, C1 | Must |
| UR-21 | Quality trust line: RO+UV + lab date + report | A2, A3, E2 | Must |
| UR-22 | Return-jar request + 10-working-day SLA | E1 | Must |
| UR-23 | Delivery discipline: hours, Sun/holiday, lift rule, next-day default | E1, E2 | Must |
| UR-24 | Payment safety: idempotency, COD reconcile, reminders | C5, D4 | Must |
| UR-25 | Minimal checkout: single sheet, <30s reorder target | A3, A1, C5 | Should |

MoSCoW: Must = v1 ship blocker · Should = v1 expected, deferrable only with approval · Could = v2 · Won't = explicitly out of v1 (noted inline).

---

## UR-01 — Home is the repeat booking screen (BOOK NOW)
- **Description**: Home screen IS the booking screen (no dashboard). One big BOOK NOW button with last quantity, address, and window pre-selected. 3-tap max repeat path.
- **Source**: A1 (home = booking; reorder = real use case), C1 (predictive one-tap repeat), PO §Core Flow #1
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Cold open with order history shows last qty/address/window pre-selected without extra taps.
  - [ ] BOOK NOW visible above fold on a 5.5" Android device, ≥48dp target.
  - [ ] Repeat path = ≤3 taps from home to confirmed (measured on device).

## UR-02 — Repeat defaults: 2 jars, kal subah
- **Description**: Default booking = 2 jars, delivery = tomorrow morning ("kal subah") unless user changes it. Same-day is not the default.
- **Source**: PO (default 2 jars / tomorrow morning), E1 (no same-day start → next working day), C3 (adapt: same-day = later SLA, not default)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Fresh install / no history defaults to qty 2 + next-working-day morning window.
  - [ ] If next day is Sunday/public holiday, default rolls to next serviceable day with reason shown.
  - [ ] Changing defaults persists as new "last settings" for next open (see UR-01).

## UR-03 — Product card: 20L Jar Refill Rs 28 + stepper prefilled
- **Description**: Product card for 20L Refill at Rs 28 with inline −/+ stepper. Stepper is prefilled (default contributes to the 2-jar total) and adjustable without leaving the list.
- **Source**: A3 (quantity on product page, no extra screen), A1 (named SKUs, not free quantity entry), PO
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Card shows name "20L Jar Refill", "Rs 28", stepper with current count.
  - [ ] Tapping −/+ updates qty inline and updates quote total immediately (no navigation).
  - [ ] Stepper range 0–10; at 0 the card shows "0" and quote excludes it.

## UR-04 — Product card: Jar + Container Rs 30 + stepper prefilled
- **Description**: Product card for 20L Jar + Container (new jar) at Rs 30 with inline −/+ stepper, same inline behaviour as UR-03.
- **Source**: A3, A1, PO (Rs 30 SKU)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Card shows name "20L Jar + Container", "Rs 30", stepper with current count.
  - [ ] −/+ updates inline; combined N = refill qty + new-jar qty drives deposit math (UR-05).
  - [ ] New-jar qty > 0 always triggers deposit-line visibility even if empties declared (E2 formula).

## UR-05 — Empty-exchange stepper + Rs 150 refundable deposit note
- **Description**: Booking card asks empties to return via stepper labelled "Empty jars with cap to return". Shows "Rs 150/jar refundable deposit" note and live math `deposit = max(0, N − E) × 150`.
- **Source**: E1 (empty prompt with cap + stepper, one-time + subscription), E2 (Rs 150 incl. taxes, formula), C3 (Rs 150 refundable, Return & Repeat), A2 (deposit is P&L-critical; show math upfront), PO
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Stepper E clamped 0 ≤ E ≤ N (cannot declare more empties than ordered).
  - [ ] Deposit line updates live, e.g. "2 ordered − 1 empty = Rs 150 deposit (refundable)".
  - [ ] Word "refundable" always adjacent to Rs 150 figure.
  - [ ] Non-Shodasha / no-deposit empties path shows "no refund — reason" at handover (E1 eligibility adapt), never silently accepted.

## UR-06 — Cap rule: handover with caps, Rs 3 per missing cap
- **Description**: Booking shows "Empties must have caps. Rs 3/jar extra if cap missing." Vendor counts caps at handover; charge added there.
- **Source**: E2 §4
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Cap note visible at booking (not only at door).
  - [ ] Handover cap count recorded per order (M missing × Rs 3) and reflected on bill.
  - [ ] Order with 0 caps missing shows no extra charge line.

## UR-07 — Quote lock before confirm; never reprice after booking
- **Description**: Fixed total (water + deposit + disclosed charges) shown BEFORE confirm and frozen at confirm. Price/surge changes allowed pre-booking only with explicit re-quote; reassignment never reprices.
- **Source**: A1 (binding slot price; surge pre-booking only; reassign at quoted price), A2 (seasonal surcharge precedent only if pre-communicated)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Confirm screen shows itemised quote: water + deposit + cap note + total, no hidden line added post-confirm.
  - [ ] Any price change before confirm forces visible re-quote and re-tap to confirm.
  - [ ] After confirm, vendor reassignment / reattempt keeps quoted price (verified in vendor+admin flows).

## UR-08 — Address + GPS + pincode serviceability
- **Description**: Saved addresses with last-used preselected; add/edit address with GPS pin + pincode; BOOK NOW disabled outside service area with reason. Address edits sync to driver stop.
- **Source**: A1 (cached addresses, digital addresses), A5 (address update synced to driver app), C5 (tap-1 location + geohash zone), E1 (address + pincode), E2 (pincode green/red check)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Last-used address preselected on home.
  - [ ] New address requires pincode + GPS pin (or manual pin drop if GPS denied, with warning).
  - [ ] Unserviceable pincode → BOOK NOW disabled + "We are not servicing this pincode" + WhatsApp help link.
  - [ ] Address edit mid-order propagates to vendor stop before dispatch (else blocked with message).

## UR-09 — Delivery window select + 30-min arrival window (no live dot)
- **Description**: User picks a delivery window at booking (default kal subah). After confirm, app shows a firm 30-min arrival window (e.g. 9:00–9:30 AM). No live moving dot in user app; raw GPS stays internal (vendor/admin).
- **Source**: A1 (window beats dot; map only near arrival), D4 (ETA feeds window), E1/E2 (hours + next-day), PO
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Window picker lists only serviceable windows inside 8 AM–8 PM, excluding Sun/holidays.
  - [ ] Confirmed order always shows a 30-min window (start–end), never "arriving soon" alone.
  - [ ] No live rider dot on user map in v1; near-arrival detail (if any) is text ("rider nearby"), not a moving marker.

## UR-10 — Tracking card: 4-step status + window + rider name + call
- **Description**: Order tracking card shows 4-step status, the 30-min window, assigned rider name + call button, and a pause link. Push updates carry window changes.
- **Source**: A1 (window + record), A5 (push windows replace status calls), D4 (picked/packed/assigned/dispatched/delivered lifecycle), PO
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Tracker shows 4 user-facing steps (e.g. Confirmed → Packed → On the way → Delivered) mapped from canonical lifecycle.
  - [ ] Once assigned, rider name + call button visible; tap initiates phone call.
  - [ ] Window change triggers push + in-card update with reason; old window never silently overwritten.
  - [ ] Pause link present on upcoming (undispatched) orders (hands to UR-15).

## UR-11 — OTP login (phone-only), quote visible pre-auth
- **Description**: Phone-number + OTP login; no password/email required in v1. Prices and quote visible WITHOUT account (guest browse); OTP required only at booking commit.
- **Source**: A5 (dual OTP → few-tap signup), C5 (Firebase phone auth + 60s resend pattern), A1 (no registration wall before quote)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Guest can see SKUs, prices, deposit note, and computed quote without login.
  - [ ] OTP: 6-digit, 60s resend timer, invalid-code + expired-code error states.
  - [ ] Successful OTP creates/links customer record; session persists across restart.

## UR-12 — Language: Hindi v1 (Hindi-first, English fallback)
- **Description**: v1 UI ships Hindi-first with English fallback. Mixed-language input tolerated on help/support surfaces where present. RTL-ready layout not required in v1 but strings externalised for v2 languages.
- **Source**: C5 (Hindi-first UI, 22-language ceiling deferred), A2 (low-literacy: read-aloud/visual accommodation spirit)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Language toggle Hindi/English on onboarding + profile; default Hindi.
  - [ ] All booking-critical strings (qty, deposit, window, pay, confirm) available in Hindi; missing key falls back to English, never blank.
  - [ ] Strings in resource files (no hardcoded UI copy) to allow v2 additions.

## UR-13 — Payment chips: UPI + COD
- **Description**: Booking offers UPI and Cash on Delivery chips. Bisleri is prepaid-only — Shodasha deliberately diverges (local Rs 28/30 refill market). Deposit payable via UPI now or cash at door.
- **Source**: D4 (flexible modes incl. cash; driver cash entry), C5 (UPI intent + state guards), PO; diverge-from E2 (no-COD) — log as ADR
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] UPI / COD chips single-select, preselected last mode.
  - [ ] UPI select → UPI intent; COD select → "Pay cash at door" note + deposit-due-at-door line.
  - [ ] No dead-end: payment failure returns to booking sheet with quote intact (see UR-24 guards).

## UR-14 — Firm confirmation: ID + time + amount, WhatsApp-shareable bill
- **Description**: After confirm/pay, show order ID + delivery time/window + amount charged/due. Invoice/bill viewable in-app and shareable to WhatsApp (link-pay pattern for UPI dues).
- **Source**: D4 (auto-generated summaries/invoices, link-pay, NPS driver), A1 (confirmation as record), C1 (concierge alerts + shareable confirmations), PO (goal #3 + #4)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Confirmation screen always shows order ID, window, amount paid/due — none missing.
  - [ ] "Share on WhatsApp" prefills `wa.me` text with order ID + qty + amount + address (C1 pattern).
  - [ ] Bill re-openable from order history; pending-dues state shows pay-link (D4 link-pay).

## UR-15 — One-tap pause auto-delivery
- **Description**: Pause link under BOOK NOW / on upcoming orders. Hold for a date range; push confirms hold; no support call needed.
- **Source**: A5 (calendar pause without calling support), E1 FAQ-3 (Hold Deliveries + date range), PO
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Pause from home or order card in 1 tap + date-range pick + Confirm.
  - [ ] Paused state visible (badge + resume CTA); push confirms "Paused till <date>".
  - [ ] Paused undispatched orders excluded from vendor route; admin sees hold flag.

## UR-16 — Resume with ≥24h cutoff + preferred date + auto-resume
- **Description**: Resume requires ≥24h before scheduled delivery and a chosen preferred delivery date. Optional return date at pause time enables auto-resume.
- **Source**: E1 FAQ-4 (resume ≥24h + must pick preferred date), A5 (auto-resume)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Resume <24h before delivery blocked with "Resume at least 24 hours before delivery" + next valid date offered.
  - [ ] Resume always asks preferred delivery date (no dateless resume).
  - [ ] Return date set at pause → auto-resume fires with push "Deliveries resumed" and last settings intact.

## UR-17 — WhatsApp help button
- **Description**: WhatsApp help entry on home, account, and tracking screens. Opens `wa.me` thread with prefilled order context; support hours 8 AM–8 PM ex-Sun/holidays noted.
- **Source**: C1 (wa.me deep-link entry, concierge thread), C3 (call/WhatsApp support), E1 (8 AM–8 PM ex-Sun pattern), PO (goal #4)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Help button on all three surfaces (home, account, tracking); single tap opens WhatsApp thread.
  - [ ] Prefill includes order ID + issue stub when opened from an order; generic greeting otherwise.
  - [ ] Hours note "8 AM–8 PM, closed Sun/holidays" adjacent to help entry.

## UR-18 — Order status lifecycle visible to user
- **Description**: User-facing statuses mapped from canonical lifecycle: placed → picked → packed → assigned → dispatched → delivered (+ failed/cancelled branches). Cancel/modify allowed pre-dispatch only.
- **Source**: D4 (picked/packed/assigned/dispatched/delivered + reattempt + pre-dispatch cancel), A1 (order object + shared record)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Every order shows current canonical state in user words; terminal states (delivered/cancelled/failed) clearly badged.
  - [ ] Cancel allowed only before dispatch; after dispatch shows "Contact help on WhatsApp" instead.
  - [ ] Failed (late/no-answer) shows reattempt note, never silent disappearance.

## UR-19 — Post-delivery feedback / rating
- **Description**: After delivery, prompt for quick rating + optional comment. Low ratings route to complaint flow (UR-20).
- **Source**: C5 (post-delivery rating), D4 (NPS/CSAT spirit; full dashboards = v2)
- **Priority**: Should
- **Acceptance criteria**:
  - [ ] Rating prompt appears once per delivered order (dismissible, not blocking).
  - [ ] Rating ≤ threshold (e.g. ≤3/5) offers "Raise complaint" shortcut with order pre-attached.
  - [ ] Submitted feedback visible in history; no duplicate prompts after submit.

## UR-20 — Complaint / dispute ≤3 days via WhatsApp + call
- **Description**: Discrepancies raisable within 3 days of delivery comms via WhatsApp help or call; logged to super-admin queue; 78%/89% retention logic: recovery is the feature.
- **Source**: E2 (3-day window via toll-free/email → adapt channel to WhatsApp+call), D4 (78%/89% CX stats as cited; retention lever), C1 (status alerts in thread)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] "Report issue" entry on order for 3 days post-delivery; after expiry shows hours + help contact (no silent removal).
   - [ ] Complaint creates ticket with order ID + reason code (11-code catalog, §14.3) + text ≤500 chars (photos join in v2 with object storage — ADR-017), visible status (open → under review → resolved).
  - [ ] Resolution push + in-app update; unresolved > SLA escalates in admin queue (admin surface).

## UR-21 — Quality trust line: RO+UV + lab date + report
- **Description**: Quality strip near product cards / home: "RO+UV purified · Lab tested <date> · View report". Copy hierarchy: taste → ease → proof → health last.
- **Source**: A2 (visible proof beats claims; quarterly testing; taste+convenience beat health), A3 (§04 quality trust line: RO+UV/lab/report), E2 (10-step/114-test/TDS proof pattern)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Strip visible without scrolling past BOOK NOW on home or product list.
  - [ ] Shows purification stages (RO+UV), last test date, tappable report link/file.
  - [ ] Stale test date (>90 days or CMS threshold) flags admin; app never shows future date.

## UR-22 — Return-jar request + 10-working-day SLA
- **Description**: Profile/menu "Return Empty Jar": qty + address + landmark → submit. Confirmation shows "Pickup within 10 working days". Phase-1 refund via UPI/manual; wallet = v2.
- **Source**: E1 FAQ-5 (qty + address + landmark; 10 working days; wallet refund → v2), E-group summary (refund path adapt)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Request requires qty ≥1 + address + landmark; submit disabled until complete.
  - [ ] Post-submit shows "Pickup within 10 working days" + request ID + refund path note ("Refund via UPI after pickup; wallet in v2").
  - [ ] Request appears in history with state (requested → picked → refunded).

## UR-23 — Delivery discipline: hours, Sun/holiday, lift rule, next-day default
- **Description**: Booking surfaces: delivery hours 8 AM–8 PM, closed Sun + public holidays, next-working-day default, and "No lift → gate / 2nd floor only" (lift flag captured at address).
- **Source**: E2 (§1 24h endeavour; §6 lift; §7 hours), E1 (next-working-day FAQ-2§9)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Sunday/holiday selected → blocked with next-serviceable suggestion.
  - [ ] Address form includes lift flag (yes/no); no-lift orders show gate/2F note at confirm + vendor stop.
  - [ ] "Delivery from next working day" copy shown wherever window picker appears.

## UR-24 — Payment safety: idempotency, COD reconcile, reminders
- **Description**: Double-pay guarded (idempotency; 409 treated as already-paid, not error); driver cash entry reconciles COD in admin; pending-dues + low-balance reminders via push.
- **Source**: C5 (create-order 400/404/409 guards, HMAC verify), D4 (driver cash entry → admin reconcile; pending-payment/low-balance reminders; link expiry/partial-cash/offline-queue branches)
- **Priority**: Must
- **Acceptance criteria**:
  - [ ] Double-tap / retry on pay never creates second charge (idempotency key per order).
  - [ ] COD paid at door reflects in user bill within vendor-sync SLA; partial cash shows dues carried forward.
  - [ ] Expired pay-link reissues from order; offline vendor cash queues and syncs on reconnect (vendor/admin contract).

## UR-25 — Minimal checkout: single booking sheet, <30s reorder target
- **Description**: Checkout is one sheet: qty → empties → address/GPS → window → UPI/COD chips → confirm. Reorder timed <30s as design target (instrumented, not asserted).
- **Source**: A3 (cut checkout steps), A1 (<30s target; instrument, don't assert), C5 (3-tap skeleton: location → size → pay)
- **Priority**: Should
- **Acceptance criteria**:
  - [ ] No separate quantity screen; all steps on one scrollable sheet / single flow.
  - [ ] Analytics logs per-step drop-off + reorder duration; <30s reported as measured distribution, not claim.
  - [ ] Every field prefilled where history exists; empty-state requires no more than address + OTP (UR-08, UR-11).

---

## Out of v1 (explicit)
- Subscription tiers (10/20/30 jars, 10/15/20% off) + priority/weekend SLA — model fields kept, ship in auto-delivery v2 (C3).
- Wallet (pay / top-up ≥ order / withdraw) — v2; Phase-1 = UPI + COD + manual deposit ledger (E1 FAQ-7 → defer).
- Voice ordering, 22-language coverage, live-dot tracking, promo/coupon engine, NPS dashboards — v2 (C5, D4, A5).
- Route optimisation — vendor/admin roadmap, not user-app v1 (A5 roadmap).
