# Shodasha — Auth, UPI, Subscription & Vendor-Flow Audit

- **Date:** 2026-10-24
- **Branch:** `035-premium-ui-states-release` @ `1ec478065b625ee247935df5f0dab214a44d4074`
- **Mode:** read-only audit. No application code, schema, production data, deployment, or push was changed.
- **Skill:** `security-audit` (guidance mode; findings carry file:line or live-request evidence).
- **Verdict:** Authentication is live and behaves correctly. **Money and subscription flows are release-blocked by five P0 defects.**

---

## 1. Environment

| Item | Value | How verified |
|---|---|---|
| API base | `https://water.adityathakur452007.workers.dev/v1` | Live requests |
| Worker | `water`, version `07e98028-2434-4487-aad1-be52938f97cb` | Recorded at audit start (ADR-132) |
| D1 | `shodasha`, 26 migrations through `027_pod_otp_lifecycle.sql` | `wrangler.jsonc`, local migrate output |
| Cron trigger | `*/15 * * * *` | `workers/api/wrangler.jsonc:34-37` |
| Production users at start | **9** | ADR-132 baseline; not re-read during this audit |
| Expected after QA registration | 10 | Unverified: no D1 authentication |
| QA user | `69af983e97af40f2aeb4e2c2f2b4ba33`, phone `+91 90000 7***`, device `qa-sub-20261024-0826` | Register response |
| QA order | `110cb098df6841fb9a6aa6b4424cf287` | Order create response |
| QA payment | `051007dd27ef4080a0d59b0daa35b20c` | UPI intent response |
| Razorpay order | `order_Trg9yamrg2L9fm` (test-mode key) | UPI intent response |
| Local harness | Disposable SQLite, migrations 002–027, Razorpay HTTP stubbed | `local-*.out.txt` |
| Evidence directory | `%TEMP%\shodasha-audit-20261024` | Sanitized bodies/headers, scripts, outputs |

**Safety rules observed:** no owner phone, no existing user, no password guessing, no brute force, no rate-limit hammering, no real-money payment, no token in any report or commit. Token files in the evidence directory contain `REDACTED (revoked)`.

**Stop rule:** after the live dues-intent 500 (P0-1), destructive production testing was stopped. All remaining money/subscription scenarios were reproduced locally against disposable SQLite, labelled **LOCAL**.

---

## 2. Executive Summary

The auth surface passed every live scenario: registration, duplicate-account refusal, login, generic wrong-password rejection, refresh rotation with reuse detection, logout revocation, and per-device sessions. The UPI webhook also fails closed: unsigned and forged signatures both returned 401, and a captured event was idempotent.

The money layer is not release-ready:

| ID | P0 finding | Impact | Evidence |
|---|---|---|---|
| **P0-1** | `POST /v1/payments/dues-intent` returns **500** because `payments.order_id` has a foreign key to `orders(id)` and the dues path inserts the synthetic value `dues:<user_id>`. | Customer can never pay dues by UPI. The Razorpay order is created **before** the failing DB insert, so every retry leaves an orphan provider order. | Live trace `6566a78274c34563`; `005_payments.sql:9`; `payment_repo.py:275-280`; `payment_service.py:110-120` |
| **P0-2** | A canceled unpaid UPI order stays `payment_status=link_sent`; the payment link is not voided; `GET /billing/dues` still counts it; a captured webhook settles the canceled order to `paid_upi` with no refund row. | Customer can pay after cancelling. Dues never clear. Money can be taken against a canceled order. | Live: cancel `ab304517904c4818`, dues `2bf72ca7a16e49d1`; LOCAL: `local-cancel-webhook.out.txt` |
| **P0-3** | Cancellation accounting is not based on collected money. A UPI plan with ₹56 unpaid dues and **zero payments** cleared those dues to 0 and claimed a ₹1,624 refund; a monthly-prepaid plan created 0 payments but claimed ₹1,680; the delivered-order lookup misses scheduler orders because the stored idempotency key has a `POST /v1/orders:` prefix. | Users can erase dues by cancelling a UPI plan. Refund liabilities are invented. Proration overstates refunds. | LOCAL: `local-cancel-dues.out.txt`, `local-sub.out.txt`, `local-proration.out.txt`; `subscription_service.py:214-216,323-335` |
| **P0-4** | Production subscriptions never generate delivery orders. The Worker cron handler is a logged no-op; `process_due()` only returns descriptors and never creates order rows. The local scheduler does create orders and is idempotent, but it is not wired to the cron. | A “daily plan” never delivers. Recurring revenue and retention promise are dead in production. | `entry.py:37-42`; `subscription_service.py:508-558`; `wrangler.jsonc:34-37`; LOCAL: `scheduler_run1_created=1 run2_created=0` |
| **P0-5** | A same-key UPI intent retry calls the provider **again** before checking idempotency, returns the second link/ref, but the database keeps the first payment row. | Retrying a stalled “Pay” can hand the customer a link the backend cannot settle; a webhook for it resolves to an unknown ref (404), so money can be taken without being credited. Every retry also leaves an orphan Razorpay order. | LOCAL: `local-intent-idem.out.txt`; `payment_service.py:39-45`; `payment_repo.py:143-157` |

**Do not enable customer subscriptions or advertise “pay dues by UPI” until P0-1 through P0-5 are fixed.**

---

## 3. What Passed

These are not inferred from code existence; each has a live status/trace or a local output.

| Area | Result | Evidence |
|---|---|---|
| Catalog/readiness | 200, correct paise values | `GET /catalog` trace `999e3a16ab81485f` |
| Register | 200, token pair, `user_id`, device alert | trace `54cefc4b1a654439` |
| Duplicate register | 409 `ACCOUNT_EXISTS`, no session minted | trace `e89effe38a93426b` |
| `/auth/me` | 200 with the registered identity | trace `7484716efa264029` |
| Correct login | 200 | trace `d5a462beccc84427` |
| Wrong password | 401, generic message, no account oracle | trace `a69eff4db6784f72` |
| Refresh rotation | 200 with a new pair | trace `cbc422b4fa994004` |
| Refresh reuse detection | old refresh 401; the rotated access token was also revoked | traces `2671a644c2154c55`, `5a700424b8b54cc5` |
| Logout | 200 `{"ok":true}`; `/auth/me` then 401 | traces `b24fd0e7a2424210`, `e18d13b29d234b92` |
| Address create/delete | 201 / 204 | traces `3387d02043364cc4`, `c1dd8d089d4348f4` |
| Quote | 200, ₹56 for 2 refills, hash returned | trace `e9a9f98e97234f6c` |
| Order create | 201, total 5600, state `placed` | trace `d526a748eeaa4de5` |
| UPI intent | 201, real Razorpay test order + `upi://` link | trace `14a7f4bbf79d440a` |
| Unsigned webhook | 401 `UNAUTH` | trace `2ccbb319dfa94c9d` |
| Forged signature | 401 `UNAUTH` | trace `2c4b2564d1054b04` |
| Webhook replay | 200 duplicate, exactly one payment row | LOCAL: `local-webhook.out.txt` |
| Webhook amount mismatch | 422 `AMOUNT_MISMATCH` | LOCAL: `local-webhook.out.txt` |
| Unknown provider ref | 404 `NOT_FOUND` | LOCAL: `local-webhook.out.txt` |
| Scheduler idempotency | first run 1 order, replay 0; `next_run` advanced | LOCAL: `local-sub.out.txt` |

The auth behavior is materially better than the prior 028 audit: the webhook is fail-closed with the real provider, and refresh-token reuse now kills the rotated access token.

---

## 4. Live Scenario Matrix

All requests were made with `curl.exe` against the production Worker. No request printed a token.

### 4.1 Auth and account

| # | Scenario | Request | Status | Result | Trace |
|---|---|---|---|---|---|
| A1 | Register disposable customer | `POST /auth/user/register` | 200 | PASS; token pair, user id, `new_device_alert:true` | `54cefc4b1a654439` |
| A2 | Register same phone again | `POST /auth/user/register` | 409 | PASS; `ACCOUNT_EXISTS`, no session | `e89effe38a93426b` |
| A3 | Read own profile | `GET /auth/me` | 200 | PASS | `7484716efa264029` |
| A4 | Correct password login | `POST /auth/user/login` | 200 | PASS | `d5a462beccc84427` |
| A5 | Wrong password | `POST /auth/user/login` | 401 | PASS security; **contract drift:** code is `UNAUTH`, spec says `INVALID_CREDENTIALS` | `a69eff4db6784f72` |
| A6 | Rotate refresh token | `POST /auth/refresh` | 200 | PASS; new pair | `cbc422b4fa994004` |
| A7 | Reuse old refresh token | `POST /auth/refresh` | 401 | PASS; reuse detected | `2671a644c2154c55` |
| A8 | Use rotated access token after reuse | `GET /auth/me` | 401 | PASS; token family revoked | `5a700424b8b54cc5` |
| A9 | Logout | `POST /auth/logout` | 200 | PASS; `{"ok":true}` | `b24fd0e7a2424210` |
| A10 | Use access token after logout | `GET /auth/me` | 401 | PASS | `e18d13b29d234b92` |

### 4.2 Money and cleanup

| # | Scenario | Request | Status | Result | Trace |
|---|---|---|---|---|---|
| M1 | Create Bhopal test address | `POST /addresses` | 201 | PASS | `3387d02043364cc4` |
| M2 | Quote 2 refills | `POST /quotes` | 200 | PASS; 5600 paise | `e9a9f98e97234f6c` |
| M3 | Create UPI order | `POST /orders` | 201 | PASS; state `placed`, `payment_status=unpaid` | `d526a748eeaa4de5` |
| M4 | Create UPI intent | `POST /payments/upi-intent` | 201 | PASS; Razorpay `order_Trg9yamrg2L9fm`, link `am=56.00` | `14a7f4bbf79d440a` |
| M5 | Unsigned webhook | `POST /webhooks/upi` | 401 | PASS; fail-closed | `2ccbb319dfa94c9d` |
| M6 | Forged-signature webhook | `POST /webhooks/upi` | 401 | PASS; fail-closed | `2c4b2564d1054b04` |
| M7 | Pay dues by UPI | `POST /payments/dues-intent` | **500** | **FAIL (P0-1):** `SERVER`; local FK-on repro confirms the constraint failure | `6566a78274c34563` |
| M8 | Cancel unpaid UPI order | `POST /orders/{id}/cancel` | 200 | **FAIL (P0-2):** order `cancelled`, payment still `link_sent` | `ab304517904c4818` |
| M9 | Read dues after cancel | `GET /billing/dues` | 200 | **FAIL (P0-2):** still ₹56, line status `link_sent` | `2bf72ca7a16e49d1` |
| M10 | List subscriptions | `GET /subscriptions` | 200 | PASS; `{"data":[]}` for the QA user | `91b19e28612b4a96` |
| M11 | Delete test address | `DELETE /addresses/{id}` | 204 | PASS; cleanup | `c1dd8d089d4348f4` |

### 4.3 Blocked live scenarios

| Scenario | Why blocked | Safety decision |
|---|---|---|
| Live subscription create/cancel | Stopped after M7 P0, per the stop rule | Local SQLite only |
| Live vendor route/stop/PoD | No vendor access code; no brute force | Code trace only |
| Live admin dispatch/visibility | No admin access code | Code trace only |
| Valid signed live webhook | `UPI_WEBHOOK_SECRET` not available | Local `_rzp.py` signed harness |
| Production cron execution/logs | No `wrangler` authentication | Code trace + local runner |
| D1 cleanup and user-count verification | `npx wrangler whoami` = not authenticated (rechecked 2026-10-24) | Rows left in place, ids reported |
| Real UPI app / device return | No device, no live money allowed | Not attempted |

---

## 5. Local Scenario Matrix

All local runs used the real service/repository code, a disposable SQLite database, 26 migrations, and a stubbed Razorpay HTTP boundary. They are not production calls.

| # | Scenario | Result | Evidence |
|---|---|---|---|
| L1 | Dues intent with SQLite FK **off** | Succeeds; payment row inserted with `order_id=dues:u1` | `repro-dues-fk.out.txt`: `FK=False: OK` |
| L2 | Dues intent with SQLite FK **on** | Fails `FOREIGN KEY constraint failed` (wrapped as `ConflictError` by the stdlib path) | `repro-dues-fk.out.txt`: `FK=True ... cause=IntegrityError` |
| L3 | Two active daily plans | Both created; 2 active rows for one user | `local-sub.out.txt`: `active_count=2` |
| L4 | One-time order while a plan is active | Created; total 5600, state `placed` | `local-sub.out.txt` |
| L5 | `monthly_prepaid` + `upi` create | 0 payments created | `local-sub.out.txt` |
| L6 | Cancel that prepaid plan | `is_prepaid=True`, claimed ₹1,680, no refund row, dues unchanged (0) | `local-sub.out.txt` |
| L7 | Cancel a UPI per-delivery plan with ₹56 dues | Dues **5600 → 0**; claimed ₹1,624; 0 payments; 0 refund rows | `local-cancel-dues.out.txt` |
| L8 | Proration lookup | `delivered_query_used_by_cancel=0` while 1 delivered order exists | `local-proration.out.txt` |
| L9 | Scheduler first run / replay | 1 order created / 0 on replay; `next_run=2026-10-26` | `local-sub.out.txt` |
| L10 | Captured webhook | 200, order `paid_upi`, payment `paid` | `local-webhook.out.txt` |
| L11 | Webhook replay | `duplicate=True`, 1 payment row | `local-webhook.out.txt` |
| L12 | Bad signature | 401 `UNAUTH` | `local-webhook.out.txt` |
| L13 | Amount mismatch | 422 `AMOUNT_MISMATCH` | `local-webhook.out.txt` |
| L14 | Failed event | `ok=True`, `declined=True`, order/payment remain `link_sent` | `local-webhook.out.txt` |
| L15 | Authorized event | `ok=True`, `ignored=True` | `local-webhook.out.txt` |
| L16 | Unknown ref | 404 `NOT_FOUND` | `local-webhook.out.txt` |
| L17 | Cancel order, then captured webhook | Order `cancelled` + `paid_upi`; payment `paid`; dues 0; no refund row | `local-cancel-webhook.out.txt` |
| L18 | Same-key UPI intent retry | 2 provider calls, 1 payment row; second response returns `order_RETRY2`, but the second ref was never stored | `local-intent-idem.out.txt` |

---

## 6. Findings

### P0-1 — Dues UPI payment is dead: FK violation turns into a 500, and the provider order is created first

**Live evidence**

```
POST /v1/payments/dues-intent
HTTP/1.1 500 Internal Server Error
{"error":{"code":"SERVER","message":"Internal error","details":{},"trace_id":"6566a78274c34563"}}
```

At the same time, `GET /billing/dues` reported `dues=5600` for the canceled QA order. The customer has dues and no way to pay them.

**Root cause**

- `payments.order_id` is declared `TEXT NOT NULL REFERENCES orders (id)` (`workers/api/src/app/db/migrations/005_payments.sql:9`).
- The dues path inserts the synthetic value `dues:<user_id>` into that column (`workers/api/src/app/repositories/payment_repo.py:275-280`).
- No `orders` row has that id, so D1 rejects the insert. The live Worker surfaces it as an uncaught 500.
- The provider call happens **before** the insert: `created = self.provider.create_intent({"id": f"dues-{user_id}", "total": dues})` (`workers/api/src/app/services/payment_service.py:118`), then `create_dues_intent(...)` (`:119-120`).
- The local stdlib path catches `sqlite3.IntegrityError` and wraps it as `ConflictError` (`payment_repo.py:290-296`). The live Worker returns 500, so the D1 path is not mapping this constraint failure to a 4xx. Even the local path proves the FK is the blocker.

**Impact**

- Dues UPI is completely unavailable, while the UI/Wallet presents it as available.
- Each retry creates another Razorpay order with receipt `dues-<user_id>`, but no local payment row. Those provider orders are orphaned. A webhook for one of them would 404 as an unknown ref, so a payment against an orphan link would not be credited.

**Why tests missed it**

- The test suite opens SQLite without enabling foreign keys (`workers/api/src/app/db.py:92`; `workers/api/tests/test_payments.py:53`). The targeted suite (34 tests) passes while the production FK is active.
- No test asserts that `create_dues_intent` works with `PRAGMA foreign_keys=ON`.

**Fix direction (not implemented)**

- Make the dues intent durable before calling Razorpay: either allow `payments.order_id` to be nullable for dues rows, or add a dedicated `dues_intents` table. Insert the local intent, then create the provider order, then update the row — with compensation/void on provider failure.
- Add a regression test with `PRAGMA foreign_keys=ON` and a D1-shaped adapter.
- Add a provider-order reconciliation/cleanup job for receipts matching `dues-*`.

---

### P0-2 — A canceled unpaid order remains payable and continues to count as dues; the webhook will settle it

**Live evidence**

```
POST /orders/110cb.../cancel -> 200
{"order_id":"110cb...","state":"cancelled","bill_total":0,"deposit_reversed":0,"refund":null}
```

Then:

```
GET /billing/dues -> 200
{"dues":5600,"lines":[{"order_id":"110cb...","total":5600,"paid":0,"due":5600,"status":"link_sent"}],
 "pay_link":"upi://pay?pa=adityathakur…@oksbi&pn=Shodasha&am=56.00&cu=INR",
 "provider":"fake","razorpay_ready":false}
```

The order detail confirms `state:"cancelled"` and `payment_status:"link_sent"` (`order-detail.body.json`).

**Local proof that the webhook settles it**

`local-cancel-webhook.out.txt`:

```
before={'state': 'placed', 'payment_status': 'link_sent'} payment=link_sent
cancel_refund=None after_cancel={'state': 'cancelled', 'payment_status': 'link_sent'} payment=link_sent
webhook_ok=True after_webhook={'state': 'cancelled', 'payment_status': 'paid_upi'} payment=paid dues=0
```

A captured webhook flips the canceled order to `paid_upi` and marks the payment `paid` — with **no refund row**, because `cancel_settle` only creates a refund when the order was already in `PAID_STATUSES` at cancel time. In the live scenario the `link_sent` order is what keeps the ₹56 in `get_dues`; once it flips to `paid_upi`, the dues line disappears without a refund ever being queued. (The local run started with ledger dues 0, so the printed `dues=0` is not itself proof of clearing.)

**Root cause**

- `OrderRepo.cancel_settle` updates `orders.state` and, when money was already collected, inserts a refund. It never voids or closes the open payment intent (`workers/api/src/app/repositories/order_repo.py:419-485`).
- `PaymentRepo.apply_webhook` looks up the payment by provider ref and updates it, then updates the order to `paid_upi`, without checking `orders.state` (`workers/api/src/app/repositories/payment_repo.py:191-218`).
- `PaymentService.get_dues` selects every order with `payment_status IN ('unpaid','link_sent','partial_dues')` and does not exclude `state='cancelled'` (`workers/api/src/app/services/payment_service.py:126-142`).

**Impact**

- A customer who cancels but still has the Razorpay link can pay for a canceled order.
- The order becomes `cancelled` + `paid_upi`; no refund is queued.
- The customer continues to see ₹56 dues on a canceled order, and the pay-dues button is broken anyway (P0-1).
- This is a real-money exposure when live keys are used. The audit used test keys, so the QA order is test-mode only.

**Fix direction**

- On cancel, mark any open payment intent `void`/`cancelled` and, where supported, void the provider order/link.
- Reject webhook settlement when `orders.state='cancelled'` (or settle + auto-refund in the same transaction; never leave it silently paid).
- Exclude canceled orders from `get_dues` and from any “pending payment” list.
- Add a state-machine test: create → intent → cancel → captured webhook must not produce `paid_upi`.

---

### P0-3 — Cancellation writes off dues and invents refunds without collected money

**Local evidence — dues wipe**

`local-cancel-dues.out.txt` (UPI per-delivery plan, no payments, ₹56 ledger dues):

```
before_cancel: dues=5600 deposit_paid=0 payments=0
cancel_response: is_prepaid=True claimed_refund=162400 return_id=None
after_cancel: dues=0 deposit_paid=0 refund_rows=0
```

**Local evidence — prepaid claim with zero collection**

`local-sub.out.txt`:

```
monthly_prepaid: billing_mode=monthly_prepaid payments_created=0
cancel_response: is_prepaid=True unused_water_refund_paise=168000 return_id=None
cancel_row: canceled_at_set=True refund_amount_paise=168000 ledger_dues_before=0 after=0
```

**Local evidence — proration lookup misses the scheduler key**

`local-proration.out.txt`:

```
delivered_query_used_by_cancel=0 actual_delivered_orders=1
cancel_claim: is_prepaid=True unused_water_refund_paise=168000
```

The scheduler writes order idempotency keys as `POST /v1/orders:sub:<sub_id>:<date>` (`order_service.py:31,165`; `workers/api/src/app/jobs/scheduler.py:114`), but the cancel query looks for `sub:<sub_id>:%` (`subscription_service.py:323-325`). It therefore counts zero delivered orders and refunds the full 30-day cycle.

The harness printed `expected_if_prorated_one_day=166400`; recomputing gives **₹1,624** (`30 × 2 × ₹28 − 1 × 2 × ₹28 = ₹1,680 − ₹56`), not ₹1,664. The important fact is the zero delivered count, not the harness annotation.

**Root cause**

- `is_prepaid` is inferred from `payment_method in ('upi','prepaid','online')`, not from an actual prepaid charge (`subscription_service.py:333`).
- `unused_refund_paise = 30-day cycle total - delivered_cost` is computed even when the payment table has zero rows (`:329-335`).
- The cancel handler then applies `d_dues=-min(unused_refund_paise, dues)` (`:382-392`), which **reduces real dues** as if a refund had been paid.
- No `refunds` row is created for a subscription cancel; only `subscriptions.refund_amount_paise` is set (`:370-380`).
- The delivered-order query uses the wrong key prefix (`:323-325` vs `order_service.py:31,165`).

**Impact**

- A customer with ₹56 COD dues can create a UPI plan, cancel it, and have the dues erased without paying. This is a direct write-off.
- The response and UI claim a refund that was never collected and is not queued.
- Proration is wrong for every scheduler-generated delivered order.

**Fix direction**

- Compute refunds from `payments`/ledger credits, never from `payment_method`.
- Do not write off `ledger.dues` on cancellation unless an actual refund/credit transaction is recorded.
- Query delivered orders with the exact stored prefix (`POST /v1/orders:sub:<id>:%`), or better, store a `subscription_id` / `source` column and query that.
- Add tests: zero payments + dues > 0 → no dues change, no refund claim; one delivered scheduled order → prorated amount.

---

### P0-4 — Production subscriptions never create delivery orders

**Code evidence**

`workers/api/src/entry.py:37-42`:

```python
async def scheduled(self, controller, env, ctx):
    set_worker_env(env)
    # ... This tick stays a logged no-op until the cron wiring is tested against real D1.
    print("water: cron tick received, scheduler async-ready, wiring pending.")
```

`workers/api/src/app/services/subscription_service.py:508-558` returns descriptors only:

```python
"""Generate due runs + fire auto-resumes. ... Returns descriptors the future cron
turns into orders (order-row creation stays with the orders slice ...)."""
```

The working order-creating runner is `workers/api/src/app/jobs/scheduler.py:78-131`; it calls `SubscriptionService.process_due()` and then `OrderService.create(..., f"sub:{sub_id}:{date}")`. Local output shows it works and is idempotent (`run1_created=1`, `run2_created=0`). The cron handler never calls it.

**Impact**

- A customer can create a “daily” plan, but no delivery order is ever generated by the production Worker.
- The UI promises a next run (`next_run` is returned), but nothing executes it.
- A plan order appears only if someone runs the local job manually or inserts it out-of-band; the production cron never creates one.

**Fix direction**

- Wire `scheduled()` to the existing `run_all`/`run_due_subscriptions` with a real `D1Conn`, a bounded batch, and an invocation log.
- Add a production canary: create a disposable subscription due today, run the cron tick, assert one order and one replay no-op.
- Remove the “subscription” promise from release copy until this is live.

---

### P0-5 — A same-key UPI intent retry creates a second provider link and returns a reference the database does not store

**Local evidence**

`local-intent-idem.out.txt` (two `PaymentService.intent` calls with the same idempotency key):

```
provider_calls=2 receipts=['o1', 'o1']
first_ref=order_RETRY1 second_ref=order_RETRY2 payments_rows=1
```

The second call created `order_RETRY2` at the provider and returned its link, but `payments` still holds only the first call's row; the second ref was never stored.

**Root cause**

- `PaymentService.intent` calls `self.provider.create_intent(order)` unconditionally (`workers/api/src/app/services/payment_service.py:39`), **before** the repository checks the idempotency key.
- The repository replay returns the stored payment (`workers/api/src/app/repositories/payment_repo.py:152-157`), which carries the first provider ref, but the service ignores that row when building the response and returns the freshly created ref/link (`payment_service.py:40-45`).
- Idempotency therefore protects the database row, not the provider side effect.

**Impact**

- A double-tap or timeout retry on “Pay with UPI” creates a new Razorpay order each time. Only the first is recoverable by the backend.
- The retry response contains a link whose `provider_ref` is absent from `payments`. A captured webhook for that link takes the unknown-ref path (`payment_repo.py:195-196`; proven 404 as L16), so a successful payment is not credited and dues do not change.
- This is a money-capture risk whenever live keys are enabled, not only test noise.

**Fix direction**

- Check the idempotency key **before** any provider call and return the stored payment plus its original link.
- If a provider call is required, persist a `pending` intent with the key first, then create the provider order, then update the row; compensate/void on failure.
- Add a test asserting: same key twice → provider called once, second response ref equals the first, one payment row.

---

### P1-1 — Duplicate active plans are allowed

**Evidence:** `local-sub.out.txt` creates two active daily plans for the same user/address with different idempotency keys: `first=0f9b... second=0993... both_created=True active_count=2`.

`SubscriptionService.create` checks quantity, address, schedule, payment method, and billing mode, but never checks for an existing active plan for the same user/address (`subscription_service.py:187-259`).

**Impact:** two daily deliveries, double deposits, double vendor load, confused cancellation/refund accounting. The customer UI has no “you already have a plan here” guard.

**Fix direction:** enforce one active plan per `(user_id, address_id)` at the service/DB layer, or explicitly support multiple plans with a clear UI and separate schedules. Add a unique partial index if the one-plan rule is chosen.

---

### P1-2 — One-time orders are allowed while a plan is active

**Evidence:** `local-sub.out.txt` creates a one-time order while two plans are active: `one_time_order_while_active: created=f9bb... total=5600 state=placed`.

`OrderService.create` has no active-subscription check (`order_service.py:162-300`).

**Impact:** the customer can receive the same jars twice on the same day, double-charge deposits, and create conflicting vendor stops. The Home screen does not warn that a plan already covers the address.

**Fix direction:** if a plan is active for the address and covers the requested window, block or warn: “Your plan already delivers 2 jars on this date.” Allow an override only with explicit acknowledgment.

---

### P1-3 — Payment/billing mode is decorative; UPI plan deliveries have no intent, and monthly modes are never charged

**Evidence**

- The donor plan builder deliberately does not send payment or billing mode: `plan_builder_sheet.dart:12-14` (“The payment/billing mode fields are not sent because the ported ApiClient.createSubscription contract does not carry them (server default: per-delivery COD).”).
- The API client body has only `address_id`, `qty`, `sku_mix`, `window`, `schedule_type`, `recurrence` (`api_client.dart:762-781`).
- Checkout’s subscription branch also omits `paymentMethod` and `billingMode` (`checkout_service.dart:210-250`).
- The server stores `billing_mode` (`subscription_service.py:245-256`) but the scheduler only uses `payment_method` to set the order’s `payment_mode` (`scheduler.py:104-115`); it never charges a monthly cycle or creates a prepaid payment.
- `monthly_prepaid` + `upi` created **0 payments** in `local-sub.out.txt`.

**Impact**

- Every plan created from the current donor UI is per-delivery COD, regardless of what the customer thought they chose.
- If a UPI plan is created through the API/legacy UI, the scheduled order is `payment_mode=upi` but no intent/link is generated. Collection depends on the customer opening the order and starting a payment, or the vendor collecting cash at the door.
- `monthly_prepaid`/`monthly_postpaid` are labels with no money path.

**Fix direction:** decide the v1 billing model and implement one path. If per-delivery, remove monthly modes from the API/UI. If prepaid, charge at plan creation and consume credit per delivery. Send the chosen mode from every client and include it in the idempotency hash (see P1-5).

---

### P1-4 — Vendors cannot see that a stop is a subscription delivery; auto-assign only works for pre-bound customers

**Evidence**

- The vendor route query selects order fields but no source/subscription id (`vendor_service.py:315-329`).
- `_stop_out` adds items, customer name/phone, and instructions, but no plan marker (`vendor_service.py:1190-1202`).
- The only marker is the order’s idempotency key `POST /v1/orders:sub:<id>:<date>`, which is not exposed to the vendor.
- `auto_assign_trusted_vendor` returns `None` unless `users.assigned_vendor_id` is set (`dispatch_service.py:434-448`). New customers’ subscription orders therefore stay `placed` and never appear on a vendor route until an admin assigns them.
- `today_route` still has a TODO for paused-subscription/late-skip coverage (`vendor_service.py:367`).

**Impact:** the vendor sees plan deliveries as ordinary one-time orders, cannot prioritize recurring customers, and may not see them at all for new customers. The customer sees “next delivery” while no vendor has the stop.

**Fix direction:** persist `source='subscription'` and `subscription_id` on the order/stop DTO; show a “Plan delivery” pill and the plan cadence in the vendor app; auto-assign by zone/capacity when no trusted vendor exists; add a dispatch queue view for `placed` subscription orders.

---

### P1-5 — Subscription idempotency hash excludes payment, billing, and schedule fields

**Evidence:** `subscription_service.py:214-216` hashes only `{address_id, qty, schedule_type, recurrence}`. It omits `payment_method`, `billing_mode`, `window`, and `next_run`. The same idempotency key with a changed payment/billing mode replays the old plan instead of returning `PAYLOAD_MISMATCH` (`:217-230`).

**Impact:** once the UI starts sending these fields, changing “UPI” to “COD” on a retry with the same key will silently keep the old plan. The customer cannot see the mismatch.

**Fix direction:** include every money-relevant field in the hash, and rotate the key when any of them changes (the order checkout already does this).

---

### P1-6 — Customers cannot see or manage their plan from the primary surfaces

**Evidence**

- Home has no active-plan/next-delivery state (`customer_home_screen.dart:84-125`).
- The Wallet “Review dues” action routes to Subscriptions, not to a dues-payment surface (`donor_wallet_screen.dart:413-456`).
- The subscription card shows address, quantity, window, next run, due, and monthly estimate, but no payment method or billing mode (`subscription_screen.dart:752-855`).
- The cancel sheet promises “Unused water (if prepaid) and the jar deposit are refunded to your UPI after pickup” and the result says “the refund is on its way” (`subscription_controller.dart:91-101`), even when no refund row exists.

**Impact:** a customer with an active plan sees no plan on Home, cannot tell how they will pay, and is misled about refunds. Wallet’s primary dues action leads to a plan list, where the dues strip is a second step.

**Fix direction:** add the Home plan banner; add payment/billing rows to the card; route “Review dues” to a dues sheet that actually calls dues-intent; replace the refund copy (see §9).

---

### P2-1 — `GET /billing/dues` reports `provider:"fake"` and `razorpay_ready:false` while real Razorpay intents work

**Evidence:** live dues body `provider:"fake", razorpay_ready:false`; live UPI intent returned Razorpay `order_Trg9yamrg2L9fm`. `get_dues` reads `UPI_PROVIDER` with a default of `fake` (`payment_service.py:154-161`), while the DI factory always returns the live provider (`upi.py:186-192`).

**Impact:** the API contradicts the actual payment path. Any UI/consumer that trusts `razorpay_ready` will hide or degrade UPI. The donor app currently does not read the field, so this is not a live UI break — but it is a contract lie.

**Fix direction:** derive readiness from the provider/key configuration actually used by `get_provider()`, or delete the field.

---

### P2-2 — Order address snapshots lose the house number

**Evidence:** live order detail: `delivery_address.house_no = null`, while the address was created with `house:"QA 24/7"` and `formatted:"QA 24/7, Zone 1 Test Lane, ..."`. The snapshot reads `addr_row.get("house_no")` (`order_service.py:238`), but the address model/column is `house` (`addresses.py:63`, `address_repo.py:102-118`).

**Impact:** the structured delivery snapshot has no house number; vendors must parse `formatted`. Any consumer that uses `house_no` gets a blank.

**Fix direction:** snapshot `house` (and, if desired, map it to `house_no` for API compatibility). Add a snapshot test that asserts every address field survives.

---

### P2-3 — Auth error-code contract drift: `UNAUTH` vs `INVALID_CREDENTIALS`

**Evidence:** live wrong-password 401 body has `"code":"UNAUTH"` (`auth-login-wrong.body.json`); the spec says `401 INVALID_CREDENTIALS` (`spec-034-auth-password-delivery-otp.md:365`). The code raises `UnauthError("Invalid mobile number or password.")` (`auth_service.py:583-585`).

**Impact:** clients that branch on `INVALID_CREDENTIALS` will fall through to a generic handler. The current donor app checks status 401, so the live UX still works.

**Fix direction:** either change the spec to `UNAUTH` or add a specific code while keeping the generic message. Do not leak whether the phone exists.

---

### P2-4 — A failed payment event is a no-op; the order stays `link_sent`

**Evidence:** LOCAL: `failed_event: ok=True declined=True order_payment=link_sent payment_row=link_sent` (`local-webhook.out.txt`). `webhook_ingest` returns `{"ok": True, "declined": True, ...}` before touching the payment/order (`payment_service.py:56-57`).

**Impact:** the customer is not told the payment failed; the order/payment remain in “link sent” indefinitely. This is not a money-loss bug (the customer can retry), but it is a status-honesty and support burden.

**Fix direction:** record a `failed` attempt (status + timestamp + reason) and show “Payment failed — try again” in the order/dues UI. Keep the order payable.

---

### P2-5 — Tests do not enforce SQLite foreign keys, so the P0-1 class of bug is invisible

**Evidence:** `get_connection` calls `sqlite3.connect(...)` without `PRAGMA foreign_keys=ON` (`db.py:92`); tests use it directly (e.g. `test_payments.py:53`). The targeted 34 tests pass; the local FK-on repro fails.

**Impact:** schema-contract bugs pass CI. The production D1 always enforces the FK.

**Fix direction:** enable `PRAGMA foreign_keys=ON` for test connections (or a dedicated D1-shaped fixture) and add a migration-contract test.

---

### P2-6 — Cancellation copy promises a refund “on its way” even when none exists

**Evidence:** `subscription_controller.dart:91-101` says “Unused water (if prepaid) and the jar deposit are refunded to your UPI after pickup” and “the refund is on its way.” Local cancel with zero payments and zero refund rows still returns a positive `unused_water_refund_paise` (`local-sub.out.txt`).

**Impact:** the customer expects money that was never collected and is not queued. This is a trust and support issue.

**Fix direction:** conditional copy based on actual collected payments and a created refund row; see §9.

---

## 7. Subscription Deep Dive

### 7.1 Actual lifecycle (as built)

```
POST /subscriptions
  -> validate qty/address/schedule/payment_method/billing_mode
  -> optional idempotency replay (hash excludes payment/billing/window/next_run)
  -> INSERT subscriptions(status='active')
  -> return row + first_cycle_estimate
        |
        +--> production cron: scheduled() = no-op  ----------------> NO ORDER
        |
        +--> local runner: process_due() -> descriptors
                 -> OrderService.create(..., key="sub:<id>:<date>")
                 -> auto_assign_trusted_vendor()
                        -> only if users.assigned_vendor_id is set
                        -> else order stays 'placed'
```

### 7.2 What is real

- Plan creation, pause/resume/skip endpoints, list/detail, and estimate are implemented.
- The local due runner creates one order per due plan, is idempotent per day, and advances `next_run`.
- Order creation re-prices with the current quote and writes the normal order/ledger path.
- Cancellation writes a `canceled_at`, optionally creates a return row when jars are held, and records a refund number.

### 7.3 What is not real

| Promise | Reality |
|---|---|
| “Daily plan delivers automatically” | Production cron is a no-op (P0-4). |
| “Monthly prepaid” | No charge at creation, no credit consumption, 0 payments (P1-3). |
| “UPI plan” | No intent/link is generated by the scheduler; collection is manual or cash (P1-3). |
| “Refund of unused water” | Based on `payment_method`, not collected money; can write off dues (P0-3). |
| “One plan per address” | No guard; duplicate active plans allowed (P1-1). |
| “Plan covers this address” | One-time orders still allowed during a plan (P1-2). |
| “Vendor sees plan deliveries” | No source field; auto-assign requires a pre-bound vendor (P1-4). |
| “Next delivery” on Home | Home has no plan widget (P1-6). |

### 7.4 Money invariants to restore

1. A refund may never exceed collected payments for that subscription/order.
2. Cancellation may never reduce `ledger.dues` without a matching credit/refund transaction.
3. A canceled order may never accept new money; open intents must be voided.
4. A plan’s billing mode must map to an actual charge/credit path, or be removed.
5. Every scheduled order must be traceable to a subscription id, not just an idempotency string.

---

## 8. Vendor Deep Dive

### 8.1 What the vendor receives today

`today_route` returns `{route, stops, loading, skip}` (`vendor_service.py:302-370`). Each stop includes:

- stop: `id`, `route_id`, `order_id`, `return_id`, `customer_id`, `seq`, `fulls_exp`, `empties_exp`, `version`, `triple`, `status`, `synced_at`
- order: `payment_mode`, `payment_status`, `total`, `deposit_due`, `state`, `window_start`, `items`
- address: `label`, `formatted`, `pincode` (overlaid from the frozen snapshot when present)
- customer: `name`, `phone`
- derived: `paid_sum`, `hold_blocked`, `hold_reason`
- `_stop_out` adds parsed `items`, `customer_name`, `customer_phone`, `instructions`

### 8.2 What is missing

| Missing field | Why it matters |
|---|---|
| `source` / `is_subscription` | Vendor cannot distinguish a plan delivery from a one-time order. |
| `subscription_id` | Support cannot trace a stop back to the plan. |
| `plan_cadence` / `next_run` | Vendor cannot see that this customer receives jars daily/alternate days. |
| `billing_mode` | Vendor cannot tell prepaid from per-delivery; cash collection may be wrong. |
| `subscription_status` (active/paused/canceled) | Vendor may deliver a paused/canceled plan if an old order exists. |

### 8.3 Operational gaps

- **Auto-assign:** only customers with `users.assigned_vendor_id` are auto-routed (`dispatch_service.py:434-448`). New subscription customers stay `placed`; no vendor sees them until an admin assigns.
- **No push/poll for new assignments:** this audit did not re-test the prior finding, but the code path still relies on the vendor refreshing the route.
- **PoD cash on a UPI plan:** `pod_complete` accepts `cash_paise > 0` and calls `mark_paid_cash_locked` without checking `payment_mode` (`vendor_service.py:694-702`). A UPI plan can be collected as cash, bypassing the intended method.
- **Paused/skip list:** `today_route` still has a TODO for paused subs/late skips (`vendor_service.py:367`). The scheduler checks skips before creating orders, so this is mostly a vendor-UI gap.
- **Live vendor tests blocked:** no vendor access code. The code trace is the only evidence for this section.

---

## 9. UX Recommendations With Exact Copy

The goal is honest state, not more decoration. Each recommendation maps to a real code path above.

### 9.1 Home — active plan banner

**Where:** `customer_home_screen.dart:84-125` (no plan state today).

**When:** an active subscription exists for the selected address.

**Copy:**

> **Daily plan active**
> 2 jars · next delivery Sun, 25 Oct · 8:00–8:30 am
> **Manage plan**

**Paused variant:**

> **Plan paused until 28 Oct**
> Your next delivery resumes on 28 Oct.
> **Resume in Plans**

**Why:** the customer currently has no idea a plan exists while ordering one-time jars. This is the single highest-value subscription UI change.

### 9.2 Home / checkout — duplicate plan warning

**Where:** before `POST /orders` when an active plan covers the address/date.

**Copy:**

> **Your plan already delivers on this date**
> You have 2 jars scheduled for Sun, 25 Oct. Ordering again may create a second delivery.
> **Keep my plan** · **Order anyway**

**Why:** prevents double delivery and double deposit. “Order anyway” preserves choice; no silent block.

### 9.3 Plan builder — payment and billing

**Where:** `plan_builder_sheet.dart:227-236` and `:370-372`.

**Current:** “No payment is collected now. The first delivery is billed as usual.” No payment method or billing mode is shown or sent.

**Recommended (per-delivery v1):**

> **Payment**
> Cash on delivery
> **Billing**
> Pay for each delivery
>
> No payment is collected now. You’ll pay ₹56 at each delivery.

**If UPI is supported:**

> **Payment**
> UPI before each delivery
> We’ll create a payment link when the delivery is scheduled.

**If monthly prepaid is not implemented:** remove the option entirely. Do not show a disabled “coming soon” row in a money flow.

**Why:** the customer must know how they will pay before creating a recurring commitment. The current copy hides the only material term.

### 9.4 Subscription card — payment/billing rows

**Where:** `subscription_screen.dart:752-855` (card shows qty/window/next run/due/monthly, no payment/billing).

**Add:**

> Payment · Cash on delivery
> Billing · Per delivery

**For UPI:**

> Payment · UPI link before each delivery

**For paused:**

> Payment · Cash on delivery · resumes 28 Oct

**Why:** the plan card is the only management surface; omitting the payment method makes cancellation/refund surprises likely.

### 9.5 Cancel sheet — replace the refund promise

**Where:** `subscription_controller.dart:91-101`.

**Current:**

> “Unused water (if prepaid) and the jar deposit are refunded to your UPI after pickup. The server calculates the final amounts.”
> “Your subscription is canceled. Bottle pickup is scheduled and the refund is on its way.”

**Recommended:**

> **Cancel this plan?**
> We’ll stop future deliveries. If you’ve already paid for deliveries you won’t receive, we’ll calculate that refund after pickup. Jar deposits are refunded when we collect the jars.
>
> **Keep plan** · **Cancel plan**

**Result dialog:**

> **Plan canceled**
> Future deliveries are stopped. If a refund is due, it will appear in Wallet after pickup. Nothing is refunded for deliveries that were never paid.

**Why:** the current copy promises money that may not exist (P0-3) and says “on its way” when no refund row is created.

### 9.6 Wallet — dues action

**Where:** `donor_wallet_screen.dart:413-456` (“Review dues” → `onOpenSubscriptions`).

**Recommended (after P0-1 fix):**

> **₹56 outstanding**
> Pay now with UPI, or pay cash on your next delivery.
> **Pay dues** · **View plans**

**If dues payment is unavailable (current P0-1 state):**

> **Dues payment is temporarily unavailable**
> No money was taken. Pay cash on your next delivery, or contact support.
> **Contact support**

**Why:** “Review dues” currently opens a plan list, not a payment surface. The current 500 also produces a generic “Server problem — retry in a moment,” which encourages retries that create orphan provider orders.

### 9.7 Dues-intent error copy

**Where:** `subscription_controller.dart:396-410` (all 5xx → “Server problem — retry in a moment.”).

**Recommended:**

> **Couldn’t start UPI payment**
> No money was taken. Try again in a few minutes, or pay cash on your next delivery.
> **Try again** · **Pay cash**

**Why:** “retry” is safe for the customer but not for the provider (orphan orders). The copy should set expectations and offer the cash path.

### 9.8 Vendor stop card — plan badge

**Where:** vendor route/stop card (payload lacks `source`; add it in `vendor_service.py:315-329` and `_stop_out:1190-1202`).

**Copy:**

> **Plan delivery** · 2 jars
> Daily · next: tomorrow 8:00 am

**One-time order:**

> One-time · 2 jars

**Why:** the rider currently cannot tell a recurring customer from a one-off. A badge changes prioritization and cash handling.

### 9.9 Empty/blocked states

| State | Copy |
|---|---|
| No active plan | No banner. Do not upsell on Home; keep one-time ordering primary. |
| Plan list empty | **No plans yet** — “Start a plan if you want jars on a regular schedule.” |
| Duplicate plan blocked | **You already have an active plan here** — “Cancel or pause it before starting another.” |
| Plan created, payment not collected | **Plan created** — “No payment was collected. The first delivery is billed as usual.” (already close to current copy) |
| Canceled with no refund | **Plan canceled** — “No refund is due because no deliveries were prepaid.” |

---

## 10. Blocked Tests and What Would Unblock Them

| Test | Status | Blocker | Unblock |
|---|---|---|---|
| Live subscription create/cancel | BLOCKED | Safety stop after P0-1 | Disposable user + P0-1 fix; then create/cancel with cleanup |
| Live vendor route/stop/PoD | BLOCKED | No vendor access code | Issue a disposable vendor code via admin; assign a QA order |
| Live admin dispatch/visibility | BLOCKED | No admin access code | Admin session for a disposable environment |
| Valid signed live webhook | BLOCKED | `UPI_WEBHOOK_SECRET` unavailable | Owner-provided test secret or Razorpay dashboard test webhook |
| Production cron execution/logs | BLOCKED | `wrangler` not authenticated | `wrangler login` + `wrangler tail`/D1 read |
| D1 cleanup and count | BLOCKED | `wrangler` not authenticated | Owner-run D1 queries/deletes |
| Real UPI app / device return | BLOCKED | No device; no real money | Owner device smoke with test keys |
| 429 / rate-limit behavior | NOT TESTED | Avoided hammering | Controlled test with a disposable IP/user |

---

## 11. Cleanup and Production State

### 11.1 What was cleaned

| Item | Action | Result |
|---|---|---|
| QA address `4e77c2875aef4faba19a391a5a19f3bb` | `DELETE /addresses/{id}` | **204**, trace `c1dd8d089d4348f4` |
| QA order `110cb098df6841fb9a6aa6b4424cf287` | `POST /orders/{id}/cancel` | **200**, trace `ab304517904c4818` |
| QA sessions | Logout | **200**, trace `b24fd0e7a2424210`; access token rejected after |

### 11.2 What remains

| Row | ID | State |
|---|---|---|
| User | `69af983e97af40f2aeb4e2c2f2b4ba33` | **Still present** (test phone is **not** gone) |
| Order | `110cb098df6841fb9a6aa6b4424cf287` | `state=cancelled`, `payment_status=link_sent` |
| Payment | `051007dd27ef4080a0d59b0daa35b20c` | `status=link_sent`, Razorpay `order_Trg9yamrg2L9fm` |
| Razorpay order | `order_Trg9yamrg2L9fm` | Still open in test mode; link not voided |
| Sessions | Unknown count | Registration/login/refresh/logout rows; logout revoked the live access token |
| Idempotency keys | At least the order-create key | Dues-intent key was never inserted because the FK failed |
| Order events | 2 | `placed`, `cancelled` |
| Address | `4e77...` | Deleted |
| Subscriptions | None | `GET /subscriptions` returned `{"data":[]}` |

**D1 access:** `npx wrangler whoami` returned “You are not authenticated” on 2026-10-24. No production count/delete was possible. The expected user count is **10** (9 baseline + 1 QA), but this is **unverified**. Do not claim the test phone is gone.

**Razorpay exposure:** the audit used the test key (`rzp_test_...`), so no real money moved. The open test-mode order should still be voided/ignored by the owner to avoid test-webhook noise.

### 11.3 Owner cleanup checklist (not executed)

1. Authenticate `wrangler` and read the QA rows:
   - `SELECT id, phone, created_at FROM users WHERE id='69af983e97af40f2aeb4e2c2f2b4ba33';`
   - `SELECT id, state, payment_status FROM orders WHERE user_id='69af983e97af40f2aeb4e2c2f2b4ba33';`
   - `SELECT id, order_id, status FROM payments WHERE user_id='69af983e97af40f2aeb4e2c2f2b4ba33';`
2. Review dependent rows (sessions, devices, idempotency keys, order events, ledger) before deleting.
3. Delete only rows tied to the QA user id; leave the 9 production users untouched.
4. Verify `SELECT COUNT(*) FROM users` returns 9 after cleanup.
5. In the Razorpay test dashboard, close/ignore `order_Trg9yamrg2L9fm` and any orphan `dues-69af...` orders.

---

## 12. Test and Coverage Notes

- Targeted backend tests: **34 passed** (`test_payments.py`, `test_upi_real.py`, `test_phase02_splitb.py`, `test_sub_cancel.py`, `test_scheduler.py`).
- The suite does not enable SQLite foreign keys (`db.py:92`; tests use `get_connection` directly), so P0-1 is invisible to CI.
- No test covers:
  - dues intent with FK on;
  - cancel → open intent voided;
  - webhook on a canceled order;
  - zero-payment subscription cancel → no dues write-off;
  - duplicate active plan;
  - one-time order while a plan is active;
  - scheduler key prefix in cancel/proration queries;
  - same-key UPI intent retry → one provider call and a stable returned ref;
  - vendor stop source/subscription marker.
- The local scheduler is idempotent and is the right base for P0-4; it is not wired to the Worker cron.

---

## 13. Recommended Fix Order

1. **P0-1 dues intent**: durable local row before provider call; nullable/dues table; FK-on test; orphan provider-order cleanup.
2. **P0-2 cancel vs payment**: void open intents, exclude canceled orders from dues, reject webhook settlement on canceled orders, refund in the same transaction if money was captured.
3. **P0-3 cancel accounting**: refund only collected money; never write off dues without a credit; fix the `POST /v1/orders:sub:` prefix; add ledger invariants.
4. **P0-4 cron**: wire `scheduled()` to `run_due_subscriptions`, add a canary and invocation log; until then, do not promise recurring delivery.
5. **P0-5 intent replay**: check idempotency before the provider call, return the stored link/ref, and test that a same-key retry calls the provider once.
6. **P1 guards**: one active plan per address; block/warn one-time orders during a plan; send and persist payment/billing mode; add vendor `source`/`subscription_id`; fix idempotency hash.
7. **P1 UX**: Home plan banner, subscription card payment/billing rows, wallet dues route, honest cancel copy.
8. **P2 hygiene**: provider readiness truth, `house` snapshot, auth error code, failed-event status, FK-enabled tests.

---

## 14. Evidence Index

All files are in `%TEMP%\shodasha-audit-20261024` unless noted.

| File | Contents |
|---|---|
| `catalog.json`, `catalog.headers` | Live catalog 200, trace `999e...` |
| `auth-register.*`, `auth-register-duplicate.*` | Register 200 / duplicate 409 |
| `auth-login-B.*`, `auth-login-wrong.*` | Correct login 200 / wrong password 401 |
| `auth-refresh-C.*`, `auth-refresh-reuse-old.*`, `auth-me-C-after-reuse.*` | Rotation / reuse / revocation |
| `auth-logout.*`, `auth-me-after-logout.*` | Logout and post-logout 401 |
| `address-create.*`, `address-delete.*` | Address 201 / 204 |
| `quote.*`, `order-upi-create.*`, `order-detail.*`, `orders-list.*` | Quote, order, snapshot, list |
| `upi-intent.*` | Live Razorpay intent 201 |
| `webhook-unsigned.*`, `webhook-bogus-sig.*` | Live webhook 401s |
| `dues-intent-while-link-pending.*` | Live dues 500, trace `6566...` |
| `order-upi-cancel.*`, `dues-after-cancel.*` | Cancel 200, dues still 5600 |
| `subscriptions-list-live.*` | Live subscription list 200 |
| `local-sub.out.txt` | Duplicate plans, prepaid 0 payments, scheduler idempotency |
| `local-proration.out.txt` | Delivered lookup 0 vs 1 |
| `local-cancel-dues.out.txt` | Dues 5600 → 0 on cancel |
| `local-cancel-webhook.out.txt` | Canceled order settled by webhook |
| `local-intent-idem.out.txt` | Same-key intent retry: 2 provider calls, 1 row, mismatched ref |
| `local-webhook.out.txt` | Full local webhook matrix |
| `repro-dues-fk.out.txt` | FK off succeeds / FK on fails |
| `local-audit.db`, `local-cancel-*.db` | Disposable databases |
| `local_*.py`, `repro_dues_fk.py` | Reproducible harnesses (`local_intent_idem_audit.py` is the P0-5 repro) |
| `sanitize.py` | Token/phone redaction pass |

---

## 15. Bottom Line

Auth is ready. The payment and subscription story is not.

- A customer cannot pay dues by UPI (P0-1).
- A customer can pay after cancelling, and the canceled order still counts as dues (P0-2).
- Cancelling a UPI plan can erase unpaid dues and invent a refund (P0-3).
- A production subscription never creates a delivery order (P0-4).
- Retrying a UPI intent can produce a link the backend cannot credit (P0-5).

Fix those five before shipping any subscription or dues-UPI messaging. The vendor app should not be told “plan delivery” until the order/stop payload carries a real subscription source and the cron is live.
