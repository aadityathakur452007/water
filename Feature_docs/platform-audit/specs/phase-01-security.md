# Phase 1 — Security (authorization, sessions, webhooks, PoD, adjudication)

- **Goal**: close every privilege-escalation and money-forgery path; backend enforces all boundaries (frontend hiding is never the enforcer).
- **Workstreams**: W1a backend authz+session+webhook · W1b admin/vendor web guards+cookies (disjoint files — parallel-safe). W1a owns `workers/api/src/app/**`; W1b owns `apps/admin_app/src/server/*` + guards. Contract between them: worker returns 401/403 with `{error:{code}}`; BFF maps to login redirect (401) vs access-denied card (403) — never renders admin chrome for non-admin.

## 1.1 Suspended-write bypass [P0-6] (Track A F-001, code-conclusive, test-missing)

- **Evidence**: `orders.py:63-106` (all 5 handlers) + `addresses.py:63-92` (all 4) depend on `get_current_user` only; `OrderService`/`AddressRepo` never re-check `suspended`. Suspended principal creates/cancels/reschedules orders and mutates addresses, defeating §14.1. Contrast correct: payments/returns/subs/complaints/ratings/devices use `require_active_user`. Only `test_auth.py:366` covers PATCH /me — no suspended-write test exists.
- **Fix**: swap those 9 write handlers to `require_active_user`; reads stay on `get_current_user`.
- **Tests**: suspended session → POST /orders|/cancel|/reschedule|/addresses* → 403 + zero rows; active user unaffected; suspended reads still 200.
- **Also**: `devices.py:55` DELETE on `get_current_user` → same swap (minor).

## 1.2 Any-role write surface [P1] (Track A F-002, code-confirmed, test-missing)

- **Evidence**: `payments.py:43-59` (upi-intent, cod-confirm), `returns.py:57-59`, `subscriptions.py:47-50`, `orders.py:63-70` accept any authenticated role — a vendor session mints UPI intents/COD confirms/subscriptions/returns/orders as itself. Order-bound reads still 404 at service layer (blast radius capped), but cross-principal money-adjacent writes exist.
- **Fix**: add `require_vendor_block` semantics — user-surface writes require `role=='user'` (new dep `require_role("user")` on orders/returns/subscriptions create + payments intent/cod-confirm). Vendor MUST see spec matrix: vendor money moves only via owned-stop `cash_post`.
- **Tests**: role matrix — vendor token on each → 403 + zero rows; user happy paths green. (Fills the "no role-varied test" gap explicitly.)

## 1.3 Cookies without httpOnly [P1] (Track S1 F9)

- **Evidence**: `admin-session.ts:34-38` COOKIE_FLAGS lacks `httpOnly`; all 4 setCookie sites inherit. XSS → `sh_session`/`sh_refresh` theft. BFF keeps tokens server-side already, so nothing breaks.
- **Fix**: add `httpOnly: true` to COOKIE_FLAGS (both admin + vendor session fns share it).
- **Tests**: login sets `HttpOnly` attribute (assert Set-Cookie string); guard flows unchanged.

## 1.4 Dead admin logout + presence-only guards [P1] (Track D A1/A5)

- **Evidence**: `logoutServer` zero call sites; `account-switcher.tsx:84-87` dead item; `dashboard/route.tsx:28-39` gates on cookie presence — vendor cookie renders full admin sidebar then per-card 401/403.
- **Fix**: wire logout item → `logoutServer` (clear cookies + worker revoke, mirror vendor `profile.tsx:90-93`); dashboard guard: after presence check, role-assert via a cheap admin read (or worker `/me` role) → non-admin bounces to `/auth` with access-denied copy (no shell render). Vendor guard symmetric (already correct pattern — keep).
- **Tests**: vendor cookie on `/dashboard/*` → redirect, zero admin widgets rendered (assert no sidebar request fires).

## 1.5 Webhook fail-closed [P0-3] (Track B P0-2)

- **Evidence**: `FakeUpiProvider.verify_webhook` (`upi.py:96-109`) ignores signature/timestamp/nonce, approves everything except `DECLINE*`; route has no session auth (`payments.py:50-54`); `get_provider` defaults fake (`upi.py:174-178`); prod vars absent (`wrangler.jsonc:20-27`). Any authed user knowing their `provider_ref` flips own order `paid_upi` + zero dues. Shape proven by `test_router_webhook_no_auth_and_admin_claim` (pays without signature).
- **Fix**: default-deny — refuse `fake` provider when `APP_ENV=prod` (raise `UpstreamError` in `get_provider`); require `UPI_WEBHOOK_SECRET` at boot in prod. Owner provisions (per answers): `UPI_PROVIDER=razorpay` + `UPI_KEY_ID/SECRET/WEBHOOK_SECRET/AGENCY_UPI_VPA` as Cloudflare secrets (never git); code documents required names in `.env.example` + wrangler comments only.
- **Tests**: prod-env fake → 502; unsigned callback → 401/422, no ledger write; signed happy path (existing tests) green.

## 1.6 PoD OTP random + attempt cap [P0-8] (Track A F-004)

- **Evidence**: `pod_otp = sha256(order_id:route_date)%1e6` (`vendor_service.py:66-72`, own TODO `:69`), disclosed in owner detail, accepted with no attempt limit (`:347-350`).
- **Fix**: complete the documented TODO — random per-order OTP stored at dispatch (new nullable col on stops, backfill NULL = legacy deterministic for in-flight); per-stop attempt counter + lockout after 5 fails (DB-backed, not isolate memory); wrong-OTP responses indistinguishable from unknown-stop (no oracle).
- **Tests**: computability test (observer with order id cannot derive); 5-fail lockout; legacy NULL rows still completable during migration window.

## 1.7 Vendor adjudication downgrade [P0-9] (Track E §4, argued from code)

- **Evidence**: vendor `agree=True → status="resolved"` in one call (`vendor_service.py:599-604`), note optional (`VerifyIn.note=""`), no evidence/amount check, no countersign; notice copy promises "redelivery/refund jaari" (`support_controller.dart:62-64`). Vendor judges a dispute it is party to, on records it wrote via triple. Quality `agree → confirmed` same unilateral shape (`:639-640`).
- **Fix**: vendor `agree` → `vendor_confirmed` (+ mandatory note ≥10 chars) + admin release step to `resolved`; disagree path unchanged (`under_review`). Admin resolve stays the only `resolved` writer.
- **Tests**: vendor agree → status `vendor_confirmed`, not resolved; admin release → resolved + audit; direct-to-resolved impossible for vendor role.

## 1.8 Vendor refresh device mismatch [P1] (Track D P1)

- **Evidence**: login mints `device_fp="vendor-web"` (`vendor-session.ts:30`) but guards refresh with `device:{id:"admin-web"}` (`admin-session.ts:95-98`) while `refresh()` rejects `device_id != device_fp` (`auth_service.py:516-517`). Vendor web dies ~30m after login despite valid 7d cookie. Admin path matches — unaffected.
- **Fix**: vendor guard refreshes with `device:{id:"vendor-web"}` (mirror the login device id); add constant `VENDOR_WEB_DEVICE` shared by both fns.
- **Tests**: mint-as-vendor → refresh-as-vendor → 200 + rotation; cross-device refresh → 401 (existing pin preserved).

## 1.9 Exit criteria

- [ ] 9 handler swaps + role gates + httpOnly + logout + guards + webhook guard + OTP store + adjudication + refresh device — all with tests above, pytest green
- [ ] Security re-sweep of S1 F1–F16: each marked FIXED (with test) or carried to a later phase with reason
- [ ] No new packages; no D1 prod writes without owner go-ahead
