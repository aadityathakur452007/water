# Phase 0 benchmark - profile b

- **Label:** local-b-1
- **Result:** pass
- **Started (UTC):** 2026-10-25T09:28:37Z
- **Finished (UTC):** 2026-10-25T09:38:42Z
- **Base URL:** `http://127.0.0.1:8787`
- **Duration:** 600.009 s (target 600.0 s, warmup 5.0 s)
- **Target rate:** 5.56 rps, concurrency 40
- **Requests:** 3336 (5.56 rps achieved)
- **Errors:** 0 (0.00%)
- **5xx:** 0 (0.00%)
- **Network errors:** 0
- **Retries:** 3324
- **Schedule resets:** 0

| Route | Count | 5xx | p50 (ms) | p95 (ms) | p99 (ms) |
|---|---:|---:|---:|---:|---:|
| health | 167 | 0 | 5.6 | 21.9 | 27.0 |
| catalog | 501 | 0 | 4.3 | 19.2 | 27.1 |
| me | 501 | 0 | 10.6 | 27.5 | 32.2 |
| orders | 667 | 0 | 6.5 | 23.4 | 30.0 |
| order_detail | 667 | 0 | 7.1 | 22.9 | 25.7 |
| dues | 500 | 0 | 12.1 | 30.5 | 33.9 |
| vendor_route | 333 | 0 | 16.2 | 32.8 | 37.2 |
| **Total** | 3336 | 0 | 9.8 | 25.8 | 32.8 |
