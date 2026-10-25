# Phase 0 benchmark - profile smoke

- **Label:** local-smoke-1
- **Result:** pass
- **Started (UTC):** 2026-10-25T09:17:59Z
- **Finished (UTC):** 2026-10-25T09:17:59Z
- **Base URL:** `http://127.0.0.1:8787`
- **Duration:** 0.050 s (target 0.0 s, warmup 0.0 s)
- **Target rate:** 1.0 rps, concurrency 1
- **Requests:** 7 (139.008 rps achieved)
- **Errors:** 0 (0.00%)
- **5xx:** 0 (0.00%)
- **Network errors:** 0
- **Retries:** 0
- **Schedule resets:** 0

| Route | Count | 5xx | p50 (ms) | p95 (ms) | p99 (ms) |
|---|---:|---:|---:|---:|---:|
| health | 1 | 0 | 7.0 | 7.0 | 7.0 |
| catalog | 1 | 0 | 2.0 | 2.0 | 2.0 |
| me | 1 | 0 | 8.2 | 8.2 | 8.2 |
| orders | 1 | 0 | 5.4 | 5.4 | 5.4 |
| order_detail | 1 | 0 | 5.0 | 5.0 | 5.0 |
| dues | 1 | 0 | 9.8 | 9.8 | 9.8 |
| vendor_route | 1 | 0 | 13.0 | 13.0 | 13.0 |
| **Total** | 7 | 0 | 7.0 | 13.0 | 13.0 |
