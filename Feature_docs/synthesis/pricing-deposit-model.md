# Pricing & Deposit Model — Shodasha Mineral Waters (SYN-2)

- **Date**: 2026-09-29
- **Role**: SYN-2 Synthesizer
- **Inputs**: E-bisleri (`_group-E-summary.md` R1–R20 + §4 table), C-competitors (`C2-rekart-blueprint.md` §§5–7, `C3-paniwale.md` pricing/tiers), B-operations (`_group-B-summary.md` §§2–3/§5, B3 §5/§13, B2 pricing), D-dev-guides (D2 §1 payments, D3 §4 deposits, `_group-D-summary.md` §4 MVP/v2), `context/project-overview.md`, F-market context (Actowiz QC band per brief — UNVERIFIED)
- **Status**: Proposed. Nothing here locks until the local survey (§8) validates Rs 28/30 + Rs 150.

## 1. SKUs (scope-locked, survey to validate)

| SKU | Price | When |
|---|---|---|
| 20L Jar Refill | **Rs 28** | Repeat / one-time, customer hands empty |
| 20L Jar + Container (new container out) | **Rs 30** | First issue / extra container kept by customer |

Both cards carry −/+ steppers + an **empty-exchange stepper** ("Empty jars with cap to return") with a live deposit note (E R1/R3). Booking default: 2 jars / next morning (project-overview).

## 2. Deposit formula (binding rule)

```
N = jars ordered (stepper 1–10, Bisleri-qty pattern E R2)
E = empties with cap declared at booking (stepper)
M = caps missing counted at handover (vendor app counter)

deposit_due    = max(0, N − E) × 150        # Rs 150/jar refundable, incl. taxes (E R2)
cap_charge     = M × 3                       # Rs 3/jar extra, caps mandatory (E R4)
water_bill     = (refills × 28) + (new_containers × 30)
payable        = water_bill + deposit_due (+ cap_charge at handover if M > 0)
refund_on_return = returned_jars × 150 → Phase-1 UPI/manual; wallet rails v2
```

- **Worked examples**:
  - Order 2 refills (2×28=56), declare 1 empty with cap → deposit (2−1)×150 = **Rs 150**; payable now 56+150 = **Rs 206** (+Rs 3 only if a handed empty lacks its cap).
  - B-ledger example (_group-B-summary §2): 2× Refill + 1× Jar+Container = 56+30 = **Rs 86** water bill; hand 2 empties → held = 0+3−2 = **1**; deposit 1×150 = **Rs 150**; dues 86 carry-forward until UPI/COD reconciles.
  - PaniHisab bill-pattern anchor (B3 §5): 25×₹30 + ₹240 previous = **₹990** — the `(jars × rate) + previous` shape Shodasha copies, plus `+ deposit_due − payments`.
- **Billing formula (monthly/period)**: `bill_total = (jars_this_period × rate) + previous_balance + deposit_due − payments_received`; partials carried, never zeroed silently (B3 §5 + _group-B-summary §3).
- **Ledger fields (keep now, even for v2 items)**: `empties_declared, empties_returned, caps_missing, deposit_ledger (paid/refunded/balance), held_jars, dues, hold_range, resume_cutoff, return_sla, dispute_window, wallet_balance (v2)` (E §5-item-2).

## 3. Rs 28/30 vs Rs 72→98 QC gap — UNVERIFIED, different business

- Delhi quick-commerce band **Rs 72 → Rs 98** (Actowiz/F-market per brief): flag **UNVERIFIED** — vendor marketing, no disclosed methodology (ADR-007b: F-market). Never quote as anchor without the caveat.
- **Why it must not set Shodasha price**: different product (brands/packaged lots vs local 20L refill loop), different channel/city (Delhi QC 10-min vs local route), and F1's "separate business" rule forbids blending bare vs delivered cuts. The 3.3–3.5× gap is quoted **only with the "different business" caveat**.
- **City band context (also unverified, Rekart guide C2 §5)**: retail 20L most cities **Rs 40–120**; wholesale tie-up **Rs 15–35/jar**; new food-grade jar asset **Rs 200–400**. Shodasha Rs 28–30 sits **below** the C2 retail band — price advantage is real on paper but unvalidated locally; the survey (§8) must confirm willingness before lock.
- **Shodasha posture**: win on **reliability cues** (confirmation ID/time/amount, window adherence, WhatsApp proof), not a price war (C3 UX note; project-overview goal 3).

## 4. Subscription tiers (from Paniwale C3 — defer to v2, keep fields now)

Paniwale verbatim (Pune, Rs 69/jar base, snippet-sourced — in-browser confirm pending):
10 jars **Rs 621** (690 − 10%) · 20 jars **Rs 1,173** (1,380 − 15%) · 30 jars **Rs 1,656** (2,070 − 20%), free + same-day delivery, Rs 150 deposit, Return & Repeat.

Shodasha translation at **Rs 28 refill** (PROPOSED, illustrative — not locked):

| Tier | Jars/mo | Base @28 | Discount | Illustrative price |
|---|---|---|---|---|
| S10 | 10 | 280 | 10% | **Rs 252** |
| S20 | 20 | 560 | 15% | **Rs 476** (+ priority delivery) |
| S30 | 30 | 840 | 20% | **Rs 672** (+ priority + weekend) |

- **Phase-1**: one-tap repeat + pause only; tiers ship in subscription v2 (C3 implication; E §3 simplify; D-summary §4).
- **Keep in model now**: `plan + tier + discount_pct + perks` (flexible → priority → weekend ladder sells perks, not just volume — C3 UX note).
- **Bisleri matrix reference** (model, don't ship all): Daily/Weekly/Custom × 1/3/6/12 mo + delivery days + pay frequency (E R6/R7); no same-day start → next working day (E R8); offers void on cancel (E R19).

## 5. Prepaid wallet v2 vs UPI + COD v1 (deliberate diverge)

| | Bisleri / Rekart-guide reference | Shodasha |
|---|---|---|
| Phase-1 | Bisleri online/wallet-only, **no COD** (E R5); Rekart prepaid-wallet "most scalable" (C2 §7) | **UPI + COD** (scope lock; local Rs 28/30 market necessity). Deposit collected via UPI/COD at door. |
| v2 | Bisleri wallet: pay / top-up ≥ order / withdraw to source (E R14); Rekart wallet auto-deduct + low-balance alerts (C2 §9) | **Prepaid wallet**: auto-deduct per delivery, low-balance WhatsApp alerts + one-tap links, B2B postpaid + credit limit (C2 §7). Confirm-first for any auto-reorder (D3 §9). |
| Model now | — | `wallet_balance, deposit_ledger` fields from day one so v2 is a migration, not rewrite (E §3). |

Money always lands in the **agency's own bank** (own-bank UPI QR, zero-fee pattern — B2 §6; B3 §6).

## 6. RWA + offices (GTM phasing, from C2)

- **RWA empanelment**: one approval = **50–200 households**, trial week free (C2 §6). Adopt: households first, RWA bulk later (matches audience note).
- **Offices**: one floor = **20–30 jars/month**; one 50-jar/mo office ≈ 10–15 households; facility-manager channel (C2 §6).
- **Acquisition math (Rekart claims, unverified)**: door-to-door 10–15 conversions/day; one trusted WhatsApp-group message = 20–30 enquiries; first-50 proof-of-concept rule. Carry as hypotheses for the survey, not plan commitments.
- **Ops rollout**: 2–3 km start zone; expand 100–200 customers/zone, one adjacent zone at a time, dedicated driver per zone, local depot if > 5 km (C2 §§2/10).

## 7. Buffer, hours, return, dispute (operating constants)

| Rule | Value | Source |
|---|---|---|
| Jar buffer | **2.5–3 jars per active customer** (+ 10–15% buffer); 100 cust → 250–300 jars; tempo (40–60/trip) above ~50/route | C2 §5 |
| Delivery hours | **8 AM–8 PM, closed Sundays + public holidays**; arrival window lives inside hours; 24h endeavour SLA | E R15/R16 |
| Lift rule | No lift → **gate / 2nd floor only**; address lift flag + vendor stop instruction | E R17 |
| Return SLA | **Pickup ≤ 10 working days** on Return-Jar request (qty + address + landmark); eligibility note adapted (non-Shodasha/no-deposit = no refund + reason) | E R11–R13 |
| Dispute window | **≤ 3 days** from comms; via WhatsApp help + call, logged in admin (Bisleri pattern: 18001211007 / wecare@) | E R18 |
| Hold/resume | Date-range hold; resume **≥24h before** delivery + pick preferred date | E R9/R10 |
| Hold-limit | Outstanding **> 3 → pause / ask deposit**; alert at 5+ jars / 3+ days | C2 §8; B3 §13; VR-12 |

## 8. Local survey validation plan (price lock gate per ADR-007b)

Lock Rs 28/30 + Rs 150 **only after** filing under `Feature_docs/research/F-market/`:

1. **Price census** (30 zones / 10 cities method, 20L separate cut, dual bare+delivered reporting): local refill band, Jar+Container band, deposit band (test Rs 150 vs C2's Rs 200–300), cap-charge awareness.
2. **Household willingness**: weekly/bi-weekly frequency, window vs same-day, UPI vs COD split, pause need, WhatsApp-bill acceptance; RWA/office pipeline (50–200 HH, 20–30/floor/mo).
3. **Jar economics check**: asset Rs 200–400 (B3 Hindi page; C2 §5) vs Rs 150 deposit — confirm leakage tolerance; hold-limit (>3) acceptability.
4. **Re-verify before quoting**: Paniwale tiers in-browser (JS-shell caveat); CanCan wa.me mystery-shop; Actowiz QC band diary-check (F1 post-window findings).
