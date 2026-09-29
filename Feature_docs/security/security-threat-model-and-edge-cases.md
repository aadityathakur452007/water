# Shodasha Mineral Waters — Security Threat Model, Edge Cases & Production Readiness

> Skill: `ssdlc` (`.agents/ssdlc/SKILL.md`) — STRIDE + OWASP Top 10 + 7-phase gates applied.
> Stack: 2× Flutter Android (user + vendor) + Next.js Super Admin web + **FastAPI (Python) on Cloudflare Workers** + **Cloudflare D1 (SQLite)** + **Firebase Auth phone OTP + FCM push**.
> Terminology fix (honest): **FCM does NOT verify OTPs.** Firebase **Auth (phone)** verifies OTPs; **FCM** delivers push (order accepted, rider arriving, skip reminders). This doc uses that split everywhere.
> Status: spec — no app code yet. Each SEC/EC row has acceptance criteria for Phase-2 build.

## 1. Data classification + trust boundaries

| Class | Examples | Handling |
|-------|----------|----------|
| PII | phone, name, home/office GPS + address, FCM tokens | TLS, D1 least-privilege, never in logs, redacted in admin exports |
| Credentials | OTP hashes, session/refresh tokens, admin password hash (argon2id) | hashed, short TTL, rotation, never returned to client |
| Money | order totals, deposits (Rs 150/jar), dues, UPI refs | server-computed only, idempotent, audited |
| Internal | jar ledger internals, margin, other users' orders, raw audit rows | admin/vendor-role only, never to user app |

Trust boundaries: Flutter apps (untrusted) → Workers API (enforces authz) → D1 (trusted store) → Firebase Auth/FCM + UPI (third-party, verify server-side). **Never trust role, price, qty, or address from the client.**

## 2. Auth: OTP login, sessions, FCM (SEC-A series)

Design: phone → Firebase phone OTP verify → Workers mints session (D1 `sessions`: token hash, user_id, role, device fingerprint, expires) → Flutter keeps token in **Secure Storage** (never plain prefs), web uses **HttpOnly cookie**. Short-lived access (30 min) + rotating refresh (7 d). Every non-public endpoint checks token + role **in the service layer**.

| ID | Scenario / attack | Mitigation + acceptance |
|----|-------------------|-------------------------|
| SEC-A01 | OTP brute force (6-digit guess) | Max 5 attempts/code, 5-min expiry, exponential resend cooldown (30s→2m→10m). 6th fail burns code. Test: 6th guess rejected even if correct. |
| SEC-A02 | OTP resend / SMS-pump abuse | Per-phone 5/hr + per-IP 20/hr + per-device 10/day rate limits (Workers KV/edge). Cost alert on Firebase Auth spend spike. |
| SEC-A03 | Non-Indian / malformed numbers | E.164 allowlist: default `+91` + 10 digits starting 6–9 (Pydantic regex). Non-+91 → explicit "launch region: India only" error, logged, **no OTP sent**. International = v2 decision, not silent accept. |
| SEC-A04 | Dummy / wrong email (admin seed, bills) | Email optional for users; where required (admin, receipts): format + MX check at entry, verification link before use. `test@test`, `abc@xyz` → rejected with reason; never written as verified. |
| SEC-A05 | SIM-swap / stolen phone | Refresh rotation + device fingerprint bind; new device → fresh OTP + FCM "new login" alert to old token; admin can revoke all sessions per user. |
| SEC-A06 | Token theft (localStorage/XSS on web) | Web tokens **HttpOnly Secure SameSite=Lax cookies only**; Flutter Secure Storage. Tokens carry `iss/aud/exp`; leaked-token replay window ≤30 min. |
| SEC-A07 | FCM token abuse (push to others) | FCM tokens stored per-user+device, overwritten on login, deleted on logout. Push send = server-side Firebase Admin SDK with user lookup — **never accept target UID from client**. |
| SEC-A08 | Fake Firebase ID tokens | Workers verifies Firebase ID token signature + `aud` (project id) + `exp` on every auth call via Admin SDK / JWKS. Unverified token = 401, no D1 write. |

## 3. Input validation at every boundary (SEC-I series, Pydantic everywhere)

| Field | Rule | Reject examples |
|-------|------|-----------------|
| phone | `^\+91[6-9]\d{9}$` | `+91 123`, `999`, `+1 555…`, alphabets |
| email (optional) | RFC format + verify-before-trust | `a@b`, `test@test.com` unverified |
| pincode | `^[1-9]\d{5}$` + serviceability check | `000000`, out-of-zone → "not served yet" |
| GPS | lat −90..90, lng −180..180, accuracy ≤100 m else warn | (0,0) null-island, mocked-location flag → require map-pin confirm |
| qty/address/notes | int ranges (see §4), 500-char cap, Unicode-safe, no HTML | `<script>`, 10 MB strings, null bytes |

SQL: **parameterized D1 queries only** — string-concatenated SQL is a ship-blocker.

## 4. Order limits, bulk policy, tanker path (EC-O series — user's core ask)

Household reality: 1–2 jars/order. Bulk without checks = deposit fraud + delivery failure + COD default risk.

| ID | Rule | Behaviour |
|----|------|-----------|
| EC-O01 | Home address: qty 1–5, auto-accept | Normal flow. |
| EC-O02 | Home qty 6–10 | **Soft-stop**: "Ordering 6+ for home? Confirm or split." Requires explicit confirm + COD cap check. Logged as anomaly. |
| EC-O03 | Home qty >10 | **Hard-stop**: suggest **tanker** option / "Call vendor to verify" CTA (tap-to-call + vendor callback ticket). Order stays `needs_verification`, never dispatches silently. |
| EC-O04 | Office address: qty up to 30, SKUs mixed (with/without container) | Allowed **only** on `address_type=office` + GST-optional + vendor accept step. Over 30 → same tanker path. |
| EC-O05 | Hundreds of jars (fat-finger / abuse) | UI stepper cap (99) + server cap enforced independently. >cap → 422 + tanker upsell + admin alert. Client cap alone is **not** a control. |
| EC-O06 | COD exposure cap | COD orders >Rs 2,000 (tunable) require advance UPI partial or vendor confirm. Prevents cash-default bulk. |

Acceptance: server rejects over-limit even with tampered client; each block emits admin-visible event with trace id.

## 5. Addresses: home/office + Google Maps GPS (EC-G series)

- `address_type`: `home | office` (office unlocks bulk policy + container-mix SKUs + invoice fields).
- Save flow: GPS fix → reverse-geocode (Google Maps Platform) → user confirms pin + house/flat + landmark → `place_id + lat/lng + formatted + pin` stored. No raw free-text-only delivery address.
- Spoofing: mock-location / low-accuracy → "confirm on map" forced; out-of-service polygon → graceful "not served yet + notify me" (lead saved, no fake order).
- Privacy: exact GPS visible to **assigned vendor only** during active window; admin sees zone-level by default, exact on drill-down (audit-logged).

## 6. Subscriptions / autopay + skip-today (EC-S series)

| ID | Scenario | Handling |
|----|----------|----------|
| EC-S01 | Daily auto-delivery ("send 2 jars every day to home") | Subscription object: qty, SKU mix, address, window, payment method on file (UPI mandate intent; COD allowed with vendor confirm). Next-run preview + cancel-anytime. |
| EC-S02 | "Don't send today" | One-tap skip before cutoff (e.g. 9 PM prior day). Vendor route sheet next morning shows **SKIP list** (greyed, no dispatch). Late skip → `late_skip` + vendor call button, no silent no-show. |
| EC-S03 | Pause range (vacation) | Date-range hold (Bisleri pattern, E1): auto-resume date; FCM reminder day before resume. |
| EC-S04 | Autopay failure | Order stays `payment_pending`, no dispatch, retry link + COD fallback offered. Never negative-ledger or free-dispatch on failed mandate. |
| EC-S05 | User cancels after dispatch | State machine decides: pre-dispatch → free cancel; dispatched → cancel creates vendor callback + return-fee rule shown **before** confirm (quote-lock principle). |

## 7. Vendor-side failures (EC-V series)

| ID | Scenario | Handling |
|----|----------|----------|
| EC-V01 | Vendor never receives order (push lost / offline) | FCM + in-app polling fallback; vendor queue is server source of truth. Unacknowledged order escalates (re-push → SMS/vendor call → reassign) with SLA timer visible in admin. |
| EC-V02 | Vendor offline at stop | Offline-first queue: triple (fulls/empties/cash-UPI) cached, synced on reconnect with conflict rule (server wins on ledger, vendor wins on PoD photo/OTP). No silent drop — pending-sync badge. |
| EC-V03 | Delivered but marked failed (or vice versa) | PoD = OTP + photo + empties count. State transitions append-only; reversal needs reason code + admin-visible entry. |
| EC-V04 | Empty-jar dispute (cap missing, brand mismatch) | Rs 3/jar cap rule + photo evidence at door; deposit math `(N−E)×150` recomputed server-side, shown to both sides. |

## 8. Payments: UPI + COD (SEC-P series)

- **Quote lock**: price computed server-side at booking; surge/quote changes **before** booking only, never after (A1 rule). Client-sent totals ignored.
- **Idempotency**: `Idempotency-Key` header on POST /orders + UPI verify; double-tap / retry never double-charges or double-creates (unique key → same order id).
- **UPI verification**: verify transaction ref server-side (provider callback/signature), amount + payee match; `pending` UPI ≠ paid.
- **COD**: collected amount entered by vendor, reconciled in evening sheet; partials carry forward as dues — never silently zeroed.
- **No price/file manipulation**: SKU rates from server catalog; no client-provided discounts.

## 9. Fraud & abuse: device farms, multi-accounts (SEC-F series)

User's scenario (many names/numbers, one device) is real (referral/deposit abuse).

| ID | Control |
|----|---------|
| SEC-F01 | Device fingerprint (per-device id, not PII alone) + max 3 verified accounts/device/30 d; 4th → manual review queue. |
| SEC-F02 | Same-device rapid OTP cycling → step-up (cooldown + admin flag). |
| SEC-F03 | Emulator/root/tamper signals (Play Integrity on Android) → block payment actions, allow browse. |
| SEC-F04 | Referral/deposit farming: first-order deposit + device + phone graph checks; rewards stay **v2** so v1 has nothing to farm. |
| SEC-F05 | Rate limits on auth, orders, complaints per user/device/IP; 429 with `Retry-After`, all hits in admin abuse dashboard. |

## 10. Secrets, config, access control (SEC-C series — blocking gates)

- **No hardcoded secrets**: Firebase keys, D1 bindings, UPI provider secrets via Workers vars/secrets + `.env` gitignored + `.env.example` placeholders. CI scans (`gitleaks`) — hardcoded key = ship-blocker.
- **Env separation**: dev/staging/prod bindings never shared; prod secrets rotated on personnel change + incident.
- **RBAC enforced server-side**: `user < vendor < admin`; role from session/DB, never client header. Every endpoint: authenticate → authorize (ownership/role) → validate → act.
- **IDOR**: `/orders/{id}` checks owner/assignee/admin; enumeration (id+1) returns 404-not-yours, same shape as missing (no oracle). Internal fields (margin, others' PII, raw audit) stripped from user/vendor responses.
- **CSRF/XSS/CORS**: web mutations SameSite cookie + CSRF token; output escaped, no raw HTML; CSP + `X-Content-Type-Options` + `X-Frame-Options`; CORS allowlist (admin web + localhost dev) — never `*` on credentialed routes.
- **RF ("access rf")**: treat as **CSRF + request forgery** — covered above + webhook signature verification (UPI/Firebase callbacks HMAC-checked, timestamp window).

## 11. Graceful errors, no corruption, progress saved (EC-R series)

- Client errors generic ("Something went wrong, ref #abc123"); details server-side only.
- **Transactions**: order create + ledger + dues in one D1 batch — partial failure rolls back, never half-written money.
- **Resume**: booking draft (SKU/qty/address/window) persisted locally + server draft id; crash → "Resume order?" restores to last confirmed step.
- **Offline vendor**: queued ops with visible pending state; conflicts resolved by rule (§7), surfaced to admin.
- **Fuzz-tested inputs**: Unicode, 10k-char notes, null bytes, malformed JSON → 422 with field errors, no 500/stack-leak.

## 12. Super Admin observability (what admin sees that users never do)

- Audit log: who/what/when/trace-id for auth events, order states, money/deposit edits, admin actions (append-only).
- Dashboards: OTP fail spikes, 429 hits, over-limit blocks, skip/cancel rates, COD pending, unacknowledged vendor orders, payment pending aging.
- PII redaction in logs/exports; exact GPS + phone masked by default, drill-down audited.
- Incident runbook link: revoke sessions → rotate secrets → rollback Worker → notify.

## 13. Production-readiness checklist (gates — all must pass)

- [ ] SAST (Semgrep/CodeQL) + SCA (`pip-audit`, Dependabot) clean; lockfile pinned; no debug routes.
- [ ] DAST (ZAP baseline) on staging for login/OTP/order/pay/admin paths; abuse test cases (expired token, wrong-owner, tampered total, oversize, rate-limit) in suite.
- [ ] TLS/HSTS/helmet headers, CORS allowlist, edge rate limits + body-size caps verified.
- [ ] Secrets via Workers secrets, rotation tested; backup/restore of D1 tested.
- [ ] Monitoring + alerts (auth fails, 5xx, payment pending age, vendor SLA) wired to admin.
- [ ] Load test: OTP burst + morning route-assign burst; D1 write contention measured.
- [ ] Privacy: retention/erasure policy (OTP rows purged, logs TTL) documented.

## 14. Open items for Phase-2 spec

1. Confirm Firebase plan: **Auth (phone) + FCM** SKUs and sender-id allowlist.
2. Tunables to lock after survey: bulk caps (5/10/30), COD cap (Rs 2,000?), skip cutoff time.
3. Tanker partner flow (redirect vs in-house) for EC-O03 overflow.
