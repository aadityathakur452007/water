# 00 — Audit Index

**Branch:** `037-uiux-unslop-audit` (from `036-demo-cleanup-admin-code`)
**Base commit:** `c738786` — `docs(ux-audit): install unslop skill and write audit handoff prompt`
**Session date:** 2026-10-31
**Status:** Audit and synthesis complete (23/23 documents written); approval gate presented and waiting.

## Gate baseline (recorded before any audit work)

| App | `flutter analyze` | `flutter test` | Result |
|---|---|---|---|
| `apps/user_app_donor` | No issues found | **75 / 75 passed** | Matches ADR-154 |
| `apps/vendor_app` | No issues found | **68 / 68 passed** | Matches ADR-154 |

These numbers are the baseline. They must be identical at the end. No app file was touched
to produce this audit.

## Evidence status

| Evidence | Status | Path |
|---|---|---|
| Donor login screen, 390×844 | Captured, opened | `shots/donor-login-390.png` |
| Donor login screen, 360×800 | Captured, opened | `shots/donor-login-360.png` |
| Authenticated donor screens | **Not captured** | Web build reaches login only; no session/credentials were used. Golden harness not built — timebox expired. Agents audit these from code. |
| Vendor screens | **Not captured** | Vendor access code is server-owned; no credentials were used. Agents audit from code. |

Rule for agents: if you did not open a screenshot, write `VISUAL: not captured — code audit`
in your header. Never describe a screenshot you did not open.

## Phase 0 artifacts

| File | Purpose |
|---|---|
| `00-tokens-actual.md` | Every real token (color/type/radius/spacing/motion), drift vs `ui-context.md`, off-scale census |
| `00-slop-signals.md` | Signal counts per app/feature folder + where the real slop is |
| `00-index.md` | This file |

## Key Phase 0 facts every agent must carry

1. **No gradients, no glass, no emoji, no raw hex outside the theme.** Do not invent them.
   The slop is rhythm, type sprawl, composition, flow, and copy.
2. **Donor type scale is 12/14/16/18/22/28.** 19 sizes are used. `13` is a de-facto second
   body size (84 uses).
3. **Spacing scale is 4/8/12/16/24/32.** `10`, `14`, `18`, `20` are used as real padding.
4. **Every `ElevatedButton` is money-green by theme default** (`theme.dart:311`). List
   non-money uses.
5. **Vendor has no spacing/type/motion scale.** Audit it against its own consistency, not
   against donor's scale.
6. **Vendor is bilingual (Hindi/English); donor is English-only.** Language is an owner
   decision, not a screen defect.

## Agent roster

### Donor app — 12 agents

- [x] D1 `01-donor-auth.md` — login, auth gate, auth controller, first-run address sheet
- [x] D2 `02-donor-shell-nav.md` — 5-tab shell, notifications
- [x] D3 `03-donor-home.md` — home, top bar, mode cards, purity card, featured products
- [x] D4 `04-donor-booking.md` — booking sheet, stepper, product detail, quote confirm, booking controller, catalog
- [x] D5 `05-donor-orders.md` — my orders, order card, orders controller (list/filter)
- [x] D6 `06-donor-tracking.md` — tracking screen (polling, OTP, live state)
- [x] D7 `07-donor-bill-rating.md` — bill screen, rating sheet
- [x] D8 `08-donor-subscriptions.md` — subscription screen, plan builder, subscription controller
- [x] D9 `09-donor-wallet.md` — wallet, payment history, wallet controller
- [x] D10 `10-donor-addresses.md` — address screen, map picker, selected address store
- [x] D11 `11-donor-profile.md` — profile screen, edit sheet, profile controller
- [x] D12 `12-donor-support-returns.md` — support screen/controller, return sheet/controller

### Vendor app — 4 agents

- [x] V1 `13-vendor-auth-shell-profile.md` — vendor code, auth gate, strings, shell, profile
- [x] V2 `14-vendor-route-stops.md` — route, route controller, stop detail, PoD, triple, stops controller
- [x] V3 `15-vendor-duty-sync.md` — duty, sync, cascade
- [x] V4 `16-vendor-customers-inventory-earnings-support.md` — customers, inventory, earnings, support

### Cross-cutting — 4 agents (after screen agents)

- [x] X1 `17-system-tokens-shared-ui.md` — both themes, all donor `shared/ui`, AppMotion
- [x] X2 `18-duplication-dead-code.md` — repo-wide within both apps
- [x] X3 `19-flows-state-machines-nav.md` — cross-screen flows + mermaid current/proposed
- [x] X4 `20-copy-a11y-motion.md` — all strings, semantics, contrast, reduced motion, polling

### Synthesis

- [x] `21-synthesis.md`
- [x] `22-backlog.md`
- [x] `23-owner-decisions.md`

## Scope guard

- **Allowed:** markdown under `Feature_docs/ux-unslop-audit/` and screenshot PNGs.
- **Forbidden:** any change under `apps/*/lib`, `apps/*/test`, `workers/`, `pubspec.yaml`,
  CI, config. No new dependencies. No money/auth/API/test-expectation changes.
- **Do not run** `flutter build apk`, hit production with credentials, create orders, or
  spend money.
