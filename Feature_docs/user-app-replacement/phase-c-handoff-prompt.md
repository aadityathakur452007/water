# Handoff Prompt — Phase C (P2): Close the 8 State-Audit Findings + First-Run Decision

> Copy everything below this line into a NEW agent session. It is written so a fresh
> agent with zero memory of this project can execute correctly and safely.
> Phase C is **NOT yet approved** — your first deliverable is a plan for owner approval,
> not code.

---

## MISSION

Close the 8 P2 findings from `Feature_docs/user-app-replacement/state-audit.md` §6 and resolve
the one open product decision (first-run locate→address onboarding: port or ADR-drop), on the
replacement customer app at `apps/user_app`.

Nothing else. Do not refactor beyond scope, do not touch the backend, do not touch the legacy app.

## MANDATORY FIRST READS (in order, before anything else)

1. `Agent.md` — full execution protocol (design-first: **Spec → Clarify → Approve → Implement**).
2. `SKILLS.md` — master skill index; pick the right skill, load it, **read its `SKILL.md`**.
   For this work the fit is **`ui-checklist`** ("Verify pages/components/flows are complete",
   `.agents/ui-checklist/`); add `design-basics` only if a fix changes visuals. State which
   skill you loaded before planning.
3. `context/progress-tracker.md` — current phase and gate evidence.
4. `context/flow.md` — how the app works (flows updated through Phase B).
5. `context/decision.md` — **ADR-119–125**; Phase C must append ADR-126 when done.
6. `Feature_docs/user-app-replacement/state-audit.md` — §5 (P1 fix-map pattern to follow),
   §6 (the exact P2 list = your scope), §7 (phased plan + gate ritual).
7. `States.md` (repo root) — the state checklist the audit was measured against.
8. `Feature_docs/user-app-replacement/spec.md` — feature map, only if a finding touches scope.

Audit line numbers were written before Phase A/B edits. **Re-locate every finding by behavior**,
not by the old line numbers.

## NON-NEGOTIABLE RULES

- Work on branch **`032-user-app-replacement` ONLY**. Never commit to `main`. Do not push.
- Conventional commits. Previous phases used pairs: `fix(user-app): …` for code,
  `docs(context): …` for context sync.
- Backend `workers/api` is **read-only** for you (you may read handlers to answer P2-8; never edit).
- `apps/user_app_legacy_flutter` is a read-only reference (you will read `first_run_screen.dart`).
- Ponytail law: laziest working fix, shortest diff, no speculative abstractions, **no new
  dependency without owner approval** (P2-6 and P2-7 may need that question).
- **Design-first gate:** produce the plan below, get explicit owner approval, then implement.
  No code before approval. This was the rule for Phases A and B and it is the rule for C.
- After each finding: `flutter analyze` clean + `flutter test` green (from `apps/user_app`).
- Before declaring done: update `context/progress-tracker.md`, `context/flow.md`,
  `context/decision.md` and mark Phase C done in `state-audit.md` §7.

## CURRENT STATE (as of 2026-10-22, before you start)

- Branch `032-user-app-replacement`, working tree clean.
  - `81a85db` docs(context): Phase B record (HEAD)
  - `a8972f4` fix(user-app): the 14 P1 fixes
  - `f56cd37` docs(context): Phase A record · `85d7b02` fix(user-app): the 3 P0 fixes
  - `main` is at `a836fe8` — untouched by Phases A/B; nothing pushed.
- Gates at Phase B: `flutter analyze` clean · **210/210** tests green · release APK **55.8 MB**,
  SHA256 `CC21EB44E4C479E0765B68D7AB9E222D9011AB701D857E2699D837B409B1D244`
  (3 ABIs: prod URL present ✓, `http://localhost:8787` absent ✓, Razorpay test key present ✓).
- Device-verification debt (unchanged, do not claim closed): Razorpay return, real UPI intent,
  GPS fixes, live OSM tiles, debug-cert signing / owner keystore.
- Baseline tests live in `apps/user_app/test/`. Phase A/B added
  `session_reset_test.dart`, `checkout_recovery_test.dart`, `phase_b_states_test.dart`; expect
  `phase_c_states_test.dart` for new logic.

## HARD LAWS (violate any = reject)

- No fake/hardcoded money or statuses; everything money-related is server-owned.
- One money formatter: `lib/core/money.dart formatInr` (₹, 2dp only when needed). Never
  reintroduce `~/ 100` truncation anywhere money renders.
- Delivery OTP is server-owned. UPI verification is webhook-only + poll
  `GET /v1/orders/{id}` ≤5× every 2s until `payment_status == 'paid_upi'`.
- COD and UPI are both first-class. `Idempotency-Key` on every money POST.
- https/loopback guard stays. Auth = Bearer + `X-Device-Id`.
- Design laws: ONE theme file (`lib/core/theme.dart`); green money CTAs only; blue links/info
  only; teal structure/nav; no gradients; 48dp targets; English copy for v1.
- Release build defines (for the final APK rebuild):
  `--dart-define=SHODASHA_API_BASE=https://water.adityathakur452007.workers.dev/v1 --dart-define=RAZORPAY_KEY_ID=rzp_test_Thq4I47cEMIjbF`

## SCOPE — the 8 P2 findings (state-audit.md §6)

| # | Finding | Where (re-locate by behavior) | Fix intent / acceptance |
|---|---------|-------------------------------|--------------------------|
| P2-1 | Splash restore can hang forever | `lib/features/auth/auth_gate.dart` (restore branch, ~`:41-44` pre-B) | Session restore gets a timeout (e.g. 5s) → fall back to login/guest instead of an infinite splash. Widget test with a never-completing restore. |
| P2-2 | **First-run locate→address onboarding missing** — the only legacy flow not ported | New app: Home / addresses flow. Legacy: `apps/user_app_legacy_flutter/lib/features/auth/first_run_screen.dart` | **Decision required (ask owner).** Option (a) port: one-time bottom sheet on Home when the address list is **loaded, authed, and empty**; reuse the existing address sheet + map picker; 2 steps (locate → address); *skip also persists* (no nagging); denied location never dead-ends. Option (b) write an explicit ADR note dropping it. Audit **recommends porting**. Legacy mechanics to mirror: `kFirstRunFlag = 'firstrun_done_v1'` in SharedPreferences, `shouldOfferFirstRun()`, `markFirstRunDone()`, `maybeOfferFirstRun(context, addressCount, onAddAddress)`. Do not offer while the list is loading/failed. Tests for the flag + emptiness gate. |
| P2-3 | Booking sheet dismissible while paying | `lib/features/booking/booking_sheet.dart` (~`:39-57`) | While a payment (UPI intent/poll) is in flight, swipe/back must not silently drop the poller. Block dismissal or confirm first (use the existing `attention` confirm variant from ADR-124). If a confirm is used, mirror the address form pattern: `setState` allow-pop then pop in `addPostFrameCallback` (`PopScope.canPop` is build-time). Test: dismissal blocked while paying, allowed after settlement/failure. |
| P2-4 | 409/conflict copy + absent bill rows | `lib/features/addresses/address_screen.dart` (409 already mapped ~`:296, :324`) · `lib/features/orders/bill_screen.dart` (rows hidden when 0) | Verify/sharpen the address delete-conflict copy (order holds the address). In the bill, render absent rows (`Cap`, `Previous dues`, `Payment`) as `—` / `Not billed` instead of hiding them. **Display-only — no money math changes.** Widget test for the hyphen rows. |
| P2-5 | Android back on a non-Home tab exits the app | `lib/features/shell/user_shell.dart` | System back on any non-Home tab goes to Home first; only Home's back exits. `PopScope` at the shell; widget test. |
| P2-6 | OSM tile failure placeholder + reconnect banner | Map: `lib/features/addresses/map_picker.dart` (`TileLayer` ~`:166`) · Banner: cross-cutting (`lib/core/api_client.dart` / shell) | Map: add a tile-failure placeholder/retry so a dead OSM request doesn't show a blank grid. Banner: show an offline/“back online” banner after network restore — **evaluate the cheapest approach first**; a connectivity package is a NEW DEPENDENCY and needs owner approval. Propose options in the plan. |
| P2-7 | Tablet/large-screen layout | App-wide (`lib/features/shell/user_shell.dart` or per-screen) | Either a centered max-width column at the shell (small, low risk) or explicitly document phone-first in ADR-126. Audit flags it as “intentional?” — propose one, let owner pick. |
| P2-8 | Support / payment-history pagination | `lib/features/support/support_screen.dart` · `lib/features/wallet/payment_history_screen.dart` · read-only check of `workers/api` list handlers | Read the backend handlers to see if those lists cap (limit/cursor). If capped: add Orders-style load-more (single-flight guard, id dedupe, footer error/retry — copy the P1-3 pattern from `orders_controller.dart`). If not capped: document N/A in ADR-126. Do not modify the backend. |

## FIRST DELIVERABLE — PLAN, THEN STOP

Present a short plan to the owner covering, per finding: root cause (one line), minimal fix,
files touched, tests added, design deltas, risk. Explicitly ask:

1. P2-2 — port the first-run sheet (recommended) or ADR-drop it?
2. P2-7 — shell max-width or phone-first ADR?
3. P2-6 — may I add a connectivity dependency, or do you want the no-new-dep approach?

Then **stop and wait for explicit approval**. Suggested order after approval: independent small
fixes first (P2-1 splash, P2-3 booking dismiss, P2-5 back, P2-7 if code), then copy/display fixes
(P2-4, P2-6 map), then P2-8 pagination, then P2-2 first-run (biggest, depends on the owner's
answer). Keep tests green after every slice.

## FINISH GATES (after the last fix)

1. `flutter analyze` clean · `flutter test` all green (baseline was 210/210 — count must go up,
   never down).
2. Rebuild the release APK with the two defines; report size + SHA256; verify per-ABI that the
   prod URL is present and `http://localhost:8787` is absent (same scan as Phases A/B).
3. Update `context/progress-tracker.md` (Phase C block), `context/flow.md` (any flow changed),
   `context/decision.md` (append **ADR-126** — Phase C fixes + the first-run decision + any
   deliberate non-goals), and mark Phase C done in `state-audit.md` §7.
4. Commit on `032-user-app-replacement` only, code + docs as separate conventional commits.
   **Do not push.**

## DO NOT

- Do not touch `workers/api`, `apps/user_app_legacy_flutter`, admin/vendor apps, or `main`.
- Do not claim device-verification debt closed (it requires hardware).
- Do not add dependencies or invent UI patterns outside the theme laws without asking.
- Do not start coding before the owner approves the plan.
