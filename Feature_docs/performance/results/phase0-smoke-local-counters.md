# Phase 0 benchmark - profile smoke

- **Label:** local-counters
- **Result:** pass
- **Started (UTC):** 2026-10-25T09:19:12Z
- **Finished (UTC):** 2026-10-25T09:19:12Z
- **Base URL:** `http://127.0.0.1:8788`
- **Duration:** 0.062 s (target 0.0 s, warmup 0.0 s)
- **Target rate:** 1.0 rps, concurrency 1
- **Requests:** 7 (113.286 rps achieved)
- **Errors:** 0 (0.00%)
- **5xx:** 0 (0.00%)
- **Network errors:** 0
- **Retries:** 0
- **Schedule resets:** 0

| Route | Count | 5xx | p50 (ms) | p95 (ms) | p99 (ms) |
|---|---:|---:|---:|---:|---:|
| health | 1 | 0 | 15.7 | 15.7 | 15.7 |
| catalog | 1 | 0 | 4.2 | 4.2 | 4.2 |
| me | 1 | 0 | 8.3 | 8.3 | 8.3 |
| orders | 1 | 0 | 5.9 | 5.9 | 5.9 |
| order_detail | 1 | 0 | 5.1 | 5.1 | 5.1 |
| dues | 1 | 0 | 9.3 | 9.3 | 9.3 |
| vendor_route | 1 | 0 | 13.2 | 13.2 | 13.2 |
| **Total** | 7 | 0 | 8.3 | 15.7 | 15.7 |
