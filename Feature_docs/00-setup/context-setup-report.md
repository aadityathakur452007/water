# Context Setup Report — Series-1 Bootstrap (S1-2)

Date: 2026-09-29
App: Shodasha Mineral Waters
Scope source: `context/pani-app-research-report.pdf` (PaniBox report, 29 Sep 2026) + user-approved Series-1 brief.

## 1. What changed

1. Read `Agent.md`, `SKILLS.md`, `context/project-overview.md`, `context/progress-tracker.md`, `context/flow.md`, `context/decision.md`, `context/architecture.md`, and `context/pani-app-research-report.pdf` (via Read tool, PDF text extraction).
2. Rewrote `context/project-overview.md` for Shodasha — SKUs, repeat-order home, jar exchange, arrival window, pause, WhatsApp, UPI+COD, 3 surfaces; kept Goals, Core User Flow (5 steps), Target Audience, Success Metrics sections.
3. Rewrote `context/progress-tracker.md` — Current Phase = Phase-1 Research (Series-1 setup running, Series-2 deep research next); Completed = skills install kicked off + Shodasha scope locked; Next Up = Series-2 6-group research + Series-3 synthesis; Open Questions = market price verification (Rs 28–30 vs Rs 98). File structure preserved.
4. Updated `context/decision.md` without editing old entries — appended ADR-004 (3-surface split), ADR-005 (Feature_docs/ at root in English full deep-dive with browseros-neo), ADR-006 (specify-cli install mandated); added 3 rows to Decision Index.
5. Created research folders under `Feature_docs/` (see tree below). Left existing `Feature_docs/00-source-index.md` untouched.
6. Did NOT run Skills.py. Did NOT fetch URLs (index-only; bodies deferred to Series-2 with browseros-neo).

## 2. Shodasha scope (locked)

- Products: 20L Jar Refill Rs 28 + 20L Jar + Container Rs 30, −/+ steppers on cards.
- Home = repeat machine: big BOOK NOW, last settings pre-selected (default 2 jars, next morning).
- Jar exchange at booking: empty-jar stepper, Rs 150/jar refundable deposit note (cap missing +Rs 3 per Bisleri reference).
- Fulfilment signal: 30-min arrival window + rider name/call button; no live map dot.
- Self-service: one-tap pause/resume link under order button.
- Support: WhatsApp help button (home + account); bills/confirmations WhatsApp-shareable later.
- Payments: UPI + COD chips at booking; prepaid wallet deferred to v2.
- Surfaces: (1) Flutter Android user app, (2) Flutter Android vendor/delivery app, (3) Next.js React Super Admin website.

## 3. Folder tree

```
Feature_docs/
├── 00-setup/
│   └── context-setup-report.md        (this file)
├── 00-source-index.md                 (pre-existing, untouched)
├── research/
│   ├── A-ux-case-studies/             (Series-2 agent R-A: A1, A2, A3, A5)
│   ├── B-operations/                  (Series-2 agent R-B: B1, B2, B3, B4)
│   ├── C-competitors/                 (Series-2 agent R-C: C1, C2, C3, C5)
│   ├── D-dev-guides/                  (Series-2 agent R-D: D1, D2, D3, D4)
│   ├── E-bisleri/                     (Series-2 agent R-E: E1, E2)
│   └── F-market/                      (Series-2 agent R-F: F1, F2)
└── synthesis/                         (Series-3 merge → spec + decisions)
```

## 4. Next steps for Series-2

1. One agent per research group (A–F), English full deep-dive, reading live pages via browseros-neo skill (load skill + read SKILL.md first per Agent.md).
2. Each group writes findings + evidence + design implications into its folder; tag every finding per surface (user/vendor/super-admin).
3. Flag unverified market numbers (Rs 28–30 vs Rs 98) for primary verification — do not lock pricing in Series-2.
4. Series-3 synthesises the 6 outputs in `Feature_docs/synthesis/` (spec, flow deltas, ADR proposals).
5. Context sync continues: progress-tracker + flow + decision updates on every series.
