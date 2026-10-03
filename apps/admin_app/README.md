# Shodasha Admin (Super Admin Console)

Shodasha Mineral Waters' super-admin dashboard — orders, users, vendors, payments, jar ledger, operations, trust and audit, backed by the Python Workers API (`workers/api` → D1).

## Provenance

Imported from the open-source **Studio Admin** template
[arhamkhnz/tanstack-shadcn-admin-dashboard](https://github.com/arhamkhnz/tanstack-shadcn-admin-dashboard)
(TanStack Start + React 19 + Tailwind CSS v4 + shadcn/ui, MIT — see [LICENSE](./LICENSE)).
Its `.git` folder was removed on import (branch `013-premium-admin-dashboard`) so this app is part of
the Shodasha monorepo. Upstream remains the recovery path for any removed template screen.
Template screens we don't use were deleted (see spec: `Feature_docs/premium-admin-dashboard/spec.md`);
shared components/design system were kept untouched.

## What's inside (our screens)

| Route | Surface | Worker endpoints |
|---|---|---|
| `/dashboard` | Overview (KPIs, GMV trend, UPI/COD split, on-time %, alerts) | `GET /v1/admin/metrics/overview`, `GET /v1/admin/metrics` |
| `/dashboard/orders` + `$orderId` | Orders list + detail (assign/reassign/cancel-override, activity) + client-side CSV export | `GET /v1/admin/orders`, `POST …/assign\|reassign\|cancel-override`, `GET /v1/admin/audit` |
| `/dashboard/users` + `$userId` | Directory + 360 detail, block/unblock (typed reason) | `GET /v1/admin/users(/detail)`, `POST …/suspend\|unsuspend` |
| `/dashboard/vendors` + `$vendorId` | Vendors + custody/payouts/strikes, review-hold | `GET /v1/admin/vendors(/detail)`, `POST …/review-hold\|release` |
| `/dashboard/payments` | Payments + refunds tabs (status/method filters) | `GET /v1/admin/payments`, `GET /v1/admin/refunds` |
| `/dashboard/analytics` | FR-33 KPI matrix (GMV/AOV, fulfilment, on-time, dues, deposit, payouts, UPI/COD), payment-mix + on-time trends, vendor/customer leaderboards | `GET /v1/admin/metrics/overview`, `GET /v1/admin/custody`, `GET /v1/admin/users` |
| `/dashboard/finance` | FR-30/31 money command center: collections/dues/deposit/payout cards, day-close leak watch, dues follow-up (wa.me Hindi reminder + audited write-off) | `GET /v1/admin/metrics/overview\|reconciliation\|dunning\|ledger`, `POST /v1/admin/dues/{id}/write-off` |
| `/dashboard/dispatch` | FR-26 dispatch board: state funnel, unassigned pool, vendor custody, route board + generate | `GET /v1/admin/orders\|reconciliation\|custody`, `POST /v1/admin/routes/generate` |
| `/dashboard/ledger` | Jar ledger positions + per-row audited adjust (deltas + mandatory reason) | `GET /v1/admin/ledger`, `POST /v1/admin/ledger/{id}/adjust` |
| `/dashboard/operations` | Reconciliation, custody, dues, routes-generate | `GET /v1/admin/reconciliation\|custody\|dunning`, `POST /v1/admin/routes/generate` |
| `/dashboard/trust` | Quality / strikes / complaints / returns queues + resolve | `GET /v1/admin/quality\|strikes\|complaints\|returns` + actions |
| `/dashboard/audit` | Audit log viewer (actor/action filters) | `GET /v1/admin/audit` |
| `/dashboard/config` | Runtime config editor (audited) | `GET/POST /v1/admin/config` |
| `/auth/v1/login` | Admin phone-OTP sign-in (Firebase, or dev shortcut) | `POST /v1/auth/otp/start\|verify`, `/v1/auth/refresh`, `/v1/auth/logout` |

Auth = HttpOnly cookie BFF (`sh_session` 30 min + `sh_refresh` 7 d) set inside server functions
(`src/server/admin-session.ts`); all reads/writes flow browser → server fn → Workers (`src/server/admin-api.ts`)
with silent refresh-once on 401. The access token never enters browser code.

## Run locally

```bash
# 1. Python worker (port 8000)
cd workers/api && SHODASHA_DB_PATH=./data/shodasha.db python -m uvicorn app.main:app --port 8000

# 2. This app (port 3200)
cd apps/admin_app && npm install && npm run dev
```

`.env.example` documents every variable. `API_MODE=mock` (default) renders fixtures offline;
`API_MODE=live` + `API_URL=http://127.0.0.1:8000` uses the real worker. Without Firebase env vars the
sign-in uses the worker's `DEV_AUTH` path (`dev|<phone>|…`) — never enable that in production.

## Checks

```bash
npx tsc --noEmit      # types
npm run build         # production build (Nitro output in .output/)
npx biome check       # lint/format
```
