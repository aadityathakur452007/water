# Server OTP via Fast2SMS — spec (approved 2026-10-01)

## Problem
1. APK `POST /v1/auth/otp/verify` → 400: app sent `device` as a string, server
   contract requires `device: {id}` object (`auth_impls.dart:45`).
2. Any send/verify failure shows "Network me dikkat" — `sendOtp` catch-all masks
   Firebase failures and server 4xx/5xx (`auth_controller.dart:273`).
3. Firebase Phone-Auth SMS needs Blaze billing (since Sept 2024). User refuses
   billing. No free production SMS exists in India; cheapest verified 2026
   option is Fast2SMS (Rs 0.25/SMS from a Rs 100 recharge, +18% GST + Rs 0.025
   DLT scrubbing). Under 2k OTPs/month ≈ Rs 100–500 wallet.

## Decision
Server-generated OTP over Fast2SMS DLT route, behind the existing
fake/real adapter seam (`OTP_PROVIDER=firebase|fast2sms`, default firebase —
zero behavior change until switched). Admin panel keeps Firebase.

## Backend changes
- `adapters/sms.py` (new): `SmsProvider.send_otp(phone, code)`; `FakeSmsProvider`
  (log-only, dev/test); `Fast2SmsProvider` (httpx, key from worker env/secret);
  `get_sms_provider()` factory on `OTP_PROVIDER`.
- `db/migrations/008_otp.sql` (new): `otp_codes(phone PK, code_hash, attempts,
  expires_at, created_at)`. sha256 hash only — never the plain code.
- `repositories/otp_repo.py` (new): `issue(phone, hash, ttl)` / `consume(phone,
  hash)` (checks expiry + max 5 attempts, deletes on success).
- `auth_service`: `otp_start` with provider=fast2sms → 6-digit `secrets` code,
  5-min TTL, same 202 shape + `channel: sms`. `otp_verify` accepts
  phone+otp_code (either Firebase token OR server code, never both required).
  Existing phone/IP/device rate limits reused.
- `api/v1/auth.py`: `OtpVerifyIn` gains optional `phone` + `otp_code`;
  `firebase_id_token` becomes optional; service rejects empty both.
- `core/config.py`: `otp_provider`, `fast2sms_api_key`, `fast2sms_sender_id`,
  `fast2sms_entity_id`.
- Tests: `tests/test_sms_otp.py` (fake round-trip, wrong/expired/attempts cap,
  provider default unchanged).

## App changes
- `auth_impls.verifyOtp`: `device: {'id': deviceId}` (the 400 fix).
- `AuthApi.startOtp` returns channel (`firebase|sms`); controller skips the
  Firebase `requestCode` step on `sms` and posts the typed code via new
  `verifyServerCode(phone, code, deviceId)`.
- Error strings: `smsError` (Firebase send failed — billing/quota), server
  4xx message passthrough, `networkError` only for real offline/5xx.

## Security (ssdlc)
6-digit `secrets` code, sha256 at rest, 5-min expiry, 5 attempts then burn,
per-phone + per-IP + per-device rate limits (existing), no code in logs or
responses, DLT template carries the brand name (TRAI).

## User-side steps (DLT, plain language — see section below)
Fast2SMS real mode stays dormant until: DLT entity + sender header + OTP
template approved AND `FAST2SMS_API_KEY` set as a worker secret AND
`OTP_PROVIDER=fast2sms` var set. Until then the app uses Firebase (test
numbers work free for QA).

## What is DLT (for the business owner)
India blocks all business SMS that is not registered. DLT is a one-time
paperwork on the telecom portals:
1. Register the business (Principal Entity) — PAN/GST + letter; you get an
   Entity ID. Fast2SMS offers free DLT support to walk through this.
2. Register the sender name (Header, e.g. SHODASHA) — this shows on the phone.
3. Register the exact OTP message (Template, must carry the brand name,
   e.g. "Your Shodasha code is {#var#}") — approval takes ~3–5 days.
After approval, paste the IDs into Fast2SMS, recharge Rs 100, set the worker
secret — OTPs deliver even to DND numbers, 24x7.
