# 026 UPI monthly + Razorpay-truth + compact schedule — Spec

Branch: `026-upi-monthly-redesign` (from main 6d7e740). Approved direction from clarify gate.

## 1. Problem (evidence)

- `apps/user_app/lib/features/booking/booking_sheet.dart:_collectUpi` (L267-312):
  `FAKE-*` refs open `upi://pay?pa=shodasha@upi...` via `launchUrl(externalApplication)`.
  No UPI VPA is configured (`AGENCY_UPI_VPA` default `shodasha@upi`, `UPI_PROVIDER=fake`
  default in `workers/api/src/app/adapters/upi.py:get_provider`), so the intent
  either finds no app or pays a non-existent account. Real `order_*` refs open
  `Razorpay.open` — the only path where `POST /webhooks/upi` can actually mark
  `paid_upi`. Result: "UPI not working as it should".
- Schedule step (`booking_sheet.dart:_scheduleStep` + `booking_controller.dart:DeliveryType`
  5 values) renders a `Wrap` of 5 `ChoiceChip`s + always-present fixed-window card /
  rhythm note + full `TableCalendar` for custom. Cluttered, tall, 5+ rows.
- Subscriptions (`subscription_service.py:create/list`, `subscriptions.py:SubCreateIn`)
  only know `payment_method` (default `cod`), no monthly concept. UI
  (`subscription_screen.dart`) is pay-per-day (`dueTodayPaise = qty*2800`, dues from
  `GET /billing/dues.pay_link` which is itself a `upi://` link).

## 2. Decisions (user-approved)

- **Razorpay-only, no `upi://`.** User: "Razorpay webhook will be our money gathering,
  don't do the UPI link because we don't have configured the UPI account."
  Frontend never launches `upi://`; backend `pay_link` stays as informational server
  truth, UI gates on provider readiness.
- **Monthly = both prepaid + postpaid**, reflected on vendor + admin via existing
  money truth (ledger dues/held + order `payment_mode`), no new money tables.
- **Schedule picker compaction** as senior-designer rewrite (dropdown + progressive
  disclosure), not chip-wall shuffle.

## 3. Scope

### Backend (`workers/api`)
- `012_monthly.sql`: `ALTER TABLE subscriptions ADD COLUMN billing_mode TEXT NOT NULL
  DEFAULT 'per_delivery'` (apply-once; `CREATE` stays idempotent).
- `SubscriptionService`: `billing_mode ∈ {per_delivery, monthly_prepaid, monthly_postpaid}`,
  `payment_method ∈ {upi, cod}` validated; self-healing `PRAGMA table_info` + conditional
  `ALTER` (precedent: `ensure_profile` convergence, ADR-065) so old `:memory:` DBs keep
  working; `INSERT`/`list`/`get_owned` carry `billing_mode`; `list` adds
  `due_today_paise` (existing) + `monthly_estimate_paise = qty*rate*30`;
  `process_due` generated dicts carry `billing_mode`.
- `subscriptions.py:SubCreateIn`: `+ billing_mode` (default `per_delivery`, max 24).
- `payment_service.get_dues`: `+ provider` (`fake|razorpay` from `UPI_PROVIDER`) and
  `+ razorpay_ready: bool` alongside existing `dues/lines/pay_link`. No shape break.
- Scheduler (`jobs/scheduler.py:run_due_subscriptions`): already maps
  `payment_method → payment_mode`; passes `billing_mode` through descriptor (order rows
  keep `payment_mode` only — monthly lives on the subscription).
- Tests: migration-applied harness + new `test_monthly_billing.py`
  (create prepaid/postpaid/cod-monthly, list carries mode + estimate, dues carries
  provider flag, process_due carries mode).

### User app (`apps/user_app`)
- `booking_controller.dart`: `+ enum BillingMode {perDelivery, monthlyPrepaid, monthlyPostpaid}`
  + `billingMode` field (once → forced `perDelivery`).
- `api_client.dart:createSubscription`: `+ billing_mode, payment_method` params.
- `checkout_service.dart:placeCheckout`: passes `billing_mode/payment_method` for
  non-once path; once path unchanged (upi/cod order + `upiIntent`).
- `booking_sheet.dart`: **rewrite** `_scheduleStep` → compact
  `DropdownButtonFormField<DeliveryType>` + progressive disclosure (once → Subah 8–12
  card only; custom → calendar only); **rewrite** `_payStep` → monthly toggle
  (`UPI monthly [prepaid|postpaid]` vs `COD`) for subscriptions; **rewrite**
  `_collectUpi` → Razorpay-only (reject empty/non-`order_/rzp_` refs with honest
  maintenance copy, never `launchUrl(upi://)`).
- `subscription_screen.dart`: billing-mode badge + monthly estimate row; dues row uses
  `provider/razorpay_ready` (real link only when ready, else COD-to-vendor guidance).

### Vendor app
- No schema change. Stops/customers already show `paymentMode + held/dues`
  (`route_controller/route_screen/stop_detail`). Subscription monthly orders flow
  through scheduler `payment_method → payment_mode`, so vendor sees them as
  `UPI/COD • Collect` with zero code change. Verified, not rebuilt.

### Admin (`apps/admin_app`)
- No new page. Payments screen already filters `upi/cod`; dues/finance already read
  ledger. Monthly visibility = subscription `billing_mode` on API + dues truth.
  Dedicated subs admin page parked as future.

## 4. Success criteria
- `POST /subscriptions` with `monthly_prepaid/upi` persists + lists with estimate;
  `monthly_postpaid/cod` persists; invalid mode → 400.
- Checkout UPI with `FAKE-*` ref never opens an external app; shows maintenance + COD path.
- Checkout UPI with real `order_*` + key opens Razorpay; success re-reads
  `GET /orders/{id}` for `paid_upi`.
- Schedule step is 1 dropdown + 1 contextual block (no 5-chip wall).
- `pytest` green; `flutter analyze` 0; no new packages; no `upi://` launch path left.
