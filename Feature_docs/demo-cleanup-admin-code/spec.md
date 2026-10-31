# Spec — Demo Data Removal + Admin Access-Code Consolidation

- **Date:** 2026-10-31
- **Status:** Implemented — approved 2026-10-31 (branch `036-demo-cleanup-admin-code`)
- **Branch (proposed):** `036-demo-cleanup-admin-code`
- **Owner request:** remove demo data from the donor/vendor frontends, resolve the two-D1-database question, and leave one working admin access code for admin phone `+917828442476`.

## 1. Problem

1. The Cloudflare account shows two D1 databases (`shodasha`, `shodasha-staging`). The owner believes one is a dummy duplicate.
2. The donor and vendor apps still expose a demo-login door and prefilled QA credentials even though the production demo door is already closed server-side.
3. Production has two admin access-code rows. One is live, one is already revoked; neither is the owner-requested code.

## 2. Verified findings (read-only, 2026-10-31)

| Item | Evidence | Verdict |
|---|---|---|
| `shodasha` (D1 `da762aad-1d5c-46eb-992e-acc79505cc95`) | 737,280 B; 28 migrations; 10 users, 11 orders, 1 stop, 1 subscription; bound to Worker `water` at `https://water.adityathakur452007.workers.dev` | **Production — keep** |
| `shodasha-staging` (D1 `05772775-a957-4852-8ec3-6b14082d4a62`) | 14,462,976 B; 28 migrations; 1,112 users, 10,009 orders, 3,005 payments, 1,000 addresses/subscriptions, 801 stops; bound to Worker `water-staging`; created 2026-10-25 for Phase 0/3 performance work | **Staging/test bench — not a dummy, not used by live apps** |
| Admin access code A | id `c1743f07be8f45aeb93466f22e854492`; live; mask `..45`; expires 2027-10-07; last used 2026-10-07 | Revoke (keep row for audit) |
| Admin access code B | id `921bbaefca0b48dcb3044485f3671c2a`; already revoked 2026-10-07; mask `..Jj` | Already inactive; keep row for audit |
| Requested code hash | Neither row matches SHA-256 of the owner-requested code | Must issue a new row |
| Vendor access code | One live code for real vendor `Bhopal` (`bc075e…`) | Keep — unrelated to admin |
| Demo customer | `demo-user-1` / `+919000000001`: 7 orders, 1 address, 1 ledger row, 7 ledger events, 3 payments, 14 sessions, 1 device token, 1 stop | Remove |
| Demo vendor | `demo-vendor-1` / `+919000000002`: 14 sessions, vendor profile (`review_hold=1`), demo route `demo-route-1`, demo stop `demo-stop-1` | Remove |
| Demo door | `config.demo_login_enabled = 0`; `demo_codes = 0` | Already closed server-side |
| Demo UI — donor | `login_screen.dart` "Try the demo", `demo_sheet.dart` prefills `+919000000001` / `111111` | Remove |
| Demo UI — vendor | `vendor_code_screen.dart` "Demo try karein", `demo_sheet.dart` prefills `+919000000002` / `222222` | Remove |

Other checks: no hardcoded sample orders, addresses, wallet balances, or telemetry were found in the two app trees. The visible demo content comes from the two seeded accounts and the demo route/stop. The admin app's mock fixtures only run when `API_MODE=mock`; production uses `API_MODE=live`.

## 3. Goals

1. One live admin access code for `+917828442476`, using the owner-supplied 6-digit code, verified by a real admin login.
2. No demo-login entry point in the donor or vendor app.
3. No demo account, demo order, demo route, or demo stop left in production D1.
4. Keep production D1 intact; preserve audit history.
5. Clarify that `shodasha-staging` is intentional test infrastructure, not a duplicate production database.

## 4. Non-goals

- Do not delete real customers, real orders, or the real vendor account.
- Do not remove the backend `/v1/auth/demo` route in this change; it is already fail-closed (`demo_login_enabled=0`, no `demo_codes`).
- Do not change the vendor's access code.
- Do not delete `shodasha-staging` unless separately approved after an export.
- Do not add new features or redesign the login screens.

## 5. Requirements

### R1 — Admin access code

- Take a fresh D1 export before any write.
- Revoke the live admin row (`c1743f07…`) by setting `revoked_at`; do not hard-delete it.
- Leave the already-revoked row in place as audit history.
- Insert exactly one new `access_codes` row:
  - `user_id = 1a276f3033644bc496e31f115c5950f2`
  - `expected_role = 'admin'`
  - `code_hash = sha256(owner-supplied code)`
  - `masked_hint` ends in `07`
  - `expires_at` = approved duration
  - `created_by` = admin user id
- Write matching `audit_log` rows for the revoke and issue.
- Verify with `POST /v1/auth/admin/login` and `GET /v1/auth/me` (role must be `admin`).

### R2 — Remove demo UI

Donor app:
- Remove the demo CTA, `UserDemoSheet`, `demoLogin` controller/API methods, demo strings, and demo tests.
- Keep mobile/password sign-in, registration, password reset, and session handling unchanged.

Vendor app:
- Remove the demo CTA, `DemoSheet`, `demoLogin` controller/API methods, demo strings, and demo-only tests.
- Keep phone + access-code sign-in unchanged.

### R3 — Remove demo data

Use an explicit allowlist of `demo-user-1` and `demo-vendor-1`. Delete owned rows in FK-safe order, including:

- demo orders, order events, stops, route, payments, refunds, dues intents, idempotency keys
- demo ledger, ledger events, address, sessions, device tokens
- demo vendor profile, slots, zones, leaves, payouts, quality incidents
- demo complaints, ratings, returns, damaged containers, strikes
- phone-keyed `otp_codes`, `demo_codes`, and `leads` for the demo phones

Retain `audit_log` as the security trail. Verify zero demo users/orders/stops/routes afterward.

### R4 — Database decision

- Default: keep both databases.
- `shodasha` remains the only production database.
- `shodasha-staging` remains isolated test infrastructure.
- If the owner still wants one database, export staging first, then delete `shodasha-staging`, remove the `staging` block from `workers/api/wrangler.jsonc`, and retire Worker `water-staging`. This is a separate destructive step and needs explicit approval.

## 6. Implementation outline

1. Fresh D1 export + Time Travel bookmark (already taken for this draft: 106,520 B, SHA-256 `D473DF55…`, bookmark `000002df-…`).
2. Create branch `036-demo-cleanup-admin-code`.
3. Apply demo-data cleanup SQL and admin-code SQL.
4. Remove demo UI/controller/API/tests from donor and vendor apps.
5. Run `flutter analyze` and `flutter test` for both apps.
6. Rebuild APKs only if the owner asks for installable artifacts.
7. Verify live `/health`, `/v1/catalog`, and admin login.
8. Update `context/progress-tracker.md`, `context/flow.md`, and `context/decision.md`.
9. Commit locally; do not push or release without explicit approval.

## 7. Verification

- `SELECT COUNT(*) FROM users WHERE id IN ('demo-user-1','demo-vendor-1')` = 0
- `SELECT COUNT(*) FROM orders WHERE user_id IN (...)` = 0
- `SELECT COUNT(*) FROM stops WHERE customer_id IN (...) OR order_id = 'demo-order-1'` = 0
- `SELECT COUNT(*) FROM routes WHERE id = 'demo-route-1'` = 0
- Exactly one live admin code; its hash matches the owner-supplied code
- Real admin login returns 200 with role `admin`
- `GET /health` = 200; `GET /v1/catalog` = 200
- Donor/vendor `flutter analyze` clean; test suites green

## 8. Rollback

- Preferred: D1 Time Travel restore to the pre-change bookmark.
- Secondary: restore the 106,520-byte SQL export.
- Code rollback: revert the branch commit; the backend demo endpoint was not changed.

## 9. Open questions

1. Keep staging (recommended) or delete it after export?
2. Remove demo UI only, or UI + demo accounts/orders/route (recommended)?
3. Admin code expiry: 90 days, 180 days (recommended), or 1 year?
4. Build local APKs after the change, or code/test only for now?

## 10. Security note

The Cloudflare API token and R2 access key pasted into chat are exposed. They were not used or stored by this task. Rotate/revoke them in the Cloudflare dashboard. The local Wrangler OAuth session already has the required D1 access.
