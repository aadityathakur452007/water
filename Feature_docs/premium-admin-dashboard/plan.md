# Plan: Premium Admin Dashboard (`013-premium-admin-dashboard`)

**Input spec**: [Feature_docs/premium-admin-dashboard/spec.md](../../Feature_docs/premium-admin-dashboard/spec.md) ✅ user-approved 2026-10-03
**Design source**: Studio Admin template (shadcn ecosystem components + template's own token system + template's premium layout patterns/components).
**Stack**: TanStack Start (React 19, SSR server functions) ⇄ Python Workers BFF (`workers/api`) ⇄ D1.

## 0. Ground rules (from spec)

- No invented design — everything composes template components (`#components/ui/*`, dashboard table/card/-components patterns); template edits stay minimal.
- `apps/admin_app` + `workers/api`: **zero diffs** on this branch (git-audited).
- All colors/Via template tokens; no hardcoded colors; no emoji anywhere; `EMPTY/ERROR/LOADING` states honored.
- Every write needs typed confirm; every action fires a toast; no silent failures.
- Live/`mock` data mode selection is centralized in one module (env switch, `mock` default when unset).
- Dev server: port `3200` (vite `dev --port 3200`, template already sets a port flag in package.json).

## 1. Foundation (serial — everyone depends on it)

```
apps/admin_app/   # (imported as admin_app_v2 in round 1; renamed on round-2 cutover, replaces legacy admin)
├── src/
│   ├── routes/(main)/dashboard/-components/     # KEEP: app shell, header, sidebar — VERBATIM
│   ├── navigation/sidebar/sidebar-items.ts      # EDIT: our nav tree only
│   ├── routes/(main)/auth/-components/          # EDIT-ADAPT: admin-otp-login-form.tsx (RHF+zod, template Field/Input/Button)
│   ├── routes/(main)/auth/v1/login              # KEEP layout, swap form content
│   ├── server/                                  # ADD: admin-session.ts, admin-api.ts, admin-fixtures.ts, admin-actions.ts
│   ├── hooks/                                   # ADD: use-admin-api.ts (fetch hooks)
│   ├── data/admin/                              # ADD: admin-fixtures/*.ts (all surfaces, API shapes)
│   └── lib/                                     # ADD: money.ts (paise/₹ formatter)
├── vite.config.ts                               # EDIT: react-start + nitro + react plugin stack stays; port 3200; env
├── package.json                                 # EDIT: name, scripts (--port 3200); deps KEEP all; REMOVE: dnd-kit, fullcalendar, simple-icons, d3-geo, topojson, react-day-picker, react-resizable-panels, embla-carousel
└── tsconfig.json / biome.json / components.json # KEEP
```

Auth flow (new `src/lib/*`):
```
Server fn loginServer({ action: "start|verify", phone, code })
  → workerFetch fetch("http://127.0.0.1:8000/v1/auth/otp/start|verify", POST)
  → 200 verify && role==="admin"
      → setCookie("sh_session", access_token, 30min) + setCookie("sh_refresh", refresh_token, 7d)
  → non-admin → { error: { code: "FORBIDDEN", ... } }
client hook useLogin() → navigate({ to: sign-in, search: { next: "/dashboard" } })
```

Data (server `src/server/admin-api.ts`):
```
server fn adminGet(path)  → fetch(API_URL + "/v1/admin/*" + path) via cookie sh_session
server fn adminPost(path, body) → POST fetch via cookie sh_session + CSRF header
  401 → one silent refresh via /v1/auth/refresh, retry 1x, else 401 out
Errors map 1:1 with the template's error components; HTTP errors surface clean text.
Mock mode: getApiMode() → env API_MODE ("mock" default) → adminFixtures[path] || fixtures fallback.
```

Nav edit — sidebar shows **only**:
```
Dashboards → Overview (/dashboard), Orders (/dashboard/orders)
People → Users (/dashboard/users), Vendors (/dashboard/vendors), Trust (/dashboard/trust)
Operate → Payments (/dashboard/payments), Ledger (/dashboard/ledger),
          Operations (/dashboard/operations), Audit (/dashboard/audit), Config (/dashboard/config)
```
SearchDialog command palette keeps prefix matching — it reads `sidebarItems`, so it auto-follows our nav.

## 2. Route deletion (template "hide")

```
REMOVE (folders/files): crm finance analytics productivity ecom academy logistics infra file-manager patient-monitoring
                        legacy/* (default-v1, crm-v1, finance-v1, analytics-v1)
                        chat (both), mail, calendar, kanban, tasks, invoice, profile, roles, coming-soon, unauthorized
KEEP: dashboard route.tsx (shell), index.tsx (redirect), default/ → becomes our Overview feed,
      auth/* layouts + form components (`/-components/`), (external)/index → redirect dashboard,
      -components/not-found | root-error, __root.tsx

npm run generate-routes (tsr generate) after deletion — never touch routeTree.gen manually.
DELETE: auth register forms + GoogleButton (not in flow), chat/mail subfolders in dashboard routes.
```

## 3. Parallel work (Fan-out — each agent owns disjoint files; no shared files touched)

| Agent | Owns (files+folders) | Surfaces built |
|---|---|---|
| **A** | `dashboard/default/-components/*` (+ new folder `orders/`) | Overview KPI cards (default metric cards, performance-overview charts), Orders list + detail adapter |
| **B** | `dashboard/users/-components/*` (extend data.tsx + columns/table), `vendors/` (new folder) | Users list+detail; Vendors list+detail w/ custody/payouts/strikes |
| **C** | `payments/`, `ledger/`, `operations/`, `trust/`, `audit/`, `config/` (all new folders) | 6 read surfaces + zone board, custody, dunning, routes-generate, trust resolutions |

**Overlap-free rule**: A/B/C each own only folders above; shared imports stay read-only imports from layer modules. Each runs ti18n/`biome check --write` on its own files only. After A/B/C: I run `generate-routes` once, delete sidebar access to `mock` names, final biome, typecheck.

## 4. Integration (serial, after fan-out)

1. `npm run generate-routes`, wire nav badges (Trust live count = `GET /v1/admin/metrics`), sidebar deep-links.
2. Wire `link-proxy` in `__root.tsx` with the `next` param forwarding on 401 guard.
2. Full build: `npm run build` + `tsc --noEmit` + biome check green.
3. `git diff main -- apps/admin_app workers/api` audit → empty (spec FR-003/004).
4. Sync context docs: this plan, `context/progress-tracker.md`, `context/flow.md` route map, `Developer_Notes/admin-app-v2.md` (ports/env notes).
