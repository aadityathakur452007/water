# 034 — Password auth, delivery-code lifecycle, customer state audit

Status: **APPROVED** (2026-10-22) — implementation started
Date: 2026-10-22
Target branch: `034-auth-password-delivery-otp`, cut from `033-donor-parity`
Scope surface: `workers/api` + `apps/user_app_donor` only
Untouched: `apps/user_app`, `apps/user_app_legacy_flutter`, `apps/vendor_app`, `apps/admin_app`, `main`

---

## 1. Goal

1. Replace customer auth OTP with **name + optional email + Indian mobile + password**.
2. Keep **only** the short-lived delivery-handoff OTP (the code the customer reads to
   the rider at the door).
3. Make the delivery code obey a real lifecycle: **valid 24h from dispatch, deleted
   on successful use, delivery failure/cancel, or expiry**, never guessable from the
   order id/date.
4. Audit every customer screen plus auth and delivery-code states against
   `States.md`, and fix the missing P0/P1 states.
5. Verify against the **local Python backend first**, then leave Cloudflare as the
   deployment target. Do not configure Firebase.

---

## 2. Locked decisions (from the user)

| Decision | Value |
|---|---|
| Customer identity | Indian mobile number (`+91[6-9]\d{9}`) |
| Customer proof | Password; no customer login OTP |
| Name | Required |
| Email | Optional |
| Existing preview accounts | No OTP migration or auto-claim. Use a new phone, clear preview customer rows, or admin reset. No real users exist. |
| Delivery OTP lifetime | 24 hours from dispatch |
| Delivery OTP deletion | On successful use, terminal delivery failure/cancel, or expiry (not on a single wrong code) |
| Backend verification | Local Python FastAPI first |
| Cloudflare | Deployment target; credentials/secrets later |
| App scope | `apps/user_app_donor`; keep `apps/user_app` as fallback |
| Staff/vendor/admin | Do not modify their apps |
| Git | Feature branch only; no `main` commits; no push |
| Code gate | No application code before explicit written approval of this spec |

---

## 3. Decisions that need sign-off

Recommended values are marked **R**. Each alternative changes the design materially.

### 3.1 Workers plan and password hashing

- **R — Workers Paid + PBKDF2-HMAC-SHA256 at 600,000 iterations.**
  - Python Workers run in Pyodide. `hashlib.pbkdf2_hmac` is not reliably available
    there; use WebCrypto `crypto.subtle.deriveBits` in Workers and
    `hashlib.pbkdf2_hmac` locally.
  - 600k iterations is roughly 200–300 ms of CPU, which exceeds the Workers Free
    10 ms CPU limit. Deploying password auth on Free will fail closed/hit CPU limits.
  - If the project must stay on Workers Free, password auth needs a different
    architecture (external auth service or a non-Workers auth endpoint). That is
    outside this spec.
- Alternative: lower iterations. **Rejected** — a runtime-selectable lower cost is a
  downgrade path and is weaker than current OWASP guidance.

### 3.2 Optional email validation

- **R — accept any valid email address.** Empty is allowed. Lowercase and trim.
  Max 254 chars. Email is a contact field, not an identity and not verified.
- Alternative: keep Gmail-only. Rejected — the current Gmail restriction is a donor-era
  constraint and the user asked for optional email, not a Gmail account.

### 3.3 Old app compatibility

- **R — fail closed.** `apps/user_app` and `apps/user_app_legacy_flutter` keep their
  source untouched. Their old `/auth/user/register` payload lacks a password and their
  OTP calls will receive `410 OTP_RETIRED`. They will not be able to sign in/register.
  This is accepted because there are no real users and the donor app is the target.
- Alternative: keep a legacy takeover-compatible register path. **Rejected** — it
  reintroduces the account-takeover hole (an existing phone gets a new session without
  proving anything).

### 3.4 Password recovery

- **R — support/admin reset only.** No self-service OTP, no security questions, no
  email reset link (no mail sender exists).
  - Add `POST /v1/admin/users/{user_id}/password-reset` (admin-only).
  - The admin sets a new password out-of-band; all of the user's sessions are revoked.
  - The customer app shows “Forgot password? Contact support” with the real support
    phone/WhatsApp action.
  - No admin UI change in 034 (admin app is out of scope); document the endpoint for
    support tooling. Admin app work is a follow-up.

### 3.5 Delivery-code replay after success

- **R — an owned completed stop returns the original outcome without the code.**
  The code is cleared on success, so the old implementation's “same code required for
  replay” would break offline outbox flushes. The authenticated vendor already owns the
  stop; replay writes nothing and returns `replay: true`.
- Alternative: retain a hash of the used code for replay. Rejected — extra secret
  retention with no customer benefit.

### 3.6 Delivery-code reissue

- **R — owner-only reissue from the app** when the current state is `expired`,
  `locked`, or `unavailable`.
  - Limit: 3 successful reissues per order per 24h, counted from audit rows.
  - Reissue mints a new random code, resets attempts, and starts a fresh 24h expiry.
  - Reissue writes an audit row and is available only while the order is
    `dispatched` with a pending stop.
  - `active` -> `409 CODE_ACTIVE`; no active stop -> `404`.
- Alternative: support-only reissue. Rejected for v1 because it creates a dead end when
  the code has expired at the door.

### 3.7 TTL start point

- **R — TTL starts when the order transitions `assigned → dispatched`.**
  - Assignment mints a code with `pod_otp_expires_at = NULL`; the customer may see it
    while assigned, but it cannot be used until dispatch.
  - Dispatch sets `pod_otp_expires_at = now + 24h`. If the stop has no code (legacy
    NULL row), dispatch mints one first.
  - Reassignment clears the failed stop's code and mints a fresh code for the new stop;
    its expiry starts at the new dispatch.
- Alternative: 24h from assignment. Rejected because a long pre-dispatch wait would
  expire the code before the rider leaves.

### 3.8 State-fix scope

- **R — fix all P0/P1 state gaps in this slice; P2 polish only when it is a one-line
  change.** P0 = auth takeover, password flows, delivery-code lifecycle, silent session
  expiry. P1 = the concrete gaps listed in §8.
- Alternative: auth/delivery only, leave state audit for 035. Rejected — the user
  explicitly asked for all customer screens plus auth/delivery OTP.

---

## 4. Boundary and non-goals

### In scope

- `workers/api` customer auth routes, auth service, user repo, migrations, delivery-code
  read/verify/reissue paths, scheduler, tests.
- `apps/user_app_donor` auth UI/controller/API seam, delivery-code UI/state, and the
  state fixes in §8.
- Local API smoke and Flutter E2E smoke against the local Python backend.

### Out of scope

- Firebase setup or Firebase client SDK.
- Real SMS auth OTP.
- Vendor/admin/legacy app source changes.
- Admin web UI for password reset.
- Payment gateway changes.
- Production Cloudflare deployment (after local verification; needs owner secrets).
- Full localization/Hinglish rewrite. Keep the current string style.
- Deleting the unused SMS/Firebase provider modules. The routes are retired; provider
  code is left for a separate cleanup pass to keep this diff reviewable.

---

## 5. Current state (verified)

### Auth

- `POST /v1/auth/user/register` currently requires name + **Gmail-only** email + phone;
  it finds an existing user by phone and **issues a session with no password or OTP**
  (`auth_service.user_register`). This is an account-takeover path.
- Customer login uses `/auth/otp/start` + `/auth/otp/verify`, with
  `upsert_phone_user` creating a user on verify. The donor app has no Firebase SDK;
  the default backend `OTP_PROVIDER=firebase` cannot complete.
- No `/auth/user/login` exists. No password column/hash exists.
- `normalize_phone` strips `+91`/`91` but **not** a leading `0`; route regex accepts
  `0`. Flutter's normalizer strips it, so backend and client disagree.
- Profile `PATCH /auth/me` still enforces Gmail-only email and a loose phone regex.
  Changing a phone to an existing number can hit a DB unique error instead of a clean
  409.
- `AuthGate` has no session-expiry notice. `forceLogout` silently returns to login.
- Logout copy still says “You will need your phone OTP to sign in again.”

### Delivery code

- `stops.pod_otp` is plaintext, with `pod_attempts`; no expiry column.
- Assignment/reassignment mints a random 6-digit code, but it lives until used or the
  stop dies.
- `order_service.detail` falls back to the deterministic `pod_otp(order_id, date)` when
  the stored code is NULL. That fallback is guessable and must not survive for active
  stops.
- `pod_complete` verifies with constant-time compare, locks after 5 failures, but:
  - has no expiry check;
  - keeps the code after success/failure/cancel;
  - requires the old code for completed-stop replay, so deleting the code would break
    replay;
  - has no reissue path.
- The scheduler does not purge stop codes.
- The customer UI shows a delivery code with no expiry, countdown, expired, locked, or
  used state.

### Customer states

Confirmed P0/P1 gaps:

1. `ApiException.isNetwork` conflates offline with 5xx (`api_client.dart:44`), so 5xx
   can show “No internet”.
2. `_SearchSheet` (`donor_shell.dart:423`) spins forever when catalog `rates` are null
   and there is an error; no retry.
3. Wallet defines `LedgerSnapshot.isEmpty` but `donor_wallet_screen.dart` always renders
   the deposit hero; payment-history error has no retry.
4. Profile has no loading skeleton and no retry when identity fails; it shows
   “Shodasha customer / Phone on file” before load.
5. Notifications only surfaces a subscription error; order-list errors disappear when
   other notes exist.
6. Address form does not validate the optional phone field.
7. Returns maps 401 to copy but the sheet has no sign-in/close action; success closes
   immediately instead of showing request id/SLA.
8. `AuthGate` does not tell the user that the session expired.
9. Delivery-code UI has no expiry/used/expired/locked states.
10. Stale OTP copy remains in auth strings, profile logout, and comments.

Subscriptions, support, payment history, booking checkout, address list/map, and rating
already have most loading/empty/error/retry states; they still need the 5xx-vs-offline
split and the state-matrix verification in §8.

---

## 6. Auth design

### 6.1 Canonical identity rules

One backend helper and one Flutter helper must agree:

- Strip whitespace and all non-digits for normalization only.
- Accept:
  - `9876543210` (10 digits)
  - `+91 98765 43210`
  - `91 98765 43210`
  - `0 98765 43210`
- Normalize to `+91` + 10 digits.
- Valid: `^[6-9]\d{9}$` after prefix removal.
- Reject other lengths, non-Indian prefixes, letters, and numbers starting `0–5`.
- Route DTOs keep the `+91|91|0` optional prefix but must never accept an invalid
  subscriber number after normalization. The service is the source of truth.
- Store canonical `+91XXXXXXXXXX` in `users.phone`, `addresses.phone`, and login keys.

The same rule applies to registration, login, profile phone changes, and the address
form's optional contact phone.

### 6.2 Password policy

- Length 8–128 characters. Count Unicode code points, not bytes.
- At least one letter and one digit.
- Do not trim passwords. Spaces and symbols are allowed.
- No breached-password list, no security questions.
- Client sends the password only over HTTPS in production; localhost is allowed for
  the local smoke.
- Client confirmation field is UI-only; the server never receives `confirm_password`.
- Server rejects with `400 VALIDATION` and field detail `{"password": "..."}`. The UI
  shows inline copy, not a raw server dump.

### 6.3 Password hashing

New module: `workers/api/src/app/core/passwords.py`.

- Algorithm: PBKDF2-HMAC-SHA256.
- Iterations: 600,000.
- Salt: 16 random bytes from `secrets.token_bytes` (local/Workers Python) or
  `crypto.getRandomValues` where needed.
- Derived key: 32 bytes.
- Encoding:
  `pbkdf2_sha256$600000$<base64url(salt)>$<base64url(dk)>`.
- Verify parses the encoded cost and salt, re-derives, and uses
  `hmac.compare_digest`.
- Workers path: WebCrypto `crypto.subtle.deriveBits` with `PBKDF2`, `SHA-256`.
- Local/tests path: `hashlib.pbkdf2_hmac`.
- Runtime selection must be explicit (`sys.platform == "emscripten"` / Workers
  detection), not a silent fallback to weaker parameters.
- Unknown phone/login with no password: verify against a fixed dummy hash so response
  timing does not reveal account existence.
- Never log the password, hash, salt, or derived key.
- `password_hash` must never appear in `_public_user`, `GET /auth/me`, error details,
  audit rows, or admin responses.

### 6.4 Schema and migration

New file: `workers/api/src/app/db/migrations/026_user_password.sql`.

```sql
ALTER TABLE users ADD COLUMN password_hash TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN password_updated_at TEXT;
```

- Existing customer rows keep `password_hash = ''`. They cannot log in.
- No backfill from OTP, Firebase uid, phone, or email.
- Registration is create-only. An existing phone returns `409 ACCOUNT_EXISTS`; it does
  not overwrite name/email/password and does not mint a session.
- Preview/local DB policy: no customer row is auto-claimed. Use a new phone, or clear
  the local preview customer rows, or use the admin password reset. There are no real
  users; this is intentional.

### 6.5 API contracts

#### `POST /v1/auth/user/register`

Request:

```json
{
  "name": "Asha Verma",
  "email": "asha@example.com",
  "phone": "+919876543210",
  "password": "correct-horse-9",
  "device": { "id": "device-abc" }
}
```

- `email` is optional; `null`, missing, or `""` -> stored as `""`.
- `password` is required.
- `device.id` is required.

Responses:

| Status | Code | Meaning |
|---|---|---|
| 200 | — | `access_token`, `refresh_token`, `token_type`, `role: "user"`, `user_id`, `new_device_alert`, `expires_at`, `details`, `verified: false` |
| 400 | `VALIDATION` | Field invalid; details name the field only |
| 409 | `ACCOUNT_EXISTS` | Phone already exists; no session; UI pivots to sign-in |
| 422 | `ROLE_RESERVED` | Phone belongs to vendor/admin |
| 429 | `RATE_LIMITED` | Includes `retry_after_s` |

- Rate limits: 5/phone/hour and 20/IP/hour, reusing `_limit_check`.
- Name: trimmed, 1–100 characters, not blank.
- Email: optional, lowercase, max 254, one `@`, a dot in the domain, no spaces.
- Phone: normalized as §6.1.
- Password: §6.2.
- Staff phone check happens before create; generic `ROLE_RESERVED` copy.
- Session creation reuses `_issue_session` (device cap, restrictions, new-device flag).

#### `POST /v1/auth/user/login`

Request:

```json
{
  "phone": "+919876543210",
  "password": "correct-horse-9",
  "device": { "id": "device-abc" }
}
```

Responses:

| Status | Code | Meaning |
|---|---|---|
| 200 | — | Same `_issue_session` fields (`access_token`, `refresh_token`, `token_type`, `role`, `user_id`, `new_device_alert`, `expires_at`, `details`); no client OTP state |
| 401 | `INVALID_CREDENTIALS` | Generic: wrong phone, wrong password, empty hash, or staff role |
| 429 | `RATE_LIMITED` | Includes `retry_after_s` |
| 400 | `VALIDATION` | Malformed phone/password/device |

- Rate limits: 5 login attempts/phone/15 min and 20/IP/hour. The existing windowed
  limiter is acceptable; a successful login does not reset the window.
- Never return “phone not found”, “no password set”, or “staff account”.
- For a staff row, even if a hash somehow exists, the customer endpoint returns generic
  401. Staff use their own access-code endpoints.
- Suspended users: after a correct password, issue a session with the existing
  `restrictions` payload so `GET /auth/me` can explain the suspension; writes remain
  blocked by `require_active_user`.
- No user is created here.

#### `PATCH /v1/auth/me` (changes)

- `phone`, when supplied, is required to be non-empty and normalized; changing to a
  phone owned by another user -> `409 PHONE_TAKEN`; changing to a staff number ->
  `422 ROLE_RESERVED`.
- `email`, when supplied, accepts empty or any valid email; no Gmail rule.
- `name`, when supplied, is trimmed and non-blank.
- Returned user still excludes `password_hash`.

#### Password reset

`POST /v1/admin/users/{user_id}/password-reset`

```json
{ "new_password": "new-temporary-9" }
```

- Admin role only; target must be a `user`.
- Validate the same password policy.
- Set `password_hash` and `password_updated_at`.
- Revoke all sessions for the user (existing `SessionRepo.revoke_user`).
- Write an audit row `user.password_reset` with the admin actor; no password/hash.
- Return `{ "ok": true, "sessions_revoked": <n> }`.
- No customer self-service endpoint in 034.

#### OTP retirement

- `POST /v1/auth/otp/start` -> `410 OTP_RETIRED`
- `POST /v1/auth/otp/verify` -> `410 OTP_RETIRED`

Both routes accept requests without body validation (so old clients get the explicit
410, not a Pydantic 400). The customer app removes all OTP calls. Demo login
`/auth/demo` remains server-gated for QA and is not a customer auth proof in prod.

### 6.6 Auth UI

Keep `login_screen.dart` and `DonorLoginScreen` to limit churn, add an internal mode:

- **Sign in (default):** mobile, password, “Sign in”, “Forgot password? Contact
  support”, “New here? Create account”, demo access (QA).
- **Create account:** name, optional email, mobile, password, confirm password,
  “Create account”, “Already have an account? Sign in”, terms line.
- Both: password visibility toggle, autofill hints, proper keyboard types and
  `TextInputAction`, inline validation, disabled fields/buttons while busy, spinner in
  the submit button, scrollable layout with keyboard inset.
- On `409 ACCOUNT_EXISTS` during signup: switch to sign-in mode, prefill the mobile,
  show “This number already has an account. Sign in.” Do not offer account claim.
- On `422 ROLE_RESERVED`: staff-number copy.
- On `429`: rate-limit copy and a visible wait/retry countdown using `retry_after_s`.
- On `401`: generic “Mobile number or password is incorrect.”
- On offline/5xx: split copy; retry keeps the typed values.
- On success: `AuthGate` swaps to the shell. No OTP step.
- Remove all “OTP”, “Gmail-only”, “verification code”, and “phone OTP” copy from auth,
  profile logout, comments, and tests.

`AuthController` / `AuthApi`:

- Replace `register({name,email,phone,device})` with
  `register({name,email?,phone,password,device})`.
- Add `login({phone,password,device})`.
- Remove `startOtp`, `verifyOtp`, `OtpStartResult`, OTP screen state and timers.
- Keep `demoLogin`.
- Add `forceLogout({bool sessionExpired = false})`; when true, set a one-shot
  `sessionNotice`. `AuthGate` passes the notice to the login screen and clears it after
  display. Manual logout shows no “expired” notice.
- On 401/403 from any authed call, `ApiClient.onUnauthorized` calls
  `forceLogout(sessionExpired: true)` once. It must not call an authed endpoint.
- `restoreSession` timeout still shows login; a restore failure shows a retry notice,
  not an infinite splash.

`ApiBackedAuthApi`:

- `register` -> `/auth/user/register` with password.
- `login` -> `/auth/user/login`.
- Delete `startOtp`/`verifyOtp` calls.
- Keep `_toSession` backstops for missing expiry.

### 6.7 Security controls

- Generic login errors; no account/role oracle.
- Constant-time password compare and dummy-hash verification.
- PBKDF2 parameters are server-side constants, never client-selected.
- Registration and login have DB-backed rate limits (`rate_counters` + L1).
- Passwords never go in URLs, logs, analytics, or crash reports.
- Admin reset is admin-only, audited, and revokes all sessions.
- The old deterministic `pod_otp(order_id, date)` is not part of auth; it is removed
  for active delivery stops in §7.
- No Firebase dependency is added.

---

## 7. Delivery-code lifecycle

### 7.1 State machine

| State | When | `pod_otp` | `pod_otp_expires_at` | Customer UI |
|---|---|---|---|---|
| `none` | before assignment, cancelled, failed, rejected | NULL | NULL | hide code |
| `active` | assigned, not yet dispatched | 6 digits | NULL | code shown; “ready at delivery” |
| `active` | dispatched, before expiry, attempts < 5 | 6 digits | dispatch + 24h | code + countdown |
| `expired` | dispatched, now >= expiry | cleared by scheduler or on read | retained as tombstone | “Code expired” + reissue |
| `locked` | attempts >= 5 | cleared | retained | “Too many wrong attempts” + reissue |
| `unavailable` | dispatched, no code present (legacy/race) | NULL | maybe NULL | “Code unavailable” + reissue |
| `used` | delivered | cleared | cleared | “Delivery complete”; no code |

Rules:

- Mint at assign/reassign: `secrets.randbelow(1_000_000)` formatted to 6 digits,
  zero-padded. Retry on collision within the same stop is unnecessary (random space
  with one active code per stop).
- TTL starts at the `assigned → dispatched` transition, not at mint.
- If dispatch finds a NULL code, mint first, then set expiry in the same transaction.
- Reassignment marks the old stop `failed` and clears its code, expiry, and attempts
  before inserting the new stop.
- Cancel/failure/rejection clears code/expiry/attempts for pending stops.
- Success clears code/expiry/attempts in the same write that marks the stop done.
- Expiry clears the secret but keeps the expiry timestamp as a tombstone so the UI can
  say “expired”. Reissue replaces both.
- Lockout clears the secret when the 5th wrong attempt is recorded; attempts stay at 5
  so the state remains `locked` until reissue.
- No deterministic fallback is returned or accepted for an active stop.
- The code is never logged, put in a URL, or included in list responses.
- Only the order owner sees it. Other users get `404` exactly like a missing order.

### 7.2 Schema and migration

New file: `workers/api/src/app/db/migrations/027_pod_otp_lifecycle.sql`.

```sql
ALTER TABLE stops ADD COLUMN pod_otp_expires_at TEXT;
CREATE INDEX IF NOT EXISTS idx_stops_pod_expiry ON stops(pod_otp_expires_at);
```

Backfill in the same migration:

- Active **dispatched** stops with a code and no expiry:
  `pod_otp_expires_at = strftime('%Y-%m-%dT%H:%M:%S+00:00', 'now', '+24 hours')`.
  There is no dispatch timestamp on legacy stops; migration time is the honest
  fallback and is documented. All new timestamps use ISO 8601 with `+00:00` so Dart
  and Python parse them as UTC, not local time.
- Active **assigned** stops stay `NULL`; dispatch starts their 24h.
- Rows whose expiry is already past: leave the timestamp, clear `pod_otp` (the
  scheduler also does this).
- Completed/cancelled rows: clear any remaining code.
- Never derive a code from order id/date.

### 7.3 Order detail / tracking contract

Add to `OrderDetailOut` and `tracking`:

```json
{
  "delivery_otp": "482910",
  "delivery_otp_expires_at": "2026-10-23T10:30:00+00:00",
  "delivery_otp_state": "active",
  "delivery_otp_reissue_available": false
}
```

- `delivery_otp` is `null` unless state is `active`.
- `delivery_otp_expires_at` is `null` for assigned/no-expiry, present for active
  dispatched/expired/locked.
- `delivery_otp_state` is one of `none|active|expired|locked|unavailable|used`.
- `delivery_otp_reissue_available` is true for `expired|locked|unavailable` while the
  order is `dispatched` with a pending stop.
- `used` is returned for a delivered order; `none` for cancelled/failed/pre-assignment.
- `stops_ahead` and `rider` behavior is unchanged.
- The list endpoint (`OrderOut`) does not include the code. The order card must not
  pretend it has one.

### 7.4 Reissue endpoint

`POST /v1/orders/{order_id}/delivery-code/reissue`

- Auth: order owner (`get_current_user`), not staff/admin.
- Allowed: order `dispatched`, pending stop, state `expired|locked|unavailable`.
- Not allowed: `active` -> `409 CODE_ACTIVE`; no pending stop -> `404`; other order
  state -> `409 STATE_CONFLICT`.
- Rate limit: 3 successful reissues per order per rolling 24h, counted from
  `audit_log` rows with action `order.delivery_code_reissue` and entity id = order id.
  Over limit -> `429 RATE_LIMITED` with `retry_after_s`.
- On success: new random code, `pod_attempts = 0`,
  `pod_otp_expires_at = now + 24h`, audit row, return the same four delivery fields.
- If the order has no pending stop, do not create one.
- No Idempotency-Key: each call intentionally mints a new code; the UI disables the
  button while busy and the rate limit bounds abuse.

### 7.5 Vendor verification

Update `VendorService.pod_complete`:

1. Load the owned stop, order, triple, code, attempts, expiry.
2. Completed-stop replay:
   - If the stop is `done` and `triple.pod` is set, return the existing outcome with
     `replay: true` **without requiring or comparing the code**.
   - No write, no attempt increment.
3. Active stop:
   - If attempts >= 5 -> `429 POD_LOCKED` (no code check).
   - If expiry is present and `now >= expiry` -> `410 DELIVERY_CODE_EXPIRED`.
   - If code is NULL -> `410 DELIVERY_CODE_UNAVAILABLE`.
   - Wrong code -> increment attempts; on the 5th failure clear `pod_otp`; return
     `404 NOT_FOUND` for wrong attempts 1–4 (no stop-existence oracle), then
     `429 POD_LOCKED` on the 5th and later.
   - Correct code -> transition order to delivered, mark stop done, clear
     `pod_otp`, `pod_otp_expires_at`, and `pod_attempts` in the same write.
4. Remove the deterministic `pod_otp` fallback for active stops.
5. Keep GPS soft-flag, cash, seal, and ledger behavior unchanged.

The vendor app is not modified. Its existing error handling should surface
`DELIVERY_CODE_EXPIRED`/`POD_LOCKED` copy as-is or through its generic error path; this
is verified in the local smoke, not by editing vendor code.

### 7.6 Scheduler

Extend `workers/api/src/app/jobs/scheduler.py`:

- New idempotent job `purge_pod_codes(conn)`:
  - `UPDATE stops SET pod_otp = NULL WHERE pod_otp IS NOT NULL AND pod_otp_expires_at IS NOT NULL AND pod_otp_expires_at <= now`.
  - Keep `pod_otp_expires_at` as a tombstone for the UI.
  - Clear codes on terminal stops (`done`, `failed`, `skipped`) regardless of expiry.
  - Never touch attempts/order state.
- Include the job in `run_all`/CLI output and return a count.
- Dry-run/import safety: the job is idempotent and safe to run repeatedly.

### 7.7 Delivery-code UI

`Order` model additions:

- `DateTime? deliveryCodeExpiresAt`
- `String deliveryCodeState` (default `none`)
- `bool deliveryCodeReissueAvailable`

Tracking (`tracking_screen.dart`):

- `active` with expiry: show code + “Expires in 23h 59m” (minute precision; recompute
  from the timestamp on resume, do not run a per-second timer for 24h).
- `active` without expiry (assigned): show code + “Rider will ask at delivery.”
- `expired` / `unavailable`: hide the digits; show copy + “Get new code” button.
- `locked`: hide digits; show “Too many wrong attempts” + “Get new code”.
- `used`: hide digits; show “Delivery complete — code used.”
- `none`: hide the whole chip.
- Reissue: busy spinner, disable repeat taps, update the order model from the response,
  show the new code, surface 429/409/offline/5xx inline.
- On 24h rollover while the screen is open, switch to expired locally and show the
  CTA; no polling required.
- Keep the code visually distinct (slate inset) but update the label from “DELIVERY
  PIN” to “Delivery code” consistently.
- `order_card.dart`: remove the code block from the list card (the list never returns
  it). The tracking screen
  is the single place that displays the secret.

---

## 8. Customer state audit

### 8.1 Method

- Walk every customer screen/route in `apps/user_app_donor/lib/features`.
- For each applicable `States.md` item, record handled / missing / not applicable.
- Fix P0/P1 first; do not invent data or fake success.
- Every network error must distinguish:
  - `NETWORK`/timeout -> offline copy + retry, offline strip.
  - 5xx -> “Server is having trouble” + retry, **not** offline.
  - 401/403 -> session-expiry login notice; no retry loop.
  - 429 -> rate-limit copy + wait.
  - 409 -> conflict copy with the next action.
- Every list has: initial, skeleton, loaded, empty, refresh, error+retry, and partial
  error (stale rows + inline banner).
- Every form has: default, focused, filled, inline validation, submitting/disabled,
  success, server validation, offline/5xx, and cancel/discard.

### 8.2 Global fixes

1. Split `ApiException.isNetwork`:
   - `isOffline => code == 'NETWORK'`
   - `isServerError => statusCode >= 500`
   - update every call site; 5xx no longer shows the offline banner.
2. Add a session-expiry notice (`AuthController.sessionNotice`) and show it on the
   login screen. Manual logout does not show it.
3. Add a shared “no internet — retry” inline pattern and a “server problem — retry”
   pattern; no duplicate per-screen wording drift.
4. Ensure the offline strip only appears for transport failures, not 5xx.
5. Remove all stale OTP copy.

### 8.3 Per-screen matrix

| Screen / flow | Required states | 034 work |
|---|---|---|
| Auth gate / restore | splash, timeout, restore failure, session expired, no session | add retry + expired notice; keep 5s timeout |
| Sign in | default, focus, filled, invalid, busy, 401, 429, offline, 5xx, success | new password UI/controller |
| Create account | default, focus, filled, optional email, validation, 409, 422, 429, busy, success | new password UI/controller; no claim path |
| Forgot password | no self-service; support action | dialog with call/WhatsApp |
| Home top bar / profile chip | loading, loaded, error+retry, no name | skeleton, no fake fallback |
| Featured products / catalog | loading, loaded, rates error+retry, offline, stale | verify; fix 5xx split |
| Search sheet | initial, typing, loading, no results, rates error+retry | fix infinite spinner; add retry |
| Booking / checkout | empty, rates loading/error, quote loading/error, address missing, stale quote, payment busy/success/failure, COD, offline, replay | verify; fix 5xx split; no local price math |
| Address list | loading, empty, loaded, error+retry, offline, delete blocked 409 | verify; 5xx split |
| Address form | default, focus, validation (label/pincode/line/map/phone), serviceability yes/no/unknown, GPS denied, save busy/success/error, discard | add optional phone validation + step gate |
| My orders | initial, skeleton, empty, loaded, search no results, refresh, error+retry, partial, pagination | verify; 5xx split; no code in list |
| Order card | active/closed, delivered/cancelled/failed, no code | remove fake code block |
| Tracking | loading skeleton, poll refresh, offline stale, error+retry, active/expired/locked/used code, reissue busy/success/error, cancel/reschedule busy/conflict, call/WhatsApp failure | add full delivery-code state machine + countdown + reissue |
| Bill | loaded, missing order/404, offline | verify |
| Rating | default, validation, submitting, success, duplicate/already rated | verify |
| Subscriptions | skeleton, empty, loaded, error+retry, partial, actions busy/conflict | verify; 5xx split |
| Plan builder | addresses loading/error, estimate loading/error, validation, submit busy/success/duplicate | verify; 5xx split |
| Wallet ledger | skeleton, empty (use `isEmpty`), loaded, error+retry, offline | add honest empty state |
| Recent receipts | loading, empty, loaded, error+retry | add retry; 5xx split |
| Payment history | loading, empty, loaded, error+retry, 401 | verify; 5xx split |
| Return sheet | address unavailable, UPI validation, busy, 401 action, offline/5xx, success | show request id/SLA success; add close/sign-in action on 401; 5xx split |
| Profile | skeleton, loaded, error+retry, stale+banner, edit validation/busy/success, addresses entry | add skeleton/retry; no fake identity; password logout copy |
| Edit profile | prefill, name required, phone required/normalized, email optional/any-valid, busy, 409 phone taken, 401 | update validation; 5xx split |
| Notifications | loading, empty, loaded, subscription error, order error, partial, refresh | surface both errors as banners; 5xx split |
| Support | skeleton, empty, loaded, error+retry, form validation, submit busy/success, offline | verify; 5xx split |
| Map picker | loading, permission denied, GPS unavailable, pin missing, save error | verify copy/retry |
| Global shell | online/offline/reconnecting/restored, slow, timeout, 5xx, 401 | offline strip only for transport; session notice |

### 8.4 P0/P1 acceptance

- No customer auth path creates an account or session without the password.
- No customer OTP can mint a session; both customer OTP routes return 410, and no OTP
  screen/client method/copy remains.
- Every delivery code shown has an expiry/used state and can be reissued when expired.
- A 5xx never renders the offline banner or “No internet” copy.
- A 401/403 always produces a visible sign-in-again notice and clears the local session.
- No screen shows fabricated identity, balance, order, rider, or success data.
- Every list/form has an explicit empty and error state with an action where the user
  can act.

P2 polish (spacing, extra animation, copy tone) is not part of 034 unless it is a
one-line change.

---

## 9. Testing

### 9.1 Backend

New/updated tests (pytest):

- `test_password_auth.py`
  - normalize `+91`, `91`, `0`, spaces, and invalid forms;
  - register success (optional email empty and valid), hash format, no hash in response;
  - duplicate phone -> 409, no session, original name/password unchanged;
  - staff phone -> 422;
  - login success, wrong password, unknown phone, staff phone, empty hash -> generic 401;
  - rate limits 429 with `retry_after_s`;
  - suspended user can authenticate and receives restrictions;
  - admin reset: 403 for non-admin, 404 missing user, hash changes, sessions revoked;
  - OTP routes -> 410;
  - old Gmail-only registration payload -> 400.
- `test_delivery_code.py`
  - assign mints code, dispatch sets 24h expiry;
  - owner detail/tracking returns code + state; other user 404;
  - expiry returns no code and `expired`; reissue works and resets attempts;
  - reissue rate limit 3/24h; active -> 409; non-dispatched -> 409;
  - wrong code increments, 5th locks, code cleared;
  - correct code clears code/expiry/attempts;
  - completed replay returns outcome without code;
  - cancel/failure clears code;
  - scheduler clears expired/terminal codes;
  - no deterministic fallback on a NULL active stop.
- Update `test_auth.py`, `test_e2e.py`, `test_sms_otp.py`, `test_orders.py`,
  `test_vendor.py`, `test_phase01_split2.py` expectations. Keep old tests only where
  they still describe non-customer internals; remove customer OTP route assertions.
- Migration/idempotence tests include 026/027.

Run from `workers/api`:

```powershell
python -m pytest -q
```

### 9.2 Flutter

- Update `test/auth_otp_test.dart` -> `test/auth_password_test.dart`.
- Update `test/login_screen_test.dart` for sign-in/create-account, validation, busy,
  401, 409, 429, offline.
- Add tests for:
  - delivery-code active/countdown/expired/reissue/used rendering;
  - wallet empty state;
  - profile skeleton and error retry;
  - notifications order-error banner;
  - search-sheet rates error retry;
  - address optional phone validation;
  - returns success panel + 401 action;
  - `ApiException.isOffline` vs `isServerError`.
- Run from `apps/user_app_donor`:

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

### 9.3 Local E2E smoke

1. Use a fresh temp DB and apply migrations.
2. Start the Python API on port 8787 (Flutter's default base) or pass a matching
   `SHODASHA_API_BASE`:

```powershell
cd workers/api
$env:PYTHONPATH='src'
$env:SHODASHA_DB_PATH='./data/034-smoke.db'
python -m app.migrate
python -m uvicorn app.main:app --port 8787
```

3. Bring up the donor app against the local backend on a connected target
   (Windows desktop or Chrome is available on this machine; Android emulator if
   present):

```powershell
cd apps/user_app_donor
flutter run -d windows --dart-define=SHODASHA_API_BASE=http://127.0.0.1:8787/v1
```

4. Smoke path:
   - create a fresh account (name + optional email + mobile + password);
   - sign out and sign in with the same mobile/password;
   - confirm the wrong password gets the generic 401;
   - browse catalog;
   - add an address;
   - place a COD order;
   - assign + dispatch it through the admin API/seed;
   - open tracking; code visible with expiry state;
   - reissue after forcing expiry;
   - verify the old code is rejected and the new code completes the stop;
   - confirm the code disappears and replay returns the outcome;
   - confirm a 5xx/offline state shows the correct copy (point the base URL at a dead
     port for the offline variant).
5. If Windows/Chrome cannot run due to a platform plugin, fall back to the Android
   debug APK on an emulator/device and note it; do not fake a pass.

### 9.4 Manual/production gates

- Physical Android smoke and release signing remain open from 033.
- Cloudflare deployment requires owner secrets and Workers Paid. Do not deploy in 034
  without explicit approval.

---

## 10. Rollout and rollback

### Apply order

1. Back up the local/preview DB.
2. Apply `026_user_password.sql`.
3. Apply `027_pod_otp_lifecycle.sql`.
4. Deploy the API with the new routes.
5. Ship the donor app.
6. Keep `apps/user_app` as the fallback binary; do not rebuild it.

### Data

- Existing customer rows with no password are intentionally unusable; support can use
  the admin reset endpoint, or the local preview DB can be cleared.
- No OTP migration, no silent claim, no backfill from Firebase uid.
- Active delivered/dispatched stop codes are backfilled as described in §7.2.
- Migration logs contain no secrets.

### Rollback

- App rollback: reinstall the previous donor APK; it will fail against the new backend
  because OTP is retired. There is no old-app compatibility by decision.
- API rollback: restore the previous API build and DB backup. Do not re-enable
  deterministic delivery codes; if rollback is required, keep the 027 expiry column
  and old code path only under a verified maintenance window.
- No `main` commits and no push in 034.

---

## 11. Files expected to change

### Backend

- `workers/api/src/app/api/v1/auth.py` — register/login schemas, OTP 410 stubs.
- `workers/api/src/app/api/v1/admin.py` — password reset.
- `workers/api/src/app/api/v1/orders.py` — reissue route.
- `workers/api/src/app/services/auth_service.py` — password register/login, email,
  phone, reset.
- `workers/api/src/app/services/order_service.py` — delivery-code state, reissue,
  no fallback.
- `workers/api/src/app/services/vendor_service.py` — expiry/lock/replay/clear.
- `workers/api/src/app/services/dispatch_service.py` — mint/clear/expiry hooks.
- `workers/api/src/app/repositories/user_repo.py` — password columns, phone conflict.
- `workers/api/src/app/repositories/order_repo.py` — stop code lookup + state fields.
- `workers/api/src/app/schemas/orders.py` — detail fields.
- `workers/api/src/app/core/passwords.py` — new.
- `workers/api/src/app/core/errors.py` — 410/409 helpers if needed.
- `workers/api/src/app/jobs/scheduler.py` — purge job.
- `workers/api/src/app/db/migrations/026_user_password.sql` — new.
- `workers/api/src/app/db/migrations/027_pod_otp_lifecycle.sql` — new.
- Backend tests listed in §9.1.

### Donor app

- `lib/features/auth/login_screen.dart`
- `lib/features/auth/auth_controller.dart`
- `lib/features/auth/auth_gate.dart`
- `lib/core/auth_impls.dart`
- `lib/core/api_client.dart`
- `lib/main.dart` (session-expiry hook)
- `lib/features/orders/orders_controller.dart`
- `lib/features/orders/order_card.dart`
- `lib/features/orders/tracking_screen.dart`
- `lib/features/wallet/donor_wallet_screen.dart`
- `lib/features/wallet/wallet_controller.dart`
- `lib/features/wallet/payment_history_screen.dart`
- `lib/features/profile/donor_profile_screen.dart`
- `lib/features/profile/edit_profile_sheet.dart`
- `lib/features/profile/profile_controller.dart`
- `lib/features/addresses/address_screen.dart`
- `lib/features/home/notifications_screen.dart`
- `lib/features/shell/donor_shell.dart`
- `lib/features/returns/return_sheet.dart`
- `lib/features/returns/returns_controller.dart`
- `lib/features/booking/booking_controller.dart` (and call sites using `isNetwork`)
- Flutter tests listed in §9.2.

### Docs/context after implementation

- `Feature_docs/user-app-donor/spec.md` — link 034 and note accepted auth/delivery
  deviations.
- `context/progress-tracker.md`
- `context/flow.md`
- `context/decision.md` — append decisions: password hashing/Workers Paid, optional
  email, OTP retirement, delivery TTL/reissue/replay, state-fix scope.

---

## 12. Acceptance criteria

- [ ] Customer can register with name + optional email + Indian mobile + password.
- [ ] Customer can sign in with mobile + password; wrong/unknown/staff credentials are
      generic 401s.
- [ ] No customer OTP can mint a session; both OTP routes return 410; no OTP screen,
      client method, or stale auth-OTP copy remains.
- [ ] `POST /auth/user/register` is create-only; an existing phone gets 409 and never a
      session.
- [ ] Password hashes use the documented PBKDF2 format; no password/hash is returned or
      logged.
- [ ] Admin password reset works, is audited, and revokes all sessions.
- [ ] Delivery code is minted at assignment, expires 24h after dispatch, is deleted on
      success/failure/cancel/expiry, and never uses the deterministic fallback.
- [ ] Expired/locked/unavailable codes can be reissued by the owner; old codes fail.
- [ ] Completed-stop replay works without the code.
- [ ] Customer tracking shows active countdown, expired, locked, unavailable, and used
      states.
- [ ] 5xx is never rendered as offline; 401/403 always returns to login with a visible
      notice.
- [ ] Wallet empty, profile skeleton/retry, notifications double-error, search retry,
      address phone validation, and returns success/401 states are fixed.
- [ ] Backend pytest green; Flutter analyze/test/build green.
- [ ] Local E2E smoke passes against the Python API on the local network.
- [ ] No changes to `apps/user_app`, `apps/user_app_legacy_flutter`, `apps/vendor_app`,
      `apps/admin_app`, or `main`; no push.
- [ ] `progress-tracker.md`, `flow.md`, and `decision.md` updated.
- [ ] Commit(s) on `034-auth-password-delivery-otp` only.

---

## 13. Approval

Reply with **APPROVED** to accept this spec as written, or list the specific changes
you want (especially §3.1 Workers Paid, §3.3 old-app failure, §3.4 admin-only reset,
§3.6 reissue, and §3.7 TTL start). No code will be written until that approval is
explicit.
