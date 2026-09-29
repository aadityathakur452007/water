# Shodasha MVP Scope v1 (SYN-3)

**Date:** 2026-09-29
**Companion:** `feature-requirements.md` (FR-01…FR-37) — this file locks the v1 cut.
**Scope anchors:** Refill Rs 28 / Jar+Container Rs 30 · Rs 150 deposit · Rs 3 cap-missing · 30-min window, no live dot · UPI+COD · WhatsApp help · 8AM–8PM ex-Sun · gate/2nd-floor lift rule.

## 1. MVP v1 — what ships (one screen + spine)

- **User app (Flutter Android)**
  - [ ] One-screen repeat home: big BOOK NOW, last settings pre-selected (FR-01)
  - [ ] SKU steppers Refill/Jar+Container + empty-exchange stepper + Rs 150 + Rs 3 notes + quote lock (FR-02, FR-03, FR-04)
  - [ ] Window picker + one-tap pause/resume with date + ≥24h cutoff (FR-05, FR-06)
  - [ ] UPI/COD chips + invoice links (FR-07)
  - [ ] WhatsApp help + shareable bills (FR-08)
  - [ ] GPS address + lift flag + pincode check (FR-09)
  - [ ] OTP auth, prices visible pre-auth (FR-10)
  - [ ] Status card 4-step tracker + 30-min window + rider name/call (FR-11)
  - [ ] Static trust line (FR-12), feedback sheet → WhatsApp (FR-13), history + read-only jar/deposit/dues (FR-14), pushes incl. ID/time/amount (FR-15), return-jar request (FR-16), Hindi (FR-17)
- **Vendor app (Flutter Android, basic triple)**
  - [ ] Duty toggle + sequenced stop queue, big sunlight targets (FR-18)
  - [ ] Doorstep triple: fulls + empties (+cap counter) + cash/UPI, one screen (FR-19)
  - [ ] PoD OTP + photo + counts + cash; offline queue → sync (FR-20, FR-21)
  - [ ] State advance + internal nav + call customer + shift totals + hold-block surfacing + loading-sheet consumption; Hindi (FR-22…FR-25)
- **Admin web (Next.js, order list + ledger + bills)**
  - [ ] Order list: accept/reject/assign, manual route sheets + loading numbers (FR-26)
  - [ ] Basic schedules + pause handling (FR-27)
  - [ ] Jar ledger held/deposit/dues + alerts (FR-28); manual deposit-refund closure + manual breakage adjust, logged (FR-29)
  - [ ] Bill engine `(jars×rate)+prev+deposit−payments` + WhatsApp send + UPI QR (FR-30)
  - [ ] Dues carry-forward + reminders + evening route reconciliation (FR-31)
  - [ ] Complaint/return/dispute queues + basic reports (on-time, repeat, reorder-time, UPI/COD split, disputes) + Hindi templates (FR-32, FR-33, FR-34)
  - [ ] State-machine guards + idempotency + roles + reserved v2 fields (FR-35, FR-36, FR-37)

**MVP acceptance bar:** repeat order <30s instrumented · quote locked pre-commit · every stop mutates ledger atomically · day-close reconciliation clean · pause needs no support call · confirmation always shows ID/time/amount.

## 2. v2 — parked (do not build in v1, reserve fields)

Wallet (pay / top-up ≥ order / withdraw → source) · tier rewards + auto-coupons + unused-point nudges + explicit anti-abuse · referrals / games · AI suggestions + silent auto-reorder (**confirm-first rule**) · IoT (TDS/shelf sensors, smart alerts) · customer live map + ±15-min traffic ETA · route-AI auto-sequencing + load-balanced beats · RWA/bulk + corporate rates + dealer tier (₹18 pattern) + society billing · payroll / expenses / P&L (30-report pattern) · cards / dynamic pricing · lab-report viewer + certification badges · NPS/CSAT dashboards + promos + B2B portal · Gujarati + further langs · photo-proof analytics · social login.

## 3. Out of scope (v1 + v2 horizon)

- Tanker marketplace mechanics beyond transferable UX rules (A1 economics do not transfer).
- Prepaid-only / wallet-only checkout (Bisleri R5 — Shodasha diverges to UPI+COD with ADR).
- Same-day subscription start; Sunday/holiday delivery; above-2nd-floor no-lift delivery.
- Deposits above Rs 150, non-Shodasha/no-deposit empty refunds, retail/DB jar returns.
- Live-dot tracking, traffic ETA, and auto-dispatch optimisation in v1.
- Enterprise pricing/quotes for ops tooling (market anchor ₹99–₹360/mo noted, no commitment).

## 4. Risks

1. **Price unverified (HIGH).** Rs 28–30 is a scope input from the reference image, not a validated market price; F2 QC Rs 98 is an unverified vendor claim about a different channel/city/product. Locking price off either → margin or trust loss. Mitigation: local survey gate (§5.1) before pricing lock.
2. **Deposit theft / jar leakage (HIGH).** Asset P&L lives in the ledger; paper/exchange-at-door without stepper + hold-limit + reconciliation → held-jar drift and refund disputes. Mitigation: FR-03+FR-19+FR-28+FR-31 all MVP, never a side notebook; customer-visible balances.
3. **On-time promise (MEDIUM).** 30-min window believability is untested (A1 author's own caveat); traffic + manual sequencing + 8AM–8PM/Sun-closed constraints break windows. Mitigation: window-not-dot, concierge copy, internal-GPS-only v1, on-time adherence dashboard, no ±15-min ETA claims until v2.
4. **Evidence gaps (MEDIUM).** D1 reconstructed (403), A3 primary missing, C3 JS-shell, D4 CX stats second-hand, all B/C/F traction figures single-sourced. Mitigation: verification checklist below; never quote externally.

## 5. Verification checklist (must clear before Series-3 build lock)

- [ ] **Local survey — price census (F §3 Step 1):** 15–25 nearby suppliers (refill, new-jar, deposit/jar, cap charge, fee, min-order, window promise); bare-vs-delivered split; MRP photos → file `local-survey-*.md`. Confirms or replaces Rs 28–30.
- [ ] **Local survey — household check (F §3 Step 2–3):** 20–30 households (supplier, price, pains, reaction to 28/30 + 150 + 30-min window + pause); reconciliation gate vs Rs 98 QC claim with channel/brand/city note.
- [ ] **D1 re-verify:** real-browser read (browseros-neo per ADR-005) of Octal page; replace reconstruction; confirm tri-app + cost claims.
- [ ] **C1/C3 counters:** mystery-shop CanCan wa.me (pricing/SLA/500+/50+/10k/4.9); in-browser confirm Paniwale body + Rs 150 refund + pause mechanics.
- [ ] **Series-3 spec gates (D §6):** lock assign-after-pack vs assign-before-pick; pause semantics (skip-one vs pause-all) with R-B; deposit edges (breakage, brand-mismatch, refunds) with R-B + R-E; confirm-first auto-reorder rule; COD-divergence + wallet-v2 ADR.
