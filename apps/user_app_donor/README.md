# Shodasha donor customer app

A customer-only clone of the donor UI at
`github.com/ayushsingh930/Shodasha-Mineral-water`, wired to the Shodasha API
in `workers/api`. The donor screens and flows are preserved; the donor's local
fake orders, wallet balance, addresses and delivery codes are replaced by
the real 032 controllers and server contracts.

The original replacement app remains at `apps/user_app` as the fallback. The
pre-032 app is parked at `apps/user_app_legacy_flutter` for reference and is
never built. Staff/rider/plant panels stay in `apps/vendor_app` and
`apps/admin_app`.

## Scope

- Five customer tabs: Home, My Orders, Subscriptions, Wallet, Profile.
- Mobile number + password auth (name + optional email on signup), plus a
  server-gated demo door for local QA.
- Real catalog, quote, checkout (UPI/COD), orders, tracking, bills, returns,
  subscriptions, addresses, complaints, profile and ledger.
- The delivery code is a 24h handoff secret shown only on tracking, with
  reissue for expired/locked/unavailable stops.
- No customer rider controls, partner portal, fake PIN, fake wallet balance,
  fake live plant telemetry or client-side price math.
- Demo login is not a customer auth proof: the server must have the demo door
  enabled and the seeded demo customer available.

## Run

```
flutter pub get
flutter run --dart-define=SHODASHA_API_BASE=https://water.adityathakur452007.workers.dev/v1
```

`SHODASHA_API_BASE` must be https, or loopback for local dev
(e.g. `http://localhost:8787/v1`); anything else is rejected at construction.
`RAZORPAY_KEY_ID` is a publishable key only — the secret stays server-side.

## Test

```
flutter analyze
flutter test
flutter build apk --debug
```

## Still open

- Physical-device smoke (Razorpay return, UPI intent, GPS, OSM tiles) has not
  run.
- Release signing has no owner keystore yet.
- Password auth needs the Workers Paid runtime and the Cloudflare secrets;
  local QA should use the server-gated demo login.
