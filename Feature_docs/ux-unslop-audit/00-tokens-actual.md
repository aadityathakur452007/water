# 00 — Tokens Actually Defined in Code

Extracted 2026-10-31 from the two theme files. This file is the ruler for the audit.
`context/ui-context.md` is the *intended* contract; this file is what the build renders.

Sources:
- Donor: `apps/user_app_donor/lib/core/theme.dart` (417 lines)
- Donor facade: `apps/user_app_donor/lib/core/constants/app_constants.dart` (51 lines)
- Vendor: `apps/vendor_app/lib/core/theme.dart` (131 lines)

---

## 1. Donor (`ShodashaTheme`)

### Colors — every token defined

| Token | Value | Intended role | Line |
|---|---|---|---|
| `bg` | `#F8FAFC` | Page ground | 21 |
| `surface` | `#FFFFFF` | Card / sheet ground | 24 |
| `ink` | `#0F172A` | Primary text | 27 |
| `muted` | `#64748B` | Secondary text | 30 |
| `border` | `#E2E8F0` | Hairline | 33 |
| `skeleton` | `#E2E8F0` | Loading blocks | 36 |
| `teal` | `#0D9488` | Brand / nav / active | 40 |
| `tealDark` | `#0F766E` | Teal press/hover | 43 |
| `tealDeep` | `#115E59` | White-on-teal fill | 46 |
| `tealTint` | `#CCFBF1` | Teal chip tint | 49 |
| `green` | `#16A34A` | Money green | 53 |
| `greenDark` | `#15803D` | Money CTA fill | 56 |
| `greenSoft` | `#F0FDF4` | Success banner ground | 59 |
| `greenTint` | `#DCFCE7` | Success chip tint | 62 |
| `greenBorder` | `#BBF7D0` | Success tile border | 65 |
| `solar` | `#FACC15` | Badge / highlight | 69 |
| `solarHover` | `#EAB308` | Solar press | 72 |
| `solarDark` | `#CA8A04` | Solar text on light | 75 |
| `solarTint` | `#FEF9C3` | Solar note ground | 78 |
| `solarBorder` | `#FDE047` | Solar tile border | 81 |
| `onSolar` | `#78350F` | Ink on solar | 84 |
| `blue` | `#0284C7` | Info / ETA | 88 |
| `blueTint` | `#E6F3FA` | Blue tint | 91 |
| `link` | `#0369A1` | Link text | 94 |
| `eta` | alias of `link` | ETA text | 97 |
| `etaTint` | `#E0F2FE` | ETA chip | 100 |
| `danger` | `#B91C1C` | Error | 104 |
| `success` | `#10B981` | Delivered / paid fill | 107 |
| `successDark` | `#047857` | Success text | 110 |
| `warning` | `#B45309` | Warning text | 113 |

Duplicates / aliases: `skeleton == border` (`#E2E8F0`); `eta == link` (`#0369A1`);
`AppColors.primary == teal`, `AppColors.money == green`, `AppColors.error == danger`
(`app_constants.dart:11-36`).

Missing semantic tokens (no token exists): pressed state for green CTA, disabled text
(uses `muted`), overlay/scrim (hardcoded per-sheet in `app_sheet.dart:146`), divider (alias
of border), focus ring (uses `tealDark`).

### Type scale — every role defined

| Role | Size | Weight | Line height | Line |
|---|---|---|---|---|
| `displaySmall` | 28 | 800 | 1.2 | 171 |
| `headlineSmall` | 22 | 800 | 1.25 | 178 |
| `titleLarge` | 18 | 700 | 1.3 | 185 |
| `titleMedium` | 16 | 700 | 1.35 | 191 |
| `titleSmall` | 14 | 600 | 1.35 | 197 |
| `bodyLarge` | 16 | 500 | 1.5 | 203 |
| `bodyMedium` | 14 | 500 | 1.45 | 209 |
| `bodySmall` | 12 | 500 | 1.4 | 215 |
| `labelLarge` | 14 | 700 | 1.2 | 221 |
| `labelMedium` | 12 | 600 | 1.2 | 227 |
| `labelSmall` | 12 | 600 + 0.2 tracking | 1.2 | 233 |

Theme-level overrides: AppBar title 18/800 (`:267`), nav label 12/500–800 (`:296`),
elevated button 16/800 (`:320`), filled 16/700 (`:343`), outlined 14/700 (`:357`),
input label 14/600 (`:375`), helper/error/counter 12 (`:385-391`).

### Radii, spacing, motion

| Token | Value | Line |
|---|---|---|
| `radiusSm` | 8 | 117 |
| `radius` | 12 | 120 |
| `radiusLg` | 16 | 123 |
| `radiusSheet` | 28 | 126 |
| `minTarget` | 48 | 129 |
| `AppSpacing.xs/sm/md/lg/xl/xxl` | 4/8/12/16/24/32 | 138-143 |
| `kMaxContentWidth` | 560 | 147 |
| `AppMotion.fast/normal/slow` | 150/180/220 ms | 152-158 |
| `AppMotion.reduced` | `MediaQuery.disableAnimationsOf` | 161 |

No `AppMotion` token is defined for sheet entrance, page transition, or list stagger.

---

## 2. Vendor (`ShodashaTheme`)

| Token | Value | Line |
|---|---|---|
| `bg` | `#FFFFFF` | 8 |
| `ink` | `#111111` | 9 |
| `muted` | `#595959` | 10 |
| `blue` | `#0284C7` | 11 |
| `blueTint` | `#E6F3FA` | 12 |
| `border` | `#E5E5E5` | 13 |
| `danger` | `#B91C1C` | 14 |
| `success` | `#15803D` | 15 |
| `radius` | 8 | 17 |
| `minTarget` | 48 | 18 |

Vendor defines **no** spacing scale, **no** type scale, **no** motion tokens, **no**
`surface` token (page ground is white), **no** warning token, **no** radius step above 8.

Type in vendor is written per-widget: 18/700 app bar (`:49`), 12 nav (`:66`), 16/700
button (`:82`). Everything else is screen-local.

---

## 3. Drift — `context/ui-context.md` vs code

| # | Doc says | Code says | Verdict |
|---|---|---|---|
| D1 | Color table lists 17 roles | Code defines 30 color constants | Doc incomplete, not contradicted |
| D2 | "Money CTAs use `greenDark` with white text" | `elevatedButtonTheme` makes **every** `ElevatedButton` green | Global default contradicts the "only Book/Pay/Confirm" law |
| D3 | Label/small = 12/600 | `labelLarge` = 14/700 | Doc omits the 14 role |
| D4 | `AppMotion` 150/180/220 | 150/180/220 | Match |
| D5 | Radius 8/12/16/28 | 8/12/16/28 | Match |
| D6 | Spacing 4/8/12/16/24/32 | 4/8/12/16/24/32 | Match, but 90+ off-scale uses exist (see §4) |
| D7 | `ShodashaTheme.surface` white; `bg` slate | Match | Match |
| D8 | "No screen-local hex" | No raw `Color(0x` outside theme (0 hits) | Holds |
| D9 | Vendor app "not governed by this file" | Vendor has a separate 8-color, 1-radius theme | Structural split; no vendor contract exists |
| D10 | "System platform font only" | No `fontFamily` set; base ThemeData font | Holds |
| D11 | Doc says shell tabs Home/Orders/Plans/Wallet/Profile | Verify in `donor_shell.dart` (D2 agent) | Open |

---

## 4. Off-scale census (the ruler's violations)

### Spacing values used in `EdgeInsets.*` and `SizedBox(height|width:)`

Donor (all numeric values 1–64 in those constructs, occurrence counts):

| On scale | Count | Off scale | Count |
|---|---|---|---|
| 4 | 30 | 1 | 3 |
| 8 | 108 | 2 | 24 |
| 12 | 78 | 3 | 4 |
| 16 | 48 | 5 | 2 |
| 24 | 19 | 6 | 51 |
| 32 | 0 (in this sample) | 10 | 39 |
| | | 14 | 37 |
| | | 18 | 12 |
| | | 20 | 16 |
| | | 28 | 1 |
| | | 40 | 1 |
| | | 64 | 1 |

Vendor: 4=13, 8=37, 12=49, 16=40, 24=11, 32=1; off-scale 2=2, 6=2, 10=5, 14=2,
18=2, 20=4, 48=1.

`2`/`3`/`5`/`6` are mostly line heights and dot sizes (legitimate micro-nudges). `10`,
`14`, `18`, `20` are used as real padding/gap values and are the actionable drift.

### Font sizes outside the theme

Donor screens use **19 distinct sizes**: 10, 10.5, 11, 11.5, 12, 12.5, 13, 13.5, 14, 15,
16, 17, 18, 19, 20, 22, 24, 28, 32.

The documented scale is 12/14/16/18/22/28. Off-scale sizes and counts:
10×1, 10.5×2, 11×18, 11.5×4, 12.5×16, 13×84, 13.5×1, 15×9, 17×9, 19×2, 20×10, 24×3,
32×1. `13` alone appears 84 times — it is a de-facto second body size.

Vendor screens use 11, 12, 13, 15, 16, 18, 20, 22, 24 per-widget, with `13` as the
dominant body size.

### Other token drift

- `11px` and below appears 25 times in donor screens. The prior UX review set an 11px
  floor for this cohort (`Feature_docs/user-app-ui-import-audit/05-uiux-conversion-review.md:36`);
  10 and 10.5 break even that floor.
- `Colors.white` is used directly in the wallet (`donor_wallet_screen.dart:337,364`)
  instead of `ShodashaTheme.surface`.
- `withValues(alpha:)` appears 37 times in donor and 6 in vendor. Most are tints of a
  token (acceptable); each should be checked for a missing token rather than a one-off.
- Shadows exist only in `map_picker.dart:240,323,375`; the rest of the app is flat.

---

## 5. What this means for agents

1. Measure every spacing/type/color claim against **this file**, not `ui-context.md`.
2. A value is only a finding when it is (a) off the 4px spacing grid, (b) off the type
   scale, (c) a raw color, or (d) inconsistent with a sibling element. "I would have
   chosen differently" is not a finding.
3. The global `ElevatedButton` green default (D2) is a system-level defect. Screen agents
   should record where non-money actions use `ElevatedButton`; X1 owns the fix.
4. Vendor has no scale at all. X1 owns whether that is acceptable for an internal ops app.
