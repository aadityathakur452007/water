# Phase 0 benchmark - profile c

- **Label:** staging-c-knee
- **Result:** fail
- **Started (UTC):** 2026-10-25T09:18:48Z
- **Finished (UTC):** 2026-10-25T09:18:59Z
- **Base URL:** `https://water-staging.adityathakur452007.workers.dev`
- **Duration:** 6.395 s (target 300.0 s, warmup 5.0 s)
- **Target rate:** 55.6 rps, concurrency 200
- **Requests:** 45 (7.036 rps achieved)
- **Errors:** 25 (55.56%)
- **5xx:** 25 (55.56%)
- **Network errors:** 0
- **Retries:** 0
- **Schedule resets:** 0

> **ABORTED:** 5xx rate 88.00% > 2.00%

| Route | Count | 5xx | p50 (ms) | p95 (ms) | p99 (ms) |
|---|---:|---:|---:|---:|---:|
| health | 2 | 1 | 144.2 | 283.3 | 283.3 |
| catalog | 8 | 5 | 218.4 | 2651.9 | 2651.9 |
| me | 7 | 3 | 315.0 | 1339.9 | 1339.9 |
| orders | 9 | 7 | 164.8 | 772.9 | 772.9 |
| order_detail | 6 | 5 | 137.0 | 1177.1 | 1177.1 |
| dues | 7 | 2 | 603.4 | 1925.6 | 1925.6 |
| vendor_route | 6 | 2 | 1711.1 | 5876.6 | 5876.6 |
| **Total** | 45 | 25 | 218.4 | 2105.1 | 5876.6 |

## Notes

- profile c is a stress profile; results find the knee, not a launch gate
