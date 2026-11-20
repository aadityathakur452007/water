# Executive Summary — Shodasha Water Delivery

**Date:** 2026-11-20
**Target:** `workers/api` (FastAPI/Python Worker), surfaced to four clients (customer, vendor, rider, admin) plus Razorpay UPI webhooks.
**Engine:** PentestCode v0.2.7 (autonomous multi-agent pentest CLI) installed in WSL2 + a custom in-process DAST harness that drives the real ASGI app with real session tokens.
**Scope:** local, synthetic data only. No production database, no live Razorpay calls, no third-party targets.

## Result in one line

The API's authorization core is strong — 21 of 24 targeted probes were denied by design — but **three real flaws were found, one of which allowed a vendor to take over any account, including the platform admin.** All three are now fixed and covered by regression tests, and a full order-to-doorstep workflow passes end to end over HTTP (26/26 steps), including rider sign-in-code rotation.

## Findings

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| VULN-001 | **Critical** | `POST /v1/vendor/riders` rewrote the role of *any* existing phone to `rider` and re-assigned it to the calling vendor. Chained with phone-only rider login this is full account takeover; it could also demote the platform admin. | **Fixed + retested** |
| VULN-002 | **High** | `POST /v1/auth/rider/login` authenticated with a phone number alone. Anyone who knows a rider's number got a rider session and could read live delivery routes (customer addresses) and mutate stops. | **Fixed + retested** |
| VULN-003 | Medium | The `sh_session` cookie was accepted for state-changing requests with no CSRF defence. A cross-origin request cancelled an order in testing. | **Fixed + retested** |
| RISK-001 | Low | Per-isolate session cache (`AUTH_SESSION_CACHE_TTL_S`, default 10 s) delays suspend/logout propagation to other isolates. | Documented, accepted risk |

## What this means by role

- **Customer:** no IDOR found. Another customer cannot read, cancel, reschedule, reissue a code for, or invoice your order (all 404). Price/quantity tampering is rejected server-side.
- **Vendor:** cannot read or mutate another vendor's stops, post cash against them, or complete them. Cannot mint orders as a customer. Rider onboarding is now contained to their own riders.
- **Rider:** cannot touch another vendor's stops or a stop explicitly assigned to another rider. Delivery completion is OTP-gated with a working 5-attempt lockout. Rider sign-in now requires a vendor-issued, expiring, hash-stored code — the phone number alone is no longer a credential.
- **Admin:** role gates hold on every probed admin endpoint; SQL injection and unsignable webhooks failed. Cookie sessions are now same-origin only.
- **Money:** server recomputes quotes; a ₹1 quote for a ₹150 order is rejected (`STALE_QUOTE`). Webhooks require a valid HMAC and a fresh `created_at`; replays are idempotent.

## Verification performed

- `workers/api`: **558 passed, 1 skipped** (`pytest -q`), including the 23 new regression tests.
- Dynamic probes: 24 + 7 + 6 executed requests plus a 26-step HTTP workflow against a live `uvicorn` server; raw evidence in `security-audit/pentest/*.json`.
- Clients: `flutter analyze` clean and `flutter test` green for `apps/rider_app` (9/9) and `apps/vendor_app` (96/96) after the rider-code change, including two widget tests for the rider-list rotate action.
- Not verified: Flutter client behaviour, live Razorpay sandbox settlement, D1 (as opposed to sqlite) semantics, dependency CVEs (no auditor installed offline), load/concurrency beyond SQLite's single-writer model.

## Recommended next steps

1. Run the PentestCode agents against the running API once a model-provider key is available; the installation is complete and idle at `\\wsl$\Ubuntu\home\aditya\.local\pentestcode`.
2. Add `pip-audit`/`npm audit` to CI (SSDLC Phase 5 gate) — not run here.
3. Rotate any credential pasted into a chat during this engagement, and keep the Cloudflare/R2 keys out of the repository.
