# Free-tier launch readiness — spec

**Status:** **APPROVED by the owner on 2026-10-26 (G0).** The spec, pilot envelope, read-only probe plan, alert plan, and rollback plan are approved. This document still authorizes **no code, config, deploy, migration, load test, or production write**; G1, G3, and G4 remain separately gated. It defines the Free pilot decision and the evidence required to make it.

**Branch:** `035-premium-ui-states-release` · **HEAD at drafting:** `dbc5304`

**Owner decisions captured 2026-10-26:**

| Decision | Choice |
|---|---|
| Scope | Free pilot readiness + GO/NO-GO |
| Observability | Structured logs + Cloudflare Alerts; production traces stay **off** |
| Production probes | `/health` + public GETs only |
| Thresholds | 50% warn / 80% critical |
| Monitoring owner | Owner daily + email alerts |

**Related:**

- `Feature_docs/performance/2026-10-25-1000-user-capacity-audit.md` — A/B/C model and the Free-plan blocker.
- `Feature_docs/performance/2026-10-25-phase0-results.md` — measured `1102`/`1101` on Free.
- `Feature_docs/performance/2026-10-26-phase2-results.md` — current query counts and staging verification.
- `Feature_docs/performance/2026-10-26-phase3-ab-validation-spec.md` — Phase 3F/3P split.
- `Feature_docs/performance/free-tier-launch-runbook.md` — operator checklist and incident playbooks.

---

## 1. Why this phase exists

The owner wants to launch Shodasha on Workers **Free** for the initial low-traffic phase. Phase 3F proved local route correctness and write idempotency, but it did not prove Workers CPU, D1 latency, login, cron, or 1,000-user capacity. Phase 3P (A/B/C) is deferred until the account moves to Workers Paid.

This phase answers one question:

> **Can Shodasha run a bounded pilot on Workers Free without violating the Free envelope or misleading the owner about capacity?**

It is a **GO/NO-GO decision**, not a capacity certification. The 1,000 registered / 1,000 DAU targets remain Phase 3P on Paid. A Free pilot is a temporary bridge, not a launch at scale.

**Current answer: NO-GO for a transactional pilot until the auth and cron gates pass.** Phase 0 measured intermittent `1102` on production `/health` at 9 users, and no Free evidence exists that password login (PBKDF2 100k) or the new cron tick fits 10 ms CPU / 50 D1 round trips. The read-only canary may still be possible.

---

## 2. What “launch” means here

Three distinct outcomes are possible. The evidence decides which one, not the calendar.

| Outcome | What it allows | Preconditions |
|---|---|---|
| **A. Read-only canary** | Public `GET /health`, `/v1/catalog`, `/v1/windows` at low rate; no auth, no writes | Production deploy gate + read-only smoke passes |
| **B. Transactional pilot** | Login/register, COD orders, order reads, cancel/reschedule, vendor PoD; **no UPI, no auto-delivery subscriptions** | A + auth gate + cron gate + pilot envelope accepted |
| **C. NO-GO on Free** | No customer-facing pilot; upgrade to Workers Paid and run Phase 3P | Auth or cron gate fails, or read-only smoke fails |

A transactional pilot is **not authorized** by this spec. It requires separate approval of the staging auth probe, the staging cron probe, and the production deploy gate.

---

## 3. Current facts

### 3.1 Workers Free hard limits (verified 2026-10-26)

| Limit | Free | Source |
|---|---:|---|
| Requests | 100,000/day | Cloudflare Workers limits |
| CPU time | 10 ms/request and 10 ms/cron invocation | Cloudflare Workers limits |
| Memory | 128 MB | Cloudflare Workers limits |
| Subrequests | 50/request | Cloudflare Workers limits |
| D1 queries per Worker invocation | 50 (a `db.batch()` counts as one) | Cloudflare D1 limits |
| D1 rows written | 100,000/day | Cloudflare D1 pricing/limits |
| D1 storage | 500 MB/database; 5 GB/account | Cloudflare D1 limits |
| D1 Time Travel | 7 days | Cloudflare D1 limits |
| Cron triggers | 5/account | Cloudflare Workers limits |
| Workers Logs | 200,000 events/day; 3-day retention | Cloudflare Workers Logs |

### 3.2 Production state (last recorded; re-verify after deploy)

| Item | Recorded value |
|---|---|
| Worker | `water` — `https://water.adityathakur452007.workers.dev` |
| D1 | `shodasha` (`da762aad-1d5c-46eb-992e-acc79505cc95`) |
| Users | 9 |
| Subscriptions | 0 |
| Migration | 028 |
| Cron | `*/15 * * * *` |
| Logs | enabled, `head_sampling_rate: 1`, `invocation_logs: true` |
| Traces | **disabled** |
| App log sample | default `OBS_LOG_SAMPLE_RATE=0.05`; 4xx/5xx/slow always log |

**Production is behind this branch.** Migration 029 and the Phase 1A/1B/2 code are staging-verified but not deployed. A launch decision on the old production code is invalid; the deploy gate is a prerequisite, not part of this approval.

### 3.3 Evidence already on record

| Evidence | Result | What it means |
|---|---|---|
| Phase 0 production `/health` | 5 probes: 200, **503 1102**, 200, 200, 200 at 1.9–4.2 s | Free CPU ceiling predates the current code and affects the 9 existing users |
| Phase 0 staging A/B/C | 27.3% / 16.7% / 55.6% 5xx, bodies `1102` then `1101` | Sustained load is not measurable on Free |
| Phase 0 warm/cold | Warm `/health` 118–194 ms; cold start 1.5–4 s | Cold start is a real UX risk, not a throughput number |
| Phase 2 query counts | Order detail 5 endpoint statements; vendor route 5; admin metrics 1 on cache hit; login pre-lookup 2 statements / 1 round trip | Read shapes are now inside the 50-round-trip cap; CPU is still the wall |
| Phase 3F local | `phase3-a` 108 counted / 115 all, 0 errors; `phase3-b` 217 / 230, 0 errors; write probe 2 creates / 2 cancels / 1 reschedule | Route/idempotency evidence only; not Workers CPU or D1 latency |
| Free auth proof | **None** | PBKDF2 100k + Python Worker has not been proven on Free |
| Free cron proof | **None** | The new scheduler has not been proven on Free at 10 ms / 50 round trips |

### 3.4 What is not being claimed

- Free cannot certify 1,000 registered users or 1,000 DAU.
- Free cannot certify UPI/Razorpay webhook behavior, provider latency, or refunds/payouts.
- Free cannot certify 60-subscription cron ticks or 1,000-subscription drains.
- Free cannot certify Flutter cold start, frames, or device behavior.
- `workers.dev` has no zone cache or WAF; CDN claims do not apply.

---

## 4. Scope

### In scope

- A Free pilot envelope with hard stop thresholds.
- A read-only production smoke after the deploy gate.
- Cloudflare Alerts / external uptime monitoring and a daily owner checklist.
- A GO/NO-GO decision with explicit upgrade triggers.
- An operator runbook and incident/rollback procedure.

### Out of scope

- Production deploy, migration 029, or any D1 write.
- Staging load tests, login bursts, cron windows, or 30-minute soak.
- Creating synthetic login users or credentials.
- Code changes, feature flags, or schema changes.
- Workers Paid purchase or Phase 3P execution.
- Product features, Flutter changes, or UI work.

---

## 5. Free pilot envelope (approved by owner 2026-10-26)

### 5.1 Platform hard limits vs pilot operating limits

The pilot is deliberately kept below the Free hard limits so a burst has room. The 50%/80% thresholds apply to **both** the Free hard limit and the pilot operating limit; the lower number wins.

| Signal | Free hard | Pilot operating cap | Warn (50%) | Critical (80%) | Action at critical |
|---|---:|---:|---:|---:|---|
| Requests/day | 100,000 | **10,000** | 5,000 | 8,000 | Pause new pilot invites; investigate |
| D1 rows written/day | 100,000 | **10,000** | 5,000 | 8,000 | Stop writes; inspect top write paths |
| CPU p99 | 10 ms | **8 ms** | 5 ms | 8 ms | Any `1102` is an immediate stop |
| D1 round trips/invocation | 50 | **45** | 40 | 45 | Identify route; batch or roll back |
| D1 size | 500 MB | **400 MB** | 250 MB | 400 MB | Purge/export or upgrade |
| Workers Log events/day | 200,000 | **160,000** | 100,000 | 160,000 | Lower `OBS_LOG_SAMPLE_RATE` |
| 5xx rate | — | **0.5%/15 min** | 0.5%/15 min | 2%/5 min | Roll back or pause |
| `/health` non-200 | — | **0 in 15 min** | 1 in 15 min | 2 consecutive probes | Pause; check D1/Cloudflare |
| Cron failed invocation | — | **0** | 1 tick | 2 consecutive ticks | Disable subscriptions; investigate |
| Auth `1102`/`1101` | — | **0** | any | any | Disable login/registration; upgrade |
| D1 error/overloaded | — | **0** | any | any | Stop writes; check D1 status |

**Metric note:** use **`db_roundtrips`** for the Free 50-query cap. `db_queries` counts statements inside a batch and is a CPU/latency diagnostic, not the platform query count. A batch of 16 statements is one D1 round trip but 16 `db_queries`.

### 5.2 Transactional pilot feature envelope (approved)

| Area | Allowed during Free pilot | Why |
|---|---|---|
| Accounts | Up to **50 registered pilot accounts**, **10 DAU**, **5 concurrent** | Keeps CPU/query bursts small; not a capacity claim |
| Auth | Login/register **only after the auth gate passes** | PBKDF2 100k is the highest-risk CPU path |
| Orders | **COD only**; create, read, cancel, reschedule | Avoids provider webhook and money-path latency |
| UPI | **Not supported** during the Free pilot | Razorpay intent/webhook is not Free-certified |
| Subscriptions | **No new auto-delivery subscriptions** until the cron gate passes | 60-sub ticks exceed Free’s 50-round-trip/10 ms envelope |
| Vendor | One route, **≤20 stops**; PoD OTP and sync allowed | Vendor route is now 5 endpoint statements |
| Admin | Read-only dashboard; no bulk exports | Keeps aggregate queries bounded |
| Support | Owner-managed WhatsApp/phone | No new support tooling |

**Enforcement gap:** there is no server-side feature flag for “COD only” or “subscriptions off.” The envelope is an **operational policy** for the pilot. Any UPI intent, new subscription, or >20-stop route is an out-of-envelope event and must be recorded. A future code change could add a flag, but that is not part of this phase.

---

## 6. Read-only production probes

These are authorized by the owner’s 2026-10-26 choice. They are **not** a load test.

| Probe | Method | Rate | Pass | Fail |
|---|---|---|---|---|
| Health | `GET /health` | Every 5 min (external monitor), plus 20 manual probes over 10 min after deploy | 200 `{"status":"ok"}`, `no-store` | Any 503/`1102`/`1101` |
| Catalog | `GET /v1/catalog` | Once after deploy, then once daily | 200, expected body | 5xx/`1102` |
| Windows | `GET /v1/windows` | Once after deploy, then once daily | 200, expected body | 5xx/`1102` |

**Not allowed:** login, registration, refresh, orders, payments, admin, vendor, cron trigger, or any SQL write. Do not use `wrangler tail` against production for a sustained period; capture only a short, sanitized window if a failure needs diagnosis, and delete the raw output.

Probe traffic is <500 requests/day, negligible against 100k.

---

## 7. Monitoring and alerts

### 7.1 Sources

| Source | What it shows | Cadence |
|---|---|---|
| Workers metrics | Requests, errors, invocation statuses, CPU p50/p95/p99, memory | Daily + alert |
| D1 metrics | Read/write queries, rows read/written, query latency, storage | Daily + alert |
| Workers Logs | Structured `http_request` lines, 4xx/5xx, slow requests, `db_queries`/`db_roundtrips` | Daily + incident |
| Cron log | `cron tick {...}` summary with `db_queries`, `db_roundtrips`, duration | Every 15 min |
| Cloudflare Alerts | Email delivery on all plans; Monitors depend on dataset availability | Alert |
| External uptime monitor | `/health` from outside Cloudflare | Every 5 min |

**Alerts availability caveat:** Cloudflare Alerts can deliver email on all plans. Whether the Workers/D1 SQL API datasets are available to **Monitors** on this Free account must be verified in the dashboard before launch. If they are not, the external uptime monitor plus the daily checklist is the fallback; do not claim an alert exists until a test email is received.

### 7.2 Required alerts

| Severity | Condition | Delivery | First action |
|---|---|---|---|
| P1 | `/health` non-200 twice consecutively | Email + external monitor | Check D1/Cloudflare status; pause pilot |
| P1 | 5xx >2% over 5 min | Email | Inspect logs; roll back if deploy-related |
| P1 | Any `1102`/`1101` burst (≥3 in 10 min) | Email/manual log check | Stop pilot; Free CPU limit; upgrade |
| P1 | Auth `1102` or login/register 5xx | Email/manual | Disable auth; upgrade |
| P1 | Cron failed invocation or 2 consecutive failures | Email/manual | Check cron summary; disable subscriptions |
| P2 | Requests or rows written ≥50% of the pilot cap | Email/manual | Review trend; prepare upgrade |
| P2 | Requests or rows written ≥80% of the pilot cap | Email/manual | Pause invites; upgrade decision |
| P2 | CPU p99 ≥5 ms (warn) / ≥8 ms (critical) | Email/manual | Profile hot route; upgrade |
| P2 | D1 round trips/invocation ≥40 (warn) / ≥45 (critical) | Email/manual | Batch/optimize; roll back |
| P2 | D1 size ≥250 MB / ≥400 MB | Email/manual | Purge/export; upgrade |
| P3 | Log events ≥100k / ≥160k per day | Email/manual | Lower log sampling |

### 7.3 Daily owner checklist (10 minutes)

1. `/health` 200? Any 503/`1102`/`1101` in the last 24 h?
2. Requests today vs 10,000 pilot cap; 50%/80% threshold?
3. D1 rows written today vs 10,000 pilot cap.
4. CPU p50/p95/p99 and any invocation status “Exceeded resources.”
5. D1 round trips per invocation: p99/max; any route ≥40?
6. 5xx rate and top failing routes.
7. Cron: last tick summary, due backlog, `due_failed`, duration.
8. Auth: login/register failures (only if the auth gate passed).
9. D1 size and growth trend.
10. Record the numbers in the runbook table; escalate per §7.2.

---

## 8. Pre-launch gates

Every gate must be checked before a pilot starts. Gates G3/G4 are **not authorized** by this spec.

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| **G0** | This spec approved by the owner | Owner sign-off 2026-10-26 | **Passed** |
| **G1** | Production backup + migration 029 + Phase 1A/1B/2 deploy | Separate explicit approval; backup SHA256; deploy version ID | Not started |
| **G2** | Read-only production smoke | 20 `/health` probes over 10 min: 0 `1102`/`1101`, 0 5xx; catalog/windows 200 | Not started |
| **G3** | Free auth proof | Separate approved staging probe: 5 logins + 1 registration, all 2xx, no `1102`, CPU p99 ≤8 ms | **Not approved** |
| **G4** | Free cron proof | Separate approved staging probe: one tick with 0 due, one with 3 due; no `1102`, `db_roundtrips` ≤45, zero missed | **Not approved** |
| **G5** | Alerts configured and tested | Test email received; external monitor shows green | Not started |
| **G6** | Pilot envelope accepted | Owner accepted §5 on 2026-10-26, including COD-only/no-subscriptions policy | **Accepted** |
| **G7** | Rollback ready | Previous Worker version ID recorded; D1 backup verified; Time Travel window known | Not started |

### Gate rules

- **G2 fails** → Free read-only canary is NO-GO; upgrade to Paid.
- **G3 fails** → transactional pilot is NO-GO; read-only canary may still proceed. Registration and login must stay closed.
- **G4 fails** → transactional pilot may proceed **only with subscriptions disabled** and no cron-dependent promises. If the cron tick itself `1102`s, treat it as a Free CPU failure and upgrade.
- **G5 fails** → no pilot; monitoring is not optional.
- **G6 or G7 fails** → no pilot.

---

## 9. GO/NO-GO decision

| Decision | Conditions |
|---|---|
| **GO — read-only canary** | G0, G1, G2, G5, G7 pass; G6 accepts no-auth/no-write scope |
| **GO — transactional pilot** | All gates pass; auth and cron proofs are recorded; COD-only/no-subscriptions policy accepted |
| **CONDITIONAL** | G4 fails but G3 passes: pilot may run with subscriptions disabled; no auto-delivery promise |
| **NO-GO** | G2 fails, G3 fails, G5 fails, or the owner does not accept the envelope |

**Default until evidence exists: NO-GO for transactional pilot.**

**Status after the 2026-10-26 approval:** G0 and G6 pass. G1, G2, G5, and G7 are not started; G3 and G4 are not approved. Therefore the current decision is **NO-GO for a transactional pilot**, and a read-only canary is **not yet GO** because G1/G2/G5/G7 have not run.

If the outcome is NO-GO, the recommendation is Workers Paid + Phase 3P. Free is not a capacity target; it is a temporary low-traffic bridge.

---

## 10. Incident and rollback

### 10.1 Stop conditions

Stop the pilot immediately on any of:

- Any `1102`/`1101` on `/health`, auth, cron, or an order path.
- 5xx >2% over 5 min, or `/health` 503 twice consecutively.
- D1 error/overloaded, or writes failing repeatedly.
- Auth failures that block login/registration.
- Cron failed invocation twice consecutively.
- Requests or rows written ≥80% of the pilot cap.
- A money-path inconsistency (double charge, missing order, wrong state).

### 10.2 Rollback

There is **no application kill switch**. The fastest safe stop is a Worker rollback.

1. Record the current Worker version ID before deploy.
2. On a bad deploy: Cloudflare dashboard → Workers & Pages → `water` → Deployments → select the previous version → Rollback. CLI equivalent: `npx wrangler rollback <version-id>` (verify the version ID first).
3. Migration 029 is additive; a code rollback should not require a DB rollback. Do **not** restore D1 unless the migration itself is implicated.
4. D1 restore uses Time Travel (7 days on Free) or the pre-deploy export. It requires explicit owner approval; restore can lose writes made after the restore point.
5. After rollback, re-run the read-only smoke and record the result.

### 10.3 Communication

- Owner notifies pilot users via the existing WhatsApp/support channel.
- State what is unavailable, what data is safe, and when the next update will come.
- Never include tokens, phone numbers, raw headers, or D1 dumps in messages or commits.

---

## 11. Ownership and cadence

| Role | Responsibility |
|---|---|
| Owner | Daily checklist, alert response, pilot communications, upgrade decision |
| Agent | Draft/maintain docs, run read-only probes only when asked, never write production |
| Cadence | Daily for the first 7 days; weekly if stable |

**Escalation:** owner email is the primary alert destination. There is no secondary on-call in this phase; if the owner is unavailable, the pilot pauses rather than runs unmonitored.

---

## 12. Upgrade triggers (Free → Paid)

Move to Workers Paid and run Phase 3P when any of these is true:

- Any `1102`/`1101` on a customer-facing path.
- Auth gate fails or login/register cannot be proven Free-safe.
- Cron gate fails, or the pilot needs auto-delivery subscriptions.
- CPU p99 ≥8 ms, or D1 round trips ≥45 on a hot path that cannot be batched.
- Requests ≥80,000/day or rows written ≥80,000/day.
- D1 size ≥400 MB.
- The owner wants to exceed 50 registered / 10 DAU / 5 concurrent.
- UPI, refunds, payouts, or real money flows are required.
- The 1,000-user launch target becomes active.

Paid starts at $5/month plus usage; the Phase 3P cost model remains a separate, unapproved estimate.

---

## 13. Risks and limitations

- **Free CPU is the dominant risk.** Phase 0 saw `1102` at 9 users; no code change in this phase removes the 10 ms ceiling.
- **Python Worker cold start** is 1.5–4 s; a pilot user may see a slow first request even when the request eventually succeeds.
- **PBKDF2 100k** is the highest-risk CPU path. A single login may exceed 10 ms; the auth gate exists because this is unproven.
- **Cron** has a 10 ms CPU and 50-round-trip limit. The new scheduler is paged at 60 due subs, but even a 3-sub tick is unproven on Free.
- **No kill switch.** Rollback is the stop mechanism; it is slower than a feature flag.
- **No CDN/WAF on `workers.dev`.** Public reads hit the Worker; the anon throttle is per-isolate and approximate.
- **Alert availability.** Monitors may not expose Workers/D1 datasets on Free; the external monitor + daily checklist is the fallback.
- **Log retention is 3 days on Free.** Export only sanitized summaries; do not rely on raw logs for a postmortem after 3 days.
- **D1 Time Travel is 7 days on Free.** A late-discovered data issue may be unrecoverable.
- **Production is behind the branch.** G1 is a prerequisite; a pilot on old code would test the wrong system.
- **Owner-only monitoring.** No secondary on-call; the pilot pauses if the owner is unavailable.

---

## 14. Approval checklist

- [x] **Approve this spec** (G0) — approved 2026-10-26.
- [x] Approve the pilot envelope in §5 (50 accounts / 10 DAU / 5 concurrent; COD-only; no subscriptions; vendor route ≤20 stops) — approved 2026-10-26.
- [x] Approve the read-only production probe plan in §6 — approved 2026-10-26.
- [x] Approve the alert plan in §7 — approved 2026-10-26; owner email destination still to be recorded at G5.
- [ ] Approve the staging auth probe (G3) — **separate approval**; creates synthetic users and credentials outside the repo.
- [ ] Approve the staging cron probe (G4) — **separate approval**; may require a temporary cron window.
- [ ] Approve the production deploy + migration 029 (G1) — **separate approval**; backup first.
- [x] Accept the rollback plan in §10 — approved 2026-10-26.

G0 and G6 are approved. The pilot remains **NO-GO** until G1, G2, G5, and G7 pass and, for a transactional pilot, G3 and G4 are separately approved and pass.

---

## 15. Evidence to record during execution

| Artifact | Location | Notes |
|---|---|---|
| Read-only smoke | Runbook table | No raw headers/IPs; counts and status only |
| Worker version IDs | Runbook | Pre-deploy and post-deploy |
| D1 backup SHA256 | Runbook | No credentials |
| Auth gate result | Runbook | Status, CPU, no credentials |
| Cron gate result | Runbook | `db_roundtrips`, duration, due count |
| Daily checklist | Runbook table | 7 days minimum |
| Incident log | Runbook | Sanitized |
| GO/NO-GO memo | This spec §9 | Owner sign-off |

Do not commit tokens, phone numbers, raw `wrangler tail` dumps, or D1 exports.
