# Phase 0 benchmark - profile b

- **Label:** staging-b-free-ceiling
- **Result:** fail
- **Started (UTC):** 2026-10-25T09:18:32Z
- **Finished (UTC):** 2026-10-25T09:18:43Z
- **Base URL:** `https://water-staging.adityathakur452007.workers.dev`
- **Duration:** 5.899 s (target 600.0 s, warmup 5.0 s)
- **Target rate:** 5.56 rps, concurrency 40
- **Requests:** 24 (4.068 rps achieved)
- **Errors:** 4 (16.67%)
- **5xx:** 4 (16.67%)
- **Network errors:** 0
- **Retries:** 0
- **Schedule resets:** 0

> **ABORTED:** 5xx rate 20.00% > 2.00%

| Route | Count | 5xx | p50 (ms) | p95 (ms) | p99 (ms) |
|---|---:|---:|---:|---:|---:|
| health | 2 | 0 | 148.4 | 645.9 | 645.9 |
| catalog | 4 | 1 | 181.4 | 653.6 | 653.6 |
| me | 4 | 1 | 481.9 | 1473.0 | 1473.0 |
| orders | 4 | 0 | 249.5 | 1051.4 | 1051.4 |
| order_detail | 4 | 0 | 466.1 | 1410.2 | 1410.2 |
| dues | 4 | 1 | 598.2 | 719.7 | 719.7 |
| vendor_route | 2 | 1 | 478.0 | 2803.9 | 2803.9 |
| **Total** | 24 | 4 | 598.2 | 1473.0 | 2803.9 |
