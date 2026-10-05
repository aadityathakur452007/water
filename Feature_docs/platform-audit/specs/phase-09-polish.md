# Phase 9 — Premium polish (state-communicating motion only)

- **Goal**: premium feel without decoration cost; every animation communicates state or improves usability (§22, §45).
- **Workstream**: W9 design polish (single stream; runs LAST — needs final screens from Phases 5–7).
- **Depends on**: all UX phases (polish applies to final truth, not interim layouts).
- **Skills (activate at build)**: `mobile-native` (touch/feel truths) · `redesign-existing-projects` (no invented components) · `impeccable`/`hallmark` Operate mode (scanability) · `design-taste-frontend` (Three Dials, low motion) · animation skills ONLY if a transition needs choreography (default: existing `flutter_animate` + CSS transitions — no new animation deps without §35 justification block).

## 9.1 Allowed motion inventory (each must map to a state)

- Skeletons on first-load (extend user-orders pattern to tracking/subs/vendor screens; admin preview/access).
- Order-status transitions (tracker dot fill, stop pending→done) — 150–250ms, transform+opacity only.
- Success confirmations (order placed, cash jama, code issued) — toast/sheet, `aria-live`, auto-dismiss.
- Bottom-sheet choreography (checkout, triple, PoD) — existing patterns, reduced-motion static.
- Animated counters on KPI cards (admin) — only if render-cheap (see 8.5 chart guard); off under `prefers-reduced-motion`.

## 9.2 Explicitly forbidden

- Pointless bounce/slow transitions/animation-everywhere (§22); startup-cost animations; accessibility-interfering motion; new animation libraries without the §35 justification (why/problem/alternative/bundle-impact/security-why-this).
- No deferred components for size (§10 rule — size is solved in Phase 4).
- No redesign-by-imagination (§44): polish follows Phases 5–7 realities; vendor stays operationally dense (seconds-to-next-action test per screen).

## 9.3 Exit criteria

- [ ] Motion inventory implemented per 9.1 with reduced-motion fallbacks verified (device + `prefers-reduced-motion` emulation)
- [ ] No new animation dependency without §35 block in the phase ADR
- [ ] Vendor "what do I do right now" ≤5s test per screen (measured, recorded)
