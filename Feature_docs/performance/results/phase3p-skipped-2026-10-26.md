# Phase 3P — skipped on Workers Free (2026-10-26)

**Decision:** **skipped, not deferred** (ADR-148). The owner rejected Workers Paid and directed the project to stay on Workers Free; any phase that requires Paid is skipped.

**Scope not run:** A/B read profiles, write probe, login burst, cron window, 30-minute soak, and cost estimate. No 1,000-user A/B certification is claimed.

**Production:** read-only and untouched in this phase. `water` remains on version `511879dc-60d4-48a2-aca9-7ae44a734f8a`; migration 029 remains because it is additive.

## 1. Why Phase 3P was stopped

The Free plan caps Worker CPU at **10 ms per request**. The login path uses PBKDF2-HMAC-SHA256 at 100,000 iterations, which cannot fit that budget. Earlier Free-pilot gates had already failed for the same reason:

| Gate | Result |
|---|---|
| G2 production `/health` | 18×200, 1×503 `exceededResources`/1102, 1×500 in 20 probes; production rolled back |
| G3 staging auth | 6/6 HTTP 200 but CPU p99 **1,269.746 ms** against a ≤8 ms gate |
| G4 staging cron | 3-due tick used **46** D1 roundtrips against a ≤45 threshold (zero missed, no 1102) |

The login probe was the last attempt to find a Free-safe path. It aborted.

## 2. What ran

All runs targeted `water-staging` only. No production request was made.

| Run | UTC | Result |
|---|---|---|
| 7-route staging smoke | 11:23:31Z | 7 requests, 0 errors, 0 5xx; `/health` 3,425.8 ms cold, other routes 224.8–460.1 ms |
| 1-request login smoke | 11:23:45Z | 1×200, 4,204.3 ms |
| Login probe | 11:25:05Z | **aborted** at 20 requests |

Login probe detail:

| Metric | Value |
|---|---|
| Requests | 20 (0.158 rps achieved, concurrency 1) |
| Statuses | 3×200, 7×409, 3×503, 7×500 |
| 5xx | 10 / 20 (**50%**) |
| p50 / p95 / p99 | 502.6 / 1,611.84 / **3,381.81 ms** |
| Duration | 126.879 s (target 600 s) |
| Abort reason | 5xx rate 50.00% > 2.00% |

Files: `phase0-smoke-20261026T112331Z.{json,md}`, `phase3-login-20261026T112345Z.{json,md}`, `phase3-login-20261026T112505Z.{json,md}`.

## 3. Diagnosis

- **7×409 were a harness bug, not capacity.** Every login used the same device ID and hit the per-device session cap. `bench_phase0.py` now issues one stable device per credential (`phase3-login-<run>-<index>`), with a regression test in `tests/test_bench_guard.py`. The 409s are excluded from the capacity conclusion.
- **3×503 were Cloudflare `exceededCpu` at the 10 ms ceiling.** The tail showed the CPU kill; the raw tail was deleted.
- **7×500 were `ErrnoError`** from the Python runtime under the same CPU pressure.
- **A single diagnostic login with a fresh device returned 200** (4,204.3 ms). The route works; it does not fit the CPU budget.
- **Independent G3 evidence:** 6/6 HTTP 200 with auth CPU p99 **1,269.746 ms** against a ≤8 ms gate.

The 10 ms ceiling is the blocker. A clean per-credential run would remove the 409s but cannot remove the `exceededCpu` failures or the ~1.27 s auth CPU cost.

## 4. What is not claimed

- No 1,000-user A/B/C certification.
- No measured throughput or latency at A or B.
- No cost estimate at B (not produced; the plan is Free).
- No production capacity, availability, or cron claim.
- Phase 3F local results remain valid only for route wiring, read mix, and write idempotency on SQLite.

## 5. Staging state and cleanup

| Item | State |
|---|---|
| Worker version | `6242eebe-36af-46ca-9f28-e25dfbc34e3b` |
| `OBS_LOG_SAMPLE_RATE` | `0.1` (restored) |
| Cron | `crons: []`, 0 schedules |
| `/health` | 200 `{"status":"ok"}` |
| D1 `shodasha-staging` | 1,112 users (91 with a password), 10,009 orders, 1,000 subscriptions, 801 stops, 20 vendors, 14,454,784 bytes |
| Leftover synthetic users | 90 `load3-login-p3p112156-*`; credentials deleted, so they cannot log in without regeneration |
| Pre-run backup | 16,833,630 bytes, SHA256 `21C8E360D79CB707B422F62F42FD3AEE75C54F04E1DD9C044D231E0ED86C7DAF`, retained outside the repo |
| Time Travel bookmark | `00000019-00000000-00005110-ceb5f523d85a8b84af3d5cbacd3cea60` |

Temporary credentials, login SQL, raw tails, and tail PID files were deleted. No token, password, phone, header, or IP is recorded here.

## 6. Follow-up

The owner chooses the next **Free-only** workstream: product/UI, reliability within the 10 ms envelope, or release readiness. No load test, write probe, cron window, or paid profile will run. If Workers Paid is ever reconsidered, it needs a new ADR and fresh explicit approval; this report does not authorize it.
