# 00 — Slop Signals Inventory

Command output captured 2026-10-31 on branch `037-uiux-unslop-audit`. Counts are a map of
where to look, **not findings by themselves**. Every finding still needs `path:line` and a
reason. Raw output is reproducible with the commands below (PowerShell; `rg` is not on PATH
on this machine).

## 1. Aggregate counts

| Signal | Donor | Vendor | Reading |
|---|---:|---:|---|
| Gradients / backdrop blur / image filters | **0** | **0** | No gradient or glass slop. This is genuinely clean. |
| `BoxShadow(` | **3** | **0** | Only the map picker floats. Rest of app is flat. |
| `Color(0x` outside `core/theme.dart` | **0** | **0** | No screen-local hex. Token law holds. |
| `withOpacity` / `withValues` | 74 | 15 | Mostly token tints; check each for a missing token. |
| `EdgeInsets.*` | 211 | 68 | Volume is fine; values are not (see §3). |
| `SizedBox(height|width:)` | 375 | 94 | Same. |
| `fontSize:` | 336 | 70 | 19 distinct sizes in donor vs a 7-role scale. |
| Empty callbacks / TODO / FIXME | **0 real** | **0 real** | 9 donor + 8 vendor hits are all `// ignore_for_file:` comments. No fake handlers found at this level. |
| Emoji in UI strings | **0** | **0** | Clean. |
| `toUpperCase()` | 5 | 13 | Acronyms (`UPI`/`COD`) are legitimate; plan/wallet labels need review. |
| `letterSpacing:` | 43 | 0 | Donor headings use negative tracking; check tracked micro-labels. |
| Animation controllers / implicit animations | 3 files | 1 file | Very little motion. Vendor has a hand-built cascade. |
| Devanagari strings | **0** | **17** | Vendor is bilingual; donor is English-only. Copy decision, not slop. |

## 2. Per-feature map (donor)

| Feature folder | Shadows | Color literals/tints | Padding calls | SizedBox | fontSize | ignore comments |
|---|---:|---:|---:|---:|---:|---:|
| `core/theme.dart` | 0 | 30 | 1 | 0 | 21 | 0 |
| `shared/ui` | 0 | 10 | 14 | 10 | 5 | 0 |
| `features/addresses` | **3** | 5 | 22 | 33 | 29 | 2 |
| `features/auth` | 0 | 4 | 12 | 20 | 24 | 2 |
| `features/booking` | 0 | 4 | 31 | **50** | 31 | 1 |
| `features/home` | 0 | 9 | 25 | 31 | 27 | 0 |
| `features/orders` | 0 | 4 | 27 | **63** | **45** | 1 |
| `features/profile` | 0 | 2 | 7 | 21 | 17 | 1 |
| `features/returns` | 0 | 0 | 4 | 21 | 18 | 0 |
| `features/shell` | 0 | 0 | 5 | 5 | 3 | 0 |
| `features/subscriptions` | 0 | 2 | 30 | **66** | **63** | 1 |
| `features/support` | 0 | 1 | 16 | 25 | 25 | 1 |
| `features/wallet` | 0 | 3 | 17 | 30 | 28 | 0 |

## 3. Per-feature map (vendor)

| Feature folder | Shadows | Color literals/tints | Padding calls | SizedBox | fontSize | ignore comments |
|---|---:|---:|---:|---:|---:|---:|
| `core/theme.dart` | 0 | 9 | 1 | 0 | 3 | 0 |
| `features/auth` | 0 | 2 | 2 | 12 | 5 | 1 |
| `features/customers` | 0 | 0 | 5 | 6 | 6 | 1 |
| `features/duty` | 0 | 0 | 4 | 5 | 1 | 1 |
| `features/earnings` | 0 | 0 | 6 | 13 | 12 | 1 |
| `features/inventory` | 0 | 0 | 5 | 4 | 4 | 0 |
| `features/profile` | 0 | 1 | 9 | 12 | 8 | 0 |
| `features/route` | 0 | 1 | 11 | 14 | 18 | 1 |
| `features/shell` | 0 | 0 | 1 | 0 | 1 | 0 |
| `features/stops` | 0 | 2 | 15 | 19 | 9 | 1 |
| `features/support` | 0 | 0 | 6 | 7 | 3 | 1 |
| `features/sync` | 0 | 0 | 3 | 2 | 0 | 1 |

## 4. Where the slop actually is

Not gradients. The slop in this codebase is **rhythm and type sprawl**, plus a small number
of composition defects that the screen agents must prove:

1. **Type scale explosion.** Donor uses 19 font sizes outside the theme (10, 10.5, 11, 11.5,
   12, 12.5, 13, 13.5, 14, 15, 16, 17, 18, 19, 20, 22, 24, 28, 32). `13` appears 84 times;
   `11` 18 times. Vendor uses 11, 12, 13, 15, 16, 18, 20, 22, 24 per-widget. Full counts:
   `00-tokens-actual.md` §4.
2. **Spacing off the 4px grid.** Donor uses 10 (39×), 14 (37×), 18 (12×), 20 (16×) as real
   padding/gap values. Vendor uses 10 (5×), 14 (2×), 18 (2×), 20 (4×). `2/3/5/6` are mostly
   dots/line heights and are not findings.
3. **Uppercase tracked micro-labels.** `plan_builder_sheet.dart:421` uppercases arbitrary
   text; 43 `letterSpacing` declarations need a pass to separate display tracking (legal)
   from tracked small caps (slop).
4. **Global green button default.** `theme.dart:311` makes every `ElevatedButton`
   `greenDark`. The money-only law is enforced by convention, not by the primitive. Screen
   agents must list every non-money `ElevatedButton`.
5. **Shadow only on the map.** `map_picker.dart:240,323,375` are the app's only shadows.
   Either intentional elevation for a floating map control or an inconsistency; D10 decides.
6. **Bilingual split.** Vendor is Hindi/English; donor is English-only. This is a product
   decision (owner decision #1), not a defect until decided.

## 5. Reproduction commands

```powershell
# signal counts
$patterns = @(
  'LinearGradient|RadialGradient|SweepGradient|BackdropFilter|ImageFilter',
  'BoxShadow\(',
  'Color\(0x|withOpacity|withValues',
  'EdgeInsets\.(all|symmetric|only|fromLTRB)\(',
  'SizedBox\((height|width):',
  'fontSize:',
  'onPressed: \(\) \{\}|onTap: \(\) \{\}|TODO|FIXME|// ignore'
)
foreach ($app in @('apps/user_app_donor','apps/vendor_app')) {
  foreach ($p in $patterns) {
    (Get-ChildItem "$app/lib" -Recurse -Filter *.dart | Select-String -Pattern $p).Count
  }
}

# distinct font sizes outside the theme
Get-ChildItem apps/user_app_donor/lib -Recurse -Filter *.dart |
  Where-Object { $_.FullName -notmatch 'core\\theme.dart' } |
  Select-String -Pattern 'fontSize:\s*([0-9.]+)' |
  ForEach-Object { [regex]::Match($_.Line,'fontSize:\s*([0-9.]+)').Groups[1].Value } |
  Group-Object | Sort-Object {[double]$_.Name}
```
