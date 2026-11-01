# Slice 1: Vendor Trust, Money & Doorstep Handover Spec

**Branch:** `037-uiux-unslop-audit`  
**Date:** 2026-10-31  
**Scope:** `DEF-01` (Unified Doorstep Handover) and `DEF-02` (Server-Authoritative Earnings Display)  
**Status:** **Implemented & Verified — 70/70 Vendor Tests Green** (ADR-157)

---

## 1. Requirements & Invariants

1. **DEF-02 — Server-Authoritative Earnings (`earnings_screen.dart:117`):**
   - Eliminate `c.stopsDone * 2000` client fallback.
   - If `c.earnedPayout > 0`: Display `rupees(c.earnedPayout)`.
   - If `c.earnedPayout == 0` and `c.stopsDone > 0`: Display `"Settlement Pending"` (Hindi: `"Hisaab baki"`) with secondary caption `"Hisaab din ke ant me hoga"`.
   - If `c.stopsDone == 0`: Display `rupees(0)`.
   - Upholds money invariant: Client never invents payout amounts.

2. **DEF-01 — Unified Doorstep Handover Modal (`handover_sheet.dart`):**
   - Consolidate `TripleSheet` and `PodSheet` into a single, cohesive 2-step bottom sheet `HandoverSheet`:
     - **Step 1: Jars & Cash** (Jars given, empties returned, damaged empties condition, missing caps, Cash/UPI collect amounts).
     - **Step 2: Customer OTP & Proof** (Delivery OTP input 4-6 digits, seal intact check, GPS capture, one-tap final confirm).
   - If a stop already has a saved triple (`tripleDone == true`), the sheet opens directly on Step 2.
   - Submitting Step 2 sequentially executes `commitTriple` (if not already done) followed by `completePod`.
   - Offline handling: If network is offline, automatically enqueues into `widget.outbox` (`SyncController`).
   - Clean single CTA on `StopDetailScreen`: `"Complete Delivery / डिलीवरी पूरी करें"` replacing the disjoint dual buttons.
   - Preserves `buildTripleBody` and `buildPodBody` API payload contracts and tests.

---

## 2. Step-by-Step Implementation Checklist

- [x] **Step 1: Fix Earnings Fallback Math** (`apps/vendor_app/lib/features/earnings/earnings_screen.dart`)
  - Replaced line 117 with server-authoritative display logic (`rupees(c.earnedPayout)` or `"Settlement Pending"`).
  - Verified layout on 360dp devices.
- [x] **Step 2: Implement Unified `HandoverSheet`** (`apps/vendor_app/lib/features/stops/handover_sheet.dart`)
  - 2-step modal: Step 1 (Bottles & Cash) $\rightarrow$ Step 2 (Customer OTP & Verification).
  - 48dp touch steppers for fulls, empties, caps, damaged condition dropdown, cash/upi inputs.
  - Step 2: 4-6 digit OTP field, seal check, summary chips, GPS position hook, final submit.
  - Sequential execution: commits triple (with version fencing) then completes PoD with OTP and location.
  - Full offline outbox support.
- [x] **Step 3: Wire `HandoverSheet` into `StopDetailScreen`** (`apps/vendor_app/lib/features/stops/stop_detail_screen.dart`)
  - Replaced fragmented `TripleSheet` and `PodSheet` buttons with unified `HandoverSheet` entry point.
  - Clean single CTA: `"Delivery Handover (Bottles + OTP)"` or `"OTP darj karein (PoD)"`.
- [x] **Step 4: Run Verification Tests**
  - Ran `flutter analyze` in `apps/vendor_app` (clean, 0 issues).
  - Ran `flutter test` in `apps/vendor_app` (**70 / 70 passed**, baseline 68 + 2 new handover tests).
  - Added test coverage in `apps/vendor_app/test/handover_sheet_test.dart`.
- [x] **Step 5: Context Sync & Commit**
  - Updated `context/progress-tracker.md`, `context/flow.md`, and `context/decision.md`.
  - Committed on `037-uiux-unslop-audit`.
