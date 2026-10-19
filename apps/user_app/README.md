# Shodasha customer app

Premium customer UI (adopted donor design language) wired to the Shodasha
API in `workers/api`. Replaces the original app, which is preserved for
reference only at `apps/user_app_legacy_flutter` (excluded from CI by
omission — it is never built).

## Run

```
flutter pub get
flutter run --dart-define=SHODASHA_API_BASE=https://water.adityathakur452007.workers.dev/v1
```

`SHODASHA_API_BASE` must be https, or loopback for local dev
(e.g. `http://localhost:8787/v1`); anything else is rejected at
construction. `RAZORPAY_KEY_ID` is a publishable key only — the secret
stays server-side.

## Test

```
flutter analyze && flutter test
```
