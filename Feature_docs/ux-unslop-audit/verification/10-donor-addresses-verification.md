# Verification Report: 10 — Donor App: Addresses & Map Picker

**Document Audited:** `Feature_docs/ux-unslop-audit/10-donor-addresses.md`  
**Target Codebase:** `apps/user_app_donor/`  
**Auditor:** Pair Programming Assistant (Antigravity)  
**Date:** 2026-11-01  
**Status:** 100% VERIFIED  

---

## 1. Action Items Matrix (P0–P3)

| ID | Finding / Requirement | Expected Behavior | Code Evidence | Status |
|---|---|---|---|---|
| **D10-01** | Replace Nagpur fallback coordinates with central Bhopal | Update `kDefaultCenter` in `map_picker.dart` to Bhopal (`23.2599, 77.4126`) so GPS-denied users center locally. | `apps/user_app_donor/lib/features/addresses/map_picker.dart:19`<br>`const LatLng kDefaultCenter = LatLng(23.2599, 77.4126);` | `[VERIFIED]` |
| **D10-02** | Move "Add address" to sticky bottom bar & eliminate list tail button | Pin primary "Add address" CTA as a sticky `AppButton` in Scaffold `bottomNavigationBar`; remove trailing button from `ListView.separated`. | `apps/user_app_donor/lib/features/addresses/address_screen.dart:580-582, 736-753`<br>`itemCount: c.items.length + 1` (header + items, no tail button). `bottomNavigationBar: ListenableBuilder(..., child: AppButton(label: addressStrings['addFirst']!, kind: AppButtonKind.primary, icon: Icons.add, onPressed: () => _openForm()))`. | `[VERIFIED]` |
| **D10-03** | Migrate form steppers & empty state to AppButton | Replace manual `ElevatedButton.styleFrom` in empty state and form sheet with canonical `AppButton` (min 48dp target). | `apps/user_app_donor/lib/features/addresses/address_screen.dart:560-565, 1157-1175`<br>Empty state: `AppButton(label: addressStrings['addFirst']!, kind: AppButtonKind.primary, icon: Icons.add)`. Stepper: `AppButton(label: 'Back', kind: AppButtonKind.secondary)` and `AppButton(label: last ? addressStrings['save']! : 'Next', kind: AppButtonKind.primary, height: 48, busy: c.busy && last)`. | `[VERIFIED]` |
| **D10-04** | Replace raw decimal coordinates with human feedback | In `map_picker.dart`, replace floating Lat/Lng strings with calm human prompts ('Tap the map to place your delivery pin' / 'Pin placed · Tap map to adjust location'). | `apps/user_app_donor/lib/features/addresses/map_picker.dart:253-261`<br>`_pin == null ? 'Tap the map to place your delivery pin' : 'Pin placed · Tap map to adjust location'` | `[VERIFIED]` |
| **D10-05** | Eliminate ad-hoc shadows & normalize card separation | Replace inline `BoxShadow` in `map_picker.dart` with `ShodashaTheme.subtleCardShadow`; normalize card separation from 10dp to `AppSpacing.md` (12dp). | `apps/user_app_donor/lib/features/addresses/map_picker.dart:239, 315, 361`<br>`boxShadow: ShodashaTheme.subtleCardShadow`. `address_screen.dart:581` `separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md)`. | `[VERIFIED]` |

---

## 2. Component & Button Migrations

| Component / Action | Requirement | Implementation Evidence | Status |
|---|---|---|---|
| Sticky "Add address" CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`, icon: `Icons.add`) | `address_screen.dart:748-752`<br>`AppButton(label: addressStrings['addFirst']!, kind: AppButtonKind.primary, icon: Icons.add, onPressed: () => _openForm())` | `[VERIFIED]` |
| Empty state "Add address" CTA | Canonical `AppButton` (`kind: AppButtonKind.primary`, icon: `Icons.add`) | `address_screen.dart:560-564`<br>`AppButton(label: addressStrings['addFirst']!, kind: AppButtonKind.primary, icon: Icons.add, onPressed: () => _openForm())` | `[VERIFIED]` |
| Form stepper "Back" | Canonical `AppButton` (`kind: AppButtonKind.secondary`, height: 48) | `address_screen.dart:1157-1162`<br>`AppButton(label: 'Back', kind: AppButtonKind.secondary, expand: false, height: 48, onPressed: () => setState(() => _step--))` | `[VERIFIED]` |
| Form stepper "Next / Save" | Canonical `AppButton` (`kind: AppButtonKind.primary`, height: 48, busy spinner) | `address_screen.dart:1167-1174`<br>`AppButton(label: last ? addressStrings['save']! : 'Next', kind: AppButtonKind.primary, height: 48, busy: c.busy && last)` | `[VERIFIED]` |
| Map picker confirm location CTA | Full-width `AppButton` (`kind: AppButtonKind.primary`, `kind: AppButtonKind.secondary`) | `map_picker.dart:395-403`<br>`AppButton(label: _pin == null ? 'Tap the map to select a pin' : 'Use this location', kind: _pin == null ? AppButtonKind.secondary : AppButtonKind.primary, ...)` | `[VERIFIED]` |

---

## 3. Design Tokens & Spacing

| Location | Token Requirement | Code Evidence | Status |
|---|---|---|---|
| Address screen list padding | `fromLTRB(16, 8, 16, 96)` | `address_screen.dart:579`<br>`padding: const EdgeInsets.fromLTRB(16, 8, 16, 96)`. | `[VERIFIED]` |
| Address card separation | `AppSpacing.md` (12dp) | `address_screen.dart:581`<br>`separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md)`. Replaced off-scale 10dp. | `[VERIFIED]` |
| Sticky footer padding | `fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg)` | `address_screen.dart:743-747`<br>`EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg)`. | `[VERIFIED]` |
| Map pill shadow token | Canonical `ShodashaTheme.subtleCardShadow` | `map_picker.dart:239, 315, 361`<br>`boxShadow: ShodashaTheme.subtleCardShadow`. Replaced all inline ad-hoc BoxShadows. | `[VERIFIED]` |

---

## 4. Typography & Hierarchy

| Typography Role | Spec | Code Evidence | Status |
|---|---|---|---|
| Map Status Feedback | 13px w600, ink | `map_picker.dart:256-260`<br>`fontSize: 13, fontWeight: FontWeight.w600, color: ShodashaTheme.ink` | `[VERIFIED]` |
| Saved Addresses Section Header | 11px w800, letterSpacing 0.8 | `address_screen.dart:591-597`<br>`fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: ShodashaTheme.muted` | `[VERIFIED]` |
| Saved Addresses Counter Badge | 12px w800, teal | `address_screen.dart:603-608`<br>`fontSize: 12, fontWeight: FontWeight.w800, color: ShodashaTheme.teal` | `[VERIFIED]` |
| Selected Card Border & Tint | 1.5px teal border, teal tinted background | `address_screen.dart:642-646`<br>`color: selected ? ShodashaTheme.teal.withValues(alpha: 0.08) : ShodashaTheme.surface`, `Border.all(color: selected ? ShodashaTheme.teal : ShodashaTheme.border, width: selected ? 1.5 : 1)` | `[VERIFIED]` |

---

## 5. Copy & Voice Polish

| Finding | Expected Copy | Code Evidence | Status |
|---|---|---|---|
| Map prompt (no pin) | Clear instruction without technical coordinates | `map_picker.dart:254`<br>`'Tap the map to place your delivery pin'`. | `[VERIFIED]` |
| Map confirmation (pin placed) | Calm reassurance and adjustment tip | `map_picker.dart:255`<br>`'Pin placed · Tap map to adjust location'`. | `[VERIFIED]` |
| Delete conflict guard (409) | Clear explanation of active order lock | `address_screen.dart:366-372`<br>`addressStrings['deleteBlockedTitle']` / `addressStrings['deleteBlockedBody']` ("This address has active orders or subscriptions. Complete or cancel them first"). | `[VERIFIED]` |

---

## 6. State Transitions & Edge Cases

| State / Edge Case | Requirement | Code Evidence | Status |
|---|---|---|---|
| GPS denied / disabled fallback | Central Bhopal camera nexus (`23.2599, 77.4126`) | `map_picker.dart:19`<br>`const LatLng kDefaultCenter = LatLng(23.2599, 77.4126);`. | `[VERIFIED]` |
| Address selection persistence | Instant controller update + write-through to `SelectedAddressStore` | `address_screen.dart:637, 244-249`<br>`c.select(a.id)` -> `SelectedAddressStore.save(addressId)`. | `[VERIFIED]` |
| Serviceability check feedback | Async verification against `/windows?pincode` with alert banner | `address_screen.dart:95-102`<br>`_CheckingPincodeBanner` and unserviceable warnings. | `[VERIFIED]` |
| User session boundaries | `c.reset()` aborts in-flight generation requests upon logout | `address_screen.dart:300-308`<br>`_generation++` prevents old user data leaks. | `[VERIFIED]` |

---

## 7. File Invariants & Verification Checklist

- [x] Invariant: Address CRUD adheres to contract §4.3 with zero data loss (`address_screen.dart:1-6`).
- [x] Invariant: 409 conflicts on active orders/subscriptions are explicitly reported to the user (`address_screen.dart:366-372`).
- [x] Invariant: Address selection writes through to `SelectedAddressStore` and persists across sessions (`selected_address_store.dart:26-37`).
- [x] Invariant: Minimum 48dp bounding touch targets on all interactive elements.

---

## 8. Automated Test Verification

Targeted address test suite execution:
- `apps/user_app_donor/test/address_screen_test.dart`

**Command Output:**
```
00:00 +0: empty state renders AppButton with primary styling for add first
00:00 +1: populated state renders sticky bottom AppButton and list items without tail button
00:01 +2: map picker displays human-readable pin prompt when no pin is placed
00:01 +3: map picker displays human-readable pin feedback when pin is set
00:01 +4: All tests passed!
```
Status: **4 / 4 passed** (100% green).

