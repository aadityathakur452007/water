# Decision Log

> **Purpose**: The "why" file. An **append-only** log of every meaningful decision —
> which library was chosen and why, architecture choices, feature decisions, branch
> decisions, tradeoffs. When anyone (human or AI) wonders "why is it built this way?",
> the answer is here.
>
> **Update rule (MANDATORY)**: Append a new entry for EVERY meaningful decision.
> **Never edit or delete past entries** — that would rewrite history and break the
> log's purpose. Before making a new decision, check this log first (don't decide
> twice).

---

## What counts as a "meaningful decision"? (MANDATORY — log all of these)

- **Library / framework / tool choice** — component library, icon set, state manager, animation lib, styling approach
- **Architecture / pattern choice** — folder structure, data flow, error strategy, server vs client components
- **Feature design decisions** — scope, UX, API shape, data model
- **Branch / workflow decisions** — git flow, release process, deployment target
- **Anything you had to think about for more than ~5 seconds**

---

## How to add a decision

1. Copy the **Template** below into the **Decision Entries** section (newest on top)
2. Fill it in — the **Why** line is the most important part
3. Add a row to the **Decision Index** table
4. If it supersedes an earlier decision, mark the old one as `Superseded by ADR-NNN`

---

## Decision Index

| ID | Date | Decision | Status | Affects |
|----|------|----------|--------|---------|
| ADR-013 | 2026-09-29 | FastAPI + Firebase Auth OTP (FCM push only) + security/edge-case spec | Accepted | workers/api/, auth flow, Feature_docs/security/ |
| ADR-012 | 2026-09-29 | Backend: Python on Cloudflare Workers + D1 SQLite for auth/users | Accepted | workers/api/, D1 schema, Flutter apps, Admin web |
| ADR-011 | 2026-09-29 | SYN-2 synthesis: vendor-reqs VR-01…VR-14 + pricing-deposit model accepted as proposed | Proposed | Feature_docs/synthesis/, Series-3 spec lock |
| ADR-010 | 2026-09-29 | Group-B operations research done; jar ledger + billing flows locked for Series-3 | Accepted | Feature_docs/research/B-operations/, Series-3 synthesis |
| ADR-009 | 2026-09-29 | Group-C competitor research done; copy-vs-differentiate locked | Accepted | Feature_docs/research/C-competitors/, Series-3 synthesis |
| ADR-008 | 2026-09-29 | Group-A UX research done; A3 cited secondary-only; top-8 user-app rules | Accepted | Feature_docs/research/A-ux-case-studies/, Series-3 synthesis |
| ADR-007 | 2026-09-29 | Group-D: canonical order-state machine + MVP/v2 split proposed | Proposed | Feature_docs/research/D-dev-guides/, Series-3 synthesis |
| ADR-007 | 2026-09-29 | F-market: all Actowiz figures UNVERIFIED, price lock gated on local survey | Accepted | Feature_docs/research/F-market/, pricing |
| ADR-006 | 2026-09-29 | specify-cli install mandated | Accepted | repo root, SDLC workflow |
| ADR-005 | 2026-09-29 | Feature_docs/ at root in English full deep-dive with browseros-neo reading | Accepted | Feature_docs/, Series-2/3 research |
| ADR-004 | 2026-09-29 | Shodasha 3-surface split (2x Flutter Android + Next.js web super-admin) | Accepted | user app, vendor app, super-admin web |
| ADR-003 | 2026-08-11 | Remove Scaffold.py; canonical trees are the source of truth | Accepted | repo root, folder-structure skill |
| ADR-002 | 2026-08-11 | Add flow.md + decision.md as living context files | Accepted | context/, all docs |
| ADR-001 | YYYY-MM-DD | [One-line decision] | Accepted | [files/features] |

---

## Template

### ADR-NNN: [Short title]
- **Date**: YYYY-MM-DD
- **Status**: Proposed | Accepted | Rejected | Superseded by ADR-NNN
- **Context**: [what triggered this decision — the problem being solved]
- **Options considered**: [alternatives, and why each was rejected]
- **Decision**: [what was chosen]
- **Why**: [the reasoning — this is the important part. Write enough that a future agent
  understands without re-deriving it.]
- **Consequences**: [positive and negative effects, things to watch out for]
- **Affects**: [features / files / branches this touches]

---

## Decision Entries

### ADR-013: FastAPI + Firebase Auth OTP (FCM push only) + security spec
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: User locked FastAPI + Firebase for OTP; asked for senior-security threat model covering payments, login/OTP, validation, order limits/tanker, addresses, subscriptions, vendor failures, device-farm fraud, secrets, OWASP, graceful errors, admin observability, prod checklist.
- **Options considered**: FCM-as-OTP-verifier (rejected — FCM is push only; Firebase Auth phone verifies OTPs); D1-only OTP codes (rejected as primary — Firebase Auth is the verifier, D1 keeps users/sessions/audit); skipping spec and scaffolding (rejected — SSDLC requires threat model before code).
- **Decision**: Firebase Auth (phone) verifies OTP → Workers verifies ID token (aud/exp) → D1 sessions; FCM = push only with server-side targeting. Spec written to `Feature_docs/security/security-threat-model-and-edge-cases.md` (SEC-A/I/P/F/C + EC-O/G/S/V/R series, STRIDE/OWASP, prod gates).
- **Why**: Correct primitive per job (Auth vs FCM), keeps zero-trust server checks, and answers every user scenario (home ≤5 / office ≤30 / tanker hard-stop, skip-today vendor list, device cap 3/30d, quote lock, idempotency) with acceptance criteria before build.
- **Consequences**: Phase-2 must wire Firebase project + sender allowlist, Play Integrity, rate limits, and admin audit dashboards; tunables (COD cap, skip cutoff) locked after survey.
- **Affects**: `workers/api/`, auth flow, Flutter Secure Storage, admin observability, Phase-2 spec

### ADR-012: Backend Python on Cloudflare Workers + D1 SQLite for auth/users
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: User locked backend: Cloudflare Workers hosts Python backend, D1 SQLite manages application user login etc. Surfaces: 2x Flutter Android (user/vendor) + Next.js Super Admin web share one API + one DB.
- **Options considered**: Vercel/Next API + Postgres Neon/Supabase (rejected — user has Cloudflare infra, wants edge SQLite ops simplicity); Durable containers / Railway FastAPI (rejected — more ops, cost); Workers JS/Hono + D1 (rejected as primary — team wants Python, keep as fallback if Python beta blocks us).
- **Decision**: One Python Worker (`workers/api/`, pure-Python deps only) exposing /auth /orders /jars /billing /admin → D1 binding (`env.DB`). Auth = phone OTP → D1 `users/sessions/otp_codes`; Flutter uses Bearer token, Admin web HttpOnly cookie same API.
- **Why**: Single edge API serves all 3 surfaces; D1 SQLite fits jar ledger + dues relational model at v1 scale with zero DB ops; tech-selection Step 0 classifies this as fullstack product-service (auth+orders+billing) so backend+DB justified — smallest thing that does the job.
- **Consequences**: Python Workers is beta — no native C extensions (no psycopg, bcrypt-C; use pure-Python/hashing via Workers crypto), CPU-time/memory caps, stateless only. D1: 10GB/db, single-writer, batch reconciliation writes. Mitigation: keep deps stdlib+pure-Python, idempotency keys, audit table for money edits. If FastAPI ASGI adapter fails on Workers, fallback to Flask-style handlers or JS Hono port (trigger documented).
- **Affects**: `workers/api/`, D1 schema (users/sessions/otp/jars/orders), Flutter auth clients, Next.js admin middleware, context/architecture.md

### ADR-011: SYN-2 synthesis — vendor requirements + pricing-deposit model (proposed)
- **Date**: 2026-09-29
- **Status**: Proposed
- **Context**: Series-3 needs buildable vendor + pricing contracts from B (all 5) + C2 + D2/D3 + E-summary + project-overview.
- **Options considered**: Full vendor-matrix prose per source (rejected — Series-3 needs atomic IDs with acceptance); atomic VR-01…VR-14 with source/priority/acceptance + v1/v2 split and a separate pricing-deposit model with UNVERIFIED flags + survey gate (chosen).
- **Decision**: Accept `Feature_docs/synthesis/vendor-requirements.md` (VR-01 triple, VR-02 offline, VR-03 ledger never-negative, VR-04 Rs150 + closure, VR-05 Rs3 cap, VR-06 pause/resume ≥24h, VR-07 route+loading sheets, VR-08 WhatsApp + own-bank QR + carry-forward, VR-09 evening reconcile, VR-10 Hindi v1, VR-11 audit, VR-12 hold>3 block, VR-13 breakage v2, VR-14 GPS-lite) and `pricing-deposit-model.md` (deposit (N−E)*150, Rs28/30 vs Rs72→98 UNVERIFIED gap with different-business caveat, Paniwale-tier translation S10/20/30 @28 = 252/476/672 proposed, wallet-v2 vs UPI+COD-v1, RWA 50–200 + office 20–30/floor/mo, 2.5–3 buffer, 8-8 Sun-closed, 10-day return, 3-day dispute, survey gate).
- **Why**: Every rule traces to a fetched source line (E rulebook for deposit/hold/return, B-matrix for ledger/billing/offline, C2 for buffer/RWA/deposit-band, C3 for tiers, D for PoD/state-machine/MVP-split); unverified numbers stay flagged per ADR-007 §06 rule so price lock waits on the local survey.
- **Consequences**: Series-3 must lock offline conflict semantics, skip-one vs pause-all, hold-limit default (3), and run the §8 survey before Rs 28/30 + Rs 150 lock.
- **Affects**: Feature_docs/synthesis/, vendor app + admin spec, pricing lock

### ADR-010: Group-B operations research — jar ledger + billing flows locked
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Series-2 Group B (R-B) deep research over B1 (Rekart), B2 (Pure Pani + RO sub-page), B3 (PaniHisab + Features), B4 (EPIXS) for Shodasha jar/deposit/route/subscription ops. All six URLs fetched full-page via webfetch (+ pricing/blog/compare supplements via search); browseros-neo skill loaded but its browser actions are not exposed in this env, so webfetch/websearch fallback used throughout — noted honestly in each file's Meta.
- **Options considered**: Shallow per-vendor summaries (rejected — Series-3 needs buildable mechanics); carry rival-source claims (Rekart ₹1,500+/mo, English-only; PaniHisab offline) as facts (rejected — labelled (R)/unverified in matrix); full spine extraction with matrix + ledger model + billing flows and explicit unverified lists (chosen).
- **Decision**: Accept 5 files in Feature_docs/research/B-operations/; Series-3 synthesis inherits: atomic doorstep triple per stop (given/empties/cash-UPI, offline-tolerant), per-customer jar ledger (held + Rs 150 deposit balance + dues, never-negative invariant), Rs 150-at-booking + refund-on-closure lifecycle, pause-with-resume schedules + auto loading sheets, WhatsApp bills with own-bank UPI QR + carry-forward dues, evening route reconciliation, Hindi v1; v2: photo proof, per-customer rates, payroll, expenses/P&L, Gujarati.
- **Why**: All four vendors run the identical spine (order→assign→deliver→collect-empty→cash→ledger→billing) and differ only in weight — the kernel above is the intersection, so it is the safest v1 scope; EPIXS supplies the lifecycle/breakage edge cases the SaaS trio omits, PaniHisab the schedule engine + ₹99 price anchor, Pure Pani the QR-ledger + offline pattern, Rekart the daily-reconcile + churn-signal discipline.
- **Consequences**: Series-3 must resolve the unverified list (deposit Rs-value handling per vendor, Rekart price/language single-sourced, Pure Pani traction/settlement, PaniHisab caps/offline, EPIXS demo unexecuted) + local price/deposit survey per §06 rule before locking constants; flow.md untouched (research-only task, no functions/routes changed).
- **Affects**: Feature_docs/research/B-operations/, Series-3 synthesis, user/vendor/super-admin surfaces

### ADR-009: Group-C competitor research — copy-vs-differentiate locked
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Series-2 Group C (R-C) deep research over C1 (CanCan), C2 (Rekart blueprint), C3 (Paniwale), C5 (JalSeva GitHub). C3 site is a JS shell — body recovered from indexed snippets; JalSeva read to source-file level (booking/login/tracking/payments/firebase/gemini/maps/types).
- **Options considered**: Treat CanCan counters and Paniwale snippets as validated facts (rejected — marketing claims / second-hand text); carry them labelled UNVERIFIED with recovery tasks + adopt only the mechanics verified in fetched bodies (chosen).
- **Decision**: Accept 5 files in Feature_docs/research/C-competitors/; Series-3 inherits: copy one-tap repeat + wa.me links (C1), jar discipline 2.5–3/cust + stop flow + wallet-deferred (C2), Rs 150 deposit + Return&Repeat (C3), OTP/3-tap/guards/domain-types (C5); differentiate on published Rs 28/30 pricing, Rs 150 (not 200–300) deposit, window-no-dot, UPI+COD v1.
- **Why**: C1 proves the WhatsApp repeat mechanic live, C2 is the only numeric ops blueprint, C3 the only subscription ladder with Shodasha's exact deposit figure, C5 the only buildable reference — together they cover channel, ops, pricing, and code with no single-source dependency.
- **Consequences**: Series-3 must mystery-shop CanCan wa.me, in-browser confirm Paniwale, and run the local price survey (Rs 28–30 still unvalidated); flow.md gets a competitor-input trace only (research task, no app functions/routes changed).
- **Affects**: Feature_docs/research/C-competitors/, Series-3 synthesis, user/vendor/super-admin surfaces

### ADR-008: Group-A UX case-study research — accepted with A3 secondary-only rule
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Series-2 Group A (R-A) deep research over A1/A2/A3/A5 for Shodasha repeat-order UX, reliability, window-vs-dot. A3 primary unrecoverable (Medium 404 on markdown+text, archive 404, author/title searches no hit).
- **Options considered**: Drop A3 entirely (rejected — PaniBox report §05/§04 preserves its two design rules and Series-3 needs the gap visible); fabricate A3 body from generic UX knowledge (rejected — dishonest); publish A3 doc as secondary-index reconstruction with BLOCKED status + recovery task (chosen).
- **Decision**: Accept 5 files in Feature_docs/research/A-ux-case-studies/; A3 cited downstream ONLY as "secondary index, primary pending"; Series-3 synthesis inherits the top-8 user-app rules (repeat-machine home, quote lock, window-not-dot, inline steppers, deposit-at-booking, OTP-first/price-unwalled, one-tap pause, proof-over-promises) and the unverified-claims inventory.
- **Why**: A1 gives the strongest UX mechanics, A2 the only causal behavioural evidence, A5 the only shipped-system reference — losing A3's traceability over a dead link would be worse than carrying it honestly labelled; explicit evidence grades stop inflated claims (40% capacity, <30s reorder, 100% migration, WTP levels) leaking into the spec.
- **Consequences**: Series-3 must retry A3 via signed-in browser (browseros-neo) or author contact; flow.md untouched (research-only task, no functions/routes changed).
- **Affects**: Feature_docs/research/A-ux-case-studies/, Series-3 synthesis, user/vendor/super-admin surfaces

### ADR-007: Group-D — canonical order-state machine + MVP/v2 split (proposed)
- **Date**: 2026-09-29
- **Status**: Proposed
- **Context**: Group-D dev-guide research (Octal/Goteso/Appinop/WDS) converged on a tri-app model and an order lifecycle; Series-3 needs one canonical machine to spec against.
- **Options considered**: D4 verbatim order (picked→packed→assigned→dispatched→delivered) vs Goteso accept-first flow; chosen merge: placed→accepted→picked→packed→assigned→dispatched→delivered with cancelled/failed/rejected branches, payment as separate field.
- **Decision**: Propose the merged machine + MVP (repeat, window, UPI/COD, invoice links, OTP/photo PoD, jar ledger) vs v2 (AI auto-reorder confirm-first, IoT parked, route-AI, live customer map) split per _group-D-summary.md.
- **Why**: D2 gives the tri-app structure, D4 the lifecycle/ETA/payment-link evidence, D3 the v2 parking lot; Shodasha scope (arrival window, no live dot, Rs 150 deposit) constrains the MVP slice.
- **Consequences**: Series-3 must lock assign-before-vs-after-pack, pause semantics, deposit edge cases; D1 needs browser re-verification (403-blocked, reconstructed).
- **Affects**: Feature_docs/research/D-dev-guides/, Series-3 synthesis, user/vendor/super-admin surfaces

<!-- Newest decisions go at the top of this section. Keep this section growing — it is
     the living memory of the project. Delete the two example entries below once you
     have real decisions. -->

### ADR-007: F-market — all Actowiz figures UNVERIFIED, price lock gated on local survey
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Group F research (R-F) read F1 + F2 fully. F1 is a method pre-registration with no findings yet; F2 is vendor marketing with no disclosed methodology, an "illustrative figures" footer disclaimer, and an internal 2026 volume inconsistency (region splits sum to 3.24M vs 7.4M headline).
- **Options considered**: Treat Rs 98 QC average as a pricing anchor (rejected — different product/channel/city, unverified); average Rs 28–30 with Rs 98 (rejected — F1's "separate business" rule forbids blending); quarantine all Actowiz numbers + gate price lock on a local survey (chosen).
- **Decision**: All F1/F2 numbers stay flagged UNVERIFIED per PDF §06; Shodasha pricing locks only after the local price-census + household-willingness survey filed under `Feature_docs/research/F-market/`. Rs 28–30 remains a scope input, not a validated market price.
- **Why**: Averaging or anchoring off unaudited vendor claims would lock a launch price to Delhi quick-commerce data that measures a different business; the survey plan in `_group-F-summary.md` §3 is the cheapest path to a defensible price.
- **Consequences**: Series-3 synthesis must quote the 3.3–3.5× gap only with the "different business" caveat; F1 URL needs a post-window diary-check for published findings.
- **Affects**: Feature_docs/research/F-market/, pricing, Series-3 synthesis

### ADR-007: Bisleri Group-E adoption (deposit/hold 1:1, COD diverge, wallet v2)
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Group-E research (E1 FAQs + E2 deposit page) gives the industry-standard jar rulebook: Rs150/jar refundable deposit, Rs3 cap-missing, empty-with-cap stepper, Daily/Weekly/Custom + 1mo-1yr, hold/resume ≥24h, 10-day return + wallet refund, 8am-8pm Sun-closed, gate/2nd-floor, 3-day dispute, no-COD/wallet-only.
- **Options considered**: Copy Bisleri prepaid-only (rejected — Shodasha Rs28/30 local market needs COD); ignore Bisleri rules (rejected — deposit/hold/return discipline prevents jar leakage); adopted split below.
- **Decision**: Adopt 1:1 — empty stepper + (N−E)×150 note, Rs3 cap charge, hold range + ≥24h resume, 10-day return SLA, lift/gate note, hours + 3-day dispute, offers-void-on-cancel. Diverge — keep UPI+COD in Phase-1 (Bisleri no-COD noted as reference). Defer — Bisleri Wallet to v2 (keep ledger fields now).
- **Why**: Jar-asset protection and pause/return UX are proven by the market leader; COD is a local-market necessity, wallet is overhead Phase-1 doesn't need — so copy the discipline, not the payment constraint.
- **Consequences**: Booking card needs live deposit math; vendor handover needs cap counter; admin needs 10-day return + 3-day dispute queues + deposit ledger; wallet v2 is a migration not rewrite.
- **Affects**: user app booking/hold/return, vendor handover, super-admin billing/disputes, Feature_docs/research/E-bisleri/

### ADR-006: specify-cli install mandated
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Series-1 setup needs a spec-driven SDLC (specify → plan → tasks → implement) after community skills bootstrap. Agent.md already requires `specify init` after Skills.py.
- **Options considered**: Manual specs in markdown only (no executable SDLC commands, drifts); specify-cli via uv from spec-kit (chosen).
- **Decision**: Mandate `uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@latest` then `specify init .` after Skills.py run.
- **Why**: Unlocks speckit.* SDLC commands for Series-2/3 research-to-build handoff; single standard spec flow across user/vendor/super-admin surfaces.
- **Consequences**: Setup series must run Skills.py first, then specify install; agents must use speckit commands once available.
- **Affects**: repo root, SDLC workflow, all future feature specs

### ADR-005: Feature_docs/ at root in English full deep-dive with browseros-neo reading
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: User approved Feature_docs/ at root, English, full deep-dive for Series-1/2/3 research (6 groups A–F + synthesis). Research sources are live web pages needing logged-in/JS-capable reading.
- **Options considered**: Hindi/mixed notes in context/ only (rejected — user explicitly approved English root folder); shallow summaries (rejected — deep-dive needed for build); plain fetch scraping (rejected — weak on dynamic pages).
- **Decision**: Research lives in `Feature_docs/` at root in English, full deep-dive; live web reading via browseros-neo skill.
- **Why**: User approval is explicit on location, language, and depth; browseros-neo is the dedicated signed-in agent browser, so it handles dynamic/login pages better than raw fetch.
- **Consequences**: Series-2 agents must load browseros-neo before web research; all group outputs in English under Feature_docs/research/.
- **Affects**: Feature_docs/, Series-2/3 research, browseros-neo usage

### ADR-004: Shodasha 3-surface split (2x Flutter Android + Next.js web super-admin)
- **Date**: 2026-09-29
- **Status**: Accepted
- **Context**: Shodasha needs customer ordering, delivery fulfilment, and back-office oversight. Research (PaniBox report F1–F8) shows repeat-order UX, jar-exchange tracking, and WhatsApp/UPI ops span three distinct actors.
- **Options considered**: Single Flutter app with roles (rejected — mixes customer simplicity with driver ops, bloats repeat-order path); all-web PWA (rejected — Android native preferred for GPS/offline delivery); chosen split below.
- **Decision**: Three surfaces — Flutter Android user app (repeat order, Rs 28/30 SKUs, Rs 150 exchange, window, pause, WhatsApp, UPI/COD) + Flutter Android vendor/delivery app (stops, empties in/out, cash collected) + Next.js React Super Admin website (orders, jars, billing, disputes).
- **Why**: Each actor gets the minimal surface it needs: one-tap repeat stays clean for users, drivers get per-stop ops, admin gets oversight — matches tri-app pattern (Octal/Goteso guides D1–D2) and keeps dependency boundaries clean.
- **Consequences**: Shared domain (SKUs, deposits, windows) must stay consistent across three codebases; Series-2/3 research must tag findings per surface.
- **Affects**: user app, vendor app, super-admin web, Feature_docs/ synthesis

### ADR-003: Remove Scaffold.py — canonical trees are the source of truth
- **Date**: 2026-08-11
- **Status**: Accepted
- **Context**: Scaffold.py generated a folder skeleton, but `npm install` / create-app already provides boilerplate. The generator produced a generic tree that ignored per-project needs and duplicated what the `folder-structure` skill already defines.
- **Options considered**: Keep Scaffold.py but improve it (extra maintenance, still redundant with the skill); remove it and rely on the canonical trees (chosen).
- **Decision**: Delete Scaffold.py. The `folder-structure` skill (`.agents/folder-structure/SKILL.md`) is the single source of truth; agents materialize its canonical trees by hand, creating only folders the product needs.
- **Why**: One source of truth instead of two. The skill's trees are the "senior engineer" hierarchy — feature-first frontend, controller-service-repository backend. Remove the Python dependency from the workflow.
- **Consequences**: Agents must create folders manually — the skill's Step 2 shows how. All docs updated (Agent.md, SKILLS.md, README.md, .agents/AGENTS.md).
- **Affects**: repo root, `.agents/folder-structure/SKILL.md`, all docs referencing it

### ADR-002: Add `flow.md` + `decision.md` as living context files
- **Date**: 2026-08-11
- **Status**: Accepted
- **Context**: Agents couldn't understand the project instantly and didn't update context properly. `progress-tracker.md` alone didn't capture HOW the app works (function call maps, user flows) or WHY decisions were made.
- **Options considered**: Fold this info into existing files (overloaded, no single "how/why" home); new dedicated files (chosen).
- **Decision**: Create `context/flow.md` (Mermaid call maps, user flows, request/response, routes) and `context/decision.md` (append-only ADR log). Both are updated on EVERY task, alongside `progress-tracker.md`.
- **Why**: Reading the three files (progress-tracker + flow + decision) gives state, structure, and rationale instantly. Decision log prevents re-deciding and preserves reasoning.
- **Consequences**: Agents must keep diagrams in sync; stale diagrams are treated as bugs. Sync protocol is enforced via AGENTS.md + Agent.md.
- **Affects**: `context/`, `AGENTS.md`, `Agent.md`, `SKILLS.md`, `.agents/AGENTS.md`, `ai-workflow-rules.md`

### ADR-001: Choose Next.js 16 + TypeScript
- **Date**: YYYY-MM-DD
- **Status**: Accepted
- **Context**: Need an SSR-capable framework with strong typing for a multi-page product.
- **Options considered**: React + Vite (no SSR, worse SEO), Astro (less dynamic for app routes), SvelteKit (smaller ecosystem for the team).
- **Decision**: Next.js 16 + TypeScript.
- **Why**: SSR/SSG out of the box, App Router supports the feature-first layout, TypeScript strict mode is a hard requirement, largest ecosystem.
- **Consequences**: Must default to server components; avoid heavy client bundles.
- **Affects**: entire app

### ADR-002: [Example — component library choice]
- **Date**: YYYY-MM-DD
- **Status**: Accepted
- **Context**: Need form controls and modals for the [feature] section.
- **Options considered**: HeroUI (too heavy to default), MUI (banned), custom (slow).
- **Decision**: Pull the [X] components from Astryx, animate with [Y].
- **Why**: Matches the design language in `ui-context.md`; copy-paste ownership preferred per `DESIGN.md`.
- **Consequences**: [things to watch out for]
- **Affects**: `features/<feature>/components/`
