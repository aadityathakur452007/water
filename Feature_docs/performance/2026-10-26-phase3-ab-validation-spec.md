# Phase 3 spec — validate A/B safely

**Date:** 2026-10-26
**Status:** Spec approved by the owner on 2026-10-26; harness extension approved and implemented the same day. **Phase 3F local runs completed 2026-10-26. Phase 3P is skipped, not deferred (ADR-148, 2026-10-26): the owner rejected Workers Paid and directed Free-only work, so no A/B reads, write probe, login burst, cron window, soak, or cost estimate will run. 1,000-user A/B certification is out of scope on Free.** The login probe was attempted and aborted at the 10 ms CPU ceiling (see §13.4). Production remains read-only. The Free-plan 10 ms CPU ceiling invalidates login bursts and causes intermittent `1102`/`1101` under load.
**Parent audit:** `2026-10-25-1000-user-capacity-audit.md` (§3, §4, §7 Phase 3, §8)
**Prior evidence:** `2026-10-25-phase0-results.md`, `2026-10-25-phase1-results.md`, `2026-10-26-phase2-results.md`
**Runbook:** `phase3-runbook.md`
**Production:** read-only. No load test, write, migration, or deploy against `water` / `shodasha` without a separate explicit approval. This spec authorizes staging work only.

## 1. Goal

Certify the two launch targets with measured evidence and produce an owner-signed GO/NO-GO:

- **A — 1,000 registered users**, ~5% concurrent at peak (50 concurrent), 2.78 average rps / 6.94 peak rps.
- **B — 1,000 DAU**, ~10% concurrent at peak (100 concurrent), 5.56 average rps / 13.89 peak rps.

C (1,000 concurrent) remains a **stress target**, not a launch gate. It may be run only as a knee-finding probe.

Phase 3 also produces a cost estimate at B and verifies that the Phase 1A cron fix holds under a 1,000-sub backlog.

## 2. Decisions already locked

| Decision | Value | Source |
|---|---|---|
| Launch targets | A = 1,000 registered; B = 1,000 DAU | Owner, 2026-10-26 |
| C | Stress target only; not a launch gate | Owner, 2026-10-26 |
| Plan | Free today; Paid required before Phase 3 | Owner + audit |
| Busiest period | Morning; traffic is low after 12:00 | Owner |
| Cron delay | Tolerable; no hard 15-minute guarantee | Owner |
| Subscription adoption | No real data; synthetic mix only | Owner |
| Production | Read-only until a separate gate | Standing rule |

## 3. Why this is not one blended run

The audit's load model uses a 20% write share and a 5% auth share. A single blended run cannot measure those cleanly on staging:

1. **Login is rate-limited at 100/hr per IP.** The benchmark exits from one source IP, and Cloudflare sets `CF-Connecting-IP`; it cannot be spoofed. At B, if the 5% auth share were login, it would be ~1,000 logins/hr and would measure `429 RATE_LIMITED`, not login capacity.
2. **Cron is bounded to 60 due subs per tick.** A 1,000-sub cohort is drained across ticks by design (Phase 1A). One synthetic "1,000-sub tick" would require a staging-only code override and would not represent production.
3. **D1 serializes writes.** Mixing sustained writes into a read run makes a p99 regression ambiguous: it could be the read path or the single writer.
4. **Admin metrics are cached for 60 s.** A 5% admin share would mostly measure cache hits, not aggregates.

Therefore Phase 3 uses **separate probes** for reads, writes, login, cron, and soak. Each probe has its own SLO and its own evidence. The A/B verdict combines them.

## 4. Profiles

### 4.1 Run A — registered-user scale

| Item | Value |
|---|---|
| Concurrent users | 50 |
| Average arrival rate | 2.78 rps |
| Burst arrival rate | 6.94 rps (2.5×) |
| Duration | 30 min |
| Mix | 15% public / 70% authed / 5% session / 5% vendor / 5% admin (§4.3) |
| Target | `water-staging` + `shodasha-staging` |

Timeline (30 min):

| Phase | Duration | Rate | Counted in SLO |
|---|---:|---|---|
| Warm-up | 2 min | 25% of average (0.70 rps) | No |
| Steady | 10 min | 2.78 rps | Yes |
| Burst | 5 min | 6.94 rps | Yes |
| Recovery | 10 min | 2.78 rps | Yes |
| Ramp-down | 3 min | linear to 0 | No |

Expected counted requests: ~5,400.

### 4.2 Run B — DAU scale

| Item | Value |
|---|---|
| Concurrent users | 100 |
| Average arrival rate | 5.56 rps |
| Burst arrival rate | 13.89 rps (2.5×) |
| Duration | 30 min |
| Mix | 15% public / 70% authed / 5% session / 5% vendor / 5% admin (§4.3) |
| Target | `water-staging` + `shodasha-staging` |

Same timeline as A. Expected counted requests: ~10,800.

### 4.3 Read/auth mix

| Class | Share | Endpoints |
|---|---:|---|
| Public reads | 15% | `GET /v1/catalog`, `GET /v1/windows?date=today` |
| Authed reads | 70% | `GET /v1/orders?limit=50`, `GET /v1/orders/{id}`, `GET /v1/subscriptions`, `GET /v1/ledger/me`, `GET /v1/billing/dues` |
| Session | 5% | `GET /v1/auth/me` |
| Vendor | 5% | `GET /v1/vendor/routes/today?date=...` |
| Admin | 5% | `GET /v1/admin/metrics`, `GET /v1/admin/metrics/overview` |

Notes:

- The audit's 20% write share is measured separately. In the read run those requests are replaced by authed reads, so the read path is stressed conservatively; vendor and admin stay at the audit's 5% each.
- `POST /auth/refresh` is excluded from the sustained mix because it rotates the session token; a shared token would produce 401s. Login is covered by the separate probe; refresh is covered by existing auth tests.
- Admin metrics hits are mostly 60 s cache hits; the first request per isolate per key pays the aggregate pass. Report hit/miss counts separately.
- Vendor route uses a fixed 41-stop route and rotates among the 20 seeded vendors to avoid one hot token.
- Every request carries a unique `X-Trace-Id`; the harness sends `Cache-Control: no-cache` so a future zone cache cannot hide app work.

### 4.4 Write probe

| Item | Value |
|---|---|
| Duration | 10 min |
| Rate | 1.11 write requests/s (B's modeled 20% of 5.56 rps) |
| Write mix | 0.37 create/s, 0.37 cancel/s, 0.37 reschedule/s |
| Endpoints | `POST /v1/quotes` (pre-create only), `POST /v1/orders` (COD), `POST /v1/orders/{id}/cancel`, `POST /v1/orders/{id}/reschedule` |
| Excluded | UPI intent, webhook, dues intent, subscription intent, any provider call |
| Idempotency | One key per logical write; same key on retry; never reuse across payloads |
| Pool | Probe-owned orders only; no real users and no seeded read orders mutated |

A create is quote + order; the quote is counted as an authed read, not a write. Cancel/reschedule use only the probe's own pool, never the seeded Phase 0 orders, and no order is reused after a terminal state. The probe runs as a separate window, never concurrently with the read runs. A write failure that returns a 4xx state conflict is recorded separately from a 5xx; only 5xx counts against the write SLO.

### 4.5 Login probe

| Item | Value |
|---|---|
| Requests | 90 logins over 10 min (9/min) |
| Source | One staging IP, below the 100/hr ceiling |
| Credentials | 90 dedicated synthetic users with known passwords |
| Measure | p50/p95/p99, 5xx, D1 queries, CPU |

The Phase 0 seed leaves `users.password_hash` empty, so the seeded tokens cannot log in. Prepare 90 dedicated synthetic users with PBKDF2 hashes (100k iterations, same as the Worker) and keep their credentials in a temp file outside the repo. Never commit or print them.

This is a latency/CPU probe, not a throughput probe. The per-phone 5/15 min and per-IP 100/hr limits are not changed for the benchmark.

### 4.6 Cron probe

| Cohort | What is measured |
|---|---|
| 60 due subs (one page) | statements, CPU, wall time, created/failed, `next_run` correctness |
| 500 due subs | per-tick 60, backlog reported, drain over consecutive ticks, zero missed |
| 1,000 due subs | same; drain time recorded against the owner's tolerance |

Rules:

- Staging cron stays **off** except during the cron window.
- The cohort is synthetic and isolated by a run prefix.
- The cohort must be active, funded, and non-Sunday so it actually generates; verify `processed` reaches the 60-row page. Low-balance and pending-payment subs are reported separately and do not count as processed.
- The gate is **zero missed due deliveries** and per-tick CPU/statements under the caps; a 1,000-sub single-tick run is not required and is not representative of the Phase 1A design.
- The cron window is followed immediately by `crons: []` and a deploy, then a backlog check.

### 4.7 Soak

| Item | Value |
|---|---|
| Profile | B average, 5.56 rps |
| Duration | 30 min |
| Mix | Same read/auth mix |
| Measure | p99 drift, 5xx drift, D1 latency, rate-limit counters, isolate recycling |

The audit proposed a 2-hour soak. This spec uses the owner-requested 30-minute soak as the gate; a 2-hour run is optional and is not required for GO. Workers isolates recycle, so a 30-minute soak is a stability check, not a memory-leak proof.

### 4.8 C stress probe (optional)

| Item | Value |
|---|---|
| Concurrent users | 1,000 |
| Duration | 60 min |
| Purpose | Find the knee; record the failure mode |
| Gate | None; not a launch target |

C requires `--allow-stress` and explicit owner approval for that run. It does not authorize Phase 4 architecture work. The Python thread harness is expected to handle A/B; C may need k6 or an async client so client-side thread exhaustion is not mistaken for a server limit.

## 5. SLOs and headroom

Gate values apply a 20% headroom to the audit's proposed SLOs. A measured value must be **at or below** the gate.

| Surface | Metric | SLO | Gate (80%) |
|---|---|---|---|
| Public reads | p50 / p95 / p99 | 80 / 250 / 600 ms | 64 / 200 / 480 ms |
| Authed reads | p50 / p95 / p99 | 150 / 500 / 1,200 ms | 120 / 400 / 960 ms |
| Writes | p50 / p95 / p99 | 300 / 900 / 2,000 ms | 240 / 720 / 1,600 ms |
| Login | p50 / p95 / p99 | 400 / 1,000 / 2,000 ms | 320 / 800 / 1,600 ms |
| 5xx | all runs | < 0.5% | < 0.5% (absolute) |
| Non-auth 4xx | all runs | < 2% | < 2% (absolute) |
| Worker CPU | p95 / p99 per request | 50 / 150 ms | 40 / 120 ms |
| D1 queries | p95 / p99 per request | 10 / 25 | 8 / 20 |
| D1 rows read | p95 / p99 per request | 200 / 1,000 | 160 / 800 |
| D1 rows written | p95 / p99 per request | 5 / 20 | 4 / 16 |
| Cron | statements / CPU / missed | < 1,000 / < 30 s / 0 | < 800 / < 24 s / 0 |
| Availability | monthly 99.9% | not certifiable in a 30-min run | report as not measured |

Additional rules:

- Percentiles are computed per route class and overall. A single route over the gate fails that class.
- A 4xx caused by a deliberate state conflict in the write probe is expected and excluded from the non-auth 4xx rate; it is reported separately.
- `429 RATE_LIMITED` in a read run is a failure of the run design, not a capacity result; abort and fix the harness.
- Worker CPU is read from the Cloudflare dashboard for the run window. If the dashboard cannot produce p95, record p99 and mark p95 as not captured; do not substitute local CPU.
- If Cloudflare cannot separate cron CPU from HTTP CPU, record wall time and mark the cron CPU gate **not certified**. Do not claim a cron GO on the CPU portion without a measurement.

## 6. GO/NO-GO

### A verdict

GO only if:

1. Every A SLO gate passes.
2. 5xx < 0.5% and no `1102`/`1101` spike.
3. No P0 concurrency regression (Phase 1A suites remain green before and after).
4. Login probe passes.
5. Cron probe has zero missed due deliveries and per-tick caps pass.

### B verdict

GO only if A is GO and every B SLO gate passes, including the 30-minute soak. B is not certified by extrapolating from A.

### NO-GO triggers

- Any SLO gate miss that is not explained by a harness defect.
- 5xx > 0.5%, or abort threshold crossed (`5xx > 2%`, overall p99 > 5 s).
- A `1102`/`1101` pattern on a Paid staging Worker.
- Any missed due delivery or wrong `next_run`.
- A P0 concurrency test failure.
- D1 errors, `7500` quota errors, or a write probe that mutates real provider state.

A NO-GO report must name the failing route, the measured value, the gate, and the smallest remediation. Re-run only after the fix.

### Report contents

- Run ID, UTC start/end, commit SHA, Worker version, D1 migration count.
- Paid-plan confirmation.
- Per-run and per-route tables with p50/p95/p99, 5xx, 4xx, D1 queries/roundtrips/rows, CPU, bytes.
- Cron table: cohort, due, created, failed, missed, statements, CPU, wall, backlog.
- Cost estimate at B with assumptions.
- Explicit statement of what was **not** measured: real subscription adoption, production traffic, CDN cache behavior, monthly availability, Flutter device performance.
- Owner signature and date.

## 7. Cost estimate method

At B: 1,000 DAU x 20 requests x 30 days = **600,000 requests/month**.

From the run, take:

- Average Worker CPU ms/request (not p95) x 600,000 = CPU-ms/month.
- Average D1 rows read/request x 600,000 = rows read/month.
- Average D1 rows written/request x 600,000 = rows written/month.
- Average D1 queries/request x 600,000 = queries/month.

Compare to the current Workers Paid and D1 Paid inclusions, and report overage at the measured average and at the p95 CPU sensitivity. Label all prices as "current published rates on the run date"; do not hardcode a monthly bill as a promise.

A is reported as a sensitivity: 1,000 registered with 5% active (50 DAU-equivalent) and with 100% active. The audit's ~20,000 requests/day for all 1,000 active is the upper bound.

## 8. Prerequisites

1. **Workers Paid** on the account (the plan applies to `water-staging`). Without it, Phase 3 does not start.
2. Staging Worker deployed at the Phase 1A/1B/2 code; D1 at migration **029**; `crons: []`.
3. Seeded data: 1,021 users, 10,000 orders, 20 vendors, 40+ stops/vendor. `data/phase0_tokens.json` present and never printed or committed.
4. **90 dedicated login users with known passwords.** The Phase 0 seed has an empty `password_hash`; prepare them with a staging-only script using `app.core.passwords.hash_password`, and store the credentials in a temp file outside the repo.
5. A probe-owned cancellable order pool (created by the write setup, not seeded read orders) and a synthetic due-sub cohort for the cron probe.
6. `OBS_LOG_SAMPLE_RATE=1` for the run window; restore `0.1` after.
7. Tail output written outside the repo (it contains headers/IPs); only sanitized summaries are committed.
8. Harness capable of: constant-arrival-rate phases, per-route percentiles, unique trace IDs, staging-only target guard, `--allow-writes` guard, and a result file in `Feature_docs/performance/results/`.
9. A D1 backup or bookmark before the write/cron probes; staging only.
10. No production host in any command. The harness refuses any host that is not loopback or does not contain `staging`.

## 9. Harness decision

The existing `workers/api/scripts/bench_phase0.py` is GET-only and uses fixed-duration, fixed-rps profiles. Phase 3 needs phases and writes.

**Recommended:** extend `bench_phase0.py` with:

- `phase3-a` / `phase3-b` profiles that read a phase timeline (warm-up, steady, burst, recovery, ramp-down), plus `login`, `write`, `phase3-soak`, and `phase3-c` profiles.
- A `--allow-writes` flag that is refused unless the target is staging and `APP_ENV=staging` is confirmed.
- A write scenario module with idempotency keys and a cancellable pool.
- A staging-only login-credential prep script (separate from the load harness) that inserts 90 synthetic users with PBKDF2 hashes and writes a temp credentials file.
- Per-route p50/p95/p99 and a JSON/Markdown result writer (reuse the existing writer).
- A hard refusal of `/v1/payments/*`, `/v1/webhooks/*`, and any provider path in write mode.

**Rejected:** a separate `bench_phase3.py` that duplicates the scheduler, result writer, and target guard. Duplication is the larger risk.

This is a code change and requires a separate approval after this spec is approved. No harness code is written yet.

## 10. Sequence and effort

| Step | Effort |
|---|---|
| Approve spec + Paid upgrade | owner |
| Extend harness + unit tests | 1 day |
| Login credential prep + pre-flight + pool prep + smoke | 1 day |
| Run A + B + write + login | 1 day |
| Cron probe + soak | 0.5 day |
| Analysis, cost estimate, report | 0.5 day |
| **Total** | **~4 days after Paid** |

C, if approved, adds 1 day plus analysis.

## 11. Risks and limitations

- **Free-plan blocker:** the current staging Worker cannot run this plan. Paid would be a hard prerequisite, but the owner rejected it; Phase 3P is skipped (ADR-148).
- **Staging is not production:** single region, synthetic data, no real provider latency. Results certify the code and the modeled load, not a monthly availability number.
- **Synthetic adoption:** the 60/20/20 billing mix is an assumption. The report must say so; a real adoption shift can change cron and write load.
- **D1 single writer:** write p99 is sensitive to concurrent money paths. The write probe is separate for that reason.
- **Cron drain time:** 1,000 due subs at 60/tick is ~17 ticks (~4.25 hours). This is within the owner's "delay tolerable" decision but must be stated in the report.
- **Log volume:** `OBS_LOG_SAMPLE_RATE=1` on a 10k-request run produces a large tail. Capture to a temp file, parse, delete the raw file.
- **Cache:** `workers.dev` has no zone cache; `CDN-Cache-Control` is inert today. Do not claim CDN offload from this run.
- **Flutter:** the API load run does not certify cold start, frames, or device memory. A separate device smoke is required before launch.

## 12. Approval checklist

- [ ] Workers Paid approved for the account (applies to staging) — **rejected by the owner 2026-10-26 (ADR-148)**.
- [x] This spec approved (profiles, gates, separate probes) — **2026-10-26**.
- [x] Harness extension approved (code change) — **2026-10-26, implemented and guard-tested**.
- [x] Login credential prep executed (90 synthetic users, temp credentials file) — **2026-10-26; probe aborted, credentials deleted**.
- [ ] Write probe endpoints approved (COD/cancel/reschedule only) — **not applicable; Phase 3P skipped**.
- [ ] Cron window approved (staging cron on temporarily, then off) — **not applicable; Phase 3P skipped**.
- [ ] 30-minute soak accepted; 2-hour soak optional — **not applicable; Phase 3P skipped**.
- [ ] Cost-estimate assumptions accepted — **not applicable; no estimate produced**.

**Phase 3P is skipped (ADR-148).** This checklist is retained as a record; no further box will be checked on Free. Production remains read-only.

## 13. Free-tier path (owner decision, 2026-10-26)

The owner will stay on Workers Free for the initial phase. Paid is deferred, not rejected. The 1,000-DAU targets remain the launch goal, but they cannot be certified on Free.

### 13.1 Phase 3F — Free-tier validation (now)

| Item | Scope |
|---|---|
| Harness | Phase 3 read mix at A/B on the **local** seeded server, compressed timeline |
| Write probe | Local disposable DB only; COD create/cancel/reschedule |
| Staging | Correctness smoke only (one pass, low rate); no A/B/C load, no login burst, no cron window |
| Production | Read-only health/smoke; no load, writes, migration, or deploy |
| Certifies | Route correctness, query counts, local throughput shape, write idempotency |
| Does not certify | Workers CPU, 1,000 DAU, login burst, 60-sub cron, D1 production latency |

**Local evidence (2026-10-26, compressed timeline 0.02, SQLite, seeded at migration 029):**

| Run | Counted / all requests | Errors / 5xx | p99 | Achieved rps | Result |
|---|---:|---:|---:|---:|---|
| `phase3-a` | 108 / 115 | 0 / 0 | 64.5 ms | 3.60 | pass |
| `phase3-b` | 217 / 230 | 0 / 0 | 24.2 ms | 7.23 | pass |
| `write` (10 s, 0.5 rps, pool 5) | 7 | 0 / 0 | 41.1 ms | 0.70 | pass |

The write probe completed 2 quotes, 2 creates (201), 2 cancels (200), and 1 reschedule (200) against probe-owned COD orders. Results: `results/phase3-phase3-a-20261026T080609Z.{json,md}`, `results/phase3-phase3-b-20261026T080658Z.{json,md}`, `results/phase3-write-20261026T080931Z.{json,md}`.

A first write attempt on the stale `data/phase0_local.db` (migration 028) returned two cancel `500`s (`no such column: mutation_token`). That run was discarded; the passing run used a fresh disposable DB seeded at migration 029. Always reseed before the write probe.

These are local SQLite numbers. They validate route wiring, the Phase 3 read mix, and write idempotency; they are **not** Workers CPU, D1 latency, or 1,000-user capacity evidence.

### 13.2 Free envelope

| Limit | Free value | Consequence |
|---|---|---|
| Worker CPU | 10 ms/request | PBKDF2 login can exceed it; heavy routes can `1102` |
| D1 queries | 50/invocation | Cron is safe only for roughly 4–5 due subs/tick |
| Requests | 100k/day | Fine for the initial low-traffic phase |
| D1 rows written | 100k/day | Fine for the initial low-traffic phase |
| Load tests | Not valid on Free | Sustained staging load produces `1102`/`1101`, not capacity data |

The initial phase is low-traffic (production currently has 9 users; traffic is low after 12:00). Monitor CPU, D1 queries, and cron due counts. **Phase 3P is skipped on Free (ADR-148); do not move to 3P without a new paid decision.**

### 13.3 Phase 3P — Paid validation (skipped 2026-10-26)

**Skipped, not deferred.** The original A/B/C plan in §4–§7 applies only if the owner later approves Workers Paid in a new ADR. No 3P run will be executed on Free, and Phase 3F evidence is not a substitute for 3P. It must not be reported as 1,000-user certification.

### 13.4 Login probe attempt and stop (2026-10-26)

The owner rejected Paid after the Free pilot closed. Before that decision, the login probe was attempted against staging with 90 dedicated synthetic users:

| Metric | Result |
|---|---|
| Requests | 20 (0.158 rps achieved, concurrency 1) |
| Statuses | 3×200, 7×409, 3×503, 7×500 |
| 5xx | 10 / 20 (**50%**) — abort threshold 2% |
| p50 / p95 / p99 | 502.6 / 1,611.84 / **3,381.81 ms** |
| Outcome | **fail, aborted at 126.879 s** |

- The 503s were Cloudflare `exceededCpu` at the **10 ms** Free ceiling; the 500s were `ErrnoError`.
- The 409s were a harness bug: all logins shared one device ID and hit the per-device cap. `bench_phase0.py` now issues one device per credential, with a regression test. The 409s are not capacity evidence.
- A single diagnostic login with a fresh device returned 200 (4,204.3 ms), so the route works; it does not fit the CPU budget.
- Independent G3 evidence: 6/6 HTTP 200 with auth CPU p99 **1,269.746 ms** against a ≤8 ms gate.

Result files: `results/phase3-login-20261026T112345Z.{json,md}` (1-request smoke, 200) and `results/phase3-login-20261026T112505Z.{json,md}` (aborted probe). The full stop record is `results/phase3p-skipped-2026-10-26.md`. No cost estimate is produced.
