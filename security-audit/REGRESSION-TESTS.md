# Regression Tests

## Added

### `workers/api/tests/test_vendor_rider_onboarding.py` (5 tests)

Locks FIX-001. Builds the real schema, seeds a vendor session and five accounts, then calls `POST /v1/vendor/riders`:

| Test | Asserts |
|------|---------|
| `test_existing_foreign_account_is_rejected[cust-1]` | 409, role stays `user`, no vendor binding |
| `test_existing_foreign_account_is_rejected[admin-1]` | 409, role stays `admin` |
| `test_existing_foreign_account_is_rejected[rider-b]` | 409, rider stays with vendor B |
| `test_own_rider_can_be_re_onboarded` | 201, rename applied, role/vendor unchanged |
| `test_new_phone_creates_a_rider` | 201, new `rider` bound to caller |

### `workers/api/tests/test_csrf_cookie_auth.py` (6 tests)

Locks FIX-002.

| Test | Asserts |
|------|---------|
| `test_foreign_origin_cookie_write_is_rejected` | 403, order stays `placed` |
| `test_cookie_write_without_origin_is_rejected` | 403, immutable |
| `test_same_origin_cookie_write_still_works` | 200, order `cancelled` |
| `test_bearer_write_from_foreign_origin_is_unaffected` | 200 (Bearer is not CSRF-able) |
| `test_cookie_read_is_unaffected` | 200 on GET |
| `test_unsafe_cookie_write_without_session_cookie_still_401` | 401, not 403 |

### `workers/api/tests/test_rider_login_code.py` (12 tests)

Locks FIX-003 / VULN-002. Seeds a rider code through the same `access_codes` shape the vendor path writes.

| Test | Asserts |
|------|---------|
| `test_phone_alone_is_not_acceptable` | `400` — `code` is a required field |
| `test_wrong_code_is_rejected_generically` | `401 Invalid credentials.` |
| `test_valid_code_signs_the_rider_in` | `200`, `role=rider`, `user_id=r1` |
| `test_code_minted_for_another_role_cannot_open_the_rider_door` | `401` for a `vendor`-role code |
| `test_revoked_code_is_rejected` | `401` after `revoked_at` |
| `test_expired_code_is_rejected` | `401` past `expires_at` |
| `test_suspended_rider_with_a_valid_code_is_rejected` | `401` |
| `test_vendor_onboarding_returns_a_code_that_actually_signs_the_rider_in` | `201` + 6-digit code, and that code logs in |
| `test_reissue_rotates_the_code_and_the_old_one_stops_working` | `200` + new code; old code `401`, new code `200` |
| `test_reissue_is_scoped_to_the_callers_own_riders` | `404` for a foreign rider and for an unknown id |
| `test_a_rider_cannot_issue_codes` | `403` with a rider token |
| `test_re_onboarding_rotates_the_code_too` | re-onboarding invalidates the seeded code |

### `apps/vendor_app/test/rider_code_reissue_test.dart` (2 widget tests)

Covers the client side of rotation (`RidersScreen`, `MockClient` — no backend).

| Test | Asserts |
|------|---------|
| `key icon rotates the code and shows it once in a dialog` | one `POST /v1/vendor/riders/r1/code`, `AlertDialog` with the returned code, dismissible, list intact |
| `failed re-issue shows the server message and no dialog` | `409` → no dialog, `SnackBar` shows `"This rider belongs to another vendor."` (not `ApiException(…)`) |

An autouse fixture resets the process-wide per-phone limiter (`reset_rate_limits`) so these tests assert the credential rule, not throttling — `OTP-01` covers the lockout itself.

## Command

```bash
cd workers/api
.venv/Scripts/python.exe -m pytest tests/test_vendor_rider_onboarding.py tests/test_csrf_cookie_auth.py tests/test_rider_login_code.py -q
# 23 passed

.venv/Scripts/python.exe -m pytest -q
# 558 passed, 1 skipped
```

Baseline before the changes was 535 passed, 1 skipped; the 23 extra are the three new regression files.

## Dynamic probe suites (not pytest, kept for evidence)

```bash
cd workers/api
.venv/Scripts/python.exe ../../security-audit/pentest/harness.py    # 24 probes -> 24/24 after fix
.venv/Scripts/python.exe ../../security-audit/pentest/harness2.py   # rider login / OTP / idempotency
.venv/Scripts/python.exe ../../security-audit/pentest/harness3.py   # vendor onboarding chain -> all PASS after fix
```

`harness2.py` RIDER-01/02/03 flipped from FAIL to **PASS** once rider login required a vendor code — it was written as the acceptance test for VULN-002 and now guards the fix:

```text
PASS RIDER-01  Rider login with phone number only (no secret)   http=401
PASS RIDER-02  Rider login rejects guessed access codes         statuses=[401, 401, 401]
PASS RIDER-03  Control: vendor-issued code opens own route      onboard=201 login=200 route=200
```

### End-to-end HTTP workflow (`e2e_http.py`)

Not a pytest file: it drives a real `uvicorn` server over TCP and asserts the whole business chain.

```bash
cd workers/api
PYTHONPATH=src .venv/Scripts/python.exe ../../security-audit/pentest/e2e_http.py
# 26/26 steps passed
```

It covers register → address → quote → COD order → admin assign → vendor triple → customer code → vendor PoD → delivered/paid → admin view → rider onboarding (with issued code) → rider login → rider route → **code rotation (old 401, new 200)** → rider completion → delivered → cancel refused → ledger clean. Results are written to `pentest/results_e2e.json`.

## Final probe state

| Suite | Before fixes | After fixes |
|-------|--------------|-------------|
| `harness.py` | 20/24 (CSRF fail, 3 harness-expectation issues) | 24/24 |
| `harness2.py` | rider takeover 3 fails, OTP + idempotency pass | **RIDER-01/02/03 PASS**, OTP + idempotency PASS |
| `harness3.py` | 3/4 fail (role flip, admin demotion, rider theft) | **4/4 PASS, 0 FAIL**; VENDOR-03/04 are conditional follow-ups to a successful takeover and are skipped once none exists |
| `e2e_http.py` | n/a (added later) | **26/26 steps** |
| `pytest` | 535 passed, 1 skipped | **558 passed, 1 skipped** |
| `flutter test` (rider / vendor) | n/a | **9/9 · 96/96** |

## Limitations

- Tests run on sqlite via `AsyncSqliteConn`; D1-specific behaviour is not covered.
- The probes are single-threaded; concurrency/race tests were not added.
- The new rider-list rotate action is covered at widget level (`rider_code_reissue_test.dart`), but only against a `MockClient`; the dialog's visual layout and the real endpoint round-trip from a device remain unexercised. No suite drives a live ops Worker. The rider app's `rider_app_test.dart` still passes (9/9) but does not log in against a server.
- The `IDEMPOTENT_REPLAY` handling in `booking_sheet.dart` remains unverified.
