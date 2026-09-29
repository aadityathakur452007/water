# API Contract Security + Consistency Audit — run 1 (2026-09-29)

> Skill: `security-audit` (Cloudflare, global install `~\.agents\skills\security-audit`) + `ssdlc` + `design-patterns` + `user-flows`.
> Target: spec docs (no executable code exists yet — `workers/api/` unscaffolded), reviewed at branch `001-shodasha-research-phase1` + uncommitted §§9–15 work.
> Mode note: skill guidance mode with finder teams (A traceability / B contract-logic vulns / C complexity+ops) + parent verification (checker ≠ finder — I verified every claim against file:line before fixing). Full-audit sandbox execution is N/A: there is no code to run; findings are contract-logic boundary violations evidenced by spec text. Report lives in-repo (deviation from skill's external-output default) because this project's convention is docs-in-repo and the user ordered the contract re-mapped.
> Verdict key: FIXED (patched in docs) · REJECTED (claim checked, not a bug — reason given) · OPEN (needs external fact — needs_validation).

## FIXED (docs patched)

**Auth/session (C1, C2, C7, C8, A4–A6):** verify mints restricted sessions (never fresh full access post-suspend); vendor suspend also kills Firebase user; per-request `users.suspended` join; refresh reuse → revoke family + force re-OTP + alert; device_id-scoped FCM deletes; architecture.md + ADR-012 + progress OTP text corrected to Firebase.
**Money races (C3, C15, C16):** `UNIQUE(payment_id)` refunds + claim lock (`claimed_by/at`, pending→claimed→done|failed); cancel requires Idempotency-Key in one transaction; webhook replay-cache + ±5 min window + nonce.
**Assignment race (C4):** read-check-assign in one D1 transaction.
**Quote replay (C5):** 15-min TTL + hash binds items/e/address/window/total/rate_version.
**Idempotency scope (C6):** `UNIQUE(user_id, scoped_key)`, payload-mismatch → 422, retention 72 h/30 d.
**CSRF (C9):** `Secure + SameSite=Lax` cookie + `X-CSRF-Token` on admin mutations.
**Reassign vs offline triple (C14):** stop `version` fencing → `409 STALE_STOP`.
**Fake-delivery economics (C11, C12):** flagged stops accrue-but-hold payout; user receipt shows recorded amount + 1-tap dispute; `tendered−change=cash` invariant.
**Device farms (C13):** Play Integrity enforced on OTP start/verify, not just payments.
**GPS spoof (C10):** `accuracy_m` field + server-side `place_id` re-verify + verified-pincode zoning.
**Missing endpoints/tables (A10–A12, A15–A18, A21, A22, A24, A25):** reschedule, returns-assign, ratings, vendor create/capacity, routes-generate, seed procedure, subscription schedule columns, `return_id`, leads, depot_stock, `PATCH /auth/me`, WhatsApp provider adapter, lab-report config URL, `effective_from`, quote/TTL retention, user poll cadence.
**Contradictions (A1–A3, A7, A23):** FR-20/UR-20/flows photo lines → v2; ADR-016 photo line corrected; ADR-007 triple-use split into 007/007b/007c with reference updates; EC-S05 visit-fee aligned to none.
**Reservations mapped (A8, A9):** tier columns + wallet/rate-override as v2-reserved NULL.

## REJECTED (checked, kept as designed — with reason)

- Dual Firebase+D1 sessions: standard split (Firebase = proof-of-phone, D1 = revocable app session + device graph); Firebase-only loses instant suspend.
- `payouts` table alongside salary model: deductions need a ledger to land in (`per_stop_fee=0` = salary).
- `skips` vs pause ranges: late-skip accountability differs from holds; kept.
- Zones + priority + caps knobs: geography vs preference vs capacity — three axes, not duplication.
- `strikes.cleared_by`: appeals need provenance.
- `tendered/change_given`: kept optional + invariant (receipt disputes need it).

## OPEN (needs_validation — external facts)

- UPI provider callback format + webhook secret storage; Firebase project ids; WhatsApp provider (templates, DLT, opt-out); Play Integrity behavior on rooted/low-end fleet; pincode master source; GPS polygon format (v2); payout model (fee vs salary); visit fee; GPS soft vs hard.

## Coverage statement

No prior runs. Single pass over 6 spec surfaces + contract + context files by 3 finder teams + parent verification. Spec-only target: no SAST/DAST/fuzz applicable until `workers/api/` exists — Phase-2 scaffold must re-run executable checks. This report does not claim exhaustive coverage.
