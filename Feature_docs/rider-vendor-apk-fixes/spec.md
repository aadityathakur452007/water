# Feature Spec: Rider/Vendor Operations, APK Build Rules, Rate-Limit Lockout & Cash Sync

## Overview
Resolves operational logic flaws, UI mismatches, rate-limit UX gaps, and Android release APK build/install failures across `workers/api`, `apps/rider_app`, `apps/vendor_app`, `apps/user_app_donor`, and `.github/workflows/release.yml`.

## Requirements
1. **Android APK Release Rules (`apps/*/android/app/`, `.github/workflows/release.yml`)**:
   - Add `proguard-rules.pro` with Flutter/plugin keep rules and reference `getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"` in all three apps.
   - Disable `isShrinkResources` (set `false`) so R8 does not strip manifest/plugin resources that cause `App not installed as package appears to be invalid`.
2. **Gradual Rate-Limit Countdown Timer (`apps/user_app_donor`, `apps/rider_app`, `apps/vendor_app`)**:
   - On `429 RATE_LIMITED`, start at 60s (1 min) and increase gradually on consecutive 429s (`60s -> 120s -> 240s ...`, capped at 1800s / 30 min, or `max(serverRetryAfter, gradualWait)`).
   - Disable all login/password/code input fields and submit buttons until the countdown finishes.
3. **Unmasked Customer Phone in Rider App (`workers/api`, `apps/rider_app`)**:
   - Return real `customer_phone` in `RiderService.routes_today()` (remove `mask_phone` for assigned route stops).
   - Dial the real customer phone number in `delivery_screen.dart` and `pod_sheet.dart`.
   - In `order_service.py:tracking()`, only return `rider` info when `s.rider_id` is assigned (do not masquerade vendor phone as rider phone).
4. **Simplified Rider Dues & Eliminated N+1 Queries (`workers/api`, `apps/rider_app`)**:
   - Replace per-stop SQL queries in `routes_today()` with 2 batch queries (`subscriptions` and `ledger` for all `customer_id`s).
   - 3 clear handover modes:
     - Active subscription (`monthly_postpaid`, `monthly_prepaid`, `weekly_postpaid`): `amount_due = 0`, never collect daily cash.
     - Cancelled subscription with `ledger.dues > 0`: collect `dues` on **only the first pending stop** per customer (`seen_dues_customers` set).
     - Regular / one-time COD: collect `order_amt` if COD and unpaid, else `0`.
   - When rider collects cash on a dues/subscription stop, clear `ledger.dues` and increment `vendor_profile.in_hand` atomically (never swallow `OverpayError` silently).
5. **Empty Jars Collection Limit (`workers/api`, `apps/rider_app`)**:
   - Compute `jars_held` from `ledger.held` and `max_empties = min(quantity, jars_held)` per stop.
   - Cap `PodSheet` empty-can stepper at `max_empties` and validate in backend `complete_stop` / `pod_complete`.
6. **Vendor Cash Collection Visibility (`workers/api`, `apps/vendor_app`)**:
   - Surface `cash_collected` (from `triple.pod.cash` / `triple.cash`) and `rider_name` in `VendorService.today_route()` and `get_stop()`.
   - Display `"Rider collected ₹X"` badge on `route_screen.dart` and `stop_detail_screen.dart`.
