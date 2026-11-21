# Feature Spec: Ecosystem Hardening (14 Fixes Across Vendor, Customer & Rider)

## Overview & Background
This specification addresses 14 operational and UX issues identified across the Shodasha Water ecosystem spanning Backend (`workers/api`), Customer App (`apps/user_app_donor`), Vendor App (`apps/vendor_app`), and Rider App (`apps/rider_app`).

---

## The 14 Fixes & Functional Specifications

### 1. Vendor: Delete / Remove Fleet Rider
- **User Story**: As a Vendor, I want to remove a rider from my fleet so they can no longer access routes or complete deliveries for my agency.
- **Backend Specification**:
  - Endpoint: `DELETE /v1/vendor/riders/{rider_id}`
  - Auth: Role `vendor` (must own the rider via `users.assigned_vendor_id = vendor_id`).
  - Actions:
    1. Unbind rider: `UPDATE users SET assigned_vendor_id = NULL WHERE id = :rider_id`.
    2. Revoke active access codes: `UPDATE access_codes SET revoked_at = :now WHERE user_id = :rider_id`.
    3. Revoke active sessions: `UPDATE sessions SET revoked_at = :now WHERE user_id = :rider_id`.
    4. Unassign pending stops: `UPDATE stops SET rider_id = NULL WHERE rider_id = :rider_id AND status = 'pending'`.
  - Response: `{"status": "removed", "rider_id": rider_id}`
- **Vendor App**:
  - In `apps/vendor_app/lib/features/riders/riders_screen.dart`, add a Delete icon button on each rider card with confirmation dialog.

### 2. Vendor: Auto-Logout Fix (Silent Token Renewal)
- **Problem**: 30-minute access token expiry kicks vendor to login screen via `AuthGate` because `isAuthenticated` checks `!_session!.isExpired`.
- **Specification**:
  - In `apps/vendor_app/lib/features/auth/auth_controller.dart`:
    - `isAuthenticated` must not mark session invalid if stored refresh token is still valid.
    - Proactive / reactive silent refresh via `refreshSession()`.
    - Only hard 401/403 or cap expiry forces logout.

### 3. Customer & Vendor: Order Cancellation Visibility & Reflection
- **Specification**:
  - Allow vendor to mark/request cancellation or cancel stop from stop detail view.
  - Fix pre-dispatch customer cancellation in `orders_controller.dart` to immediately transition local state and notify listeners.
  - Ensure cancelled orders display clearly with `Cancelled` status pill in both orders list and tracking screens.

### 4. Customer: Subscription Direct COD Activation (No Payment Gateway)
- **Specification**:
  - In `apps/user_app_donor/lib/features/subscriptions/subscription_screen.dart`, prevent redirecting to external payment gateway / Razorpay.
  - Subscriptions directly activate under Doorstep COD.

### 5. Customer & Rider: Cancelled Subscription Customer Hisaab & COD Restoration
- **Specification**:
  - In `workers/api/src/app/services/rider_service.py:routes_today()`, ensure `is_sub` is ONLY True if the customer has an active subscription (`status = 'active'`).
  - If a customer has cancelled their subscription, any order is treated as standard COD (`is_sub = False`, `amount_due = total_amount`), allowing rider to collect cash at doorstep.
  - In Rider App `pod_sheet.dart`, show standard COD cash collection for cancelled subscription users.

### 6. Customer: Display Rider Name Instead of Vendor Name
- **Specification**:
  - In `workers/api/src/app/services/order_service.py` (lines 355–373):
    - Update query to `LEFT JOIN users ru ON ru.id = s.rider_id`.
    - If `ru.name` is present, serialize `rider_info["name"] = ru.name`, `rider_info["phone"] = ru.phone`.
    - If no rider assigned (`s.rider_id IS NULL`), fall back to vendor name with clear label ("Vendor Delivery Partner").

### 7. Customer: Allow Customer Name & Personal Details Edit (Keep Phone Number Locked)
- **Specification**:
  - In `apps/user_app_donor/lib/features/profile/edit_profile_sheet.dart`:
    - Enable the `Name` field (`enabled: true`).
    - Keep `Mobile number` locked (`enabled: false` with 🔒 lock icon).
  - In `workers/api/src/app/services/auth_service.py:update_me()`:
    - Allow customer role to update `name`.
    - Keep `phone` immutable.

### 8. Rider: Session Persistence & Auto-Refresh (Fix 401 Unauthorized)
- **Specification**:
  - In `apps/rider_app/lib/core/api_client.dart`:
    - Store `refreshToken` in SharedPreferences upon login.
    - Add `tryRefresh()` calling `POST /v1/auth/refresh`.
    - Intercept 401 in `_parseResponse` or request execution to silently renew token and retry the failed request.

### 9. Rider: Order Cancellation with Vendor-Issued OTP
- **Specification**:
  - In `workers/api`:
    - Add `POST /v1/vendor/stops/{stop_id}/cancel-otp`: Vendor generates a 4-digit cancellation OTP stored in `stops.cancel_otp` with 15-minute expiry.
    - Add `POST /v1/rider/stops/{stop_id}/cancel`: Rider submits `{cancel_otp, reason}`. Backend validates OTP, clears stop, marks order `cancelled`, and logs event.
  - In `apps/rider_app`:
    - Add "Cancel Delivery (ऑर्डर रद्द करें)" in `delivery_screen.dart` / `pod_sheet.dart`.
    - Prompts rider to enter the 4-digit Cancellation OTP provided by the Vendor.
  - In `apps/vendor_app`:
    - Stop details screen shows a "Generate Cancellation OTP" button to give to the rider when delivery cannot be fulfilled.

### 11 & 12. Sabhi Apps: Auto-Refresh & No Manual Reload
- **Specification**:
  - Add `WidgetsBindingObserver` in Customer, Vendor, and Rider apps to automatically refresh data when returning to foreground (`AppLifecycleState.resumed`).
  - Add quiet periodic timer (every 20s) on active delivery / tracking screens to sync live status without user intervention.

### 13. Subscription Payment Cadences: Monthly / Weekly / Daily / Each Jar Bill
- **Specification**:
  - In `apps/user_app_donor/lib/features/subscriptions/plan_builder_sheet.dart`:
    - Present 4 billing cadence choices:
      1. `per_delivery`: "Each Jar Bill (हर जार का बिल)"
      2. `daily_bill`: "Daily Bill (रोज का बिल)"
      3. `weekly_postpaid`: "Weekly Bill (हफ्ते का बिल)"
      4. `monthly_postpaid`: "Monthly Bill (महीने का बिल)"
  - In `workers/api/src/app/services/subscription_service.py`:
    - Update `BILLING_MODES` to include `daily_bill` and `weekly_postpaid`.
    - Enforce COD collection at doorstep for all modes.

### 14. Notification System
- **Specification**:
  - Add in-app notification trigger and alert banner across all apps when order state changes (Placed, Assigned, Out for Delivery, Delivered, Cancelled).
  - Add notification badge and real-time banner update.
