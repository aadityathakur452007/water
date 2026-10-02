# Shodasha Vendor (Delivery) App — Feature Spec

- **Date**: 2026-10-02
- **Branch**: `007-vendor-app` (from `main` @ f4eda7f)
- **Status**: DRAFT — awaiting explicit user approval (no app code written)
- **Backend**: production `https://water.adityathakur452007.workers.dev/v1`
- **Inputs**: `Feature_docs/synthesis/vendor-requirements.md` (VR-01..VR-14), `pricing-deposit-model.md` (Rs 150 deposit, Rs 3 cap), `Feature_docs/backend/api-contract.md` §4.7/§9/§11/§12/§14, `workers/api/src/app/api/v1/vendor.py` + `services/vendor_service.py`, `apps/user_app/` reference (theme, api_client, session_store, auth seams), AVD `shodasha_api36`
- **Skills applied**: `design-basics` (guardrails.md law) + `premium-design` (Mode 1 Modern Minimalist) + `ui-checklist` + `hallmark` + `impeccable` (`shape` → Operate mode) + `minimalist-ui` + `design-patterns` (mobile card)

---

## 1. What this is

A **second, separate Flutter Android app** for delivery vendors (drivers), distinct from the user app:

- Separate `applicationId`: `com.shodasha.vendor_app` (user app is `com.shodasha.shodasha_app`)
- Android only, Flutter 3.44.9, compileSdk/targetSdk 36, minSdk 24
- Vendor powers against the real backend: Firebase phone OTP login (vendor role gate), duty on/off, today's route with loading sheet, stop execution with version-fenced triple commit, PoD with delivery OTP + GPS soft-flag (never blocking), offline-first outbox with idempotency keys, earnings with flagged-hold note, complaint verify agree/disagree, quality check
- Money is **display-only from server paise values**; server never trusts client money math

Out of scope for v1 (model leaves room, no build): photo PoD (v2 with object storage), per-customer/corporate rate overrides + dealer tier, payroll/expenses/P&L, prepaid wallet, route-AI auto-sequencing, customer live map, Gujarati + rest languages (Hindi v1 only).

---

## 2. Screen map (10 screens)

```
Login OTP → Duty toggle → Today route sheet → Stop detail → Triple commit → PoD
  → Sync status → Earnings → Complaints/Quality → Profile
```

| # | Screen | Route | Purpose | Backend |
|---|--------|-------|---------|---------|
| 1 | Login OTP (phone + 6-box) | `/login` | Vendor Firebase phone OTP, role=vendor gate | `POST /v1/auth/otp/start`, `POST /v1/auth/otp/verify` |
| 2 | Duty toggle | `/duty` | Shift on/off, capacity meter, assignment push | `POST /v1/vendor/duty {on}` |
| 3 | Today route sheet | `/route` | Sequenced stops + loading sheet take-X/expect-Y + SKIP list | `GET /v1/vendor/routes/today` |
| 4 | Stop detail | `/stops/:id` | Exact GPS + lift/gate note + qty/empties-expected + cash-due | `GET /v1/vendor/stops/{id}` |
| 5 | Triple commit | `/stops/:id/triple` | Atomic fulls/empties/cash-UPI + caps_missing × Rs 3 | `POST /v1/vendor/stops/{id}/triple` + Idempotency-Key + version |
| 6 | PoD | `/stops/:id/pod` | Delivery OTP + empties + cash + seal_ok + GPS soft-flag | `POST /v1/vendor/stops/{id}/pod` |
| 7 | Sync status | `/sync` | Offline outbox queue, pending badge, per-stop resolve log | `POST /v1/vendor/sync` (batch) |
| 8 | Earnings | `/earnings` | Per-shift cash/UPI totals + flagged-hold note | `GET /v1/vendor/earnings?shift=` |
| 9 | Complaints / Quality | `/support` | Verify agree/disagree + door check seal/smell/visual | `POST /v1/complaints/{id}/verify`, `POST /v1/quality/{id}/vendor-check` |
| 10 | Profile | `/profile` | Name/vehicle/zone, Hindi toggle, help, logout | `GET /v1/auth/me`, `POST /v1/auth/logout` |

Bottom nav (vendor): Route (today) · Sync (badge) · Earnings · Support · Profile. Duty toggle lives as a header switch on Route + a dedicated Duty screen on first login.

---

## 3. Endpoint → screen matrix (contract truth)

Base: `https://water.adityathakur452007.workers.dev/v1`. Money on wire = integer paise. Auth on every vendor call: `Authorization: Bearer <access_token>` + `X-Device-Id`. Writes add `Idempotency-Key: <uuid>` (scoped `UNIQUE(vendor, endpoint, key)`; replay same payload → stored outcome; different payload same key → `422 PAYLOAD_MISMATCH`).

| Method + path | Screen | Request | Response | Errors |
|---|---|---|---|---|
| `POST /v1/auth/otp/start` | Login phone | `{phone: +91XXXXXXXXXX}` | `202 {sent_to_masked, resend_after_s, channel: firebase\|sms}` | 400 bad phone · 429 resend/pump |
| `POST /v1/auth/otp/verify` | Login OTP | `{firebase_id_token? \| phone+otp_code?, device:{id*}}` | `200 {access_token (30m), refresh_token (7d rotating), role, restrictions?}` | 401 bad/expired · 409 DEVICE_CAP · 429 |
| `POST /v1/vendor/duty` | Duty | `{on: bool}` | `{vendor_id, duty_on, since}` | 401/403 (suspended → notice only) |
| `GET /v1/vendor/routes/today` | Route | `?date=` optional | `{route, stops[], loading:{take_fulls, expect_empties}, skip[]}` | 401/403/404-shaped |
| `GET /v1/vendor/stops/{id}` | Stop detail | — | `{id, route_id, order_id, seq, fulls_exp, empties_exp, version, triple, status}` | 404 not-yours = same shape as missing (no oracle) |
| `POST /v1/vendor/stops/{id}/triple` | Triple | `{fulls_given, empties_back, cash, upi, caps_missing, tendered?, change_given?, seal_ok?, version*}` + Idempotency-Key | stop + `triple{...}` + `replay:true` on replay | `409 STALE_STOP` (reassigned, pull fresh) · 400 `tendered-change=cash` (C12) · 422 never-negative ledger · 422 PAYLOAD_MISMATCH |
| `POST /v1/vendor/stops/{id}/pod` | PoD | `{delivery_otp*, empties_count, cash, seal_ok?, lat?, lng?}` | stop + `triple.pod{..., gps:{lat,lng,dist_m,flagged}, completed_at}` | 401 wrong OTP · 409 not-dispatched · GPS >200 m → `flagged:true`, delivery still completes (soft-flag, never hard-block) |
| `POST /v1/vendor/sync` | Sync | `{items:[{stop_id, version, fulls_given, empties_back, cash, upi, caps_missing, idempotency_key}...]}` | `{applied[], replayed[], rejected[{stop_id, code, message}]}` per-item | Per-item STALE_STOP/VALIDATION/PAYLOAD_MISMATCH; batch never fails whole |
| `GET /v1/vendor/earnings?shift=` | Earnings | `?shift=` optional | `{shift, stops_done, cash_total, upi_total, flagged_stops, flagged_hold, note}` | 401/403; flagged accrues but held out of payouts until admin clears |
| `POST /v1/complaints/{id}/verify` | Complaints | `{agree: bool, note ≤500}` | `{id, status, vendor_agree, vendor_note}` | 404 not-yours; agree→resolved auto, disagree→under_review + 48 h admin triage |
| `POST /v1/quality/{id}/vendor-check` | Quality | `{agree, check: seal/smell/visual, note}` | `{id, status: confirmed/disputed, ...}` | v1 words-no-photos; confirmed = strike + free redelivery/refund |

Deviations from contract: **none planned**. `pod_otp` is deterministic `pod_otp(order_id, route_date)` v1 (server TODO: random stored at dispatch) — app just forwards the customer-read OTP. Photo PoD deferred to v2 (no object storage v1) per contract §4.7 override of FR-20.

---

## 4. Visual system (hard constraints — no exceptions)

- **LIGHT MODE ONLY.** No dark mode (guardrails.md "dark mode ready" overridden — reason: doorstep sunlight legibility + low-end phones; logged as deliberate deviation).
- Canvas `#FFFFFF`; text ink `#111111`; muted `#595959`; primary buttons solid `#111111` bg + `#FFFFFF` text; links/active states water-blue `#0284C7` only (+ tint bg `#E6F3FA`); borders hairline `#E5E5E5`; radius **8dp**; danger `#B91C1C`; success `#15803D`.
- **NO** purple gradients, NO gradients at all (premium-design minimalist rule), NO emojis anywhere, **Material icons only**, NO glassmorphism on full surfaces.
- Typography: single sans (Roboto/system, user_app parity) — H 700 / sub 500 / body 400; body ≥16sp; Hindi-first copy with English fallback (follow `user_app` `authStringsHi` precedent: `Jars diye / Khaali wapas / Cash liya / Baaki`, `OTP bheja gaya`, `Sync baaki`).
- 8px grid; touch targets **≥48×48dp** with 8dp gaps (44px guardrail minimum, 48 chosen for gloves); single column mobile 360×800 first; content `max-width` full-bleed list (ops tool, not marketing page).
- Motion: `transform` + `opacity` only, 150–200 ms, `cubic-bezier(0.4,0,0.2,1)`; `prefers-reduced-motion` equivalent = disable shimmer on Android (`AnimationController` gated by `MediaQuery.disableAnimations`); no scroll-triggered reveals, no parallax.
- Tokens live in `lib/core/theme.dart` `ShodashaTheme` (mirrored from user_app) — no hardcoded colors in screens.

---

## 5. Wireframes / component trees (per screen, ASCII)

### S1 Login OTP — `features/auth/`
```
Scaffold (white)
 └─ Center Column (24px pad)
     ├─ Logo (assets/logo.png, 96dp) + "Shodasha Vendor" (H, #111)
     ├─ PhoneScreen: [+91 prefix | 10-digit field] (48dp, visible label "Mobile number / मोबाइल नंबर")
     │    └─ [OTP bhejein — black btn, disabled until 10-digit valid]
     ├─ OtpScreen: 6-box MaterialPinField (autofill, paste, error-shake) + masked "+91 ••••• XXXXX"
     │    ├─ 60s resend timer + 5-attempt force-resend + expired path
     │    └─ [Verify — black btn] → AuthController.confirm → SessionStore.save → /duty
     └─ States: loading (btn spinner) / smsError vs serverError vs networkError (distinct) / offline banner
```
ui-checklist applied: Login page (logo/title/identification, no third-party, no signup link — vendor accounts are admin-created) + Verifying Account flow + Showing Input Error (focus-loss only) + UX Copy (Hindi, one term per action).

### S2 Duty — `features/duty/`
```
AppBar: "Duty / ड्यूटी" + sync badge
 └─ DutyCard (white, 1px #E5E5E5, 8dp)
     ├─ Big Switch (48dp, active = #0284C7) "On duty / ड्यूटी पर"
     ├─ Capacity meter: "18/25 stops · 46/60 jars" (progress bar, blue fill)
     ├─ Custody meter: "Rs X in hand / हाथ में" (warn if nonzero overnight)
     └─ [Start route → /route] (black btn, disabled when off-duty)
States: loading skeleton → on/off confirm toast → 403 suspended = notice + appeal contact only.
```

### S3 Today route sheet — `features/route/`
```
Header (sticky): take-X fulls / expect-Y empties + progress "18/24 stops" + Sync pending (3) badge
 └─ ListView stops (seq order, 16px gaps)
     └─ StopCard (8dp, hairline): seq #, name, qty-due + empties-expected chips,
         cash-due (server paise → Rs), hold-limit block banner (Hindi + deposit-pay path),
         GPS pin + [Navigate] (internal only), status dot (pending/done/skipped/failed greyed)
     └─ SKIP section (paused/late, greyed, reason)
FAB/bottom: [Delivered + Next] persistent on stop, not here. Pull-to-refresh + skeleton + error-retry.
```

### S4 Stop detail — `features/stops/`
```
AppBar: Stop #seq + status badge
 ├─ CustomerCard: name, masked call btn (tel:), address + lift/gate note, exact GPS + map pin (flutter_map OSM, read-only)
 ├─ LedgerSnapshot (read-only, server values): held / deposit_balance / dues (paise→Rs)
 ├─ QtyDue: fulls_exp, empties_exp, cash-due arithmetic "Is baar Rs 86 + pichla Rs 0 = Rs 86"
 └─ [Start delivery → triple] (black btn; disabled with Hindi reason if HOLD_BLOCKED / version stale)
```

### S5 Triple commit — `features/stops/` (same screen flow, second step)
```
TripleSheet (single screen, above fold, one-hand):
 ├─ Steppers (48dp −/+): fulls_given | empties_back | caps_missing (M × Rs 3 live)
 ├─ Tender: cash + UPI split fields (paise ints; optional tendered/change_given, invariant tendered−change=cash)
 ├─ Bill preview (display-only): water + deposit_due + cap_charge = total
 ├─ [Confirm triple — black btn] → Idempotency-Key (uuid v4) + version → 409 STALE_STOP = pull-fresh toast + reason
 └─ Offline: queued badge "Sync pending", queued item persists crash-safe; double-tap never double-counts
```

### S6 PoD — `features/stops/`
```
PoDCard:
 ├─ Delivery OTP field (customer reads from their phone, 6-digit)
 ├─ empties_count + cash confirm + seal_ok checkbox ("Seal intact? / सील सही?")
 ├─ GPS capture (auto; >200 m → soft-flag note "review ke liye flagged, delivery complete")
 └─ [Complete delivery] → state dispatched→delivered; failed → [Reattempt] one-tap; seal broken → reject + quality incident
```

### S7 Sync status — `features/sync/`
```
SyncScreen: offline banner (connectivity_plus) + "Sync pending (N)" badge
 └─ Outbox list: per-stop {stop_id, version, payload summary, status: queued/sent/rejected}
     └─ Rejected row: code + Hindi message + [Retry with fresh version]
Auto-sync worker: on reconnect, POST /vendor/sync batch; server-wins on ledger; conflicts surfaced, never hidden.
```

### S8 Earnings — `features/earnings/`
```
EarningsCard: shift picker (today default)
 ├─ Stops done, cash_total vs UPI_total (server paise), pending to-collect
 ├─ Flagged-hold note: "Rs X hold par — admin clear ke baad payout" (flagged accrues, held out)
 └─ Payout proof: agency-bank UPI ref (read-only); salary-model vendors see per_stop_fee=0 + empty payouts (both coexist)
```

### S9 Complaints / Quality — `features/support/`
```
Tabs: Disputes | Quality
 ├─ DisputeCard: reason_code chip + 3-day window flag + rider note field + [Agree → resolved] / [Disagree → under review]
 └─ QualityCard: {agree, check: seal/smell/visual, note} at door/pickup; agree→confirmed, disagree→disputed + 48 h admin triage; user sees "under review", never silence
```

### S10 Profile — `features/profile/`
```
ProfileCard: name/vehicle/zone (read-only from /auth/me), language toggle (Hindi v1, English fallback)
 ├─ Training help (30-min learnable), WhatsApp support (+91 9302190067), call-TL
 └─ [Logout] (revoke own device only) + version + session role badge "vendor"
```

---

## 6. Architecture (design-patterns mobile card, user_app parity)

```
lib/
├── core/                     # mirrored from user_app (theme, api_client, session_store, auth_impls)
│   ├── theme.dart            # ShodashaTheme tokens (light-only, 8dp, #111/#0284C7/#FFFFFF)
│   ├── api_client.dart       # kApiBaseUrl via --dart-define=SHODASHA_API_BASE; Bearer + X-Device-Id + Idempotency-Key; 12s timeout; ApiException{code}
│   ├── session_store.dart    # SecureSessionStore (flutter_secure_storage; keys shodasha.access/.refresh/.role + device_id uuid)
│   └── auth_impls.dart       # AuthApi/PhoneVerifier/SessionStore seams (ApiBackedAuthApi + StubPhoneVerifier test-only)
└── features/{auth,duty,route,stops,sync,earnings,support,profile}/
    ├── <feature>_controller.dart  # ChangeNotifier, pure-Dart rules (no widgets)
    ├── <feature>_service.dart      # network boundary (ApiClient calls, DTOs, paise ints)
    ├── <feature>_repository.dart   # offline cache + outbox queue (shared_preferences/sqlite-lite; write-through)
    ├── <feature>_screen.dart       # renders only, one controller per screen
    └── components/                # feature-local widgets only
```

- Patterns named: **Layered Architecture** (always) + **Repository** (offline cache/outbox — exists because offline is a requirement) + **Service Layer** (API boundary) + **Adapter** (AuthApi/PhoneVerifier seams) + **DTO** (wire paise ↔ display Rs) + **State Machine** (stop pending→done/skipped/failed; order placed→…→delivered server-enforced) + **Singleton** (ApiClient/SessionStore via composition root `main.dart`).
- Dependency direction: screens → controllers → services/repositories → core. **Zero cross-feature imports.** No barrel `index.dart` files (user_app has none — direct imports; do not invent them).
- Minimal-code mandate: reuse `user_app` `core/` patterns by mirroring (not copy-paste dead code — no booking/catalog/checkout, no Razorpay unless vendor collects via gateway; COD + agency-QR first). New code only where vendor differs (version fence, outbox, GPS soft-flag).
- Request flow (triple): `TripleScreen → StopsController.commit() → StopsRepository.queueOrSend() → VendorService.postTriple() → ApiClient.send(POST /vendor/stops/{id}/triple + Idempotency-Key + version) → 200 stop / 409 STALE_STOP → controller maps to Hindi message → UI re-render + outbox badge`.
- Read flow: `Screen mounts → controller.load() → repository.list() → cache hit → show immediately (stale-while-revalidate) → background refresh → failure + no cache → error state with retry` (States.md per mutation: loading/success/error/empty/offline).
- Error & logging: centralized `ApiException{code}` (`NETWORK`, `STALE_STOP`, `HOLD_BLOCKED`, `PAYLOAD_MISMATCH`, `VALIDATION`); no swallowed errors; server timestamps authoritative (client clock informational); `X-Trace-Id` echoed.
- Production checklist: SecureStore tokens (never plain prefs); splash→session→deep-link; FCM token lifecycle per device (logout deletes own device only); offline banner + queued mutations + retry; lazy screens; a11y labels + font scaling + 48dp targets; env via `--dart-define`, never hardcoded.

---

## 7. UX rules for doorstep use (binding, from research synthesis)

1. **One-hand, one-tap triple**: 48dp −/+ counters for fulls/empties/cash above the fold; bulk-mode for apartments; double-tap never double-counts (idempotency).
2. **Sunlight-first contrast**: black-on-white, ≥16sp Hindi labels, no grey-on-grey, no color-only states; glanceable progress `18/24 stops · ₹ to-collect`.
3. **Gloves + low-end phones**: max 2 taps per stop, persistent bottom CTA, <1 s tap feedback, no heavy animations, no photo-mandatory v1.
4. **Hindi-first microcopy**: `Jars diye / Khaali wapas / Cash liya / Baaki`; OTP muscle-memory with autofill; English fallback only.
5. **Offline-proof confidence**: `Sync pending (N)` badge + auto-retry; no lost entries on crash; disable CTA until OTP+empties entered, with Hindi why.
6. **Cash-trust at door**: dues math on stop, partial UPI+cash split, instant WhatsApp receipt; per-shift earnings ticker.
7. **Fail gracefully, escalate fast**: no-answer → Failed→Reattempt one-tap; over-limit → Hindi reason + deposit path; dispute → rider note + 3-day flag; Call customer + Call TL, no chatbot maze.

---

## 8. Build plan (after approval only)

1. Scaffold: `flutter create --org com.shodasha --platforms android --project-name vendor_app apps/vendor_app` (applicationId `com.shodasha.vendor_app`, label `Shodasha Vendor`, fresh icons + fresh `google-services.json` from vendor Firebase project — user manual step, never committed).
2. Mirror `user_app` `core/` (theme/api_client/session_store/auth_impls) + `analysis_options.yaml` + `environment sdk: ^3.12.2` + pinned deps (`pin_code_fields: 9.4.0` exact, geolocator not permission_handler, flutter_map OSM).
3. Build features in order: auth → duty → route → stops (triple+PoD) → sync outbox → earnings → support → profile. Every mutation gets loading/success/error/empty/offline states.
4. Tests: widget/unit for controllers + offline outbox (idempotency replay, STALE_STOP, never-negative guard mapping).
5. Verify: `flutter analyze` zero issues, `flutter test` green, debug APK on `shodasha_api36` screenshot-verified login → duty → route → triple → PoD.
6. Commit on `007-vendor-app` only, conventional commits `feat(vendor): …`. Never commit secrets/`.env`/`google-services.json`.

---

## 9. Open items (need your answers — see clarifying questions)

OTP channel (Firebase vs server SMS Fast2SMS/TextBee per ADR-048/049) for vendor logins; google-services.json vendor project; per-stop fee vs salary (payout display); COD cap for vendor collection; skip-cutoff time; hold-limit default (3?); agency UPI QR source for bills; Sunday/holiday routing exclusion confirm; vendor suspend-appeal contact.

---

## 10. Compliance note

- Spec → Clarify → **Approve (HARD GATE — no app code before your explicit approval)** → Implement.
- Ponytail: shortest diff that works; reuse user_app patterns; no speculative abstractions; deletion over addition.
- Context sync on completion: `progress-tracker.md` + `flow.md` + `decision.md` (+ ADR-050 vendor kickoff).
