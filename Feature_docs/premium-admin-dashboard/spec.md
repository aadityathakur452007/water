# Feature Specification: Premium Admin Dashboard (TanStack + shadcn rebuild)

**Feature Branch**: `013-premium-admin-dashboard`

**Created**: 2026-10-03

**Status**: Draft — awaiting user approval (speckit review-spec gate)

**Input**: User description: "Clone arhamkhnz/tanstack-shadcn-admin-dashboard into the monorepo as the new admin dashboard. Don't replace the old one yet. Hide the template pages we don't need, port the features from our current admin dashboard into it, follow the template's own design system with no AI-made design, connect it to the Python backend, do everything on a new branch, and use parallel agents to go faster."

---

## 1. What we are doing (in plain terms)

Our current admin dashboard ([apps/admin_app](apps/admin_app), Next.js) **works, but looks plain**. The GitHub template
[arhamkhnz/tanstack-shadcn-admin-dashboard](https://github.com/arhamkhnz/tanstack-shadcn-admin-dashboard) ("Studio Admin")
looks **premium and polished**. The plan:

1. **Clone the template** into the monorepo at `apps/admin_app_v2` — next to `user_app` and `vendor_app`.
   Remove its `.git` folder so it becomes part of **our** repository (committed as our own admin dashboard),
   keeping the upstream `LICENSE` + a provenance note in its README.
2. **Do NOT touch the old admin** (`apps/admin_app`) or the Python backend (`workers/api`). They stay exactly as they are.
3. **Hide / remove the template pages we don't need.** The template ships ~25 screens; we need ~11.
4. **Bring our features in.** Every feature of the old admin (see §3) is rebuilt *on top of the template's own
   components, layout system, tables, charts and theme* — we use (and where needed, edit) the template's existing
   code. **We never invent new visual components or design anything from scratch.** No AI-slop look. The UI should
   be indistinguishable from the template.
5. **Connect the real Python backend.** All data flows: browser → TanStack Start server functions (BFF) →
   Python Workers (`workers/api`, FastAPI) → D1. Cookie session + CSRF discipline identical to the old admin.
6. **Everything on branch `013-premium-admin-dashboard`** — `main` is untouched.
7. **Implementation runs with parallel agents** on non-overlapping file areas after the shared foundation is in place.

### Locked decisions (user answered 2026-10-03)

| Decision | Choice |
|---|---|
| Clone location | `apps/admin_app_v2` |
| Theme preset | Template's **default neutral** theme (unchanged) |
| Dark mode | **Keep the template's light/dark toggle** |
| Deploy target | **Cloudflare Workers** (Nitro cloudflare preset + `WATER_API` service binding, `API_URL` fallback for local dev) |

---

## 2. What gets hidden vs kept (template screens)

**Kept & adapted:**

| Template screen | Becomes |
|---|---|
| Default Dashboard | `/admin` Overview — KPI cards, GMV trend, payment split, order-state mix, on-time %, alerts |
| Users Management | `/admin/users` and `/admin/vendors` (two instances of the same premium table pattern) |
| Auth screens (4) | `/sign-in` becomes our admin phone-OTP login, restyled **only** by swapping form content with our OTP inputs inside the template's own form components |
| App shell (sidebar, topbar, search, theme switcher, breadcrumbs, width controls) | stays exactly as shipped |

**Hidden (removed from the sidebar nav AND their route folders deleted — git history + upstream repo keep them retrievable):**
CRM, Finance, Analytics, Productivity, E-commerce, Academy, Logistics, Infrastructure, Patient Monitoring,
Legacy defaults (v1 variants), File Manager, Email, Chat, Calendar, Kanban, Invoice, Profile, Roles Management.

**New pages we must create by composition (no new design, only template primitives):**
`/admin/orders/[orderId]`, `/admin/users/[userId]`, `/admin/vendors/[vendorId]`, `/admin/payments`,
`/admin/ledger`, `/admin/operations`, `/admin/trust`, `/admin/audit`, `/admin/config` —
each is the template's table/detail pattern fed with our data. The template's shared `components/` library
(cards, charts, table, data-toolbar, badges, dialogs, sheets, empty/loading states) remains fully available for this.

---

## 3. Feature parity — everything the old admin does must exist here

Ported from `apps/admin_app` (source of truth: its route map in [context/flow.md](context/flow.md) and
[Feature_docs/super-admin-panel/spec.md](Feature_docs/super-admin-panel/spec.md)):

1. **Overview** — orders today (created/delivered/failed), GMV today + 14-day trend, deposits held,
   dues receivable, payouts, UPI-vs-COD split, on-time adherence; alerts list deep-linking.
2. **Orders** — list with state/payment/search filters + cursor paging; **order detail**: status tracker,
   bill, assign/reassign (vendor picker with capacity), cancel-override (confirm sheet), activity from audit.
3. **Users** — directory (search, role, suspended filters); **user detail 360** (orders, ledger, dues,
   sessions, devices, strikes, recent orders) + Block/Unblock with typed reason + level → "N sessions revoked" feedback.
4. **Vendors** — directory (capacity, duty, custody, KYC, strikes); **vendor detail** (profile, zones,
   stops done, jars delivered, payouts, strikes) + review-hold/release + suspend/unsuspend.
5. **Payments** — payments + refunds tabs, status/method filters, rider attribution.
6. **Jar ledger** — all customers' held/deposit/dues positions with hold-limit flags.
7. **Operations** — day-close reconciliation, custody queue, dues/dunning list, routes-generate action.
8. **Trust** — quality incidents (confirm/reject), strikes (clear), complaints (resolve); live badge count in sidebar.
9. **Audit** — audit_log viewer with actor/action filters, trace IDs.
10. **Config** — audited runtime-config editor.
11. **Auth** — admin phone-OTP login (Firebase channel, or dev OTP locally), admin-only gate redirect,
    logout, silent token refresh, error toasts.

**Data rules carried over:** money is integer paise on the wire and formatted ₹ on display; the server is the
only money computer; every destructive action needs a typed-confirm sheet and is audit-logged upstream.

---

## 4. User stories & testing (prioritized, independently testable)

### User Story 1 — The template becomes our admin app, untouched premium look (P1)

Clone the repo into `apps/admin_app_v2`, strip its `.git`, install its deps, keep its default neutral theme +
dark toggle, hide/remove the screens we don't need, run it in the monorepo.

**Why this priority**: without a clean clone nothing else can start.

**Independent Test**: `cd apps/admin_app_v2 && npm run dev` opens the template's own dashboard on `:3200`
with its premium sidebar/topbar; unneeded screens are gone from nav; `git log` shows the clone committed inside
our monorepo; `git diff main` shows zero changes under `apps/admin_app` and `workers/api`.

**Acceptance Scenarios**:

1. **Given** the monorepo, **When** the dev server of `admin_app_v2` runs, **Then** the exact template UI loads (neutral theme, working light/dark toggle, collapsible sidebar, command palette).
2. **Given** the sidebar, **When** navigating, **Then** only kept screens are reachable; no hidden screen appears in nav or routes.
3. **Given** the repo root, **When** inspecting `apps/admin_app_v2/.git`, **Then** it does not exist; upstream `LICENSE` and provenance note exist.

---

### User Story 2 — Premium shell talks to the real Python backend (P1)

Wire auth + data flow: `/sign-in` collects our admin phone → OTP using the template's own form components;
server functions chat to `workers/api`; one protected page (`/admin` Overview) renders **live** metrics.

**Why this priority**: proves the full pipe (browser → BFF server function → Python Worker → D1) before bulk porting.

**Independent Test**: with the Python worker running on `:8000`, sign in with an admin phone, land on `/admin`
showing today's real orders/GMV from D1; wrong-role or no-session access bounces to sign-in.

**Acceptance Scenarios**:

1. **Given** a valid admin phone, **When** OTP verify succeeds, **Then** HttpOnly `sh_session` (30m) + `sh_refresh` (7d) cookies are set exactly like today's login route.
2. **Given** no/invalid session, **When** opening any `/admin/*` route, **Then** server-side guard redirects to `/sign-in?next=…`.
3. **Given** an expired access cookie, **When** any call 401s, **Then** silent refresh retries once, then redirects to sign-in.
4. **Given** the worker is down, **When** the Overview loads, **Then** the template's error/empty state shows with retry — never a blank screen.

---

### User Story 3 — Read-only surfaces ported (P2)

Overview fully fleshed out plus Orders list, Payments, Ledger, Audit, Config viewers — every read endpoint of
the old admin, rendered through the template's table/chart/card components.

**Why this priority**: most daily value; zero mutation risk.

**Independent Test**: with seeded worker data, each surface lists real rows with working filters, cursor paging
("load more"), correct ₹/paise formatting, sort where the table pattern provides it.

**Acceptance Scenarios**:

1. **Given** seeded orders, **When** filtering Orders by state/payment/search, **Then** only matching rows show; deep-linking from Overview KPIs pre-applies filters.
2. **Given** >1 page of rows, **When** scrolling/loading more, **Then** cursor pagination fetches the next page (same `{data, next_cursor}` envelope).
3. **Given** any money value, **When** displayed, **Then** it is ₹-formatted from integer paise with tabular numerals.

---

### User Story 4 — People surfaces with block/unblock actions (P2)

Users + Vendors directories **and detail pages** with the old admin's actions: suspend/unsuspend (typed reason
+ level sheet), review-hold/release, "N sessions revoked" toasts, sidebar trust badge.

**Why this priority**: the headline power of the admin (block bad actors) must survive the rebuild.

**Independent Test**: block a user; profile + row show BLOCKED state instantly, toast reports revoked sessions,
and the audit viewer shows the new entry.

**Acceptance Scenarios**:

1. **Given** a user row, **When** Block is confirmed with reason, **Then** `POST /v1/admin/users/{id}/suspend` fires with CSRF headers; UI updates optimistically and rolls back on error with a toast.
2. **Given** a vendor with review-hold, **When** Release is clicked, **Then** the hold clears and the state chip updates.
3. **Given** a strike/complaint exists, **When** the sidebar loads, **Then** the Trust badge count matches `GET /v1/admin/metrics` (`quality_open`).

---

### User Story 5 — Order & operations actions (P3)

Order detail with tracker/bill/assign/reassign/cancel-override; Operations page (reconciliation, custody, dues,
routes-generate); Trust queue resolutions (quality confirm/reject, strike clear, complaint resolve).

**Why this priority**: completes operator powers; depends on read surfaces.

**Independent Test**: reassign an order to a vendor → detail activity updates; generate routes → confirmation
toast; resolve a quality incident → queue count drops.

**Acceptance Scenarios**:

1. **Given** a placed order with available vendors, **When** assign/reassign is confirmed, **Then** the action posts with version fencing; a stale version shows a refresh hint and the picker reloads.
2. **Given** the Operations page, **When** routes-generate runs, **Then** the worker responds and the confirmation/error surfaces in a toast (no silent failures).
3. **Given** a quality incident, **When** Confirm/Reject is clicked, **Then** status changes are audited server-side and reflected in the queue.

---

### User Story 6 — Ownership polish & green build (P3)

README/provenance, ports & env docs (`:3200`, `API_URL`, `API_MODE=mock` fixtures for offline UI work,
service binding wiring), full `tsc` + build + lint green, old admin provably untouched.

**Why this priority**: ship-quality close-out.

**Independent Test**: one command builds clean; `git diff main -- apps/admin_app workers/api` is empty.

**Acceptance Scenarios**:

1. **Given** `NEXT_PUBLIC`-style env `API_MODE=mock`, **When** running without the worker, **Then** every surface renders fixtures in template styling (offline UI dev keeps working like the old admin's mock mode).
2. **Given** the final tree, **When** typecheck/build/lint run, **Then** all pass with zero errors in `apps/admin_app_v2`.

---

### Edge Cases

- Worker unreachable/slow → template error states + retry, 15s timeout, no frozen UI.
- 403 (non-admin or suspended admin) → "Not permitted" toast + redirect; the UI is never the security gate.
- 422 validation errors → inline field errors using the template's form primitives.
- Offline/deploy environment without `WATER_API` binding → `API_URL` fallback; local dev never needs the binding.
- Concurrent admin edits → optimistic updates roll back on 409/version conflicts with a reload hint.
- Long lists → cursor paging everywhere; no infinite unbounded fetches.
- Dark mode → every ported page checked in both themes (template tokens, no hardcoded colors).
- Reduced motion → template behavior preserved; no added animations.

---

## 5. Requirements

### Functional Requirements

- **FR-001**: System MUST clone `tanstack-shadcn-admin-dashboard` into `apps/admin_app_v2` with its `.git` removed and commit it into this monorepo on `013-premium-admin-dashboard`.
- **FR-002**: System MUST keep upstream `LICENSE` and add a provenance README note (source repo + commit).
- **FR-003**: Old admin `apps/admin_app` MUST receive zero file changes on this branch (verified via git diff).
- **FR-004**: Backend `workers/api` MUST receive zero file changes; all existing endpoints are consumed as-is.
- **FR-005**: Sidebar navigation MUST list only: Overview, Orders, People (Users, Vendors, Trust), Payments, Ledger, Operations, Audit, Config — grouped, with icons from the template's icon set and the live Trust badge.
- **FR-006**: All template screens listed in §2 "Hidden" MUST be removed from navigation and their route folders deleted from `apps/admin_app_v2`.
- **FR-007**: Authentication MUST reuse the Python Workers OTP flow (`/v1/auth/otp/start|verify`, role=admin gate) via TanStack Start server functions, setting HttpOnly `sh_session` + `sh_refresh` cookies with the same flags as today.
- **FR-008**: Session refresh MUST be silent on 401 (single retry) using `/v1/auth/refresh`, then redirect to `/sign-in?next=…` on failure.
- **FR-009**: All reads MUST flow browser → server function → Worker `GET /v1/admin/*` with the session cookie forwarded server-side; the access token never enters browser code.
- **FR-010**: All writes MUST flow through server functions forwarding cookie + `x-csrf-token` + `idempotency-key` headers to the Worker (replacing today's `/api/admin-actions` behavior).
- **FR-011**: Cloudflare deployment MUST use the Nitro cloudflare preset with a `WATER_API` service binding, falling back to `API_URL` (default `http://127.0.0.1:8000`) when the binding is absent.
- **FR-012**: `API_MODE=mock` MUST render fixtures for every surface so UI work works offline, matching today's mock-mode behavior.
- **FR-013**: Every old-admin feature in §3 MUST be present and functional on its mapped screen.
- **FR-014**: All money MUST stay integer paise in code and be rendered ₹ via a single shared formatter (ported `lib/format.ts`), never recomputed client-side.
- **FR-015**: Destructive actions (block, cancel-override, strike clear, quality confirm/reject, complaint resolve) MUST use the template's dialog/sheet with typed confirmation before firing.
- **FR-016**: All UI MUST be composed from the template's existing components/tokens; new visual primitives MUST NOT be invented; edits to template files stay minimal and additive.
- **FR-017**: No hardcoded colors — the template's CSS variables/theme presets apply unchanged; the neutral preset stays default and the dark toggle stays functional.
- **FR-018**: Dev server MUST run on port `3200` (`user_app` docs untouched; avoids the old admin's `:3100`).
- **FR-019**: Implementation MUST be partitioned into tasks that parallel agents can execute on disjoint files (shell/api layer first, surfaces next, integration last).
- **FR-020**: `context` docs MUST be updated post-implementation (flow.md route map, progress-tracker) so agents can navigate the new app.

### Key Entities (mirror of the old admin's wire types, `apps/admin_app/src/lib/types.ts`)

- **OrderRow / OrderDetail** — id, user, jars (n/e), total paise, payment_status, state, window, events/activity.
- **UserRow / UserDetail** — user, role, kyc, suspended flag/reason, ledger summary, sessions/devices, strikes, recent orders.
- **VendorDetail** — profile (capacity/fees/duty/in-hand), zones, stops done, jars delivered, payouts, strikes.
- **PaymentRow / RefundRow** — order/user attribution, amount, method upi|cod, status, provider_ref.
- **LedgerRow** — customer held/deposit/refunded/dues.
- **AuditRow** — actor, action, entity, before/after, trace_id.
- **StrikeRow / QualityRow / ComplaintRow** — trust queue items with status + resolution actions.
- **Overview** — series + money totals (DayPoint / MoneyTotals).
- **ConfigRow, CustodyRow, DunningRow, Reconciliation** — operations surfaces.
- **Session** — HttpOnly cookie pair + role + admin gate (client never sees the token).

---

## 6. Success Criteria

### Measurable Outcomes

- **SC-001**: `npm run install && npm run build` + `tsc --noEmit` pass with zero errors in `apps/admin_app_v2`.
- **SC-002**: All 11 kept screens (sign-in + 10 admin surfaces) render real worker data end-to-end locally; only reachable-from-nav routes exist.
- **SC-003**: `git diff main -- apps/admin_app workers/api` is empty (old admin + backend untouched).
- **SC-004**: Design review: no invented components — every screen is realized with template components/tokens; template diffs limited to config, data wiring, form/OTP content, and nav entries.
- **SC-005**: Money formatting unified (single formatter; zero `toFixed`/raw paise in JSX).
- **SC-006**: Backend test suite (`cd workers/api && pytest`) remains fully green without modification.
- **SC-007**: ≥3 parallel agents complete their surface allocations without a single merge conflict on shared files.

---

## 7. Assumptions

- The template is a static snapshot (MIT); we do **not** track upstream updates. The upstream URL in the README provenance note is our recovery path if a removed page is ever needed.
- TanStack Start's server functions can transparently replace the old Next.js BFF routes (same cookie/CSRF/idempotency behavior); `workers/api` needs **no** changes — it already serves every endpoint the old admin used (42+ `/v1/admin/*` routes).
- Dev OTP shines locally via the worker's `DEV_AUTH` path (`dev|<phone>|<any>`), Firebase OTP in production — same as today.
- The template's own mock/demo data is not used; our fixtures mirror the real API shapes so `API_MODE=mock` and live mode differ only in data source.
- Keeping the template's neutral theme means we do **not** carry over the old admin's custom tokens (canvas/ink/steel accents); the template's tokens are the design system now.
- Ports: worker `:8000`, old admin `:3100` (unchanged), new admin `:3200`.
- Monorepo hygiene: `admin_app_v2` gets its own `node_modules` install; root `.gitignore` patterns (node_modules, .next, dist, .env) naturally exclude heavy dirs from the import commit.

---

## Appendix A — Endpoint → Surface map (verbatim from the old admin; backend untouched)

| Surface | Worker endpoints used (all existing) |
|---|---|
| Sign-in | `POST /v1/auth/otp/start`, `POST /v1/auth/otp/verify` (role=admin gate), `POST /v1/auth/refresh`, `POST /v1/auth/logout` |
| Overview | `GET /v1/admin/metrics` (badge), `GET /v1/admin/metrics/overview?days=` |
| Orders | `GET /v1/admin/orders` (+filters/cursor); detail reuses list pick + `GET /v1/admin/audit?entity=orders` + `GET /v1/admin/vendors` (picker); actions `POST /v1/admin/orders/{id}/assign|reassign|cancel-override` |
| Users | `GET /v1/admin/users`, `GET /v1/admin/users/{id}/detail`, `POST /v1/admin/users/{id}/suspend|unsuspend` |
| Vendors | `GET /v1/admin/vendors`, `GET /v1/admin/vendors/{id}/detail`, review-hold/release, suspend/unsuspend (same user endpoints; vendors live in `users` table) |
| Payments | `GET /v1/admin/payments?status=&method=`, `GET /v1/admin/refunds?status=` |
| Ledger | `GET /v1/admin/ledger` |
| Operations | `GET /v1/admin/reconciliation`, `GET /v1/admin/custody`, `GET /v1/admin/dunning`, `POST /v1/admin/routes/generate` |
| Trust | `GET /v1/admin/quality` (+confirm/reject), `GET /v1/admin/strikes` (+clear), `GET /v1/admin/complaints` (+resolve) |
| Audit | `GET /v1/admin/audit?actor_id=&action=` |
| Config | `GET /v1/admin/config`, `POST /v1/admin/config` |

## Appendix B — Parallel-agent work partition (plan phase will finalize)

1. **Foundation (serial, before fan-out)**: clone, strip `.git`, install, hide/remove routes, nav config, server-function API layer + auth + guards, mock fixtures layer.
2. **Agent A**: Overview + Orders + Order detail.
3. **Agent B**: Users + User detail + Vendors + Vendor detail.
4. **Agent C**: Payments + Ledger + Operations + Trust + Audit + Config.
5. **Integration (serial)**: cross-link badges/deep-links, README/provenance, env docs, full typecheck/build, git diff audit.

Each agent owns only its route folders + surface adapter files below `features/`/`routes/` of `admin_app_v2`;
shared shell and `lib/` are frozen after Foundation; conflicts are structurally impossible.
