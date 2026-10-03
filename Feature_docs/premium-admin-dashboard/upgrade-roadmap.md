# Upgrade roadmap — premium admin v2, round 2 (branch 013)

**Research inputs**: PaniBox research report (PDF → `.utim_tmp/pdf_text.txt`; F1 repeat, F2 jar economics,
F3/F4 reliability + window, F5 pause, F6 WhatsApp, F7 payments, Pure Pani's "₹18k–70k/mo cash leaks"),
`Feature_docs/synthesis/feature-requirements.md` (FR-26…FR-34 = the admin's power list),
`workers/api/src/app/api/v1/admin.py` (the powers actually shipped), and the template's own premium
screen patterns (analytics / finance / logistics / e-commerce blocks — recoverable from upstream).

## 1. The gap the research exposes

FR-33 defines the analytics the admin MUST have: *on-time window adherence, repeat rate, reorder time,
deposit disputes, UPI-vs-COD split*. None of it has a screen today. FR-30/31 demand WhatsApp billing +
friendly Hindi reminders (Pure Pani built their whole product around stopping ₹18–70k/month cash leaks —
our dunning table had no reminder action at all). FR-32 asks for CRM-lite. And the backend already ships
powers the old dashboard never surfaced: **returns queue, ledger adjust, dues write-off** (all audited).

**Rule for this round (ADR-061 holds): zero backend changes** — everything composes existing
`/v1/admin/*` reads + the three unused write endpoints, so the parallel 014/015 threads own the backend
without conflict.

## 2. Shipped in this round

| New surface | Research/FR anchor | Template pattern | Data (all existing) |
|---|---|---|---|
| **Analytics** `/dashboard/analytics` | FR-33 + F1/F3/F7 | analytics KPI strip + area/line charts + leaderboards | `metrics/overview` series, `users`, `custody` |
| **Finance** `/dashboard/finance` | FR-30/31/33 + F6/F7 (cash leaks) | finance cards + transactions overview + table | `metrics/overview.money`, `reconciliation`, `dunning`, `payments`, `refunds`; writes: `dues/{id}/write-off` |
| **Dispatch** `/dashboard/dispatch` | FR-26 + F2 (jars out vs back) | e-commerce KPI strip + logistics shipment board | `orders` (funnel + unassigned), `reconciliation`, `custody`; action: `routes/generate` |

| Power-up on existing pages | Anchor | What it does |
|---|---|---|
| Ledger **Adjust** sheet | FR-28/29 (admin-only manual adjust, logged) | typed `d_held/d_deposit/d_dues + reason` → `POST /admin/ledger/{id}/adjust` |
| Dunning **WhatsApp reminder** | FR-31 + F6 | `wa.me` deep link with pre-filled Hindi dues reminder per customer |
| Dues **Write-off** | FR-31 | typed reason → `POST /admin/dues/{id}/write-off` (audited) |
| Trust **Returns tab** | FR-29 (10-day SLA queue) | `GET /admin/returns` surface next to quality/strikes/complaints |
| Orders **CSV export** | admin quality-of-life | client-side export of the loaded rows |
| Fix: detail routes dead (list swallowed children — missing `<Outlet/>`) | bug from live test | layouts for orders/users/vendors + `index.tsx` lists |

Sidebar regroup (4 groups): **Monitor** Overview · Analytics · Orders — **Money** Finance · Payments ·
Ledger — **People** Users · Vendors · Trust — **Operate** Dispatch · Operations · Audit · Config.

## 3. Deliberately parked (next rounds, in priority order)

1. **Invoice + WhatsApp send** — `POST /admin/invoices/{id}/send-whatsapp` exists but is provider-stubbed
   and invoice IDs aren't exposed on admin reads; needs a tiny additive read (`GET /admin/orders/{id}/invoice`)
   + provider wiring. Blocked on backend round (coordinate with 014/015 owners).
2. **Calendar (FR-27)** — subscription/next-delivery calendar view; template calendar block is deleted,
   recover from upstream; needs a future-dated deliveries read (additive endpoint).
3. **Customer book / CRM-lite (FR-32)** — 360° customer ranking by spend/dues/last-order; needs an
   aggregate read to avoid N+1 over user details.
4. **Vendor onboarding & zones UI** — `POST /admin/vendors`, `PATCH …/capacity`, zone attach/detach exist;
   worth a dedicated "Fleet" page when vendor count grows past one screen.
5. **Roles & permissions (FR-33 v2)** — multi-admin RBAC; template has a roles screen to adapt.

## 4. Verification story (this round)

Worker on :8000 (`DEV_AUTH=1`, demo seed) + apps/admin_app on :3200 (`API_MODE=live`), admin OTP dev login,
then every surface + action exercised in the real browser (accessibility tree asserts, not just HTTP 200):
overview KPIs from D1 (₹206 GMV demo order), orders table → detail, block/unblock, WhatsApp link intent,
write-off confirm, analytics numbers matching `metrics/overview` payload.
