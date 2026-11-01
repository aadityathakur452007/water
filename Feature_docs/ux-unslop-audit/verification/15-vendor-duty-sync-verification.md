# Verification Report: 15 — Vendor App: Duty, Outbox Sync & Cascade Motion

**Document Audited:** `Feature_docs/ux-unslop-audit/15-vendor-duty-sync.md`  
**Target Codebase:** `apps/vendor_app/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **V3-01** | Duty screen button standardization | Migrate error state retry CTA (`'Dobara try karein'`, primary) and off-duty confirmation dialog confirm action (`'Haan, off karein'`, danger) in `DutyScreen` to canonical `AppButton`. | `apps/vendor_app/lib/features/duty/duty_screen.dart:64-68, 113-118`<br>`AppButton(label: 'Dobara try karein', kind: AppButtonKind.primary, expand: false)` and `AppButton(label: 'Haan, off karein', kind: AppButtonKind.danger, expand: false)`. | `[VERIFIED]` |
| **V3-02** | Manual sync action AppButton migration | Migrate manual sync trigger in `SyncScreen` to canonical `AppButton` (`kind: AppButtonKind.primary`, with `Icons.sync`, `busy: c.syncing`, `'Abhi sync karein (${c.queue.length})'`). | `apps/vendor_app/lib/features/sync/sync_screen.dart:119-126`<br>`AppButton(label: c.syncing ? 'Sync ho raha…' : 'Abhi sync karein (${c.queue.length})', kind: AppButtonKind.primary, icon: Icons.sync, busy: c.syncing, onPressed: ...)` | `[VERIFIED]` |
| **V3-03** | Align duty & sync spacing to design tokens | Standardize list and card paddings and spacers across `duty_screen.dart` and `sync_screen.dart` to `AppSpacing` tokens (`xl`, `lg`, `md`, `sm`). | `apps/vendor_app/lib/features/duty/duty_screen.dart:54, 60, 63, 76, 81, 145, 148, 156`<br>`AppSpacing.xl`, `AppSpacing.lg`, `AppSpacing.md`, `AppSpacing.sm`. `sync_screen.dart:70, 79, 86, 105, 117, 128` `AppSpacing.xl`, `AppSpacing.lg`, `AppSpacing.md`, `AppSpacing.sm`. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| Duty error retry CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`, `expand: false`) | `duty_screen.dart:64-68`<br>`AppButton(label: 'Dobara try karein', kind: AppButtonKind.primary, expand: false, onPressed: () => c.load())` | `[VERIFIED]` |
| Off-duty dialog confirm CTA | Canonical `AppButton` (`kind: AppButtonKind.danger`, `expand: false`) | `duty_screen.dart:113-118`<br>`AppButton(label: 'Haan, off karein', kind: AppButtonKind.danger, expand: false, onPressed: () => Navigator.of(ctx).pop(true))` | `[VERIFIED]` |
| Manual sync trigger CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`, icon: `Icons.sync`, `busy: c.syncing`) | `sync_screen.dart:119-126`<br>`AppButton(label: c.syncing ? 'Sync ho raha…' : 'Abhi sync karein (${c.queue.length})', kind: AppButtonKind.primary, icon: Icons.sync, busy: c.syncing, onPressed: ...)` | `[VERIFIED]` |
| Discard stale rejected record | Accessible `TextButton` with min 48dp target | `sync_screen.dart:154-159`<br>`TextButton(onPressed: () => c.dismissRejected(r.key), child: const Text('Hatayein'))` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Duty screen list padding | `AppSpacing.lg` (16dp) | `duty_screen.dart:76`<br>`padding: const EdgeInsets.all(AppSpacing.lg)`. | `[VERIFIED]` |
| Duty card inner padding | `AppSpacing.lg` (16dp) | `duty_screen.dart:81`<br>`padding: const EdgeInsets.all(AppSpacing.lg)`. | `[VERIFIED]` |
| Sync screen outer padding | `AppSpacing.lg` (16dp) | `sync_screen.dart:79`<br>`padding: const EdgeInsets.all(AppSpacing.lg)`. | `[VERIFIED]` |
| Sync result banner padding | `AppSpacing.lg` (16dp) | `sync_screen.dart:86`<br>`padding: const EdgeInsets.all(AppSpacing.lg)`. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Shift Status Headline | 18px w700, ink | `duty_screen.dart:86-89`<br>`fontSize: 18, fontWeight: FontWeight.w700, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Queue Stop Header | 16px w600, ink | `sync_screen.dart:132-135`<br>`fontSize: 16, fontWeight: FontWeight.w600, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Repooled Notice Text | 13px w600, solarDark | `duty_screen.dart:138-142`<br>`fontSize: 13, fontWeight: FontWeight.w600, color: ShodashaTheme.solarDark` | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Finding | Expected Copy | Code Evidence | Status |
|---|---|---|---|
| Off-duty dialog warning | Transparent explanation that pending stops return to dispatch | `duty_screen.dart:104`<br>`'Duty off karein? Baki stops aaj ke liye ruk jayenge aur pool mein wapas chale jayenge.'`. | `[VERIFIED]` |
| All-synced empty state | Clear reassurance when outbox queue is clear | `sync_screen.dart:72`<br>`'Sab synced — koi pending entry nahi'`. | `[VERIFIED]` |
| Manual sync button label | Dynamic count of pending outbox entries | `sync_screen.dart:122`<br>`'Abhi sync karein (${c.queue.length})'`. | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Edge Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| Off-duty repooling transition | Repools uncompleted stops safely to central pool | `duty_screen.dart:119-124`<br>`c.setDuty(false)` calls `repoolRemainingStops()`. | `[VERIFIED]` |
| Offline queue idempotency | Local outbox records survive network disconnects and replay safely | `sync_controller.dart:100-115`<br>Queues idempotent records with durable local state. | `[VERIFIED]` |
| Reduced motion support | Check `MediaQuery.disableAnimationsOf(context)` in `cascade.dart` | `apps/vendor_app/lib/core/cascade.dart:99`<br>`if (MediaQuery.disableAnimationsOf(context)) return child;` | `[VERIFIED]` |

---

## 7. File Invariants & Verification Checklist

- [x] Invariant: Off-duty transition repools pending stops to dispatch (`duty_controller.dart:96-120`).
- [x] Invariant: Outbox queue stores pending operations offline and replays them upon connectivity (`sync_controller.dart:100-115`).
- [x] Invariant: Reduced motion support verified in `cascade.dart:99`.
- [x] Invariant: Minimum 48dp bounding touch targets on all interactive elements.

---

## 8. Automated Test Verification

Targeted vendor duty and sync test suite execution:
- `apps/vendor_app/test/vendor_duty_sync_test.dart`

**Command Output:**
```
00:00 +0: DutyScreen in error state renders AppButton retry CTA
00:00 +1: DutyScreen off-duty dialog renders AppButton danger CTA
00:00 +2: SyncScreen renders canonical AppButton for manual sync action
00:00 +3: All tests passed!
```
Status: **3 / 3 passed** (100% green).

