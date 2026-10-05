# Phase 0 — Safety: baselines, branch, build unblock

- **Goal**: frozen starting point + green builds on every surface before any fix lands.
- **Workstream**: W0 (solo, blocks all others) · **Branch**: `029-remediation` from `main` tip (027/028 merge separately first — see dependencies).

## 0.1 Baselines (recorded, do not re-derive)

| Metric | Value | Source |
|---|---|---|
| Backend pytest | 241 passed, ~6–12s (`workers/api`) | Track A run |
| User Flutter test / analyze | 99 green / 0 issues | Track C |
| Vendor Flutter test / analyze | 40 green / 0 issues | Track C |
| User release APK arm64 | 26.05 MB (149s build): libflutter.so 11.05 + libapp.so 6.69 + flutter_assets 5.9 (packages 5.0 incl. shadcn 2.44/forui 1.28/country_flags 1.15 + app assets 0.82 incl. logo.png 0.82) + dex 0.93 + res 0.51 | Track C DevTools JSON |
| Vendor release APK arm64 | 18.13 MB (78s build): libflutter.so 11.05 + libapp.so 5.69 + dex 0.48 + assets 0.12, no packages dir | Track C |
| Admin `npm run build` | FAILED | P0-0 below |

## 0.2 P0-0 build unblock (only fix in Phase 0 — unblocks all admin verification)

- **Finding** (Track D, VERIFIED): `[UNRESOLVED_IMPORT] Could not resolve '../../../../-components/vendor-states'` in `src/routes/(main)/vendor/(guard)/stops/$stopId/index.tsx:9`. From `vendor/(guard)/stops/$stopId/` four `../` lands in `(main)/`, not `vendor/`. Siblings use `../../-components` / `../../../-components` correctly (`support-queue.tsx:22`, `today-strip.tsx:7`, `vendor-money.tsx:6`).
- **Fix**: one-line import → `../../../-components/vendor-states`. No other change.
- **Verify**: `npm run build` green (user runs it — admin AGENTS.md bars unasked validation; record output).

## 0.3 Branch + hygiene

- Create `029-remediation` from `main` tip. 027 (`vendor_access_*`, vendor BFF) and 028 (generalized codes, both apps passwordless) merge first; 029 rebases onto the result. If 027/028 change `vendor_service`/`admin.py` shapes, Phase 1–3 specs follow the merged truth (note drift in report §13).
- `routeTree.gen.ts` is tracked + dirty: regen via dev/build, never hand-edit.
- Backups: no prod D1 writes in any phase without explicit owner go-ahead; migrations are additive + idempotent (`IF NOT EXISTS`); no `DELETE/DROP/rename` of production fields (§42–43).

## 0.4 Exit criteria

- [ ] `029-remediation` exists from main tip (post-027/028-merge)
- [ ] Admin build green (output pasted to report §13)
- [ ] Baselines above re-run green on the new branch (pytest + both `flutter test` + both `flutter analyze`)
