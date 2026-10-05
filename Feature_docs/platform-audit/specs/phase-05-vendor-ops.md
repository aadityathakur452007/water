# Phase 5 — Vendor operations (refresh, states, duty, discovery, honesty)

- **Goal**: vendor never bounced mid-shift, never misled by UI, always knows the next action and how new work arrives.
- **Workstreams**: W5a vendor app ops (controllers/screens) · W5b vendor web parity (route/stops/collections/support components). Parallel-safe per surface; shared backend predicates (`isPaid` incl. partial/link_sent) defined once in spec and copied.
- **Depends on**: Phase 1 (OTP store, adjudication), Phase 2 (accept endpoint, repool wiring, PoD offline rule), Phase 3 (stop fields, failed/quality lists).

## 5.1 Refresh wiring [P1] (Track E §6)

- **Evidence**: client has NO refresh call — `AuthApi` exposes only codeLogin/demoLogin/logout (`auth_controller.dart:107-123`); stored refresh token never used; any 401/403 → `forceLogout → login` (`main.dart:68-70`). Access expiry (~30m) bounces mid-shift; 30d cap expiry behaves the same with no warning.
- **Fix**: wire `POST /v1/auth/refresh` with vendor-web device id (pairs with Phase 1.8 fix): silent renew on 401-once, `expiring-soon` banner when cap <24h, honest "dobara login karein" at cap. Web: same via BFF refresh (already refresh-once — verify device id after 1.8).
- **Tests**: expired-access → silent renew → request retries once; capped session → clean logout copy (no crash mid-triple; outbox survives — logout already preserves? verify `clearAll` does NOT wipe unsynced on cap-logout — keep queue, spec).

## 5.2 Honest money states [P1] (Track E §1)

- **Evidence**: `isPaid` checks only `paid_upi/paid_cash` (app `route_controller.dart:58`, `stop_detail:144-145`; web `stop-actions.tsx:115-119`) → `partial_dues`/`link_sent` render "Collect FULL total" → over-collection.
- **Fix**: predicates — `isPaid` (paid_*), `isPartial` (partial_dues → "Collect Rs REMAINING"), `isLinkSent` (link_sent → "UPI link bheja, verify karein" + no cash demand). Remaining computed server-side? No — client folds `total − paid_sum`? Server doesn't send paid_sum per stop. Phase 3 stop payload gains `paid_sum`; UI renders `Collect total−paid_sum`.
- **Tests**: widget matrix for all 5 payment statuses.

## 5.3 Duty truth + repool [P1] (Track E §§3–4)

- **Evidence**: `DutyController.load` sets onDuty=true on any route load (`duty_controller.dart:40-42`) — shows route-presence, not duty; Phase 2 wires repool into duty(off).
- **Fix**: duty switch reads server `on_duty` (add to a light endpoint or reuse profile — decide at build, ADR); off-state lists repooled count from Phase 2 response ("3 stops wapas pool mein").
- **Tests**: off-duty with stale route shows OFF; repool count displayed.

## 5.4 Assignment discovery [P1] (Track E §5)

- **Evidence**: no FCM (deps absent, grep-verified), zero `Timer/periodic` in vendor lib, web no `refetchInterval` — new assignment invisible until manual pull/refresh.
- **Fix**: vendor app polls `todayRoute + placedPool` on 60s timer while on-duty only (battery-conscious; timer cancelled off-duty/background — mobile-native rule); web `refetchInterval: 60_000` on route/placed queries. Push stays a documented gap (no provider in scope).
- **Tests**: timer fires only on-duty; off-duty/background no traffic (mock clock).

## 5.5 Stop completeness + guidance [P2] (Track E §§1,4)

- Failed (repooled) section (Phase 3 list) — renders distinctly, never as pending.
- Required-action ordering: Triple → PoD → Cash buttons gated by state (PoD needs triple done; cash needs total − paid_sum > 0), with "pehle X karein" hint instead of all-rendered.
- Single-visit option: keep 3 commits (server atomicity per op) — do NOT merge into one mega-commit (D1 non-atomicity makes that worse).
- Pull copy fix: app "Placed orders kheenchein" → honest "Naye orders dekhein (assign dispatch karega)" until Phase 2 vendor-accept ships; then wire accept.
- Duty display, sync-discard affordance for stuck `STALE_STOP` rejects, wa.me empty-phone guard (don't render link without 10-digit phone), web name/call/navigate on stop detail, order-pipeline states surfaced (no raw `order_state` text — mapped Hindi labels + what-it-means).

## 5.6 Exit criteria

- [ ] Full vendor shift runnable: login → poll-discover → accept (P2) → triple → PoD → cash → earnings, offline-tolerant, no mid-shift bounce
- [ ] Zero misleading money/action UI (matrix test per status)
- [ ] Duty, failed, sync-reject, discovery all honest states with retry/discard paths
