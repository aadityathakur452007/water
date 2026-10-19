# Handoff Prompt — New Agent Session: Full User-App UI Replacement (donor repo) + Backend Wiring

> Copy everything below this line into a NEW agent session. It is written so a fresh
> AI agent with zero memory of this project can execute correctly and safely.

---

## MISSION

Replace the customer app's UI entirely with a donor repo's premium Flutter UI, and connect it to OUR backend. Specifically:

1. **Do NOT delete or overwrite the existing user app.** First `git mv apps/user_app apps/user_app_legacy_flutter` — the legacy app stays in the repo, renamed, as the permanent reference (backend contract + feature spec + test behaviors). It must never be built by CI again.
2. **Import the donor repo's Flutter app INTO `apps/user_app`** (same folder position, so CI workflow paths keep working): https://github.com/ayushsingh930/Shodasha-Mineral-water — remove its `.git` if cloning into place; commit all its files into OUR repo.
3. **Wire the donor app to our backend** (`workers/api`) — the donor app currently has NO network layer at all; you will build one.
4. **Map our features onto the donor UI** — our legacy user app has many features the donor repo does not have; port them onto the donor's premium screens.

## STEP 0 — READ FIRST (mandatory, before anything)

In repo root `C:\Users\Hp\Water`:
1. `Agent.md` — the execution protocol (design-first: Spec → Clarify → Approve → Implement; approval is a HARD gate before any code).
2. `SKILLS.md` — master skill index; load the right skill before coding and state which one you loaded.
3. `context/progress-tracker.md`, `context/flow.md`, `context/decision.md` (especially ADR-114 through ADR-119), `context/architecture.md`.
4. `Feature_docs/user-app-ui-import-audit/01…06` — the full donor audit: UI inventory, feature-parity gap matrix, backend-contract violations, engineering/packaging audit, UX review, strategy.
5. Create branch `032-user-app-replacement` FIRST; conventional commits only; never commit directly to main.

## THE DONOR REPO — WHAT YOU'RE GETTING

URL: https://github.com/ayushsingh930/Shodasha-Mineral-water (~5,500 lines Flutter; a prior read-only clone may still exist at `C:\Users\Hp\AppData\Local\Temp\opencode\shodasha-friend-ui` — re-clone read-only if absent).

Worth keeping (premium craft): dense order-card grammar, gradient heroes, status pills, wallet screen layout, cart/checkout sheet, login skeleton, typography/radii rhythm.

MUST be deleted or replaced (audit doc 03 — trust inversions, not ported):
- **No network layer**: 0 HTTP clients — all "data" is 5 hardcoded in-memory ChangeNotifier singletons. Build ONE `ApiClient` (copy the pattern from `apps/user_app_legacy_flutter/lib/core/api_client.dart`).
- **Fake auth**: 4-digit OTP screen accepts any code → replace with our real register/login contract.
- **Client-minted delivery PIN printed to the rider** → trust inversion; delivery OTP must come only from the server (see contract below).
- **Role mixing**: customer app embeds rider + owner control-center screens → customer app is customer-only; ask the owner whether those screens are dropped or parked.
- `com.example.shodasha` applicationId, default launcher icon, dead deps, ~1,008 dead lines, debug-signed release → fix packaging (reuse the legacy app's brand adaptive-icon vectors + gradle release config).

## BACKEND CONTRACT TO WIRE (non-negotiable — this makes the pretty UI real)

- Backend: `workers/api` — FastAPI on Cloudflare Workers (Pyodide) + D1. Prod base URL: `https://water.adityathakur452007.workers.dev/v1`.
- Release APK MUST be built with:
  `flutter build apk --release --dart-define=SHODASHA_API_BASE=https://water.adityathakur452007.workers.dev/v1 --dart-define=RAZORPAY_KEY_ID=rzp_test_Thq4I47cEMIjbF`
  (The legacy ApiClient hard-fails construction unless the base URL is https or loopback — keep that guard.)
- Transport (copy from legacy `api_client.dart`): single ApiClient; `Authorization: Bearer` + `X-Device-Id` (persisted UUID) headers; GET single-flight + replay-safe retry (3 attempts, backoff, Retry-After); keyed-POST retry semantics via `Idempotency-Key`.
- **Idempotency-Key header is REQUIRED** on: `POST /v1/orders`, order cancel, `upi-intent`, `dues-intent` (server returns 422 PAYLOAD_MISMATCH on key/body mismatch, 409 on replay).
- **UPI verification is webhook-only**: never trust gateway success alone — poll `GET /v1/orders/{id}` (up to 5×, every 2s) until `payment_status == 'paid_upi'`. COD and UPI are both first-class checkout modes.
- **Delivery OTP is server-owned**: revealed owner-only via `GET /v1/orders/{id}` (`delivery_otp`), only in states {assigned, dispatched}. NEVER client-mint.
- Auth: `POST /v1/auth/user/register` {name, email (@gmail.com only), phone (10-digit Indian)}; config-gated `POST /v1/auth/demo`; `GET /v1/auth/me`; logout.

## FEATURE MAPPING — legacy-only features the donor repo LACKS (map each onto donor screens)

1. Server-side quote/pricing + ₹150/jar refundable security deposit (once-only per container) — `POST /v1/quotes`.
2. Checkout: UPI (Razorpay intent) + COD, full idempotency lifecycle (fresh key per session, refresh on payment-mode switch/retry).
3. Delivery windows/serviceability (`GET /v1/windows`, serviceability) + address CRUD + OSM map picker (no Google key) — `POST/PATCH /v1/addresses`; 409 when an undispatched order uses the address.
4. Subscriptions: monthly prepaid/postpaid calculator, pause/resume/skip/cancel, deposit-waiver on repeats — `POST /v1/subscriptions/estimate|create|{id}/pause|resume|skips|cancel`.
5. Orders: list/detail/tracking (live stops-ahead + rider + delivery-OTP reveal)/cancel/reschedule/rating/cod-confirm.
6. Ledger truth: `GET /v1/ledger/me` (deposit/dues/held jars) — loading/error states, never a fake ₹0 wallet.
7. Payment history: `GET /v1/payments/me`.
8. Returns: empty-jar pickup + direct UPI deposit refund (`POST /v1/returns` with `upi_id`).
9. Support/complaints (`POST /v1/complaints`, list) + WhatsApp support via the single `kSupportPhone` constant.
10. Profile edit: `PATCH /v1/auth/me` (name/phone/email).
11. Legacy app is bilingual Hindi-first — clarify with the owner whether the donor's English copy stays (prior owner decision: keep English for now).

Donor-only screens with no backend counterpart (portal/donations, owner control-center, rider screens): ask the owner in your clarifying questions — drop or keep. HARD LAW: no fake/hardcoded money amounts or statuses anywhere; every number comes from a server fetch or an honest loading/error state. Empty/loading/error states on every screen (see `States.md`).

## DESIGN & THEME

- Adopt the donor's premium design language as the new base theme, centralized in ONE theme file (token law — no scattered `Color(0x…)` literals).
- Legacy locked palette v2 was teal #0D9488 brand / green #16A34A money-CTA / blue link-only / slate ground — the donor's own palette may supersede it; ask the owner at the design gate.
- Android: proper applicationId (not com.example), app label "Shodasha", brand adaptive launcher icon (reuse legacy vectors), release signing/minify config copied from legacy gradle.

## VERIFICATION GATES (every slice)

- `flutter analyze` — zero issues.
- `flutter test` — new app's suite green; port legacy behavior tests for every screen you re-wire (legacy `apps/user_app_legacy_flutter/test/` is the behavioral spec).
- Backend pytest untouched: 333 passed / 1 known pre-existing failure (`test_resilience_snapshots.py` StaleQuoteError — owner-owed, NOT yours to fix; do not re-triage).
- APK release build with both dart-defines; verify in-binary that the prod URL is present and `http://localhost:8787` is absent.
- Do NOT touch `apps/vendor_app`, `apps/admin_app`, or `workers/api` except additive backend needs (get owner approval first).
- Check `.github/workflows/release.yml` + CI matrix paths: legacy folder must be excluded from build/analyze/test; `apps/user_app` (donor) must build.

## FIRST DELIVERABLES BEFORE ANY CODE (design gate)

1. Site map + user-flow deltas: donor screens × our endpoints matrix.
2. `Feature_docs/user-app-replacement/spec.md` with the full feature-mapping table (donor screen → our controller/endpoint → what's ported/dropped).
3. Clarifying questions to the owner: palette (donor vs teal v2), donor-only screens fate, applicationId/package rename, copy language (English vs Hindi), CI naming for the renamed legacy folder.
4. **Explicit owner approval → then implement slice-by-slice, tests green per slice, context files (`progress-tracker.md`, `flow.md`, `decision.md`) updated after every task.**

## KNOWN STATE AT HANDOFF (2026-10-19)

- Branch `031-user-app-ui-revamp` (palette v2 + donor-grammar reskins, 138/138 tests green) was merged into `main` and pushed — `git log main` shows the merge commit. Start from main.
- Prod API is live and verified; Razorpay test keys active; admin/vendor apps and backend are healthy — leave them alone.
- Reference donor clone (may or may not still exist): `C:\Users\Hp\AppData\Local\Temp\opencode\shodasha-friend-ui`.
