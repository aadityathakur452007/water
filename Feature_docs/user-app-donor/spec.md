# Donor-parity customer app (033-donor-parity)

Status: implemented in `apps/user_app_donor` on `033-donor-parity` (2026-10-22); gates green; device smoke and release signing open

## Goal

Ship a customer app that is a **screen/flow clone of the donor app**, backed by the
existing Shodasha Workers API. The donor repo is the UI source of truth; the current
`apps/user_app` remains in place as the production/fallback app.

## Boundary

| App | Change |
|---|---|
| `apps/user_app_donor` | **new** customer app (this feature) |
| `apps/user_app` | untouched |
| `apps/user_app_legacy_flutter` | untouched |
| `apps/vendor_app` | untouched |
| `apps/admin_app` | untouched |
| `workers/api` | read-only; no backend edits |

Git: branch `033-donor-parity` from `032-user-app-replacement` (`f51e06b`), tag
`032-baseline` on the baseline. No push, no `main` commits.

## Donor source

- Repo: `C:\Users\Hp\AppData\Local\Temp\opencode\donor_repo`
- Commit: `76e0eba813081fddfb25df64ddc37d2e56ad75d1`
- Customer UI files: auth login, customer home + top bar/mode/featured/purity cards,
  orders/cards, subscriptions, wallet, profile, saved addresses, support, notifications.
- Staff UI in the donor (rider dashboard, rider delivery, plant hub, owner control
  center) is **out of scope** and stays in `vendor_app`/`admin_app`.

## Architecture

```
apps/user_app_donor/
  lib/
    main.dart                     # composition root; copy of 032 wiring
    core/                         # ApiClient, auth, session, money, theme (reused)
    core/constants/               # donor visual tokens
    features/auth/                # donor login + AuthGate + OTP controller methods
    features/home/                # donor customer home shell + widgets
    features/orders/              # 032 OrdersController + donor order cards
    features/subscriptions/       # 032 SubscriptionController + donor screen
    features/wallet/              # 032 WalletController + donor screen
    features/profile/             # donor profile + donor saved-address list
    features/addresses/           # 032 AddressController/screen/map picker
    features/booking/             # 032 quote/order/payment orchestration
    features/support/             # 032 complaints controller + donor support UI
    features/returns/             # 032 returns flow
```

The new app copies the proven 032 core and controllers. Donor widgets call those
controllers; no second API client, no local repository, no fake money.

## Data law

- All prices, quotes, dues, deposits, order totals, subscription estimates and
  payment states come from the server. Client never computes a payable total.
- Orders are `POST /quotes` → `POST /orders` with `Idempotency-Key`; COD is
  confirmed server-side, UPI uses the server intent/gateway and webhook-poll flow.
- Delivery OTP/PIN is server-owned and read-only for the customer.
- No hardcoded order/PIN/business registry.

## Auth

- Donor phone → OTP screen, customer portal only. No partner/staff tab (staff
  logins live in vendor/admin apps).
- Primary path: `POST /auth/otp/start` then `POST /auth/otp/verify` with
  `{phone, otp_code, device}`. This requires the backend server-code OTP provider
  (`OTP_PROVIDER=fast2sms|textbee`). The default Firebase provider needs a
  Firebase client SDK/config that this repo does not have.
- When the server answers `channel=firebase` (or the code path is unavailable),
  the screen shows an honest configuration message; it does not pretend an OTP
  was sent.
- QA path: existing server-gated `/auth/demo` sheet (seeded phone/code). The
  server decides whether the door is open.
- No fake OTP, no local success, no Firebase dependency added in this slice.

## Donor screens wired

| Donor screen | Real source |
|---|---|
| Login | `/auth/otp/*`, `/auth/demo`, secure session |
| Home top bar | `/auth/me`, selected address, real service slots |
| Mode cards / featured products | `/catalog`, quote + checkout |
| My Orders | `OrdersController` (`GET /orders`, detail/tracking, cancel/reschedule) |
| Subscriptions | `SubscriptionController` (`GET/POST /subscriptions`, pause/skip/cancel) |
| Wallet | `WalletController` (`GET /ledger/me`), payment history, returns |
| Profile | `ProfileController` (`GET/PATCH /auth/me`) |
| Saved addresses | `AddressController` (`GET/POST/PATCH/DELETE /addresses`) |
| Support | `SupportController` (complaints) + call/WhatsApp |
| Notifications | derived from real order/subscription state only |

## Deliberate donor deviations (security/honesty)

1. **No partner portal / rider / plant / owner screens.** Those are staff apps.
2. **No customer "rider deliver" action.** The donor order card can mark an order
   delivered from the customer app; that bypasses rider auth/POD. Replace with
   Track order.
3. **No fake delivery PIN.** Show the server PoD code only when the order detail
   returns it, read-only.
4. **No fake wallet top-up/balance.** Show real ledger: held jars, refundable
   deposit, dues; no invented balance.
5. **No fake live purity telemetry.** Keep the quality card visual but use static,
   verifiable copy (RO+UV/lab-tested), not random live numbers.
6. **No local address search/GPS list.** Use saved server addresses + map picker.
7. **No client price math.** Donor's `pricePerCan`/cart total are removed.

## Accepted reuse deviations (as delivered)

These keep the donor's screen role and copy, but reuse the proven 032 screen
instead of pixel-cloning the donor's local/fake implementation:

- **Subscriptions** — `WATER SUBSCRIPTION` uses the 032 plan list/actions with
  donor cards, pills and title. The donor's `Rs 65/can` 7:00 AM modal is not
  cloned because it computes money locally and writes a local notifier; the 032
  server estimate + plan builder is the real flow.
- **Saved addresses** — `SAVED ADDRESSES` uses the 032 list/form/OSM pin. The
  donor's `AddressStateService` hardcoded Bhopal addresses are not cloned.
- **Support** — `PLANT HELP & SUPPORT` keeps the donor helpline banner grammar,
  then adds real complaint history/submission. The donor's fake “ticket raised”
  dialogs are not cloned.
- **Notifications** — donor layout, but rows derive from real orders and
  subscriptions; no local notification list.
- **Mode cards / featured products** — donor layout, but the third “pump”
  product is omitted because the API has no pump SKU.

## Gates

- `flutter analyze` clean in `apps/user_app_donor`.
- Focused tests: OTP controller, donor order mapping, donor checkout guards, widget
  smoke for the five tabs.
- No changes to vendor/admin/current user app; `git diff --stat` proves it.
- Update `context/progress-tracker.md`, `context/flow.md`, `context/decision.md`.
- Device smoke and release signing remain owner debts; not claimed closed.
