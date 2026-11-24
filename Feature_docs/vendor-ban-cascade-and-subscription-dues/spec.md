# Feature Spec: Vendor Suspension Cascade & Mid-Cycle Subscription Dues Recovery

**Branch**: `main`  
**Date**: 2026-11-24  
**Status**: Specification (Awaiting Approval)  
**ADR Target**: `ADR-216`

---

## 1. Executive Summary & Problem Statement

1. **Vendor Suspension Cascade Gap**:
   - When an Admin suspends a vendor account (`POST /v1/admin/users/{user_id}/suspend`), currently only `users.suspended = 1` is set and sessions revoked.
   - **Vulnerabilities**:
     - `vendor_profile.active` remains `1`.
     - `assign_order()` and `auto_assign_trusted_vendor()` do not check `users.suspended == 0`.
     - Customers assigned to this vendor (`users.assigned_vendor_id`) continue sending new orders to the suspended vendor.
     - Active delivery stops on today's routes remain stuck on the suspended vendor's route manifest instead of returning to the zone unassigned pool.
     - Fleet riders attached to that vendor remain active without awareness of the vendor ban.
2. **Mid-Cycle Subscription Cancellation Loss of Funds**:
   - When a customer cancels a recurring subscription midway through a billing cycle, jars already supplied and consumed prior to cancellation risk non-collection if not explicitly billed.
   - The system must ensure that all delivered jars under the cancelled subscription are tallied, the dues are immediately posted to the customer's ledger, and the rider/vendor route manifests alert the delivery partner to collect the cash on the doorstep.

---

## 2. Architecture & Design Patterns

### A. Vendor Suspension Cascade (`workers/api`)
```
[Admin calls /admin/users/{id}/suspend]
                   │
                   ▼
       Is user role == 'vendor'?
                   │
                   ├─► 1. Set users.suspended = 1, record reason & admin id
                   ├─► 2. Set vendor_profile.active = 0, review_hold = 1
                   ├─► 3. Revoke all vendor sessions in sessions table
                   ├─► 4. Auto-repool active/pending stops via auto_repool() -> zone pool
                   ├─► 5. Disassociate & disarm fleet riders:
                   │      - UPDATE users SET assigned_vendor_id = NULL WHERE assigned_vendor_id = vendor_id
                   │      - Revoke active sessions for all affected riders
                   └─► 6. Write audit log: 'vendor.suspended_cascade'
```

### B. 1-Click Admin Customer Reassignment
```
[Admin detects suspended vendor with orphan customers]
                   │
                   ▼
  POST /v1/admin/vendors/{old_vendor_id}/reassign-customers
  Body: { "new_vendor_id": "...", "reason": "Vendor suspended" }
                   │
                   ├─► 1. Validate new_vendor_id is active & not suspended
                   ├─► 2. Atomic SQL update:
                   │      UPDATE users SET assigned_vendor_id = new_vendor_id 
                   │      WHERE assigned_vendor_id = old_vendor_id AND role = 'user'
                   ├─► 3. Re-route any unassigned placed/packed orders to new vendor
                   └─► 4. Return { "reassigned_count": N, "new_vendor_id": new_vendor_id }
```

### C. Mid-Cycle Subscription Cash Collection
```
[Customer cancels subscription via POST /v1/subscriptions/{id}/cancel]
                   │
                   ▼
  1. Transition subscription state to 'cancelled'
  2. Query delivered jars under subscription with unpaid status
  3. If unpaid jars > 0:
     - Compute unpaid_total_paise = delivered_count * jar_rate
     - LedgerRepo.apply_event(user_id, d_dues = unpaid_total_paise, reason = 'mid_cycle_sub_cancellation')
  4. In rider routes_today():
     - When customer has dues > 0:
       is_monthly_dues = True, is_sub = False, amount_due = dues_paise
     - Rider PodSheet displays:
       [💰 Collect ₹X Cancelled Subscription Dues (बकाया कैश लें)]
```

---

## 3. Endpoints & Schema Specification

1. **`GET /v1/admin/vendors/{vendor_id}/orphan-customers`**:
   - **Auth**: Admin Bearer
   - **Response**: `{"vendor_id": str, "count": int, "customers": [{"id": str, "name": str, "phone": str}]}`
2. **`POST /v1/admin/vendors/{vendor_id}/reassign-customers`**:
   - **Auth**: Admin Bearer
   - **Payload**: `{"new_vendor_id": str, "reason": str}`
   - **Response**: `{"old_vendor_id": str, "new_vendor_id": str, "reassigned_count": int}`
3. **`POST /v1/admin/users/{user_id}/suspend`** (Enhanced):
   - Cascades profile deactivation, auto-repool, rider disassociation, and session revocation.
4. **`POST /v1/subscriptions/{sub_id}/cancel`** (Enhanced):
   - Computes delivered jar receivables, appends to customer ledger dues, and triggers rider cash collection.

---

## 4. Verification Plan

1. **Pytest Regression Suite**:
   - Write test suite `tests/test_vendor_ban_cascade.py` verifying all 6 cascade actions.
   - Write test suite `tests/test_mid_cycle_sub_cash_recovery.py` verifying dues posting and rider stop cash tags.
2. **Live Production Smoke Verification**:
   - Run end-to-end Python test script against live production workers (`water`, `water-ops`, `water-admin`) using isolated test accounts.
   - Clean up test records after verification, preserving the admin user (`+917828442476`).
