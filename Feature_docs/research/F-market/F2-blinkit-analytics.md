# F2 — ActowizMetrics Blinkit Water Can Sales Analytics (Delhi)

| Field | Value |
|-------|-------|
| Code | F2 (Group F — Market data & pricing analytics) |
| Source | ActowizMetrics blog — "Bisleri vs Aquafina vs Kinley vs Bailley — Blinkit Water Can Sales Data Analytics Across Delhi Pin Codes 2026" |
| URL | https://actowizmetrics.com/blinkit-water-can-sales-data-analytics.php |
| Fetched | 2026-09-29 (full page read via fetch fallback; browseros-neo browser tools not available in this session, see Verification-needed §6) |
| Page date | 15 May 2026. Geography: **Delhi pin codes only** (quick-commerce / Blinkit). |
| PDF mapping | PaniBox report §05 (F2) + Finding F8; scope: market context |

> **VERIFICATION FLAG — READ FIRST:** **Every number below is an UNVERIFIED vendor
> claim.** The page is marketing content for ActowizMetrics' analytics services (lead
> form, "request early access" CTAs throughout). No sample sizes, pin-code lists,
> collection methodology, or confidence intervals are given for any table. The site
> footer itself states: *"Independent data infrastructure · Illustrative figures until
> live data is connected."* Per PDF §06 footer, these figures are "source websites'
> claims… not independently audited" — do **not** lock Shodasha pricing off them.
> Additionally, §5 records an **internal inconsistency** in the page's own tables.

## 1. Price + availability trend (UNVERIFIED source claim)

Average 20 l can price and availability rate, Delhi, 2020–2026:

| Year | Avg price (20 l can) | Availability rate |
|------|---------------------:|------------------:|
| 2020 | Rs 72 | 78% |
| 2021 | Rs 75 | 81% |
| 2022 | Rs 79 | 84% |
| 2023 | Rs 84 | 87% |
| 2024 | Rs 89 | 90% |
| 2025 | Rs 94 | 92% |
| 2026 | **Rs 98** | **95%** |

Headline deltas: Rs 72 → Rs 98 (+36% over 6 years); availability 78% → 95% (+17 pp).
Page attributes variation to logistics costs, inventory demand, and local competition
across pin codes; no per-pin-code figures are actually published.

## 2. Order-volume trend (UNVERIFIED source claim)

"Delhi Quick Commerce Beverage Sales Trends" — estimated water-can orders:

| Year | Est. orders | QC growth |
|------|------------:|----------:|
| 2020 | 1.2M | 14% |
| 2021 | 1.8M | 19% |
| 2022 | 2.6M | 24% |
| 2023 | 3.5M | 29% |
| 2024 | 4.8M | 34% |
| 2025 | 6.1M | 38% |
| 2026 | 7.4M | 42% |

## 3. Brand market-share trend (UNVERIFIED source claim)

Share across Delhi pin codes — Bisleri vs Aquafina vs Kinley vs Bailley:

| Year | Bisleri | Aquafina | Kinley | Bailley |
|------|--------:|---------:|-------:|--------:|
| 2020 | 38% | 22% | 27% | 13% |
| 2021 | 37% | 24% | 26% | 13% |
| 2022 | 36% | 25% | 25% | 14% |
| 2023 | 35% | 27% | 24% | 14% |
| 2024 | 34% | 28% | 23% | 15% |
| 2025 | 33% | 29% | 22% | 16% |
| 2026 | 32% | 30% | 21% | 17% |

Page narrative: Bisleri holds premium-urban loyalty but drifts 38% → 32%; Aquafina is
the "fastest-growing challenger" (22% → 30%) on pricing/availability; Kinley stays
competitive on distribution (27% → 21%); Bailley gains with price-sensitive buyers
(13% → 17%).

## 4. Demand by region type, 2020 vs 2026 (UNVERIFIED source claim)

| Region type | 2020 orders | 2026 orders |
|-------------|-----------:|-----------:|
| Premium residential | 220K | 640K |
| Commercial zones | 310K | 780K |
| Mixed urban areas | 420K | **1.1M** |
| Suburban locations | 250K | 720K |

Page narrative: premium brands over-index in high-income neighbourhoods; affordable
options dominate suburban/mixed-commercial regions; large-can demand lifted by hybrid
work and residential consumption.

## 5. SKU-level performance (UNVERIFIED source claim)

Top-selling SKU per year + average monthly sales:

| Year | Top-selling SKU | Avg monthly sales |
|------|----------------|------------------:|
| 2020 | Bisleri 20 l | 95K |
| 2021 | Bisleri 20 l | 118K |
| 2022 | Kinley 20 l | 142K |
| 2023 | Aquafina 20 l | 175K |
| 2024 | Aquafina 20 l | 208K |
| 2025 | Bailley 20 l | 236K |
| 2026 | Aquafina 20 l | 268K |

All four top SKUs are **20 l cans** (Bisleri / Kinley / Aquafina / Bailley 20 l) —
consistent with F1's "the can is a different business" framing and with Shodasha's
20 l-only scope.

## 6. Verification-needed (explicit)

- [ ] **Internal inconsistency (found 2026-09-29):** region-type orders for 2026 sum
  to 640K + 780K + 1.1M + 720K = **3.24M**, but the headline table claims **7.4M**
  total orders for 2026. (2020 cross-checks cleanly: 220K + 310K + 420K + 250K =
  1.2M = headline 1.2M.) 2021–2025 region splits are not published, so no further
  cross-check is possible. Treat all volume figures as suspect until reconciled.
- [ ] No methodology disclosed: demand the pin-code list, sample windows, whether
  "orders" means Blinkit-dataset observations or modelled estimates, and whether
  prices are bare or delivery-inclusive (F1 §4 shows why this distinction decides the
  comparison).
- [ ] "Average price" basis unknown: mean vs median, which SKUs/brands included,
  promo vs list price, deposit handling (Rs 150/jar per E2 would swamp a Rs 72–98
  can price if mishandled).
- [ ] Geography is Delhi quick-commerce only — not transferable to Shodasha's
  route-delivered local-refill market without a local survey (see
  `_group-F-summary.md` validation plan).
- [ ] Reading method note: page was read via markdown fetch fallback. The
  browseros-neo skill was loaded per ADR-005, but its browser tools are not installed
  in this session — re-verify figures through the agent browser when available, and
  check whether the page/figures have been revised since 15 May 2026.

## 7. Shodasha implications (per surface)

- **User app:** Delhi QC shoppers pay ~Rs 98/can for branded instant delivery; Shodasha
  households pay Rs 28–30 for scheduled local refill. These are different products in
  different channels (F1 §3) — position on **reliability + arrival window** (F3/F4),
  never on beating the QC price.
- **Vendor/delivery app:** the 78% → 95% availability climb is the QC benchmark for
  fill-rate discipline; Shodasha's equivalent metric is arrival-window adherence per
  stop, not pin-code listing availability.
- **Super-admin web:** if a competitor-price watch is ever built, track Bisleri /
  Aquafina / Kinley / Bailley 20 l separately by zone with bare-vs-delivered
  labelling (F1 method) — and quarantine every Actowiz figure as UNVERIFIED until the
  local survey lands.
