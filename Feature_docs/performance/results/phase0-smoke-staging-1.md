# Phase 0 benchmark - profile smoke

- **Label:** staging-smoke-1
- **Result:** fail
- **Started (UTC):** 2026-10-25T09:13:53Z
- **Finished (UTC):** 2026-10-25T09:13:59Z
- **Base URL:** `https://water-staging.adityathakur452007.workers.dev`
- **Duration:** 5.986 s (target 0.0 s, warmup 0.0 s)
- **Target rate:** 1.0 rps, concurrency 1
- **Requests:** 7 (1.169 rps achieved)
- **Errors:** 3 (42.86%)
- **5xx:** 3 (42.86%)
- **Network errors:** 0
- **Retries:** 0
- **Schedule resets:** 0

> **FAILED:** smoke: 3 of 7 requests failed (non-2xx or transport error)

| Route | Count | 5xx | p50 (ms) | p95 (ms) | p99 (ms) |
|---|---:|---:|---:|---:|---:|
| health | 1 | 1 | 4279.0 | 4279.0 | 4279.0 |
| catalog | 1 | 0 | 270.3 | 270.3 | 270.3 |
| me | 1 | 0 | 445.6 | 445.6 | 445.6 |
| orders | 1 | 0 | 239.0 | 239.0 | 239.0 |
| order_detail | 1 | 0 | 433.5 | 433.5 | 433.5 |
| dues | 1 | 1 | 191.5 | 191.5 | 191.5 |
| vendor_route | 1 | 1 | 126.9 | 126.9 | 126.9 |
| **Total** | 7 | 3 | 270.3 | 4279.0 | 4279.0 |
