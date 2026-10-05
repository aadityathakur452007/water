# Phase 7 — Customer UX (checkout friction, completeness, honesty, a11y)

- **Goal**: ordering answers all six questions on every screen; no dead CTAs; no silent failures; Hindi-consistent; accessible.
- **Workstreams**: W7a checkout journey (home/buy-box/checkout/confirm/track) · W7b support/subs/addresses/profile · W7c a11y sweep. Parallel-safe per screen.
- **Depends on**: Phase 4 catalog + help paths (live rates, launchable support).

## 7.1 Checkout friction [P2] (Track F §1 F1–F12)

- Schedule chosen twice (home cards + checkout chips): choose once — home selection pre-fills checkout step as read-only recap with "badlein" link (no re-ask).
- 3-step once-order: collapse to Address recap → Pay for `deliveryType==once` (schedule step only for recurring); fixed `Subah 8–12` banner stays, slots load visibly with failure LOUD (no silent 08:00 fallback — F3).
- `windowLabel` free-text for subs → server-accepted window enum/ISO (align with backend sub windows; F4).
- Subscription totals via server quote (new `POST /v1/quotes` for subs or first-cycle estimate endpoint — backend Phase 3 decision; Pay button shows server amount, F5).
- Address change keeps object identity (no stale submit — F6 UNVERIFIED → prove with test).
- Address bar shows house/street/area (2-line, F7); confirm regains breakdown + address recap + UPI-pending "what next / when to worry" (F8); tracker maps all 10 states to distinct honest rows (no flat -1 bucket, F9); window card shows date+time (F10); subscription Pay shows amount (F5).
- Tanker sheet: Call CTA + real number (with Phase 4 constant); FAQ window copy fixed to match 014 (F11/F12).

## 7.2 Support + states honesty [P1/P3] (Track F §§1–2)

- Support WhatsApp Open launches (Phase 4) — remove clipboard-fake; error builder branch fixed (currently renders `none` on error — wire `errorMessage` to visible error + retry).
- Tracking skeleton (no blank wait) + retry on error; profile ledger failure surfaces (no silent defaults); checkout error row gains retry; 403/429 copies distinct from generic (role vs limit guidance).
- Confirm English primaries → Hindi to match title (or full bilingual pass — decide per screen, record).

## 7.3 a11y top-10 (Track F §6, in priority order)

1. PayChip disabled: `Semantics(enabled:false)` (no focusable dead chip).
2. Tracker dots: Semantics labels per step (progress announced).
3. Grid-card double-announce: single tap target, label describes card.
4. Calendar locale/semantics (Hindi day names verified on device).
5. 16px iOS-zoom guard on ALL text fields (currently orders-search only).
6. Focus moved to first error on submit failures.
7. Contrast-check legally relevant muted copy (deposit/cap/COD reasons) — measure, don't eyeball.
8. 48dp audit on remaining TextButtons (Change/Badlein etc.).
9. Destructive admin dialogs gain `aria-describedby` with consequence text.
10. Keep reduced-motion gating on any new animation (Phase 9).

## 7.4 Exit criteria

- [ ] Full journey walkthrough (fresh install → register → order → COD + UPI-intent → track → support) with zero dead CTAs, zero silent failures
- [ ] a11y 1–6 done + measured; 7–10 done or device-verified
- [ ] FAQ/copy matches 014 behavior everywhere (grep-verified, no contradictions)
