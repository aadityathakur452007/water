# Slice 4 — Vendor Shell, Duty Gate & Navigation Hub

**Branch:** `037-uiux-unslop-audit`  
**Defects addressed:** DEF-05, DEF-07  
**ADR:** ADR-160

---

## Scope

### DEF-05 — Retire side drawer & introduce "More / Tools" Hub Screen

Currently, tapping Tab 4 ("More") in `VendorShell` programmatically opens an Android drawer
(`_scaffoldKey.currentState?.openDrawer()`) instead of switching the screen body. This violates standard
mobile ergonomics and causes gesture conflicts.

**Changes:**
- Remove `drawer:` property from `Scaffold` in `vendor_shell.dart`.
- Tab 4 destination in `NavigationBar` directly selects index 3 of `IndexedStack`.
- Introduce `MoreHubScreen` as the 4th tab in `IndexedStack`:
  - Customers (`CustomersScreen`)
  - Stock Log / Inventory (`InventoryScreen`)
  - Sync Log with pending queue badge (`SyncScreen`)
  - Duty Settings (`DutyScreen`)
  - Profile (`ProfileScreen`)
  - WhatsApp SOS (`launchUrl(https://wa.me/...)`)
  - Logout (`widget.auth.logout()`) with confirm dialog.
- Clean card/tile layout using `AppSpacing` tokens and vendor palette.

### DEF-07 — Soft sticky duty banner with route lock

Currently, when the driver is off duty, `VendorShell.build()` returns `DutyScreen` directly,
locking out the entire app so drivers cannot view their earnings, check profile, or contact support
without going on duty.

**Changes:**
- Remove the full-screen lockout guard from `VendorShell.build()`.
- When off-duty (`!widget.duty.onDuty && widget.duty.state != DutyState.loading`), display a persistent, high-contrast sticky banner at the top of the shell:
  - Banner copy: `"You are currently Off Duty — Turn On Duty to receive delivery stops"`
  - Quick action: `"Go On Duty"` CTA calling `widget.duty.setDuty(true)`
  - Tap banner opens `DutyScreen`.
- When off-duty, the Route tab displays an off-duty locked state (stops disabled / hidden, with clear guidance to go on duty).
- Earnings, Support, and More (Tab 1, 2, 3) remain 100% interactive while off duty.

---

## Token Constraints

| Token | Hex | Usage |
|-------|-----|-------|
| `ink` | #111111 | Vendor primary fill and text |
| `blue` | #2563EB | Primary accents and active indicators |
| `blueTint` | light blue | Soft duty banner background |
| `danger` | #DC2626 | Logout action and alerts |
| `surface` | #FFFFFF | Card backgrounds |
| `AppSpacing` | 4–32 | Standard padding/margins (exported in Slice 2) |

---

## Edge Cases

| Scenario | Behaviour |
|----------|-----------|
| Driver opens app while off duty | Shell mounts normally on Route tab; sticky banner displays "Off Duty"; Earnings and More tabs immediately accessible |
| Driver taps "Go On Duty" from sticky banner | `setDuty(true)` runs; banner disappears; Route tab becomes active and starts discovery poll |
| Driver taps "More" (Tab 4) | Body switches to `MoreHubScreen`; pending sync count badged on sync tile |
| Offline queue pending while on More tab | Pending sync badge appears on Tab 4 and sync tile |
| Duty error state | Banner displays retry / error state rather than blocking whole app |

---

## Acceptance Criteria

- [ ] `flutter analyze` 0 issues (donor + vendor)
- [ ] `flutter test` donor 80/80 + vendor passing
- [ ] Drawer completely removed from `vendor_shell.dart`
- [ ] Tapping Tab 4 switches body to `MoreHubScreen`
- [ ] Off-duty state does not lock out Earnings or Profile/More tabs
- [ ] New unit tests verifying `VendorShell` tab switching and off-duty banner

