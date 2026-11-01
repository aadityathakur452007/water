# Verification Report: 14 — Vendor App: Route & Stops Execution

**Document Audited:** `Feature_docs/ux-unslop-audit/14-vendor-route-stops.md`  
**Target Codebase:** `apps/vendor_app/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **V2-01** | Coordinate-first navigation routing | Add `lat` and `lng` to `RouteStop` and launch Google Maps navigation with exact coordinates (`query=$lat,$lng`) falling back to address; add Navigate action in `StopDetailScreen`. | `apps/vendor_app/lib/features/route/route_screen.dart:79-88`<br>`if (lat != null && lng != null) uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng')`.<br>`apps/vendor_app/lib/features/stops/stop_detail_screen.dart:346-354`<br>`TextButton.icon(onPressed: () => _navigate(address: address, lat: lat, lng: lng), icon: Icon(Icons.navigation_outlined), label: Text('Navigate'))`. | `[VERIFIED]` |
| **V2-02** | Stop actions AppButton migration | Migrate stockout dialog, delivery handover, cash collection, pickup complete, error retry, and RTO actions to canonical `AppButton`. | `apps/vendor_app/lib/features/route/route_screen.dart:127-131`<br>`AppButton(label: 'Report Stockout', kind: AppButtonKind.danger)`.<br>`apps/vendor_app/lib/features/stops/stop_detail_screen.dart:144-147, 214-218, 465-471, 507-511, 521-525, 627-631`<br>`AppButton(label: 'Delivery Handover (Bottles + OTP)', kind: AppButtonKind.primary)`, `AppButton(label: 'Cash jama karein ...', kind: AppButtonKind.money)`. | `[VERIFIED]` |
| **V2-03** | Replace raw palette colors with design tokens | Replace raw `Colors.orange`, `Colors.deepOrange`, and `Colors.red.shade50/200` with `ShodashaTheme.warning`, `ShodashaTheme.danger`, and `AppSpacing` tokens. | `apps/vendor_app/lib/features/route/route_screen.dart:104, 584`<br>`color: ShodashaTheme.warning`, `ShodashaTheme.danger`. `stop_detail_screen.dart:506, 520` `AppSpacing.sm`, `AppSpacing.lg`. | `[VERIFIED]` |
| **V2-04** | Delete competing Triple & PoD redundant files | Eliminate dual-completion paradox by permanently deleting dead `triple_sheet.dart` and `pod_sheet.dart` files. | Verified both files deleted (`Test-Path` returns `False` for both `triple_sheet.dart` and `pod_sheet.dart`). Unified doorstep handover workflow active. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| Stockout confirm CTA | Canonical `AppButton` (`kind: AppButtonKind.danger`) | `route_screen.dart:127-131`<br>`AppButton(label: 'Report Stockout', kind: AppButtonKind.danger, expand: false, onPressed: () => Navigator.of(ctx).pop(true))` | `[VERIFIED]` |
| Delivery handover CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`, icon: `Icons.verified_outlined`) | `stop_detail_screen.dart:465-471`<br>`AppButton(label: tripleDone ? 'Delivery Handover Complete' : 'Delivery Handover (Bottles + OTP)', kind: AppButtonKind.primary, icon: Icons.verified_outlined, onPressed: ...)` | `[VERIFIED]` |
| Cash collection CTA | Canonical `AppButton` (`kind: AppButtonKind.money`, icon: `Icons.payments_outlined`) | `stop_detail_screen.dart:507-511`<br>`AppButton(label: 'Cash jama karein (${rupees(remainingPaise)})', kind: AppButtonKind.money, icon: Icons.payments_outlined, onPressed: ...)` | `[VERIFIED]` |
| RTO report issue CTA | Canonical `AppButton` (`kind: AppButtonKind.danger`, icon: `Icons.report_problem_outlined`) | `stop_detail_screen.dart:521-525`<br>`AppButton(label: vtr('...', 'Report Issue (RTO)'), kind: AppButtonKind.danger, icon: Icons.report_problem_outlined, onPressed: ...)` | `[VERIFIED]` |
| Pickup complete CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`, icon: `Icons.recycling_outlined`) | `stop_detail_screen.dart:627-631`<br>`AppButton(label: 'Pickup complete karein', kind: AppButtonKind.primary, icon: Icons.recycling_outlined, onPressed: ...)` | `[VERIFIED]` |
| Error retry CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`) | `stop_detail_screen.dart:214-218`<br>`AppButton(label: 'Dobara try karein', kind: AppButtonKind.primary, expand: false, onPressed: () => _load())` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Route list padding | `AppSpacing.lg` (16dp) | `route_screen.dart:213`<br>`padding: const EdgeInsets.all(AppSpacing.lg)`. | `[VERIFIED]` |
| Stop detail action vertical gaps | `AppSpacing.sm` (8dp), `AppSpacing.lg` (16dp) | `stop_detail_screen.dart:506, 520`<br>`SizedBox(height: AppSpacing.sm)` and `SizedBox(height: AppSpacing.lg)`. | `[VERIFIED]` |
| Warning & danger colors | Canonical `ShodashaTheme.warning` and `danger` | `route_screen.dart:104, 584`<br>Standardized raw colors to `ShodashaTheme.warning` and `ShodashaTheme.danger`. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Route Stop Sequence | 12px w800, teal | `route_screen.dart:538-542`<br>`fontSize: 12, fontWeight: FontWeight.w800, color: ShodashaTheme.teal` | `[VERIFIED]` |
| Stop Customer Name | 16px w700, ink | `stop_detail_screen.dart:317-320`<br>`fontSize: 16, fontWeight: FontWeight.w700, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Delivery Window Chip | 12px w600, muted | `stop_detail_screen.dart:333-336`<br>`fontSize: 12, fontWeight: FontWeight.w600, color: ShodashaTheme.muted` | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Finding | Expected Copy | Code Evidence | Status |
|---|---|---|---|
| Coordinate navigation action | Clean "Navigate" action label | `stop_detail_screen.dart:353`<br>`label: const Text('Navigate')`. | `[VERIFIED]` |
| Stockout repool notification | Informative Hindi notice of repooled stops | `route_screen.dart:143`<br>`'Stockout report kiya. $repooled stops repool ho gaye.'`. | `[VERIFIED]` |
| Delivery handover action | Clean handover action without slash crutch | `stop_detail_screen.dart:468`<br>`'Delivery Handover (Bottles + OTP)'`. | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Edge Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| Coordinate-first navigation | Use `lat,lng` when present, address string as fallback | `route_screen.dart:81-87, stop_detail_screen.dart:60-66`<br>`if (lat != null && lng != null) uri = Uri.parse('...?query=$lat,$lng') else ...?query=${Uri.encodeComponent(address)}`. | `[VERIFIED]` |
| SOS stockout repooling | Repools undelivered stops via `api.reportStockout` | `route_screen.dart:138-146`<br>Re-pools pending stops without generating false delivery failures. | `[VERIFIED]` |
| Offline outbox queueing | Enqueue delivery and cash records on offline failure | `stop_detail_screen.dart:94-110`<br>Queues idempotent records with full offline tolerance. | `[VERIFIED]` |
| Server overpay guard | Prevent posting cash higher than `amountDue` | `stop_detail_screen.dart:88-92`<br>Validates remaining server balance before submitting cash transaction. | `[VERIFIED]` |

---

## 7. File Invariants & Verification Checklist

- [x] Invariant: Proof of delivery and cash receipts queue to offline outbox upon network failure (`stop_detail_screen.dart:94-110`).
- [x] Invariant: Server overpay prevention verified via `amountDue` check before cash post (`stop_detail_screen.dart:88-92`).
- [x] Invariant: Stockout reporting repools remaining route stops without creating false delivery failures (`route_screen.dart:138-146`).
- [x] Invariant: Minimum 48dp bounding touch targets on all interactive elements.

---

## 8. Automated Test Verification

Targeted vendor route and stops test suite execution:
- `apps/vendor_app/test/vendor_route_stops_test.dart`

**Command Output:**
```
00:00 +0: RouteStop parses coordinates lat and lng fromJson
00:00 +1: RouteScreen stockout prompt renders AppButton danger CTA
00:01 +2: StopDetailScreen renders canonical AppButtons and coordinate navigation action
00:01 +3: All tests passed!
```
Status: **3 / 3 passed** (100% green).
