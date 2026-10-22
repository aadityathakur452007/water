# State Audit — replacement app vs legacy + `States.md`

**Date:** 2026-10-21 · **Branch:** `032-user-app-replacement` · **Baseline:** `af1b115` (13 commits, tree clean)
**Scope:** `apps/user_app` (replacement) audited against `apps/user_app_legacy_flutter` (read-only reference) and the universal checklist in `States.md`.
**Method:** two read-only code explorations (legacy inventory + replacement state coverage), then every P0/P1 claim below re-verified by direct source reads. Evidence is `path:line` at the baseline commit.

**Severity**
- **P0** — money loss/duplication, data leak, dead-end, or unauthorised action.
- **P1** — broken core UX: missing retry/feedback/confirmation, stale account data, bad 401 recovery.
- **P2** — polish, accessibility, responsive/edge hardening.

**Verdict (pre-fix, baseline `af1b115`):** the app built and 188/188 tests passed, but the APK **should not ship as-is** — it carried 3 P0 defects (one a silent duplicate-order path on money). **All three P0s were fixed in Phase A on 2026-10-21** (ADR-124); the current build is 197/197 green and the release APK was rebuilt and re-verified. Evidence below is the pre-fix baseline and is kept as the audit record.

---

## 1. Summary

| Severity | Count | Areas |
|---|---|---|
| P0 | 3 | cross-account state bleed · duplicate order/subscription on post-create retry · ungated guest Orders |
| P1 | 14 | 401 route unwind · orders offline/paging/refresh · tracking feedback · rating errors · plan-builder estimate gate · skip confirm · wallet refresh & money formatting · return UPI validation · address unknown-serviceability/unsaved guards |
| P2 | 8 | splash restore timeout · dismissible paying sheet · minor a11y/back/nav polish |
| Deliberate N/A | — | legacy offline catalog fallback, language toggle, notifications, staff screens (ADR-120/121/122) |

Legacy feature parity is otherwise complete (details in §3); the only legacy flow not ported is the first-run locate→address onboarding (`first_run_screen.dart`).

---

## 2. P0 — fix before any release

> **Status: all 3 fixed 2026-10-21 (Phase A, ADR-124).** The evidence below is the pre-fix baseline.

### P0-1 · App-scoped controllers never reset on logout / user switch — ✅ FIXED
**Evidence**
- Controllers are created once in `apps/user_app/lib/main.dart:81-90` (`BookingController`, `AddressController`, `OrdersController`, `ProfileController`) and passed down at `main.dart:122-128`.
- Logout only wipes auth + `selected_address_id` pref: `features/auth/auth_controller.dart:363-382`, `_reset()` at `:440-444` is auth-only.
- 401/403 calls `forceLogout()` (`main.dart:72`), same auth-only wipe (`auth_controller.dart:384-396`).
- Shell auth listener only refreshes the ledger: `features/shell/user_shell.dart:93-95`.
- No reset API exists: `OrdersController` has no `reset`/`clear` (only `setQuery`, `orders_controller.dart:614`); `ProfileController`/`AddressController` likewise; `BookingController.resetBookingSession()` (`booking_controller.dart:491-497`) is called only on successful checkout (`booking_sheet.dart:395`).
- `ProfileScreen` loads identity only when status is not loaded (`profile_screen.dart:66-80`) — the previous user's identity stays on screen indefinitely.
- `HomeScreen` fires `addresses.load()` for guests too (`home_screen.dart:84-85`), caching a 401 error the next user must manually retry.

**Impact:** after logout→login (or expiry→login) the new user can see the previous user's orders, addresses, profile identity and dues strip. Guest tab shells can expose cached account rows. Privacy + wrong-money risk.

**Fix direction:** add `reset()` to every user-scoped controller; shell listens to auth and resets all of them on logout/expiry and on identity change (also clear the selected-address store's in-memory value and `.clear()` the HTTP cache); gate Home's `addresses.load()` behind `isAuthenticated` and re-load after login.

### P0-2 · Retry / “Choose COD” after a post-create failure creates a second order — ✅ FIXED
**Evidence**
- `placeCheckout` creates the order, then requests the UPI intent in the same call: `features/booking/checkout_service.dart:187-201` (create with key), `:260-269` (`api.upiIntent`, throws `ServerDataException` if the link is missing).
- Any throw after creation (intent network/5xx/timeout, empty link) propagates to `_pay`'s catch → error phase (`booking_sheet.dart:400-426`).
- The error branch's **Retry** rotates the key and calls `_pay()` again: `booking_sheet.dart:901-908` + `controller.refreshIdempotencyKey()` (new key ⇒ new order).
- **Choose COD** flips `paymentMode`, whose setter also rotates the key (`booking_controller.dart:315-321`), then `_pay()` ⇒ a second, COD order while the first UPI order stays pending.
- Same rotation on missing link / no UPI app / timeout: `booking_sheet.dart:432, 445, 464` (and the Razorpay-key-missing branch `:477-482`).
- Subscription path has the same shape: `createSubscription` succeeds, then a missing estimate/id throws (`checkout_service.dart:139-165`) and Retry re-posts with a fresh key ⇒ duplicate subscription.
- The UPI verify/poll that would settle the first order only runs in the happy path (`booking_sheet.dart:471-474`); after a timeout the user gets “Retry or choose COD” with no way to resume the existing order.

**Impact:** duplicate orders, double payment (UPI app actually opened, user pays, webhook settles order 1 while order 2 is COD/pending), orphaned pending UPI orders, duplicate subscriptions. This is the money-law breach of the whole card.

**Fix direction (needs your approval — it changes the flow):**
1. Once an order/subscription exists, **never** post create again with a new key. Track the created id on the controller/sheet.
2. Split recovery by stage:
   - create succeeded + intent failed → keep the order, re-request the intent **with the same idempotency key** (safe: server replays), or offer “Check Orders”/“Pay later”.
   - UPI launched but unverified → offer “I’ve paid — check status” (re-poll the existing order) and “Check Orders”, never a re-create.
   - COD switch after create → cancel the pending order server-side first (or reuse it if the backend supports mode change); otherwise keep it UPI-pending and say so.
3. Retry may rotate the key **only** while nothing was created (quote/estimate/validation stage).

### P0-3 · Guest Orders tab is ungated and can show cached rows — ✅ FIXED
**Evidence**
- Shell renders `OrdersScreen` with no guest branch: `user_shell.dart:311-317` (Subscriptions is gated at `:318-328`, so the pattern exists).
- `OrdersScreen.initState` skips loading for guests (`orders_screen.dart:59-64`), then renders cached rows if present, else `_EmptyState` (`:182-186`) which has **no action** (`:545-585`).
- Combined with P0-1, a logged-out session can display the previous user's list under a “No orders yet”/stale shell.

**Fix direction:** gate Orders exactly like Subscriptions (guest body with Sign in), and reset the controller on auth change so no cached rows survive logout.

---

## 3. Legacy → replacement feature map

Mapped from `apps/user_app_legacy_flutter/lib` screen inventory; “Deliberate” = decided by ADR-120/121/122, not a gap.

| Legacy capability | Replacement | Status |
|---|---|---|
| Register (name + Gmail + mobile, demo numbers, guest browse) | `auth/name_number_screen.dart`, `demo_sheet.dart`, `auth_gate.dart` | ✅ parity (no OTP — backend has none) |
| First-run locate → add address (`first_run_screen.dart`) | — | ❌ **not ported** (see P2-2) |
| Home storefront, address bar, server rates, dues strip | `booking/home_screen.dart` | ✅ parity, prices server-only by law |
| Offline catalog fallback | dropped | Deliberate (S3 money law) |
| Booking flow: schedule slots, quote, COD/UPI, Razorpay | `booking/booking_sheet.dart`, `checkout_service.dart` | ✅ parity + idempotency; P0-2 recovery gap |
| Product detail | `booking/product_detail_sheet.dart` | ✅ |
| Addresses: list/add/edit/delete, map picker, serviceability | `addresses/address_screen.dart`, `map_picker.dart` | ✅ parity; P1 serviceability/unsaved gaps |
| Orders list, search, bill, rating, tracking, reschedule, cancel | `orders/*` | ✅ parity; P1 state gaps listed below |
| Repeat order / reorder | `user_shell.dart:185-193` | ✅ |
| Subscriptions: list, pause/resume/cancel | `subscriptions/subscription_screen.dart` | ✅ + stale banner, pull-to-refresh |
| Legacy stub plan calculator | `subscriptions/plan_builder_sheet.dart` (server estimate) | ✅ improved; P1 estimate gate |
| Wallet/dues/payment history | `wallet/*` (new) | ✅; P1 refresh + formatting |
| Returns with pickup address | `returns/return_sheet.dart` (new) | ✅; P1 UPI validation |
| Complaints with reason codes + 40-day window | `support/support_screen.dart` | ✅ |
| Profile, edit, logout | `profile/profile_screen.dart` | ✅; P0-1 identity bleed |
| Language toggle (Hinglish) | deferred | Deliberate (English v1) |
| Notifications tab | dropped | Deliberate |
| Staff/vendor screens | dropped | Deliberate |
| Legacy defects (silent catalog fallback, unwired guest gate, stub calculator, unsafe casts, no unsaved guards) | — | Correctly **not** copied |

---

## 4. Per-feature state matrix (`States.md` categories condensed)

Legend: ✅ handled · ⚠️ partial/weak · ❌ missing · N/A not applicable.

### Auth & shell
| Screen | Handled | Missing |
|---|---|---|
| AuthGate (`auth_gate.dart`) | splash, restoring, guest, authenticated, session expired→register, logged out (`:61-73`) | ⚠️ restore has no timeout/error path — a secure-store read throw strands the splash forever (`auth_gate.dart:41-44`, `auth_controller.dart:401-425`) → **P2-2** |
| NameNumber (`name_number_screen.dart`) | default/focused/invalid/submitting/success/failure, guest browse, demo numbers | ⚠️ no unsaved-changes note (trivial, P2) |
| Shell (`user_shell.dart`) | 5 tabs, lazy mount, guest gates for Subs/Wallet/Profile/Addresses, ledger refresh | ❌ Orders guest gate (P0-3) · ❌ controller reset on auth change (P0-1) · ❌ 401 route unwind (P1-1) · ⚠️ Android back on non-Home tab exits app (P2) |

### Booking & checkout
| Screen | Handled | Missing |
|---|---|---|
| Home (`home_screen.dart`) | catalog skeleton, error+retry, stale banner, address bar, dues strip, guest buy gate | ⚠️ address load fires as guest and caches 401 (P0-1) · ⚠️ no pull-to-refresh for rates (P2) |
| Product detail | qty/validation, reduced-motion safe images | — |
| Booking sheet (`booking_sheet.dart`) | slots loading/error/retry, quote loading/error/retry, estimate loading/error, COD gate, paying, success, error+retry/plain-COD | ❌ duplicate order/subscription on post-create retry (P0-2) · ⚠️ swipe-dismiss during paying abandons pending payment without feedback (`:39-57`) → **P2-3** · ⚠️ no “Check Orders / I’ve paid” recovery path |
| Checkout service (`checkout_service.dart`) | keyed create, STALE_QUOTE re-quote, price-change throw, honest server-only fields | ❌ throws after create with no result returned — root of P0-2 (`:260-269`) |
| Quote confirm (`quote_confirm.dart`) | success summary, next actions | — |

### Addresses
| Screen | Handled | Missing |
|---|---|---|
| List (`address_screen.dart`) | skeleton, error+retry, empty CTA, pull-to-refresh, select, delete confirm + result snackbar, busy guard | ⚠️ 409/conflict copy not distinguished (P2) |
| Form sheet | validation, saving state, success/failure snackbar, serviceability note | ⚠️ serviceability `null` (check failed) silently proceeds (`:779-783`) → **P1-14** · ❌ no unsaved-changes guard on dismiss → **P1-14** |
| Map picker (`map_picker.dart`) | GPS off/permission denied/denied-forever copy, locate timeout note, settings deep-link, pin confirm | ⚠️ OSM tile load failure has no UI (map stays draggable) → P2 |

### Orders
| Screen | Handled | Missing |
|---|---|---|
| List (`orders_screen.dart`) | skeleton, empty, no-results, error+retry, search, pull-to-refresh, action busy | ❌ guest gate (P0-3) · ❌ offline banner unreachable (`orders_controller.dart:633-639` vs `orders_screen.dart:196-201`) → **P1-2** · ❌ loadMore no in-flight guard, silent failure (`orders_controller.dart:649-665`) → **P1-3** · ❌ not reloaded after checkout/reorder (`user_shell.dart:116-121, 172-180`) → **P1-4** · ⚠️ 401 retry dead-end until root-pop fix → P1-1 |
| Tracking (`tracking_screen.dart`) | skeleton, error+retry, poll refresh, live/assigned banners, cancel confirm, reschedule confirm, action busy, dialer/WhatsApp fallback | ❌ reschedule result ignored — no success/error (`:219`) → **P1-5** · ❌ cancel failure shows “could not load orders” (`:146-153`) → **P1-6** · ⚠️ detail retry reloads whole list → **P1-7** |
| Bill (`bill_screen.dart`) | server fields, refund/deposit rows when present | ⚠️ missing fields silently omitted (P2) |
| Rating (`rating_sheet.dart`) | busy guard, thanks / already-rated snackbar | ❌ all failures (network/401/already) collapse to “rate once” and close the sheet (`:61-74`, `orders_controller.dart rate`) → **P1-8** |

### Subscriptions
| Screen | Handled | Missing |
|---|---|---|
| List (`subscription_screen.dart`) | guest gate, skeleton, empty CTA, error+retry, stale banner, pull-to-refresh, pause/resume/cancel sheets + confirm, late-skip dialog, action busy | ❌ Skip today fires with no confirmation (`:116-119`) → **P1-10** |
| Plan builder (`plan_builder_sheet.dart`) | address picker, estimate loading/error card, signed-out gate, submitting/busy, idempotent submit | ❌ `canSubmit` ignores estimate loading/error (`:234`) → user can create a plan without ever seeing the first-cycle amount → **P1-9** · ⚠️ unsaved-changes guard absent (P2) |

### Wallet & returns
| Screen | Handled | Missing |
|---|---|---|
| Wallet (`wallet_screen.dart`) | guest gate, skeleton, error+retry, empty explained, ledger rows, returns entry | ❌ no pull-to-refresh on main tab; stale after return and after dues paid elsewhere (`:84-108`) → **P1-11** · ❌ paise truncated with `~/ 100` (`:105, 205, 272, 277, 281`) → **P1-12** |
| Payment history (`payment_history_screen.dart`) | skeleton, empty, error+retry, pull-to-refresh, 401 copy | ❌ 401 offers only “Try again”, no sign-in action (`:98, 367-394`) → **P1-13** (partly moot after root-pop fix) · ❌ paise truncated (`:229, 285`) |
| Return sheet (`return_sheet.dart`) | qty stepper, address picker, busy, server SLA + refund snackbar | ❌ UPI required but only non-empty check (`:44, 180-190`) — invalid VPA means failed refund → **P1-14** |

### Profile & support
| Screen | Handled | Missing |
|---|---|---|
| Profile (`profile_screen.dart`) | guest CTA, skeleton, error+retry, loaded identity, edit sheet, logout confirm, links | ❌ cached identity never reset/refreshed (P0-1) → wrong user data |
| Edit profile sheet | validation, busy, success snackbar | ⚠️ no unsaved-changes guard (P2) |
| Support (`support_screen.dart`) | skeleton, empty, error+retry, complaint form validation, 422 window→WhatsApp path, busy, success | ⚠️ 401 route dead-end until root-pop fix (P1-1) |

### Cross-cutting
| Area | Handled | Missing |
|---|---|---|
| Network (`core/api_client.dart`) | GET dedupe, retry NETWORK/408/429/5xx, POST retry only with idempotency key, offline copy per screen | ⚠️ no reconnect/restored banner (P2) · ⚠️ per-screen offline semantics inconsistent (P1-2) |
| 401/403 | `onUnauthorized` → local wipe → AuthGate shows login | ❌ does not pop pushed routes/sheets; a modal can sit above the login screen and retry-loop (`main.dart:117-131`, `auth_gate.dart:61-73`) → **P1-1** |
| Reduced motion | handled at every `flutter_animate` site (`home_screen.dart:176`, `product_detail_sheet.dart:310`, `stepper.dart:39`, `tracking_screen.dart:547`) | ✅ |
| Touch targets / theme | 48dp minimum via theme; semantic labels on icon buttons | ✅ (spot-check) |
| Tablet/desktop | phone-first; no max-width column | ⚠️ intentional? (P2) |
| Browser back/refresh, multiple tabs, invalid URL, file states | — | N/A — native app, no files/uploads |
| Undo | — | N/A — destructive actions use confirm dialogs instead (acceptable per States.md) |

---

## 5. P1 detail (fix map)

| # | Issue | Evidence | Fix |
|---|---|---|---|
| 1 | 401 leaves pushed routes/sheets above login; retry loops | `main.dart:117-131`, `auth_gate.dart:61-73` | Root `navigatorKey`; on unauthorized schedule a post-frame `popUntil(first)` (also closes sheets) before AuthGate swaps to login |
| 2 | Offline banner unreachable; cached rows not marked stale | `orders_controller.dart:633-639`, `orders_screen.dart:196-201` | Set `_isOffline=true` on any non-4xx fetch failure; keep `loaded` when rows exist so the banner renders above cached rows |
| 3 | loadMore: double-fetch duplicates rows; failure silent | `orders_controller.dart:649-665` | `_loadingMore` guard + dedupe by order id + inline error/retry row or snackbar |
| 4 | Orders stale after checkout / reorder / tab jump | `user_shell.dart:116-121, 172-180` | `orders.load()` when entering the tab after checkout/reorder (and after pull-to-refresh ordering) |
| 5 | Reschedule result ignored | `tracking_screen.dart:219` | Await result → success snackbar/banner or error copy; keep the sheet confirm |
| 6 | Cancel failure shows order-list error copy | `tracking_screen.dart:146-153` | Cancel-specific failure copy (“Could not cancel — try again”) |
| 7 | Detail retry reloads whole list | `tracking_screen.dart:~268-300` | Retry through `refreshOrder(id)` with a local detail error state |
| 8 | Rating failures all read as “already rated”, sheet closes | `rating_sheet.dart:61-74` | Keep sheet open on network/401, show retry; reserve “rate once” for a real already-rated response |
| 9 | Plan builder submits while estimate failed/loading | `plan_builder_sheet.dart:234` | `canSubmit` requires `_estimate != null && !_estimateLoading && _estimateError == null` |
| 10 | Skip today has no confirmation | `subscription_screen.dart:116-119` | Confirm dialog (same pattern as pause/cancel) |
| 11 | Wallet stale after returns/dues; no pull-to-refresh | `wallet_screen.dart:84-108` | `RefreshIndicator` + reload after return; shell triggers wallet reload after dues payment/tab switch |
| 12 | Paise silently truncated | `wallet_screen.dart:105,205,272,277,281`; `payment_history_screen.dart:229,285` | Shared `formatInr(paise)` (2dp only when needed) used everywhere money renders; add unit test |
| 13 | Payment history 401 has no sign-in action | `payment_history_screen.dart:98,367-394` | Fixed structurally by #1; add explicit “Sign in” CTA as fallback |
| 14 | Return UPI unvalidated; address serviceability unknown proceeds; no unsaved guards | `return_sheet.dart:44`; `address_screen.dart:779-783`, form sheets | VPA regex + inline error; serviceability `null` → warning copy (“couldn’t verify — delivery is confirmed by the server”); dirty-form confirm on dismiss |

---

## 6. P2 & deliberate non-goals

**P2 (do after P0/P1):**
1. Splash restore timeout/error fallback (`auth_gate.dart:41-44`) — timeout → login instead of infinite splash.
2. First-run locate→address onboarding (legacy `first_run_screen.dart`) — either a one-time sheet on Home when the address list is empty, or an explicit ADR note dropping it (recommend porting; it is the only legacy flow missing).
3. Booking sheet dismissible while paying — block swipe/back or confirm (`booking_sheet.dart:39-57`).
4. Conflict/409 copy for address delete conflicts; bill rows that are absent could show “—/not billed” instead of hiding.
5. Android back on a non-Home tab returns to Home instead of exiting.
6. OSM tile failure placeholder in map picker; reconnect banner after network restore.
7. Tablet/large-screen max-width column (or explicitly document phone-first in ADR).
8. Support/payment-history pagination audit if server caps lists.

**Deliberate N/A (documented decisions, not gaps):** offline catalog fallback (ADR-122 money law), Hinglish/language toggle (English v1), notifications tab, staff screens, web/browser navigation states, file upload/download states, undo (confirm dialogs used instead).

---

## 7. Fix plan (Phase A approved + implemented 2026-10-21)

**Phase A — P0 — ✅ DONE (2026-10-21, commit on `032-user-app-replacement`)**
1. `reset()` + generation guards on Orders/Addresses/Profile/Booking controllers, owned by a root `AuthController` listener in `main.dart`; guest Home stops fetching addresses; shell reloads them after an in-session login. ✅
2. Guest gate for Orders (mirrors `_GuestBody` / Subscriptions). ✅
3. Checkout recovery rework: created-order tracking (`_placed`), same-key intent retry (`Retry payment`), `Check payment again` re-poll, `Check Orders` escape hatch, `UnconfirmedCreateException` for unusable create responses; `attention` confirm variant. **Design delta:** instead of “COD switch cancels/reuses the pending order”, the COD switch is no longer offered after create at all (no new cancel endpoint needed) — the created order stays and the user either retries payment or opens Orders. Same for subscriptions. ✅
4. Regression tests landed: `test/session_reset_test.dart` (reset clears + late-response discard + key policy) and `test/checkout_recovery_test.dart` (service: one `POST /orders`, same key replay, `UnconfirmedCreateException`; widget: recovery UI + request counts). Guest Orders covered in `shell_test.dart`. 401 route-unwind test is Phase B (P1-1). ✅
5. Gates: analyze clean · **197/197** tests · release APK 55.7 MB, SHA256 `F21C4F1CAB9D26C2FBDFF687EF2340915C1643AF2B2FDE4B6B5A161FF70CC380` · prod URL present / `localhost:8787` absent. ✅

**Phase B — P1 — ✅ DONE (2026-10-22, commit on `032-user-app-replacement`)**
1. **P1-1 root unwind:** `MaterialApp.navigatorKey`; on an authenticated→guest transition the auth listener resets user-scoped controllers and post-frame `popUntil(isFirst)`, so pushed routes/sheets never sit above the login screen. Payment History also offers a “Sign in” CTA on 401/403 as a fallback.
2. **P1-2 orders offline truth:** a network/5xx list failure keeps cached rows (`status = loaded`), raises `isOffline`, and renders the stale banner; 4xx still uses the error state.
3. **P1-3 load-more:** `_loadingMore` in-flight guard, id dedupe across overlapping cursor pages, `loadMoreFailed` + inline footer error/retry, spinner while loading.
4. **P1-4 fresh after checkout:** the shell reloads Orders in `_openCheckout.onDone` (reorder shares this path) in addition to the existing tab-entry reload.
5. **P1-5 reschedule feedback:** success/failure snackbars use new `rescheduled` / `rescheduleFailed` copy.
6. **P1-6 cancel feedback:** a failed cancel now says `cancelFailed`, not the generic load-error title.
7. **P1-7 tracking retry:** detail-missing retry calls `refreshOrder(id)` under a local `_detailLoading`; it no longer reloads the whole list.
8. **P1-8 rating outcomes:** `RateResult { success, alreadyRated, failed }`; server 409/`ALREADY_RATED` and the local “already rated” guard map to `alreadyRated`; network failures keep the sheet open with `rateFailed` copy and a retryable button.
9. **P1-9 plan-builder gate:** `canSubmit` requires a loaded estimate with no error and no in-flight request; `_submit` guards the same condition.
10. **P1-10 skip confirm:** “Skip today” opens a confirm dialog (`Skip today` / `Keep delivery`); no POST on cancel.
11. **P1-11 wallet freshness:** `RefreshIndicator`, reload after a return is filed, and a shell-owned `refreshTick` bumped on every Wallet tab entry (covers dues paid in Subscriptions).
12. **P1-12 money display:** new `lib/core/money.dart` `formatInr` (₹, 2dp only when the amount has paise); `formatRupees` and both `rupeesLabel` helpers delegate, and wallet/payment-history stop truncating with `~/ 100`. **Design delta:** money now renders `₹56` / `₹56.50` everywhere (was mixed `Rs 56` / `₹56`); subscription tests updated.
13. **P1-13 payment-history 401:** explicit “Sign in” CTA wired through Wallet and the shell (root unwind remains the primary path).
14. **P1-14 input completeness:** return sheet validates the refund VPA with an inline error (`name@bank`) and keeps Send disabled until valid; address serviceability `null` shows the new “couldn’t verify” warning; the address form tracks a dirty baseline and `PopScope` asks before discarding on close/system back/drag (save and confirmed discard bypass via a post-frame pop).
15. Regression tests: `test/phase_b_states_test.dart` (11 — formatter, VPA, load-more dedupe/guard/failure, offline truth, rating outcomes) + 2 subscription widget tests (skip confirm, estimate-failed submit disabled). `order_states_test.dart` / `subscription_flow_test.dart` updated for `RateResult` and ₹.
16. Gates: `flutter analyze` clean · **210/210** tests · release APK 55.8 MB, SHA256 `CC21EB44E4C479E0765B68D7AB9E222D9011AB701D857E2699D837B409B1D244` · 3 ABIs: prod URL present ✓, `http://localhost:8787` absent ✓, Razorpay test key present ✓. Backend untouched; device-verification debt unchanged.

**Phase C — P2 + first-run decision** (port or ADR-drop).

**Gates after each phase:** `flutter analyze` clean, `flutter test` all green, rebuild release APK, confirm prod URL present / `localhost:8787` absent, update `context/progress-tracker.md`, `flow.md`, `decision.md`, then commit on `032-user-app-replacement` only.

**Device-verification debt (unchanged):** Razorpay return, real UPI intent, GPS fixes, OSM tiles, and the debug-cert signing must be validated on hardware before store submission.

---

*Audit completed 2026-10-21 (read-only, no code changed). Phase A implemented the same day per owner approval — see `context/decision.md` ADR-124. Phase B implemented 2026-10-22 after the owner said “continue” — see ADR-125. Phase C (P2 + first-run decision) still requires explicit approval. Legacy app untouched.*
