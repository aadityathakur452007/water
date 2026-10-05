# Phase 4 — Flutter lightness + reliability (size, signing, network, catalog, support)

- **Goal**: smaller APKs, release-signing ready, network-resilient clients, live catalog prices, working help paths.
- **Workstreams**: W4a deps+size+signing (pubspec/gradle/assets) · W4b client reliability (api_client parity, device id, catalog) · W4c help paths (support launch, tanker CTA). Parallel-safe: different files; shared `api_client` per app owned by W4b only.

## 4.1 Dependency purge [P1] (Track C §3, measured)

- **Evidence** (import-grep VERIFIED, sizes from release DevTools JSON): user ships shadcn_flutter 2.44 MB + forui 0.91 + forui_assets 0.37 + likely country_flags 1.15 MB (transitive, confirm via `flutter pub deps`), google_maps_flutter (dead — OSM `flutter_map` is the picker, `map_picker.dart:3` comment admits blank), flutter_svg (no SVGs), intl (no direct import), cupertino_icons 113 KB, pin_code_fields (OTP deleted). ≈5 MB = 19% of user APK. Vendor: only pin_code_fields dead.
- **Fix**: delete the 7 user lines + 1 vendor line from pubspecs; `flutter pub get`; confirm `country_flags` leaves the bundle (`--analyze-size` re-run). No replacement libraries.
- **Verify**: release re-measure (target user ≤21 MB arm64); `flutter test` + `analyze` green.

## 4.2 Signing + R8 [P1/P2] (Track C §4)

- **Evidence**: both `build.gradle.kts` use `signingConfigs.getByName("debug")`; no minify/shrink/proguard.
- **Fix**: release signing with real keystore — OWNER provisions keystore + `key.properties` (never git; document names in `android/` README comment). Enable `minifyEnabled + shrinkResources` + smoke test release (login→order→vendor triple) since R8 can strip reflective calls.
- **Verify**: signed release installs; `aapt dump badging` records compile/target SDK ints (closes UNVERIFIED SDK finding).

## 4.3 Network parity + device identity [P1/P3] (Track C §2, F §1-F10)

- **Evidence**: vendor client has single-flight (`api_client.dart:69-72`), 3× backoff+jitter + Retry-After (`:193-196`), `onUnauthorized` → logout (`:64-67`). User client (`api_client.dart:98-131`) is single-shot: no retry/dedupe/401-hook → expired token shows errors instead of re-login. Both mains hardcode `deviceId 'pending-device'`; `loadOrCreateDeviceId()` (`session_store.dart:61`) never called → server device-cap/fraud dimension is junk.
- **Fix**: port vendor's retry/single-flight/401-hook to user ApiClient (copy, don't abstract — two small clients beats one clever one); wire `loadOrCreateDeviceId()` in both mains.
- **Tests**: socket-level retry test (flaky stub → success, single effect via idem key); 401 → forceLogout test (mirror vendor's).

## 4.4 Live catalog [P1] (Track F §1)

- **Evidence**: `booking_controller.dart:19-26` hardcoded 2800/3000/15000/300 + `TODO(F1)`; `_HardcodedCatalog` wired in `main.dart:74,233`; `CachingCatalogApi` never wired; checkout sends hardcoded `'v1'` (`checkout_service.dart:91`) with no `rate_version` check. Admin config rate change never reaches the app.
- **Fix**: wire `CachingCatalogApi` → `GET /catalog` on home init with hardcoded fallback (offline honesty kept); send server `rate_version`; on version drift re-quote before commit (server already 422s STALE_QUOTE — surface it, already mapped).
- **Tests**: catalog fetch populates rates; server rate change → client re-quote path (mock).

## 4.5 Help paths [P1/P2] (Track F §1)

- **Evidence**: user Support WhatsApp copies number instead of launching (`support_screen.dart:200-209`, `TODO(F1)`); tanker sheet CTA is dismiss-only with `+91XXXXXXXXXX` placeholder (`home_screen.dart:606-642`, `booking_controller.dart:49-50`); `subscription_screen.dart:426` launchUrl untraced.
- **Fix**: support Open → `launchUrl(wa.me/...)` with clipboard fallback (keep fallback, fix primary); tanker sheet gains Call button with real support number (constant already `+91 93021 90067` in api_client — promote to shared constant, delete placeholder); verify sub-screen launch path or remove it.
- **Tests**: widget tests assert launch attempted (mock url_launcher) + fallback snackbar.

## 4.6 Small reliability items [P2/P3]

- Dead `POST_NOTIFICATIONS` in both manifests: remove (no notification code exists) or wire when push returns — decide, ADR (recommend remove; re-add with FCM successor).
- Razorpay keep-or-drop: UPI-intent-only via url_launcher already covers dues/intent paths; if Razorpay stays, document why (gateway UX) else delete dep + `res/` drawables + test-key define. Decide, ADR.
- Logo re-export (837 KB → ~512px WebP, keep errorBuilder); logo `cacheWidth:32` at home (`home_screen.dart:132`); user https-or-loopback assert (copy vendor's 6 lines); 400-message generic copy (`auth_controller.dart:277-278`).
- Stale comment `orders_controller.dart:12-13` (url_launcher claim) — delete line.

## 4.7 Exit criteria

- [ ] Release re-measure recorded (target ≤21 MB user, vendor unchanged-or-less)
- [ ] Signed release smoke-tested; R8 on with no reflective breakage
- [ ] User client parity tests green; catalog live with fallback; help paths launch
