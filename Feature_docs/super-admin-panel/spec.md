# Super Admin Panel — Feature Spec (F-SA)

**Date:** 2026-09-30 · **Branch:** `005-super-admin-panel`
**Inputs:** `Feature_docs/synthesis/feature-requirements.md` (FR-26…FR-34), `mvp-scope-v1.md`, `backend/api-contract.md` (§4.11, §9, §14), PaniBox research report (PDF F1–F8), `.agents/skills/stitch-design-taste/DESIGN.md`, root `DESIGN.md`, sitemap + user-flows skills.
**Stack (locked, ADR-012/004):** Next.js 16 + TypeScript + Tailwind CSS v4, hosted on **Cloudflare Pages**. Python Workers backend (unchanged as authority) + **D1 (SQLite)**. Admin web auth = same Workers API, HttpOnly cookie session + CSRF header.

> Agent.md gate: nothing below is implemented until you approve this spec. The backend delta is **strictly additive** — zero changes to existing request/response shapes, so the Flutter apps and live tests cannot break.

## 1. What the super admin is (research-grounded)

The PDF's core lesson is that this business lives or dies on **jar-asset integrity (F2), reliability (F3/F4), cash leakage (F6/F7), and repeat rate (F1)**. The super-admin panel is the owner's cockpit for exactly those four: jars never leak, cash always reconciles by day-close, every rupee in/out is visible per user and per vendor, and misbehaving accounts are blocked with evidence. FR-26…FR-34 + contract §14 define the powers; this spec turns them into screens.

Super-admin powers (from Feature_docs + contract):
1. **See everything** — all orders by any user, all stops delivered by any vendor, every payment, ledger, audit row (contract §3: admin sees all).
2. **Statistics dashboard** — orders created/delivered/failed, GMV (user-side money), vendor payouts, deposit liability, dues receivable, UPI-vs-COD split, on-time window adherence, repeat rate.
3. **Block/suspend** — graduated warn→restrict→suspend→unsuspend with instant session revocation, for users AND vendors (§14.1, §14.5).
4. **Operate** — order accept/assign/reassign/cancel-override, routes, ledger adjustments, refunds, returns, complaints, quality incidents, strikes, custody, dunning, config, audit (all existing endpoints).
5. **Server log surface** — `audit_log` is the system journal: every money edit, state transition, login-relevant event is visible with actor/trace (user: "view over all the server logs that has been happening, every payment, every user action").

## 2. Sitemap (sitemap skill — every page on the map, nothing built off-map)

```
/                                        → redirect to /admin (public root of this app)
/login                                   → admin phone OTP (Firebase) → POST /v1/auth/otp/verify   [public]
/admin                                   → Overview: KPI stat cards + charts + alerts   [admin]
/admin/orders                            → all orders table (filter by state/payment/search)  [admin]
/admin/orders/[orderId]                  → order detail: tracker, bill, events, assign/reassign/cancel  [admin]
/admin/vendors                           → vendor directory (capacity, duty, custody, KYC, strikes)  [admin]
/admin/vendors/[vendorId]                → vendor profile: stops delivered, earnings, custody, suspend  [admin]
/admin/users                             → user directory (search, spend, jars, dues, suspend)  [admin]
/admin/users/[userId]                    → user profile: orders, ledger, deposits, dues, suspend  [admin]
/admin/payments                          → payments + refunds streams (every paisa in/out)  [admin]
/admin/ledger                            → jar-asset ledger: held/deposit/dues all customers  [admin]
/admin/operations                        → zone board, routes, day-close reconciliation  [admin]
/admin/trust                             → suspend ladder, strikes, quality, complaints queues  [admin]
/admin/audit                             → server log: audit_log viewer with filters  [admin]
/admin/config                            → rates/deposit/caps editor (audited)  [admin]
```
All `/admin/*` routes are role=admin, enforced by middleware (redirect `/login`) AND server-side on every endpoint (`require_role('admin')` — the UI is never the gate).
Data dependencies noted per page in §5 Route Map. Error/utility: 404 page, table empty/loading/error states per `States.md`.

## 3. Design system (stitch-design-taste — no AI slop)

**Light mode only. No purple gradients, no dark mode, no emoji in UI.**

| Token | Value | Role |
|---|---|---|
| Canvas | `#F9FAFB` | Page background |
| Surface | `#FFFFFF` | Cards |
| Ink | `#18181B` (zinc-950) | Primary text — never pure black |
| Steel | `#71717A` (zinc-500) | Secondary text |
| Whisper border | `rgba(228,228,231,.6)` | 1px card borders |
| **Accent: water blue** | `#0369A1` (sky-700) | Primary actions, active nav, focus rings |
| Success | `#15803D` (green-700) | delivered/paid/success states |
| Warning | `#B45309` (amber-700) | pending/dues/custody flags |
| Danger | `#B91C1C` (red-700) | blocked/failed/refund errors |
| Font | Geist Sans (UI) + Geist Mono (all numbers, order IDs, money) | |
| Radius | cards 16px · controls 8px · pills full | |
| Elevation | `0 8px 24px -12px rgba(24,24,27,.08)` whisper shadow only — no neon glow | |

Anti-slop rules applied: max 1 accent; monospace tabular numerals for every KPI; spring micro-motion (`transform/opacity` only, `prefers-reduced-motion` respected); skeletal shimmer loaders (no spinners); composed empty states (no "no data" dead text); no 3-equal-card cliché — KPI row is 4 asymmetric cells (2fr 1fr 1fr 1fr); organic demo values only; charts use single-hue ramps of the accent + zinc, no rainbow palettes.

**Libraries (DESIGN.md protocol — mixed, own-the-code):**
- **shadcn/ui** (Tailwind v4 + Radix) — tables, dialogs, sheets, dropdowns, tooltips, toast: the utility layer.
- **HeroUI** — data display surfaces where it's stronger out of the box (user-list, pagination) — sparingly.
- **Recharts** — all charts (user explicitly requested): area (GMV trend), stacked bar (UPI vs COD), donut (state mix), line (on-time adherence).
- **Motion (framer-motion)** — staggered card reveals, spring hover on rows, animated stat counters.
- **TanStack Table** — orders/users/vendors/payments tables: sorting, server-cursor pagination, column visibility.
- **TanStack Query** — all API state, `staleTime` tuned per surface, optimistic suspend toggles.
- **lucide-react** — icons only (no emoji anywhere).
- **Geist font** via `geist` package (matches architecture.md, not Inter).

## 4. User flows (user-flows skill — no dead ends)

**Flow A — Block a user (the headline power):**
```
[Users list] --search phone--> [row] --open--> [User profile]
  --Block (danger)--> [Sheet: reason + level restrict|suspend + confirm]  (typed nothing; reason required)
       --POST /v1/admin/users/{id}/suspend--> 403? → toast error, state unchanged
       --200--> row + profile show BLOCKED chip + audit entry auto-created
  --Unblock--> [Confirm dialog] --POST unsuspend--> active again
```
Dead-end guard: suspend with live sessions → API revokes sessions; UI shows "3 sessions revoked".

**Flow B — Investigate an order:**
```
[Overview KPI] --click "142 orders today"--> [/admin/orders?state=]
  --filter state/payment/search--> [row click] --> [Order detail]
  --assign/reassign/cancel-override--> action → mutation → invalidate queries → row updates
```

**Flow C — Day-close ritual (the owner's daily loop):**
```
[/admin/operations] → reconciliation card (cash+UPI vs pending vs jars-out vs deposit liability delta)
  --drill--> [/admin/payments] every collection with rider attribution
  --flag--> custody queue → vendor profile → block if walkaway suspected
```

**Flow D — Auth:**
```
[/login] phone → POST /auth/otp/start → Firebase OTP → POST /auth/otp/verify
  → role==admin ? cookie session + /admin : "not an admin" inline error (no dead end)
/admin/* middleware: no cookie → /login?next=…; cookie but not admin → inline 403 page
```

### Request/response (Flow A, all branches)
```mermaid
sequenceDiagram
    participant A as Admin (browser)
    participant N as Next.js (CF Pages)
    participant W as Workers API (Python)
    participant D as D1

    A->>N: click Block, submit reason+level
    N->>W: POST /v1/admin/users/{id}/suspend {reason, level} + CSRF + cookie
    W->>W: require_role('admin') — 403 if not admin/suspended
    W->>D: BEGIN; UPDATE users SET suspended=1, reason, by, at; audit_log INSERT; sessions revoke WHERE user_id
    D-->>W: ok
    W-->>N: 200 {user, revoked_sessions}
    N->>N: queryClient.invalidateQueries(['user', id]) + toast "Blocked · 3 sessions revoked"
    N-->>A: BLOCKED chip everywhere
    Note over N,W: 401 → silent refresh → retry once → /login on fail · 403 → toast "Not permitted" · 422 VALIDATION → inline field error · offline → retry banner
```

## 5. Route map (screen → route → endpoint)

| Screen / Action | Route | Worker endpoint | Notes |
|---|---|---|---|
| Admin login | `/login` | `POST /v1/auth/otp/start`, `POST /v1/auth/otp/verify` | cookie `sh_session`; CSRF token from verify |
| Overview | `/admin` | `GET /v1/admin/metrics`, `GET /v1/admin/metrics/overview` *(new)* | KPIs + charts |
| Orders table | `/admin/orders` | `GET /v1/admin/orders` *(extends filters)* | cursor paging |
| Order detail | `/admin/orders/[orderId]` | `GET /v1/orders/{id}` (admin pass) + `GET /v1/admin/orders/{id}/events` *(new)* | assign etc. existing |
| Vendors | `/admin/vendors` | `GET /v1/admin/vendors`, `GET /v1/admin/custody` | capacity/duty live |
| Vendor detail | `/admin/vendors/[vendorId]` | `GET /v1/admin/vendors/{id}/detail` *(new)* | stops delivered, earnings |
| Users | `/admin/users` | `GET /v1/admin/users` *(new)* | search, suspend state |
| User detail | `/admin/users/[userId]` | `GET /v1/admin/users/{id}/detail` *(new)* | orders+ledger+sessions count |
| Block/unblock | user/vendor detail | `POST /v1/admin/users/{id}/suspend\|unsuspend\|restrict` *(new, §14.5)* | audit + session revoke |
| Payments | `/admin/payments` | `GET /v1/admin/payments` *(new)* + `GET /v1/admin/returns` | every paisa |
| Refund queue | `/admin/payments` tab | `GET /v1/refunds` *(new admin read)*, `POST /v1/returns/{id}/refund` exists | claim-lock UI |
| Ledger | `/admin/ledger` | `GET /v1/admin/ledger` *(new)* | held/deposit/dues |
| Operations | `/admin/operations` | `GET /v1/admin/reconciliation`, routes generate (exists) | day-close |
| Trust queues | `/admin/trust` | `GET /v1/admin/strikes\|quality\|complaints\|dunning` (exist) | actions exist |
| Audit log | `/admin/audit` | `GET /v1/admin/audit?entity=` (exists) | add actor+action filters *(new query params only)* |
| Config | `/admin/config` | `GET/PATCH /v1/admin/config` (exists) | audited |

**New endpoints (6) — all additive, all admin-gated, all audit-logged:**
1. `GET /v1/admin/metrics/overview?days=14` — timeseries + KPI block (orders created/delivered/failed/day, GMV, deposits held, dues, payouts, UPI/COD split, on-time %).
2. `GET /v1/admin/users?query=&suspended=&cursor=` — user directory (PII masked beyond what §3 allows).
3. `GET /v1/admin/users/{id}/detail` — user 360: profile, orders count/sum, ledger, recent orders, sessions/devices.
4. `POST /v1/admin/users/{id}/suspend` + `POST /v1/admin/users/{id}/unsuspend` (+`restrict` variant via body level) — §14.5, revokes sessions, audited.
5. `GET /v1/admin/payments?cursor=&method=&status=` — payment rows + refund rows joined with order/rider attribution.
6. `GET /v1/admin/ledger` — all customers' jar positions.
   *(Plus: `GET /admin/orders` gains optional `query/payment_status/from/to` query params; `GET /admin/audit` gains `actor_id/action` query params — additive only.)*

**Vendors**: suspend/restrict for vendors reuses the same new endpoints (users table holds both) — vendor suspend also revokes sessions like §14.1; Firebase-disable stays a documented manual step (already the pattern in §14.1).

## 6. Wireframe (component tree — Overview page)

```
┌────────────────────────────────────────────────────────────────────────────┐
│ Sidebar 248px (white, 1px border-r)      │  Content (Canvas #F9FAFB)       │
│ ┌──────────────┐                         │ ┌─────────────────────────────┐ │
│ │ ◆ Shodasha   │  ← logo + "Admin" chip  │ │ Topbar: search · day chip   │ │
│ │              │                         │ │ · bell · admin avatar menu  │ │
│ │ OVERVIEW  ←──│─ active = blue left bar │ └─────────────────────────────┘ │
│ │ Orders       │                         │ ┌─ KPI row: 2fr 1fr 1fr 1fr ──┐ │
│ │ Vendors      │                         │ │ GMV ₹ with sparkline (2fr)  │ │
│ │ Users        │                         │ │ Orders today · Deltas ↑↓    │ │
│ │ Payments     │                         │ │ Deposits held · Dues        │ │
│ │ Ledger       │                         │ └─────────────────────────────┘ │
│ │ Operations   │                         │ ┌─ Row 2: 8/4 asymmetric ────┐ │
│ │ Trust ●3     │  ← live count badge     │ │ GMV + orders area chart    │ │
│ │ Audit        │                         │ │ (8 cols, 280px)            │ │
│ │              │                         │ │ Payment split donut (4)    │ │
│ │ ──────────   │                         │ └─────────────────────────────┘ │
│ │ admin@phone  │                         │ ┌─ Row 3: 7/5 ───────────────┐ │
│ │ [Sign out]   │                         │ │ Orders-by-state h-bars 7   │ │
│ └──────────────┘                         │ │ Alerts list 5 (trust+      │ │
│                                          │ │ custody+dues) → deep links │ │
│                                          │ └─────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────┘
Mobile <768px: sidebar → top slide-over (44px targets); KPI row → 2-col grid → 1-col;
charts stack; tables → horizontal scroll with pinned first column.
```
Detail pages share the shell; tables use sticky header + row hover `translateX(2px)` spring; danger actions (Block, cancel-override) open a **Sheet** with typed reason + red confirm button — matching ADR-016's "human confirms, never automatic".

## 7. Backend delta — API contract discipline

Rules to honor (from §0/§8 of the contract): same envelope `{data:[…], next_cursor}`; same error envelope; cursor pagination for lists; actor from session only (H1); every new write → `audit_log`; money integer paise; new endpoints live in `admin.py` alongside existing routes (same router, same DI); **no existing endpoint changes request/response shape** — the two existing reads only *gain optional query params* (additive, non-breaking). New repo functions go in new `repositories/admin_read_repo.py` to keep `user_repo.py`/`order_repo.py` untouched (their callers = Flutter apps — zero regression surface). Tests: pytest for each new endpoint (auth 403 non-admin, 200 admin, audit row written on suspend, session revocation on suspend, cursor paging) mirroring `tests/test_auth.py` patterns.

## 8. Success criteria (acceptance)

1. Admin can log in and every `/admin/*` page renders live data from the Workers API (no mock data in the final build; a `NEXT_PUBLIC_API_MODE=mock` flag exists for offline UI dev).
2. Block/unblock user + vendor works end-to-end: session revoked, BLOCKED chip, audit row visible in `/admin/audit` immediately.
3. Overview shows: orders created/delivered/failed today, GMV today + 14-day trend, deposits held, dues receivable, payouts, UPI-vs-COD split, on-time adherence — all from real SQL aggregates.
4. All money displayed in ₹ with monospace tabular numerals; server remains the only money computer.
5. `npm run build` clean; `pytest workers/api` fully green (existing 145 + new); lint + typecheck clean.
6. Light theme, zero purple gradients, zero emoji, zero `Inter`; tables keyboard-navigable; destructive actions always confirm + audit.
7. Context files synced: `progress-tracker.md`, `flow.md`, `decision.md` + ADR-029 (libraries) + ADR-030 (backend additive endpoints).
