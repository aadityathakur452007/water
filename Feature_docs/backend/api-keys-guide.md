# API Keys & IDs Guide — where to find them, where to paste them

> Status: slice-3 runs 100% on dummies (FakeUpi, FakeVerifier, FakeFcm, stub Google/WhatsApp). Nothing below is needed to run tests. When you paste a real key, only its adapter flips — no code changes.

## What runs on dummies today vs what unlocks with keys

| Capability now | Real key that unlocks it | Wired where |
|---|---|---|
| OTP tests via FakeVerifier | Firebase Project ID + service account | `adapters/firebase.py` RealVerifier |
| UPI tests via FakeUpi (APPROVE*/DECLINE*) | UPI provider Key ID + Secret + webhook secret + agency VPA | `adapters/upi.py` RealUpiProvider |
| Push tests via FakeFcm log | Same Firebase service account (no extra key) | `adapters/fcm.py` RealFcm |
| place_id accepted, re-verify stubbed | Google Maps API key (Places + Geocoding) | future `adapters/maps.py` |
| WhatsApp deep-links only (wa.me) | WhatsApp provider account (undecided) | future `adapters/whatsapp.py` |

## 1. Firebase (Project ID + service account) — needed first

1. Go to **console.firebase.google.com** → Add project (or select yours) → any name, disable Analytics if you like → Create.
2. **Project ID**: Project Overview → ⚙ Project settings → General → *Project ID* (e.g. `shodasha-water`). Paste as `FIREBASE_PROJECT_ID=...` in `.env`.
3. **Phone auth**: Build → Authentication → Sign-in method → enable **Phone**. (This sends real SMS; test numbers can be added under Phone numbers for sandboxing.)
4. **Service account** (later, when wiring RealVerifier): Project settings → Service accounts → Generate new private key → downloads a JSON file. **Save it on your machine only** (e.g. `C:\secrets\firebase-admin.json`), set `GOOGLE_APPLICATION_CREDENTIALS=C:\secrets\firebase-admin.json`. NEVER paste it in chat, NEVER commit it (`.env`/gitignored; the file stays outside the repo).
5. **First admin**: `SEED_ADMIN_PHONE=+91XXXXXXXXXX` in `.env` → `python workers/api/scripts/seed_admin.py` (one-shot, refuses if an admin exists).

## 2. UPI provider (example: Razorpay — any provider fits the adapter)

1. **dashboard.razorpay.com** → sign up → stay in **Test Mode** first.
2. Settings → API Keys → Generate Test Key → copy **Key ID** (`rzp_test_…`) + **Key Secret** → `UPI_KEY_ID` / `UPI_KEY_SECRET`.
3. Webhooks → Add webhook → URL `https://<your-api>/v1/webhooks/upi`, secret → `UPI_WEBHOOK_SECRET`. Our verifier checks HMAC + ±5 min + nonce replay-cache.
4. Agency payee VPA: your business UPI ID (the QR money lands in) → `AGENCY_UPI_VPA=...@upi`. Test mode: use Razorpay's test UPI handles first.
5. Flip live later: same steps in Live Mode. The adapter interface doesn't change.

## 3. WhatsApp provider (collect when we pick one)

- Meta: developers.facebook.com → app → WhatsApp → API Setup → Phone Number ID + WABA ID + permanent token; message templates need pre-approval.
- Twilio/Gupshup: console → WhatsApp sender → API key + approved templates.
- Nothing to paste yet — provider undecided (open item). `wa.me` links work with zero keys.

## 4. Google Maps (place_id re-verify)

1. **console.cloud.google.com** → project → APIs & Services → enable **Places API** + **Geocoding API**.
2. Credentials → Create Credentials → API key → **restrict** it (Android app fingerprint + API allowlist) → `GOOGLE_MAPS_API_KEY=...`.
3. Without it: place_id accepted but not re-verified (C10 documented gap).

## 5. After pasting — verify nothing broke

1. `python -m pytest workers/api/tests -q` (dummies still pass; real adapters activate only with env present).
2. Boot + `GET /health`; `POST /v1/auth/otp/start` with a real number (test-mode SMS first).
3. Check logs contain no secret values (envelope redacts; verify once manually).
