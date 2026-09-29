# F1 — Actowiz Bottled Water Price-Per-Litre Study (Method)

| Field | Value |
|-------|-------|
| Code | F1 (Group F — Market data & pricing analytics) |
| Source | Actowiz Solutions — "Bottled Water Price Per Litre Study: Method" |
| URL | https://actowizsolutions.com/bottled-water-price-per-litre-india.php |
| Fetched | 2026-09-29 (full page read via fetch fallback; browseros-neo browser tools not available in this session, see Verification-needed §6) |
| Page status | **METHOD ONLY (pre-registration). Findings NOT yet published.** |
| Method version | Method v2026-08-26 — sampling frame, fields, cadence, metric definitions final |
| PDF mapping | PaniBox report §05 (F1) + Finding F8; scope: market context |

> **VERIFICATION FLAG — READ FIRST:** This page contains **zero actual price numbers**.
> It is a method pre-registration: all schema values are `null` "until the window runs",
> and "findings for the price curve are added when the first collection window (21 days)
> closes." There is nothing here to audit yet — only a method to reuse. Per PDF §06 footer,
> any market numbers derived from Actowiz sources later are vendor claims, not audited data.

## 1. Method summary (what the page actually says)

- **Study object:** the pack-size price curve — price per litre plotted against pack size
  for packaged drinking water, from 250 ml bottles to 20-litre cans, across
  quick-commerce platforms and delivery zones.
- **Why water runs first:** near-identical product across brands, unambiguous litre
  denominator, printed MRPs, eighty-fold pack-volume range. A parsing error shows up
  immediately as an implausible price per litre instead of hiding inside category
  variation. This study doubles as the pipeline-accuracy proof for the whole programme.
- **Sampling frame:** **30 delivery zones across 10 cities** (cities not named on the
  method page). Capture at a fixed daily time (11:00 IST) so cross-platform comparison
  is like-for-like. First collection window = 21 days.
- **Pack ladder:** 250 ml | 500 ml | 1 l | 2 l | 5 l | 20 l, plus multipack counts
  (e.g. 6 × 1 l resolves to 6 litres — bundled-pack parsing is an explicit accuracy risk).
- **Computation rule:** every figure computed **twice** — on product price alone
  ("bare") and **inclusive of delivery fee at a stated minimum basket** ("delivered"),
  with the basket assumption printed next to the figure.

## 2. Metric definitions (fixed before collection — quoted/paraphrased)

| # | Metric | Computation | Why it matters |
|---|--------|-------------|----------------|
| 1 | Price per litre, bare | `selling price / (pack_litres × multipack_n)` | Core comparison across the 250 ml → 20 l ladder |
| 2 | Price per litre, delivered | `(selling price + delivery fee) / total_litres` at stated min basket | Product price alone "systematically understates the small-pack penalty" |
| 3 | Small-pack penalty | `P/L(250 ml) / P/L(20 l)`, same zone | States curve steepness as one multiple — "the figure that travels" |
| 4 | Platform spread, identical packs | P90 − P10 of P/L for same pack + same brand, one pincode, one capture hour | "Same product, same street, same hour" — cleanest comparison the channel permits |
| 5 | MRP gap | `(mrp − price) / mrp` per SKU per zone | Water carries printed MRPs, so this is directly checkable |
| 6 | Can availability by zone | Share of sampled zones where a 20 l can is listed **and** in stock | Reported **separately** from bottled packs (see §3) |

## 3. "The 20-litre can is a different product" (key Shodasha-relevant claim)

- The household 20 l can has **its own availability pattern, its own delivery
  constraints, and often its own pricing logic**. Folding it into the same curve as
  bottled packs "blends two businesses."
- It is captured on the **same schema** but reported as a **separate cut**, with its
  own availability figure by zone.
- The page repeats this for three audiences (pricing analyst, e-commerce lead, data
  lead): "your reporting blends them into one availability number" — the fix is
  "can availability reported separately by zone, with MRP gap tracked across the
  whole pack ladder."

## 4. Delivery-inclusive reporting (why both numbers are published)

- The delivery fee is a **fixed cost spread across whatever volume is in the basket** —
  on a single small bottle it dominates, so bare-price comparison understates the
  small-pack penalty "badly."
- Rule: publish **both** figures; the delivered one **always carries the minimum
  basket it assumes**. "One number without the assumption would not be interpretable"
  / "publishing a delivered price without the basket assumption" is listed as a
  measurement mistake.
- Reading qualifiers promised with every future figure: successful-capture rate per
  platform-week (weeks below threshold excluded **and the exclusion noted**), visible
  corrections with dates, raw payloads retained with capture IDs for traceability.

## 5. Planned outputs (outputs 01–07, to be published when the window closes)

1. Median P/L at each pack-ladder rung (250 ml → 20 l can).
2. (Bare vs delivered curve — implied by the dual-computation rule.)
3. **Small-pack penalty multiple per platform.**
4. **Platform spread rupee gap** (same pack, same brand, same pincode, same hour).
5–6. MRP gap + can-availability-by-zone cuts (implied by metric table).
7. **Parser accuracy note** — pack-parsing accuracy vs a labelled hold-out set,
   published because every later study depends on it.

## 6. Verification-needed (explicit)

- [ ] **No findings to verify yet.** Revisit the URL after the 21-day window closes and
  capture: the penalty multiple per platform, the platform-spread rupee gap, and the
  parser-accuracy note. Record the method version and any corrections log.
- [ ] Confirm the 10-city list and whether any zone covers Shodasha's launch geography
  (Delhi-only F2 data does not substitute for this).
- [ ] Confirm the stated minimum-basket assumption behind any delivered P/L figure
  before comparing it with Shodasha's Rs 28–30 route-delivered price (different
  baskets, different businesses — see `_group-F-summary.md`).
- [ ] Reading method note: page was read via markdown fetch fallback. The
  browseros-neo skill was loaded per ADR-005, but its browser tools are not installed
  in this session — re-verify findings through the agent browser when available.

## 7. Shodasha implications (per surface)

- **User app:** never blend 20 l jar pricing/availability with any future small-pack
  listing — separate cuts, as F1 mandates. If a delivered-price comparison is ever
  shown, print the basket assumption next to it.
- **Vendor/delivery app:** 20 l fulfilment constraints (empties, deposits, floor/lift
  rules per E2) are exactly why the can is "a different business" — ops reporting
  must keep can-availability separate from any other SKU.
- **Super-admin web:** adopt the qualifier discipline — capture rates, noted
  exclusions, correction log — for any internal pricing/availability dashboard.
