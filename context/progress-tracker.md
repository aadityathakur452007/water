# Progress Tracker

Update this file after every meaningful implementation change.

## Current Phase

**Phase-1 Research COMPLETE (2026-09-29) — 35 markdown files in Feature_docs/**

Series-1 setup done (skills 36 dirs + specify 1.0.13.dev0 + Shodasha context + 20-source index). Series-2 6-group deep research done (A/B/C/D/E/F with thorough article reads). Series-3 synthesis done (user/vendor/feature + flows + pricing + MVP).

## Current Goal

Lock Shodasha scope and research scaffold so Series-2 agents can run the 6-group deep-dive (A-ux-case-studies, B-operations, C-competitors, D-dev-guides, E-bisleri, F-market) in English full deep-dive, then synthesise in Series-3.

## Completed

- Backend locked (2026-09-29, ADR-012): Python on Cloudflare Workers + D1 SQLite for auth/users/orders/jars. See context/architecture.md Stack + Auth/Backend sections.
- Security spec done (2026-09-29, ADR-013): FastAPI + Firebase Auth OTP (FCM push-only) threat model + edge cases + prod checklist → `Feature_docs/security/security-threat-model-and-edge-cases.md` (ssdlc skill: STRIDE/OWASP, SEC-A/I/P/F/C + EC-O/G/S/V/R, home≤5/office≤30/tanker stop, skip-today, device caps, quote lock, idempotency, admin audit).

- Group-D research done (R-D, 2026-09-29): D1-octal (reconstructed — page 403-blocked), D2-goteso-triapp, D3-appinop-ai-iot, D4-customer-journey + _group-D-summary (unified tri-app checklist, canonical order-state machine proposal, MVP vs v2 split) in Feature_docs/research/D-dev-guides/; D4 slug truncation resolved to closest live match, noted honestly.

- Skills install kicked off (specify-cli mandated per ADR-006; Skills.py run deferred to setup series).
- Shodasha scope locked — 20L refill Rs 28 / Jar+Container Rs 30, repeat-order home, Rs 150 jar exchange deposit, arrival window (no live dot), pause, WhatsApp help, UPI+COD, 3 surfaces (2x Flutter Android + Next.js super-admin web).
- Context bootstrap: project-overview.md rewritten for Shodasha; Feature_docs/ scaffold at root. Series-2 six-group deep research follows, then Series-3 synthesis.
- Group F research done (R-F, 2026-09-29): F1 method-only (30 zones/10 cities, 20L separate cut, dual bare+delivered reporting — no findings yet) + F2 Delhi QC claims (Rs72→Rs98, 78%→95%, all UNVERIFIED + internal 2026 volume inconsistency 3.24M vs 7.4M) → `Feature_docs/research/F-market/` (3 files).
- Group A research done (R-A, 2026-09-29): A1 full (reorder/window/quote-lock/dispatch), A2 partial+mirrors (WTP 51%, deposit→sale, taste+convenience learning), A3 BLOCKED-404 with secondary-index fallback, A5 full (OTP/calendar/rewards/admin) + summary (comparison table, 5 flows, top-8 UX rules) → `Feature_docs/research/A-ux-case-studies/` (5 files). See ADR-007.
- Group C research done (R-C, 2026-09-29): C1 CanCan WhatsApp-only, C2 Rekart blueprint, C3 Paniwale pricing, C5 JalSeva architecture (README + 8 source files verbatim) + `_group-C-summary.md` (matrix, copy-vs-differentiate) → `Feature_docs/research/C-competitors/` (5 files). See ADR-008.
- Group E research done (R-E, 2026-09-29): E1 FAQs + E2 deposit page + `_group-E-summary.md` (Rs150 rulebook, hold/resume, 10-day return, 8-8 Sun-closed — adopt 1:1, COD-diverge, wallet-v2) → `Feature_docs/research/E-bisleri/` (3 files). See decision log Bisleri adoption entry.
- SYN-2 synthesis done (2026-09-29): `Feature_docs/synthesis/vendor-requirements.md` (VR-01…VR-14 with source/priority/acceptance, v1/v2 split) + `pricing-deposit-model.md` (deposit (N-E)*150 + Rs3 cap, Rs28/30 vs Rs72→98 UNVERIFIED gap, Paniwale-tier translation, wallet-v2 vs UPI+COD-v1, RWA/office/buffer/hours/return/dispute constants, survey gate) from B (all 5) + C2 + D2/D3 + E-summary + project-overview.

## Next Up

1. User review of Feature_docs/synthesis/ (user-requirements 25x, vendor 14x, features 37x, flows, pricing, MVP) — approve before any Flutter/Next.js scaffolding.
2. Local survey to lock Rs28/30 + Rs150 deposit (market numbers UNVERIFIED) + A3 primary recovery retry.
3. Phase-2 design-first: sitemap + user-flows skill + folder-structure for 2x Flutter + Next.js admin — needs explicit approval gate per Agent.md.

## Open Questions

- Python framework on Workers? (pure-Python Flask-style vs FastAPI ASGI adapter — confirm before scaffolding workers/api/; fallback JS Hono if beta blocks).
- OTP provider for D1 otp_codes (SMS/WhatsApp) + session TTL + admin seed method — needed for auth API spec.
- Market price verification (Rs 28–30 local refill vs Rs 98 quick-commerce average) — confirm via local survey before locking pricing.
- A3 primary recovery (Medium article 404, no archive hit) — retry via signed-in browser (browseros-neo) or author contact before Series-3 synthesis; until then cite as secondary-index only.

## Architecture Decisions

See `context/decision.md` for full decision records.
