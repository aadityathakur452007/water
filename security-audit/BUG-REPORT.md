# Bug Report — functional and business-logic issues

Findings here are reproducible defects in behaviour, separate from the security findings in `VULNERABILITY-REPORT.md`.

---

## BUG-001 — Idempotent replay returns 409 instead of the original order (Medium, by design — verify client handling)

**File:** `workers/api/src/app/services/order_service.py:327` (`_check_replay`)

Replaying `POST /v1/orders` with the same `Idempotency-Key` and the same body returns:

```
HTTP 409  {"error":{"code":"IDEMPOTENT_REPLAY","message":"Duplicate request: returning the original order.","details":{"order":{...}}}}
```

Evidence: `harness2.py` IDEM-01 (`first=201 replay=409`), and the customer and vendor apps must therefore treat `409 IDEMPOTENT_REPLAY` as success and read `details.order`, not as a failure.

**Why it matters:** it is the correct server-side outcome (exactly one order row was created — verified), but the status code is easy to mishandle. If `booking_sheet.dart` surfaces a generic 409 error, a retried checkout shows "failed" while an order exists — a duplicate-order support ticket. No server change recommended; confirm both clients branch on `IDEMPOTENT_REPLAY`.

**Root cause:** deliberate API contract (duplicate detection, changed payload returns `PAYLOAD_MISMATCH`).

---

## BUG-002 — Vendor onboarding can silently re-activate a suspended rider (Low, fixed as part of VULN-001)

`create_rider` previously set `suspended = 0` for *any* matched phone. After the fix, `suspended = 0` still applies — but only to a rider already owned by the calling vendor, which is the intended "vendor reinstates my rider" flow. Foreign accounts are rejected with 409 before any write.

---

## BUG-003 — Delivery completion is impossible for stops whose code was never minted (Low, operational)

**File:** `workers/api/src/app/services/vendor_service.py:562` (`pod_complete`)

A stop with `pod_otp IS NULL` and no expiry returns `410 DELIVERY_CODE_UNAVAILABLE` for both vendor and rider. In testing, a seeded `assigned` stop in that state could not be completed by any legitimate actor until the customer reissued a code. `reissue_delivery_code` is only offered to the customer while the order is `dispatched` (`delivery_code.reissue_available`), so an `assigned` order with no code is a dead end for the route.

**Reproduction:** `harness.py` BIZ-03 before the harness minted a code — `410 DELIVERY_CODE_UNAVAILABLE` with `order.state = assigned`.

**Impact:** an order can be stranded if the assignment job fails between "assign" and "mint code" (or the code is purged while the order is still `assigned`).

**Suggested fix (not applied — behaviour change):** allow `reissue_delivery_code` for `assigned` orders too, or have `assign_order` guarantee a code exactly like dispatch does.

---

## Non-issues confirmed (checked, working as intended)

- Price tampering: server recomputes the quote and rejects a mismatched total/hash (`STALE_QUOTE`).
- Quantity limits: `qty > 10` is rejected at the Pydantic boundary (`400`) *and* in the service (`OVER_LIMIT`).
- Duplicate submit with two different keys creates two orders — unavoidable without a client nonce; the customer app already disables the pay button after `_placed`.
- COD switch: blocked for paid or dead orders by `validate_switch_to_cod`.
- Late UPI capture on a cancelled order: routes to a refund rather than crediting a non-existent delivery (`validate_late_capture_action`).
- OTP lockout: 5 wrong codes → `429`, code cleared, no oracle before that (wrong codes read as 404).
