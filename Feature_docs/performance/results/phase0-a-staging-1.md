# Phase 0 benchmark - profile a

- **Label:** staging-a-free-ceiling
- **Result:** fail
- **Started (UTC):** 2026-10-25T09:18:14Z
- **Finished (UTC):** 2026-10-25T09:18:27Z
- **Base URL:** `https://water-staging.adityathakur452007.workers.dev`
- **Duration:** 7.838 s (target 600.0 s, warmup 5.0 s)
- **Target rate:** 2.78 rps, concurrency 20
- **Requests:** 22 (2.807 rps achieved)
- **Errors:** 6 (27.27%)
- **5xx:** 6 (27.27%)
- **Network errors:** 0
- **Retries:** 0
- **Schedule resets:** 0

> **ABORTED:** 5xx rate 28.57% > 2.00%

| Route | Count | 5xx | p50 (ms) | p95 (ms) | p99 (ms) |
|---|---:|---:|---:|---:|---:|
| health | 1 | 0 | 203.3 | 203.3 | 203.3 |
| catalog | 4 | 1 | 241.2 | 418.4 | 418.4 |
| me | 3 | 0 | 397.2 | 544.9 | 544.9 |
| orders | 4 | 0 | 961.6 | 1202.8 | 1202.8 |
| order_detail | 4 | 2 | 271.8 | 830.3 | 830.3 |
| dues | 3 | 1 | 660.5 | 847.3 | 847.3 |
| vendor_route | 3 | 2 | 1945.1 | 3263.9 | 3263.9 |
| **Total** | 22 | 6 | 397.2 | 1945.1 | 3263.9 |
