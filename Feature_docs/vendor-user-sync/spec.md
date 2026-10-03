# 015 Vendor-User Sync — Spec (approved)

## Goal
User-created order visible to vendor with payment + money truth; 4-state timelines both sides; sub pay-per-day with Due/Paid totals; simple Pull placed pool; Android basics.

## Backend
- `today_route` + `_owned_stop` LEFT JOIN orders + addresses: payment_mode/status, total, deposit_due, order_state, address_label/text/pincode.
- `GET /vendor/placed`: placed orders with no stop yet (limit 50), newest first.
- `GET /ledger/me`: held, deposit_paid/refunded, wallet_held, dues.
- Pricing once-only container deposit (014, kept). Catalog all-days.
- Scheduler still mints per-due orders (pay-per-day). No monthly prepay wallet in 015.

## User app
- Order entity + paymentMode/Status, isPaid.
- Tracking `_HeaderCard` badge: `UPI/COD • Paid` or `• Rs X due`.
- Bill shows mode (existing frozen lines kept).
- Subs: Due today (qty × rate) + Paid till now (billing dues) — computed client-side, no new endpoint.
- Timeline stays 4 steps (Confirmed/Packed/Out/Delivered), terminal -1.

## Vendor app
- `RouteStop` + paymentMode/totalPaise/paymentStatus/isPaid, fromJson maps new join keys, cashDue falls back to total.
- `money.depositDueRs` container-only + wallet flag.
- Route/stop UI shows badge (next slice wires full premium states).
- Dead purge: intl/cupertino already unused — remove in cleanup pass.

## Android
- POST_NOTIFICATIONS both manifests, backup_rules + data_extraction_rules exclude secure storage, allowBackup=false.
- Channel + clear-cache/logout-wipe UI next (015 = manifest + rules only).

## Verify
- backend 193, user 88, vendor 28, analyzes 0.
- Device run still owed: COD/UPI end-to-end, Pull placed, second-container Rs 0.
