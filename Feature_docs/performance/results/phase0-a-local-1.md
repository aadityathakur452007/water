# Phase 0 benchmark - profile a

- **Label:** local-a-1
- **Result:** pass
- **Started (UTC):** 2026-10-25T09:18:11Z
- **Finished (UTC):** 2026-10-25T09:28:16Z
- **Base URL:** `http://127.0.0.1:8787`
- **Duration:** 600.007 s (target 600.0 s, warmup 5.0 s)
- **Target rate:** 2.78 rps, concurrency 20
- **Requests:** 1668 (2.78 rps achieved)
- **Errors:** 0 (0.00%)
- **5xx:** 0 (0.00%)
- **Network errors:** 0
- **Retries:** 1662
- **Schedule resets:** 0

| Route | Count | 5xx | p50 (ms) | p95 (ms) | p99 (ms) |
|---|---:|---:|---:|---:|---:|
| health | 83 | 0 | 5.8 | 23.7 | 27.2 |
| catalog | 250 | 0 | 4.5 | 22.1 | 24.5 |
| me | 250 | 0 | 11.6 | 29.9 | 34.1 |
| orders | 334 | 0 | 7.7 | 24.7 | 30.3 |
| order_detail | 334 | 0 | 8.1 | 25.1 | 29.2 |
| dues | 250 | 0 | 13.2 | 31.9 | 37.3 |
| vendor_route | 167 | 0 | 17.5 | 33.2 | 37.6 |
| **Total** | 1668 | 0 | 11.4 | 29.0 | 34.8 |
