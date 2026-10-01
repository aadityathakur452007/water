# Super Admin Panel — Professional UI Benchmark (F-SA2)

**Date:** 2026-10-01 · **Branch:** `005-super-admin-panel` · **Status:** audit → upgrade plan executed same-day
**Sources:** [VoltAgent/awesome-design-md](https://github.com/voltagent/awesome-design-md) (extracted DESIGN.md systems: Vercel, Linear, Stripe, Notion, PostHog, Coinbase, Wise), [SaaSUI — Metric & KPI Card UX Patterns (2026)](https://www.saasui.design/blog/saas-metric-kpi-card-ux-patterns) (evidence from Stripe/Vercel/Linear/PostHog/Datadog/Dub screens), TailAdmin / shadcn dashboard-blocks / Tremor landscape (2026), plus in-repo skills: **hallmark** (anti-slop), **ui-checklist**, **premium-design**, **redesign**, **stitch-design-taste**.

> Hallmark · pre-emit critique: P5 H4 E4 S4 R5 V4 — all axes ≥ 3, emitted.

---

## 1. What the best panels do (doctrine, evidence-backed)

1. **A KPI card answers three questions at a glance** — value, change, is-it-good. A bare number is trivia (Stripe leads with gross volume *and its change*; Vercel shows requests with deltas; Linear surfaces cycle counts with direction).
2. **Never ship a number without a comparison.** Delta against a defined prior period, rendered on the card ("+12% vs previous 30 days").
3. **Direction ≠ sentiment.** Up is not always good: rising error rate, rising dues, rising custody-at-risk must color **red-up**, not green-up. Each metric declares its own good direction. A row where green always means "up" eventually celebrates failure.
4. **Sparkline for shape.** A point-to-point delta hides the path (steady climb vs crash-and-recover). Small, secondary, same period as the delta.
5. **Explicit comparison window.** "+12%" without "vs previous 30 days" undermines trust; cards must echo the global date range.
6. **Cards are doorways, not dead ends.** Click revenue → revenue breakdown. Every surprising metric's first question is "why".
7. **Design the card's non-value states.** Skeleton that holds layout; genuine zero (calm) distinguished from "no data" (onboarding); explicit in-card error with retry — never a stale or blank value that lies.
8. **A row of cards is scannable, not a wall.** Hero metric larger (North Star), consistent internal structure, units formatted identically.
9. **Tables**: sortable headers, column visibility, CSV export, sticky headers, row-level actions visible on hover — the shadcn-blocks/TailAdmin baseline for 2026.
10. **Async feedback**: toasts confirm writes with facts from the response ("Blocked · 3 sessions revoked"), not generic "Success".
11. **Session handling**: silent refresh; an admin mid-shift must never be bounced to login by a 30-minute access-token expiry.
12. **Contrast + focus**: AA (≥ 4.5:1) for all text, visible `focus-visible` rings on every interactive element, 8-state discipline (default/hover/focus/active/disabled/loading/error/success).

## 2. KPI-matrix mapping (their system ≠ ours — no blind copying)

Generic SaaS dashboards show MRR, active users, churn, tickets, error rate. Those are *their* North Stars. Shodasha's business lives on **jar-asset integrity, day-close cash reconciliation, and repeat rate** (spec §1, PDF F1–F8) — so the cockpit's KPI row stays domain-true:

| Our KPI | Professional analogue | Backend source | Good direction |
|---|---|---|---|
| GMV (order value) | gross volume (Stripe) | `/admin/metrics/overview` series | up |
| Orders created | — (volume) | same | up |
| On-time % | SLA adherence | same `on_time_pct` | up |
| Deposit liability | deferred revenue | `money.deposit_liability_paise` | down (exposure) |
| Dues receivable | AR aging | `money` + dunning | down |
| Jars held | asset inventory | `money.jars_held` | tracked |
| Custody in-hand | cash-at-risk | `/admin/custody` | down |
| UPI-vs-COD mix | payment method split | series/orders | informational |

**Honest-copy rule (hallmark gate 46):** every number above comes from the live Workers API. Zero fabricated metrics, zero "demo" values — the repeat-rate KPI is *not* added because the backend cannot compute it yet (additive change would be required first).

## 3. Version currency (user directive: "everything latest")

| Package | Was | Now | Note |
|---|---|---|---|
| next | 16.3.7 | **16.3.8** | latest; newer than the 16.3.5 requested |
| react / react-dom | 19.2.8 | **19.3.0** | latest |
| eslint-config-next | 16.3.7 | **16.3.8** | matches next |
| sonner | — | **new** | toast system (premium standard; in-repo `ask-sonner` skill present) |
| tailwindcss | 4.3.3 | 4.3.3 | already latest |
| @tanstack/react-query | 5.104.0 | 5.104.0 | already latest |
| @tanstack/react-table | 9.2.4 | 9.2.4 | already latest — **was installed but unused; now wired** |
| recharts | 3.10.1 | 3.10.1 | already latest |
| lucide-react | 1.49.0 | 1.49.0 | already latest |
| typescript | 5.9.3 | 5.9.3 | **7.0.2 exists but skipped** — TS 7 (Go rewrite) is not yet compatible with Next 16's toolchain; revisit when eslint-config-next declares support |
| eslint | 9.39.5 | 9.39.5 | **10 skipped** — eslint-config-next 16.3.8 targets 9 |
| @types/node | 20.x | 20.x | **26 skipped** — should track the Node LTS runtime, not the newest major |

## 4. Audit punch list (hallmark audit format; executed in this branch)

| # | Severity | Finding | Fix shipped |
|---|---|---|---|
| A1 | major | KPI cards had delta but no sparkline, no explicit window label | `Stat` gains `spark` + `delta.window`; range selector 7/30/90 echoes into cards + charts |
| A2 | major | Global "up = good" delta coloring — wrong for dues/custody | `Stat delta.goodWhen` per metric |
| A3 | major | TanStack Table installed but unused — tables hand-rolled, no sort/visibility/CSV | `DataTable` primitive (sort + column visibility + CSV) wired into orders/users/payments (+vendors) |
| A4 | major | No toast system; mutations gave no feedback ("Blocked · 3 sessions revoked" was spec'd, never shipped) | sonner mounted; all mutations toast with real response facts |
| A5 | critical | `sh_refresh` set at login but never used — 30-min expiry hard-logs-out the admin mid-shift | BFF: worker 401 → `POST /v1/auth/refresh` → new cookies → retry once → only then `/login?next=` |
| A6 | minor | KPI cards not clickable (doctrine: cards are doorways) | cards with a destination render as links |
| A7 | minor | Secondary query failures silently blanked alert sections | per-card/section error with retry |
| A8 | minor | Neutral badge text `#71717A` on `#F4F4F5` ≈ 4.48:1 — marginal AA fail at 11px | neutral badge text darkened to zinc-600 token |
| A9 | minor | No global `:focus-visible` ring (keyboard nav invisible) | token-driven ring in globals.css |
| A10 | info | Steel `#71717A` on canvas `#F9FAFB` = 4.60:1, on white 4.84:1 — passes AA; accent-on-white buttons 5.93:1 | verified, no change |

**Anti-slop verification (hallmark + user hard rules):** light-only ✓ · no purple/no gradients ✓ · no emoji (lucide only) ✓ · Geist Sans + mono tabular numerals on every money figure/ID ✓ · single accent ✓ · single-hue chart ramps ✓ · skeleton shimmer, no spinners ✓ · staggered `.rise`, `prefers-reduced-motion` respected ✓ · tokens locked in `globals.css` `@theme`, no inline colors ✓ · mobile verified at 375/768 (admin-first surfaces) ✓.

**Design DNA alignment:** our locked system (canvas `#F9FAFB`, ink `#18181B`, water-blue `#0369A1`, Geist, whisper shadows, radius-16) already sits in the **Vercel/Linear school** of the awesome-design-md collection — precision neutrals, one accent, mono for data. The upgrade borrows their *behavioral* patterns (cards-as-doorways, silent refresh, honest states), not their brand skins.
