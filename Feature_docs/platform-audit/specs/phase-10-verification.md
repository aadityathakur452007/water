# Phase 10 — Final verification (tests, builds, security, size, report)

- **Goal**: every claim in report §13 filled with After+Evidence; no FIXED without proof (§33).
- **Workstream**: W10 verification (runs after all phases; owns no source — writes tests only where gaps found, else records).

## 10.1 Test matrix (close §31 gaps)

| Gap (Track F §7) | bar |
|---|---|
| Concurrency double-apply (triple/cash same-key parallel) | new test, D1 semantics noted |
| D1 torn-write window | harness or documented window per money path |
| sync_batch 200-row scale + partial ordering | new test |
| 200-row admin pages + cursor round-trips | new tests |
| Absolute-cap time-travel (31d old → 401, family intact) | new test |
| Device flows (staff-number 422 → wipe → guest intact) | integration test |
| Offline outbox replay vs changed server state | new test |
| Rate-limit cross-isolate | known-weak until Phase 8 D1 counters, then test |
| Webhook unsigned-reject + PoD computability | router-level tests |

## 10.2 Build + measure

- [ ] pytest + both `flutter test` + both `flutter analyze` green (paste counts)
- [ ] Admin `npm run build` green (user runs; paste bundle notes)
- [ ] Release APKs rebuilt + re-measured (fill Before→After vs §2 baselines 26.05/18.13 MB)
- [ ] Flutter startup/cold-start spot check on device (UNVERIFIED → measured or stays listed)

## 10.3 Security re-sweep

- [ ] S1 F1–F16 + Track A F-000–F-008 re-checked: each FIXED (test cited) or explicitly carried with reason + new tracking ID
- [ ] Vendor break-in enumeration (report §F, 18 paths) re-run against final code
- [ ] Secrets scan (no keys/VPA/URLs in git); webhook secret present in prod env (owner confirms names only)

## 10.4 Report close-out

- [ ] Report §13 matrix fully filled (Before/After/Evidence/Status per row)
- [ ] §14 UNVERIFIED list shrunk with device/prod evidence or carried to next cycle with owners
- [ ] Dead-code ledger resolved (deleted or kept-with-reason)
- [ ] New ADR per phase implemented (or one ADR per workstream if batched) + tracker/flow synced
- [ ] No P0/P1 open without a named owner + date
