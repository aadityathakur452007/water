# Group F Summary — Market Pricing (F1 + F2)

| Field | Value |
|-------|-------|
| Group | F — Market data & pricing analytics (agents R-F) |
| Sources | F1 Actowiz price-per-litre method + F2 ActowizMetrics Blinkit Delhi analytics |
| Date | 2026-09-29 |
| PDF mapping | Finding F8 ("demand tezi se badh rahi hai, prices bhi"); feeds §04 pricing context |
| Status | **ALL NUMBERS BELOW ARE UNVERIFIED SOURCE CLAIMS (PDF §06). Not audited. Do not lock pricing off them.** |

## 1. Pricing table (ranges found)

| Price point | Value | Source | Status |
|-------------|-------|--------|--------|
| Shodasha local 20 l refill (jar exchange) | **Rs 28** | User reference image / project-overview scope | Locked scope input (primary — user's own market) |
| Shodasha local 20 l jar + container | **Rs 30** | User reference image / project-overview scope | Locked scope input (primary — user's own market) |
| Delhi quick-commerce avg 20 l can, 2020 | Rs 72, availability 78% | F2, §1 | ⚠️ UNVERIFIED vendor claim |
| Delhi quick-commerce avg 20 l can, 2026 | **Rs 98**, availability 95% | F2, §1 | ⚠️ UNVERIFIED vendor claim |
| 6-year QC price drift | Rs 72 → Rs 98 (+36%) | F2, §1 | ⚠️ UNVERIFIED vendor claim |
| Small-pack vs 20 l can price-per-litre gap | "Many-fold" multiple, per platform (no figure yet) | F1, §2–§3 | Method only — findings pending 21-day window |
| Shodasha-vs-QC gap (context, NOT a target) | Rs 28–30 vs Rs 98 ≈ **3.3–3.5×** | Derived (scope ÷ F2 claim) | ⚠️ Illustrative only — different products, channels, cities |

Reading the gap: the Rs 28–30 ↔ Rs 98 spread is **not** a pricing umbrella to hide
under. F1's core lesson is that the 20 l can is **a separate business** (own
availability, delivery constraints, pricing logic) — route-delivered local refill and
instant-delivery branded cans compete on different jobs (scheduled reliability vs
instant convenience). Shodasha wins on arrival-window certainty and jar-exchange
discipline, not on converging to either end of the range.

## 2. What each source contributes (one line each)

- **F1** contributes *method, not numbers*: 30 zones / 10 cities frame, bare +
  delivery-inclusive dual reporting with printed basket assumption, small-pack penalty
  multiple, platform-spread and MRP-gap metrics, and the separate-cut rule for 20 l
  cans. Reusable as Shodasha's own price-tracking template.
- **F2** contributes *directional context, not facts*: Delhi QC 20 l volumes and
  prices trend up (2020–2026), availability improves, four national brands contest the
  20 l SKU, premium-residential and mixed-urban zones order most. Every figure needs
  primary verification — including an unresolved internal inconsistency (2026 region
  splits sum to 3.24M vs 7.4M headline; see F2 §6).

## 3. Validation plan — local survey steps (PDF §06)

PDF §06 requires primary research before any market number is used ("steps 1–2" are
referenced in the footer; the step bodies are truncated in the PDF text — steps below
are the standard local-price survey operationalising that requirement):

1. **Step 1 — Local price census ( Shodasha launch geography only).**
   - [ ] List 15–25 nearby suppliers (shops, route vendors, Bisleri-style dealers):
     20 l refill price, new-jar price, deposit per jar, cap-missing charge, delivery fee,
     minimum order, delivery window promise.
   - [ ] Record bare vs delivered separately (F1 rule): note basket/fee assumption next
     to every figure. Photograph printed MRP stickers where present.
   - [ ] Output: local price band table that either confirms or replaces Rs 28–30.
2. **Step 2 — Household willingness check (20–30 households).**
   - [ ] Current supplier + price paid, pain points (late delivery, no confirmation,
     deposit disputes), reaction to Rs 28/30 + Rs 150 deposit + 30-min window offer.
   - [ ] Output: accept/reject on the launch price and the deposit note wording.
3. **Step 3 — Reconciliation gate.**
   - [ ] Compare survey band against the F2 Rs 98 QC claim; document why they differ
     (channel, brand, city, deposit handling) — do not average them.
   - [ ] Pricing is locked only after steps 1–2 are filed in this folder as
     `local-survey-*.md`. Until then, Rs 28–30 remains a *scope input*, not a
     *validated market price*.
4. **Step 4 — F1/F2 revisit.**
   - [ ] Re-check F1 for published findings (penalty multiple, platform spread, parser
     accuracy) and F2 for figure revisions; log deltas with dates.

## 4. Verification-needed (group-level, explicit)

- [ ] All F2 tables (§1–§5 of `F2-blinkit-analytics.md`) remain UNVERIFIED; the 2026
  3.24M-vs-7.4M inconsistency is unresolved.
- [ ] F1 has no findings yet; diary-check the F1 URL post-window.
- [ ] Both pages were read via fetch fallback (browseros-neo tools unavailable in this
  session) — re-verify via the agent browser per ADR-005 before Series-3 synthesis.
- [ ] Open question carried to synthesis: market price verification (Rs 28–30 local
  refill vs Rs 98 quick-commerce average) — confirm via local survey before locking
  pricing (see `context/progress-tracker.md`).

## 5. Handoff to Series-3 synthesis

- Use the pricing table (§1) as the single price reference; quote the 3.3–3.5× gap
  only with the "different business" caveat.
- Adopt F1's dual-reporting + qualifier discipline for any Shodasha pricing dashboard
  (super-admin surface).
- Surface tags: user app (reliability positioning, separate SKU cuts) · vendor app
  (window adherence as the availability metric) · super-admin (quarantined competitor
  watch + survey-gated price lock).
