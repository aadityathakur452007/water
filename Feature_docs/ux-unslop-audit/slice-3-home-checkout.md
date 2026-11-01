# Slice 3 — Donor Core Home & Checkout Machine

**Branch:** `037-uiux-unslop-audit`  
**Defects addressed:** DEF-03, DEF-13  
**ADR:** ADR-159

---

## Scope

### DEF-13 — Retire decorative search modal

The `_SearchSheet` (154 lines + state + `_ProductPick` helper) is a navigation
cul-de-sac for a 2-SKU catalog.  It adds a tap, an animation and a keyboard
raise for zero information gain.  `FeaturedProductsShowcase` already surfaces
both products on the home scroll — the donor never needs search.

**Removal:**
- `_ProductPick` data class (donor_shell.dart:462–467)
- `_openSearch()` method (donor_shell.dart:274–284)
- `_SearchSheet` + `_SearchSheetState` widget (donor_shell.dart:469–624)
- `onSearch:` named arg on `DonorHomeTab(...)` call in `donor_shell.dart`
- `onSearch` required param + field in `DonorHomeTab` constructor
- `onSearch: widget.onSearch` pass-through in `_DonorHomeTabState.build()`
- The search-bar `Material`/`InkWell` row (lines 225–270 in `top_bar.dart`)
- `onSearch` param + field in `DonorTopBar`

### DEF-03 — 1-tap reorder card on home

When the user has at least one past order where `canReorder == true`, display a
`_QuickReorderCard` on the home scroll **between the greeting row and
`ModeSelectionCards`**.  A single tap fires `onOrderProduct` directly into the
existing `BookingSheet` flow — no new sheet, no new network call.

**Additions:**
- `reorderCandidate` getter on `OrdersController` (first `_all` entry where `canReorder`)
- `OrdersController? orders` optional param on `DonorHomeTab`
- `_QuickReorderCard` private widget in `customer_home_screen.dart`
- `orders: widget.orders` passed from `_DonorShellState._bodyFor(DonorTab.home)`

---

## Token constraints

| Token | Hex | Usage |
|-------|-----|-------|
| `tealDeep` | #115E59 | Icon tint on QuickReorderCard |
| `tealTint` | light teal bg | Card background |
| `greenDark` | #15803D | `AppButtonKind.money` — Reorder CTA |
| `ink` | #111111 | Body text |
| `muted` | grey | Subtitle text |

---

## Edge cases

| Scenario | Behaviour |
|----------|-----------|
| No orders loaded yet (`_all` empty) | `reorderCandidate` returns null → card hidden |
| All orders have `canReorder == false` (legacy rows) | card hidden |
| `orders` param not passed (unit test isolation) | card hidden (null check) |
| User taps Reorder while booking sheet already open | `_orderProduct` guards via `_routeBusy` in donor_shell — same gate as existing |
| `refillQty == 0, containerQty == 0` but order exists | `canReorder` is false → not a candidate |

---

## Acceptance criteria

- [ ] `flutter analyze` 0 issues (donor + vendor)
- [ ] `flutter test` donor 75/75 + vendor 70/70
- [ ] No `onSearch` symbol anywhere in donor app (grep)
- [ ] `_SearchSheet` class removed (grep)
- [ ] `QuickReorderCard` appears in home scroll when `canReorder` order exists
- [ ] Tapping Reorder opens `BookingSheet` with correct quantities

